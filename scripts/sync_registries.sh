#!/bin/bash

set -e

CONFIG_FILE="/sync-config.yaml"

REGISTRY_URL=$(yq '.registry.url' "${CONFIG_FILE}")
REGISTRY_USER=$(yq '.registry.user' "${CONFIG_FILE}")
REGISTRY_PASS=$(yq '.registry.password' "${CONFIG_FILE}")

# Function to check if all necessary dependencies are installed
# check_dependencies() {
#     local deps=("yq" "skopeo" "helm" "curl" "jq" "sha256sum")
#     for dep in "${deps[@]}"; do
#         if ! command -v "$dep" &> /dev/null; then
#             echo "Error: Required command '$dep' is not installed. Please install it."
#             exit 1
#         fi
#     done
# }

#TODO: add comparing if images are different
check_and_copy_helm() {
    REPO_NAME="$1"
    REPO_URL="$2"
    CHART_NAME="$3"
    CHART_VERSION="$4"
    DEST_REPO="$5"
    FILE_NAME="${CHART_NAME}-${CHART_VERSION}"

    if helm show chart "${DEST_REPO}${CHART_NAME}" --plain-http > /dev/null 2>&1; then
        echo "Chart ${DEST_REPO}${CHART_NAME} exists. Skipping."
        return
    fi

    echo "Chart does not exist. Adding ${DEST_REPO}${CHART_NAME}"

    #echo "  > Adding Helm repository: ${REPO_NAME} ..."
    #helm repo add "${REPO_NAME}" "${REPO_URL}" --force-update
    #helm repo update

    echo "  > Pulling Helm chart from traditional repository..."
    helm pull "${CHART_NAME}" --repo "${REPO_URL}" --version "${CHART_VERSION}" --destination /tmp

    if [ ! -f "/tmp/${FILE_NAME}.tgz" ]; then
        echo "Error: Chart ${HELM_CHART}.tgz failed to download. Skipping."
        return
    fi
 
    helm push \
    "/tmp/${FILE_NAME}.tgz" \
    "${DEST_REPO}" \
    --plain-http

    rm "/tmp/${FILE_NAME}.tgz"
}

check_and_copy_skopeo() {
    SOURCE_IMAGE="$1"
    DEST_IMAGE="$2"

    echo "Checking if $DEST_IMAGE exists in registry..."
    if skopeo inspect "docker://${DEST_IMAGE}" --tls-verify=false >/dev/null 2>&1; then
        echo "$DEST_IMAGE already exists. Skipping copy."
        return
    fi

    echo "$DEST_IMAGE not found. Copying..."
    skopeo copy "docker://${SOURCE_IMAGE}" "docker://${DEST_IMAGE}" --dest-tls-verify=false
}

# Run dependency check
# check_dependencies

# logging skopeo in
#echo "$REGISTRY_PASS" | skopeo login "$REGISTRY_URL" --username "$REGISTRY_USER" --password-stdin

echo "--- Syncing Docker images ---"

# check_and_copy_skopeo "docker.io/library/alpine:3.22" "$REGISTRY_URL/alpine:3.22"
# check_and_copy_skopeo "docker.io/library/alpine:3.16" "$REGISTRY_URL/alpine:3.16"
# check_and_copy_skopeo "docker.io/grafana/grafana:12.0.2" "$REGISTRY_URL/charts/grafana:12.0.2"

image_count=$(yq '.dockerImages | length' "${CONFIG_FILE}")

for i in $(seq 0 $((image_count - 1))); do
    SOURCE_IMAGE=$(yq ".dockerImages[$i].source" "${CONFIG_FILE}")
    DEST_PATH=$(yq ".dockerImages[$i].destinationPath" "${CONFIG_FILE}")

    check_and_copy_skopeo "${SOURCE_IMAGE}" "${REGISTRY_URL}/${DEST_PATH}"
done

echo "--- Syncing Helm Charts ---"

# check_and_copy_helm "bitnami" \
#     "https://charts.bitnami.com/bitnami" \
#     "nginx" \
#     "15.14.0" \
#     "oci://registry:5000/charts/"

# check_and_copy_helm "kubernetes-ingress" \
#     "https://kubernetes.github.io/ingress-nginx" \
#     "ingress-nginx" \
#     "4.13.0" \
#     "oci://registry:5000/charts/"

chart_count=$(yq '.helmCharts | length' "${CONFIG_FILE}")

for i in $(seq 0 $((chart_count - 1))); do
    REPO_NAME=$(yq ".helmCharts[$i].repoName" "${CONFIG_FILE}")
    REPO_URL=$(yq ".helmCharts[$i].repoUrl" "${CONFIG_FILE}")
    CHART_NAME=$(yq ".helmCharts[$i].chartName" "${CONFIG_FILE}")
    CHART_VERSION=$(yq ".helmCharts[$i].chartVersion" "${CONFIG_FILE}")
    DEST_PATH=$(yq ".helmCharts[$i].destinationPath" "${CONFIG_FILE}")

    check_and_copy_helm \
        "${REPO_NAME}" \
        "${REPO_URL}" \
        "${CHART_NAME}" \
        "${CHART_VERSION}" \
        "oci://${REGISTRY_URL}/${DEST_PATH}"
done

sleep 1
echo "Done."

/test_functions.sh
exec /validate_sync.sh