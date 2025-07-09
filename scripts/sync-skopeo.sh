#!/bin/sh

set -e

echo "Syncing Docker images to registry..."

skopeo copy \
    docker://docker.io/library/alpine:3.22 \
    docker://registry:5000/alpine:3.22 \
    --dest-tls-verify=false
skopeo copy docker://docker.io/library/alpine:3.16 \
    docker://registry:5000/alpine:3.16 \
    --dest-tls-verify=false

# for reference, bitnami distributes HELM CHARTS, ONLY
# skopeo inspect docker://charts.bitnami.com/bitnami/nginx:15.14.0
# use docker's hubs instead
skopeo inspect docker://docker.io/grafana/grafana:12.0.2

# this obiously doesnt work, but it can, convert helm chart to OCI and then synchronize it
# skopeo copy oci://charts.bitnami.com/bitnami/nginx:15.14.0 \
#     oci://registry:5000/nginx:15.14 \
#     --dest-tls-verify=false
sleep 10
echo "Done."