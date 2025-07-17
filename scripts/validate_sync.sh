#!/bin/bash
# Script to validate synchronized Docker images and Helm charts by comparing SHA256 digests

set -e

CONFIG_FILE="/sync-config.yaml"

REGISTRY_URL="registry:5000"
# REGISTRY_USER="admin"
# REGISTRY_PASS="admin"

# Function to get Docker image SHA256 digest using skopeo inspect
# Arguments:
#   $1: image_ref (e.g., docker.io/library/alpine:3.22 or registry:5000/images/alpine:3.22)
#   $2: tls_verify_flag (e.g., --tls-verify=false or --dest-tls-verify=false for local registry)
get_docker_image_digest() {
    local image_ref="$1"
    local tls_verify_flag="$2"
    local digest=""
    local inspect_output

    echo "  > Inspecting Docker image: ${image_ref}"
    # Use skopeo inspect to get the manifest digest.
    # Redirect stderr to /dev/null to suppress "image not found" errors when inspecting non-existent images,
    # and handle the exit code.
    echo "docker://${image_ref} ${tls_verify_flag}"
    if inspect_output=$(skopeo inspect "docker://${image_ref}" "${tls_verify_flag}" 2>/dev/null); then
        # Command succeeded, now check if output is non-empty
        if [ -n "${inspect_output}" ]; then
            digest=$(echo "${inspect_output}" | jq -r '.Digest')
        else
            echo "    Warning: Skopeo inspect succeeded but returned empty output for ${image_ref}." >&2
        fi
    else
        echo "    Warning: Could not inspect image ${image_ref}. It might not exist or there's a connectivity issue." >&2
    fi
    echo "${digest}"
}

# Function to calculate SHA256 digest of a .tgz file
# Arguments:
#   $1: tgz_file (path to the tarball)
get_tgz_sha256() {
    local tgz_file="$1"
    if [ -f "${tgz_file}" ]; then
        sha256sum "${tgz_file}" | awk '{print $1}'
    else
        echo "" # Return empty string if file not found
    fi
}

# Main validation logic function
validate_skopeo() {
    echo "--- Starting Sync Validation ---"

    # Log in to the local registry for Skopeo and Helm to ensure access
    echo "  > Logging into local registry: ${REGISTRY_URL}..."
    # Skopeo login
    #echo "${REGISTRY_PASS}" | skopeo login "${REGISTRY_URL}" --username "${REGISTRY_USER}" --password-stdin || { echo "Skopeo login failed."; exit 1; }
    # Validate Docker Images
    echo ""
    echo "--- Validating Docker Images ---"
    image_count=$(yq '.dockerImages | length' "${CONFIG_FILE}")
    if [ "${image_count}" -eq 0 ]; then
        echo "  No Docker images configured for synchronization."
        return
    fi

    for i in $(seq 0 $((image_count - 1))); do
        SOURCE_IMAGE=$(yq ".dockerImages[$i].source" "${CONFIG_FILE}")
        DEST_PATH=$(yq ".dockerImages[$i].destinationPath" "${CONFIG_FILE}")
        DEST_IMAGE="${REGISTRY_URL}/${DEST_PATH}"

        echo "Checking image: ${SOURCE_IMAGE} -> ${DEST_IMAGE}"

        # Get digest for source image (assuming public registries don't need --tls-verify=false)
        SOURCE_DIGEST=$(get_docker_image_digest "${SOURCE_IMAGE}" "--tls-verify=true")
        # Get digest for destination image (using --tls-verify=false for local registry)
        DEST_DIGEST=$(get_docker_image_digest "${DEST_IMAGE}" "--tls-verify=false")

        if [ -z "${SOURCE_DIGEST}" ]; then
            echo "  Status: SKIP (Source image digest not found, possibly due to access or non-existence)"
        elif [ -z "${DEST_DIGEST}" ]; then
            echo "  Status: FAIL (Destination image digest not found - image might be missing in local registry)"
        elif [ "${SOURCE_DIGEST}" = "${DEST_DIGEST}" ]; then
            echo "  Status: PASS (Digests match: ${SOURCE_DIGEST})"
        else
            echo "  Status: FAIL (Digests mismatch)"
            echo "    Source: ${SOURCE_DIGEST}"
            echo "    Dest:   ${DEST_DIGEST}"
        fi
        echo ""
    done
}

