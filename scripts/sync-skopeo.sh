#!/bin/sh

set -e

REGISTRY_URL="registry:5000" # equivalent to "registry:5000"
REGISTRY_USER="admin"
REGISTRY_PASS="admin"

HELM_CHART_REPO_NAME="kubernetes-ingress"
HELM_CHART_REPO_URL="https://kubernetes.github.io/ingress-nginx"
HELM_CHART_NAME="ingress-nginx"
HELM_CHART_VERSION="4.13.0"

echo "--- Verifying installed tools ---"
skopeo --version
helm version --client

#echo "$REGISTRY_PASS" | skopeo login "$REGISTRY_URL" --username "$REGISTRY_USER" --password-stdin

echo "Syncing Docker images to registry..."

skopeo copy \
    docker://docker.io/library/alpine:3.22 \
    docker://"$REGISTRY_URL"/alpine:3.22 \
     --dest-tls-verify=false
skopeo copy docker://docker.io/library/alpine:3.16 \
    docker://"$REGISTRY_URL"/alpine:3.16 \
     --dest-tls-verify=false

# for reference, bitnami distributes HELM CHARTS, ONLY
# skopeo inspect docker://charts.bitnami.com/bitnami/nginx:15.14.0

# use docker's hubs instead
skopeo copy \
    docker://docker.io/grafana/grafana:12.0.2 \
    docker://"$REGISTRY_URL"/charts/grafana:12.0.2 \
     --dest-tls-verify=false

# helm chart conversion
echo "  > Adding traditional Helm repository..."
helm repo add "${HELM_CHART_REPO_NAME}" "${HELM_CHART_REPO_URL}" --force-update
helm repo update

echo "  > Pulling Helm chart from traditional repository..."
#helm pull "${HELM_CHART_REPO_NAME}/${HELM_CHART_NAME}" --version "${HELM_CHART_VERSION}" --destination /data
helm pull kubernetes-ingress/ingress-nginx --version "${HELM_CHART_VERSION}" #--destination /data

if [ ! -f "${HELM_CHART_NAME}-${HELM_CHART_VERSION}.tgz" ]; then
  echo "Error: Chart ${HELM_CHART_NAME}-${HELM_CHART_VERSION}.tgz was not downloaded. Exiting."
  exit 1
fi

helm push \
    "${HELM_CHART_NAME}-${HELM_CHART_VERSION}.tgz" \
    "oci://${REGISTRY_URL}/charts/" \
    --insecure-skip-tls-verify # Use --insecure-skip-tls-verify or --plain-http for plain HTTP registry
# helm push nginx-15.14.0.tgz oci://localhost:5000/charts/

rm "${HELM_CHART_NAME}-${HELM_CHART_VERSION}.tgz"

# this wont work WITHOUT HELM
# skopeo copy \
#     docker://kubernetes.github.io/ingress-nginx:4.13.0 \
#     docker://"$REGISTRY_URL"/charts/ingress-nginx:4.13.0 \
#      --dest-tls-verify=false

# skopeo copy oci://charts.bitnami.com/bitnami/nginx:15.14.0 \
#     oci://"$REGISTRY_URL"/nginx:15.14 \
#     --dest-tls-verify=false

sleep 3
echo "Done."