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

skopeo inspect oci://charts.bitnami.com/bitnami/nginx:15.14.0
# this obiously doesnt work, but it can, convert helm chart to OCI and then synchronize it
# skopeo copy oci://charts.bitnami.com/bitnami/nginx:15.14.0 \
#     oci://registry:5000/nginx:15.14 \
#     --dest-tls-verify=false

echo "Done."