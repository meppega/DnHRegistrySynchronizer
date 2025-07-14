#!/bin/sh

set -e

REGISTRY_URL="registry:5000"
REGISTRY_USER="admin"
REGISTRY_PASS="admin"

HELM_CHART_REPO_NAME="kubernetes-ingress"
HELM_CHART_REPO_URL="https://kubernetes.github.io/ingress-nginx"
HELM_CHART_NAME="ingress-nginx"
HELM_CHART_VERSION="4.13.0"
HELM_CHART="${HELM_CHART_NAME}-${HELM_CHART_VERSION}"

#TODO: add comparing if images are different
check_and_copy_image() {
    SOURCE_IMAGE="$1"
    DEST_IMAGE="$2"
    echo "Checking if $DEST_IMAGE exists in registry..."
    if skopeo inspect "docker://${DEST_IMAGE}" --tls-verify=false >/dev/null 2>&1; then
        echo "$DEST_IMAGE already exists. Skipping copy."
    else
        echo "$DEST_IMAGE not found. Copying..."
        skopeo copy "docker://${SOURCE_IMAGE}" "docker://${DEST_IMAGE}" --dest-tls-verify=false
    fi
}

#TODO: add comparing if images are different, finish making this
check_and_copy_chart() {
    SOURCE_IMAGE="$1"
    DEST_IMAGE="$2"
    echo "Checking if $DEST_IMAGE exists in registry..."
    # if skopeo inspect "oci://${DEST_IMAGE}" --tls-verify=false >/dev/null 2>&1; then
    if helm pull "oci://localhost:5000/charts/ingress-nginx" --version 4.13.0 --destination /tmp --insecure-skip-tls-verify >/dev/null 2>&1; then
        echo "$DEST_IMAGE already exists. Skipping copy."
    else
        echo "$DEST_IMAGE not found. Copying..."
        helm push \
            "${SOURCE_IMAGE}" \
            "oci://${REGISTRY_URL}/charts/" \
            --insecure-skip-tls-verify
    fi
}

echo "--- Verifying installed tools ---"
skopeo --version
helm version --client

#echo "$REGISTRY_PASS" | skopeo login "$REGISTRY_URL" --username "$REGISTRY_USER" --password-stdin

echo "Syncing Docker images to registry..."

check_and_copy_image "docker.io/library/alpine:3.22" "$REGISTRY_URL/alpine:3.22"
check_and_copy_image "docker.io/library/alpine:3.16" "$REGISTRY_URL/alpine:3.16"
check_and_copy_image "docker.io/grafana/grafana:12.0.2" "$REGISTRY_URL/charts/grafana:12.0.2"

# helm chart conversion
echo "  > Adding traditional Helm repository..."
helm repo add "${HELM_CHART_REPO_NAME}" "${HELM_CHART_REPO_URL}" --force-update
helm repo update

echo "  > Pulling Helm chart from traditional repository..."
#helm pull "${HELM_CHART_REPO_NAME}/${HELM_CHART_NAME}" --version "${HELM_CHART_VERSION}" --destination /data
helm pull kubernetes-ingress/ingress-nginx --version "${HELM_CHART_VERSION}" #--destination /data

if [ -f "${HELM_CHART}.tgz" ]; then
    check_and_copy_chart "${HELM_CHART}.tgz" "${REGISTRY_URL}/charts/${HELM_CHART_NAME}:${HELM_CHART_VERSION}"
    # helm push \
    #     "${HELM_CHART_NAME}-${HELM_CHART_VERSION}.tgz" \
    #     "oci://${REGISTRY_URL}/charts/" \
    #     --insecure-skip-tls-verify --plain-http
    rm "${HELM_CHART}.tgz"
else
    echo "Error: Chart ${HELM_CHART}.tgz was not downloaded. Skipping."
fi

# convert to helm
# skopeo copy oci://charts.bitnami.com/bitnami/nginx:15.14.0 \
#     oci://"$REGISTRY_URL"/nginx:15.14 \
#     --dest-tls-verify=false

sleep 3
echo "Done."