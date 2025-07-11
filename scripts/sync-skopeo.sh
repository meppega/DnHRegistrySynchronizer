#!/bin/sh

set -e

REGISTRY_URL="registry:5000" # equivalent to "registry:5000"
REGISTRY_USER="admin"
REGISTRY_PASS="admin"

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

# this wont work, the origin is a chart, its here for testing
skopeo copy \
    docker://kubernetes.github.io/ingress-nginx:4.13.0 \
    docker://"$REGISTRY_URL"/charts/ingress-nginx:4.13.0 \
     --dest-tls-verify=false

# 
# skopeo copy oci://charts.bitnami.com/bitnami/nginx:15.14.0 \
#     oci://"$REGISTRY_URL"/nginx:15.14 \
#     --dest-tls-verify=false

sleep 10
echo "Done."