validate_helm() {
    # Validate Helm Charts
    # Helm registry login (using --plain-http for insecure local registry)
    #helm registry login "${REGISTRY_URL}" --username "${REGISTRY_USER}" --password "${REGISTRY_PASS}" --plain-http || { echo "Helm registry login failed."; exit 1; }

    echo ""
    echo "--- Validating Helm Charts ---"
    chart_count=$(yq '.helmCharts | length' "${CONFIG_FILE}")
    if [ "${chart_count}" -eq 0 ]; then
        echo "  No Helm charts configured for synchronization."
        return
    fi

    # Create a temporary directory for chart downloads
    TEMP_DIR=$(mktemp -d -t helm-charts-validation-XXXXXXXX)
    echo "  > Using temporary directory for Helm charts: ${TEMP_DIR}"

    for i in $(seq 0 $((chart_count - 1))); do
        # REPO_NAME=$(yq ".helmCharts[$i].repoName" "${CONFIG_FILE}")
        REPO_URL=$(yq ".helmCharts[$i].repoUrl" "${CONFIG_FILE}")
        CHART_NAME=$(yq ".helmCharts[$i].chartName" "${CONFIG_FILE}")
        CHART_VERSION=$(yq ".helmCharts[$i].chartVersion" "${CONFIG_FILE}")
        DEST_PATH=$(yq ".helmCharts[$i].destinationPath" "${CONFIG_FILE}")
        
        # Construct destination OCI URL (e.g., oci://registry:5000/charts/nginx)
        DEST_OCI_URL="oci://${REGISTRY_URL}/${DEST_PATH}${CHART_NAME}"

        echo "Checking chart: ${REPO_URL}/${CHART_NAME}:${CHART_VERSION} -> ${DEST_OCI_URL}:${CHART_VERSION}"

        SOURCE_CHART_FILE="${TEMP_DIR}/${CHART_NAME}-${CHART_VERSION}.tgz"
        # Helm pull from OCI also names the file chartname-version.tgz

        # Pull source chart to a unique temporary file
        echo "  > Pulling source chart from ${REPO_URL}..."
        if helm pull "${CHART_NAME}" --repo "${REPO_URL}" --version "${CHART_VERSION}" --destination "${TEMP_DIR}" --untar=false >/dev/null 2>&1; then
            SOURCE_SHA=$(get_tgz_sha256 "${SOURCE_CHART_FILE}")
        else
            echo "    Warning: Failed to pull source chart ${CHART_NAME}:${CHART_VERSION} from ${REPO_URL}. Skipping validation for this chart." >&2
            SOURCE_SHA=""
        fi

        rm "${SOURCE_CHART_FILE}"

        # Pull destination chart from OCI registry to a *different* unique temporary file
        echo "  > Pulling destination chart from ${DEST_OCI_URL}..."
        # Create a distinct file name for the destination chart to avoid conflicts
        LOCAL_DEST_CHART_FILE="${TEMP_DIR}/dest_${CHART_NAME}-${CHART_VERSION}.tgz"
        if helm pull "${DEST_OCI_URL}" --version "${CHART_VERSION}" --destination "${TEMP_DIR}" --plain-http --untar=false >/dev/null 2>&1; then
            DEST_SHA=$(get_tgz_sha256 "${SOURCE_CHART_FILE}")
        else
            echo "    Warning: Failed to pull destination chart ${CHART_NAME}:${CHART_VERSION} from ${DEST_OCI_URL}. It might be missing in the local registry." >&2
            DEST_SHA=""
        fi

        if [ -z "${SOURCE_SHA}" ]; then
            echo "  Status: SKIP (Source chart digest could not be determined)"
        elif [ -z "${DEST_SHA}" ]; then
            echo "  Status: FAIL (Destination chart digest could not be determined - chart might be missing)"
        elif [ "${SOURCE_SHA}" = "${DEST_SHA}" ]; then
            echo "  Status: PASS (Digests match: ${SOURCE_SHA})"
        else
            echo "  Status: FAIL (Digests mismatch)"
            echo "    Source: ${SOURCE_SHA}"
            echo "    Dest:   ${DEST_SHA}"
        fi
        echo ""
    done

    # Clean up temporary directory
    echo "  > Cleaning up temporary directory: ${TEMP_DIR}"
    rm -rf "${TEMP_DIR}"
}

# Run validation
validate_skopeo
validate_helm

echo "--- Sync Validation Complete ---"