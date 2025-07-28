#!/bin/bash
# Script to validate synchronized Docker images and Helm charts by comparing SHA256 digests

set -o errexit
set -o nounset
#set -o pipefail

readonly CONFIG_FILE="/ARISU/config/sync-config.yaml"

REGISTRY_URL=$(yq '.registry.url' "${CONFIG_FILE}")
REGISTRY_USER=$(yq '.registry.user' "${CONFIG_FILE}")
REGISTRY_PASS=$(yq '.registry.password' "${CONFIG_FILE}")

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
	local image_count=0
	local source_image=""
	local dest_path=""
	local dest_image=""
	local source_digest=""
	local dest_digest=""

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
		source_image=$(yq ".dockerImages[$i].source" "${CONFIG_FILE}")
		dest_path=$(yq ".dockerImages[$i].destinationPath" "${CONFIG_FILE}")
		dest_image="${REGISTRY_URL}/${dest_path}"

		echo "Checking image: ${source_image} -> ${dest_image}"

		# Get digest for source image (assuming public registries don't need --tls-verify=false)
		source_digest=$(get_docker_image_digest "${source_image}" "--tls-verify=true")
		# Get digest for destination image (using --tls-verify=false for local registry)
		dest_digest=$(get_docker_image_digest "${dest_image}" "--tls-verify=false")

		if [ -z "${source_digest}" ]; then
			echo "  Status: SKIP (Source image digest not found, possibly due to access or non-existence)"
		elif [ -z "${dest_digest}" ]; then
			echo "  Status: FAIL (Destination image digest not found - image might be missing in local registry)"
		elif [ "${source_digest}" = "${dest_digest}" ]; then
			echo "  Status: PASS (Digests match: ${source_digest})"
		else
			echo "  Status: FAIL (Digests mismatch)"
			echo "    Source: ${source_digest}"
			echo "    Dest:   ${dest_digest}"
		fi
		echo ""
	done
}

#TODO: separate files for verification
validate_helm() {
	# Validate Helm Charts
	# Helm registry login (using --plain-http for insecure local registry)
	#helm registry login "${REGISTRY_URL}" --username "${REGISTRY_USER}" --password "${REGISTRY_PASS}" --plain-http || { echo "Helm registry login failed."; exit 1; }

	local chart_count=0
	local repo_url
	local chart_name
	local chart_version
	local dest_path
	local dest_oci_url
	local source_chart_file
	local existing_chart_file
	local source_sha
	local dest_sha

	echo ""
	echo "--- Validating Helm Charts ---"
	chart_count=$(yq '.helmCharts | length' "${CONFIG_FILE}")
	if [ "${chart_count}" -eq 0 ]; then
		echo "  No Helm charts configured for synchronization."
		return
	fi

	for i in $(seq 0 $((chart_count - 1))); do
		# repo_name=$(yq ".helmCharts[$i].repoName" "${CONFIG_FILE}")
		repo_url=$(yq ".helmCharts[$i].repoUrl" "${CONFIG_FILE}")
		chart_name=$(yq ".helmCharts[$i].chartName" "${CONFIG_FILE}")
		chart_version=$(yq ".helmCharts[$i].chartVersion" "${CONFIG_FILE}")
		dest_path=$(yq ".helmCharts[$i].destinationPath" "${CONFIG_FILE}")

		# Construct destination OCI URL (e.g., oci://registry:5000/charts/nginx)
		dest_oci_url="oci://${REGISTRY_URL}/${dest_path}${chart_name}"

		echo "Checking chart: ${repo_url}/${chart_name}:${chart_version} -> ${dest_oci_url}:${chart_version}"

		source_chart_file="/tmp/${chart_name}-${chart_version}.tgz"
		# Helm pull from OCI also names the file chartname-version.tgz

		# Pull source chart to a unique temporary file
		echo "  > Pulling source chart from ${repo_url}..."
		if helm pull "${chart_name}" --repo "${repo_url}" --version "${chart_version}" --destination "/tmp" --untar=false >/dev/null 2>&1; then
			source_sha=$(get_tgz_sha256 "${source_chart_file}")
		else
			echo "    Warning: Failed to pull source chart ${chart_name}:${chart_version} from ${repo_url}. Skipping validation for this chart." >&2
			source_sha=""
		fi

		rm "${source_chart_file}"

		# Pull destination chart from OCI registry to a *different* unique temporary file
		echo "  > Pulling destination chart from ${dest_oci_url}..."
		# Create a distinct file name for the destination chart to avoid conflicts
		# LOCAL_DEST_CHART_FILE="${temp_dir}/dest_${chart_name}-${chart_version}.tgz"
		if helm pull "${dest_oci_url}" --version "${chart_version}" --destination "/tmp" --plain-http --untar=false >/dev/null 2>&1; then
			dest_sha=$(get_tgz_sha256 "${source_chart_file}")
		else
			echo "    Warning: Failed to pull destination chart ${chart_name}:${chart_version} from ${dest_oci_url}. It might be missing in the local registry." >&2
			dest_sha=""
		fi

		if [ -z "${source_sha}" ]; then
			echo "  Status: SKIP (Source chart digest could not be determined)"
		elif [ -z "${dest_sha}" ]; then
			echo "  Status: FAIL (Destination chart digest could not be determined - chart might be missing)"
		elif [ "${source_sha}" = "${dest_sha}" ]; then
			echo "  Status: PASS (Digests match: ${source_sha})"
		else
			echo "  Status: FAIL (Digests mismatch)"
			echo "    Source: ${source_sha}"
			echo "    Dest:   ${dest_sha}"
		fi
		echo ""
	done

	# Clean up temporary directory
	echo "  > Cleaning up temporary directory"
	rm -f "/tmp/*.tgz"
}

# Run validation
validate_skopeo
validate_helm

echo "--- Sync Validation Complete ---"
