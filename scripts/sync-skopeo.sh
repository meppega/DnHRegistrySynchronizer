#!/bin/sh

set -e

CONFIG_FILE="sync-config.yaml"

REGISTRY_URL="registry:5000"
REGISTRY_USER="admin"
REGISTRY_PASS="admin"

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
    helm pull "${CHART_NAME}" --repo "${REPO_URL}" --version "${CHART_VERSION}"
    #--destination /data

    if [ ! -f "${FILE_NAME}.tgz" ]; then
        echo "Error: Chart ${HELM_CHART}.tgz failed to download. Skipping."
        return
    fi
 
    helm push \
    "${FILE_NAME}.tgz" \
    "${DEST_REPO}" \
    --plain-http

    rm "${FILE_NAME}.tgz"
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

# logging skopeo in
#echo "$REGISTRY_PASS" | skopeo login "$REGISTRY_URL" --username "$REGISTRY_USER" --password-stdin

echo "Syncing Docker images to registry..."

check_and_copy_skopeo "docker.io/library/alpine:3.22" "$REGISTRY_URL/alpine:3.22"
check_and_copy_skopeo "docker.io/library/alpine:3.16" "$REGISTRY_URL/alpine:3.16"
check_and_copy_skopeo "docker.io/grafana/grafana:12.0.2" "$REGISTRY_URL/charts/grafana:12.0.2"

check_and_copy_helm "bitnami" \
    "https://charts.bitnami.com/bitnami" \
    "nginx" \
    "15.14.0" \
    "oci://registry:5000/charts/"

check_and_copy_helm "kubernetes-ingress" \
    "https://kubernetes.github.io/ingress-nginx" \
    "ingress-nginx" \
    "4.13.0" \
    "oci://registry:5000/charts/"

echo "--- Syncing Docker images ---"
# Loop through dockerImages from YAML
yq -o=j '.dockerImages[]' "/sync-config.yaml" | while read -r image_json; do
    SOURCE_IMAGE=$(echo "${image_json}" | yq -p=json '.source')
    DEST_PATH=$(echo "${image_json}" | yq -p=json '.destinationPath')
    
    echo "${SOURCE_IMAGE}${DEST_PATH}"
done

echo "--- Syncing Helm Charts ---"
# Loop through helmCharts from YAML
yq -o=j '.helmCharts[]' "${CONFIG_FILE}" | while read -r chart_json; do
    REPO_NAME=$(echo "${chart_json}" | yq '.repoName')
    REPO_URL=$(echo "${chart_json}" | yq '.repoUrl')
    CHART_NAME=$(echo "${chart_json}" | yq '.chartName')
    CHART_VERSION=$(echo "${chart_json}" | yq '.chartVersion')
    DEST_PATH=$(echo "${chart_json}" | yq '.destinationPath')

    echo "${REPO_NAME}${REPO_URL}${CHART_NAME}${CHART_VERSION}${DEST_PATH}"
done

sleep 1
echo "Done."