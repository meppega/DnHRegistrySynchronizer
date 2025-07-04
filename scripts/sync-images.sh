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

echo "Done."