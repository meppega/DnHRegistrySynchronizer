# Use a base image that's good for running both skopeo and helm.
# quay.io/skopeo/stable:latest is based on UBI (Red Hat Universal Base Image),
# which is a good choice as skopeo is already there. We just add Helm.
FROM quay.io/skopeo/stable:latest

# Arguments for Helm version (can be overridden at build time)
ARG HELM_VERSION=3.14.4

# Install necessary tools for downloading and extracting Helm
RUN microdnf update -y && \
    microdnf install -y \
        wget \
        tar \
        gzip \
        # 'curl' might be useful if you add more checks
    && microdnf clean all \
    && rm -rf /var/cache/yum

# Download and install Helm
WORKDIR /tmp
RUN wget "https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz" -O helm.tar.gz && \
    tar -zxvf helm.tar.gz && \
    mv linux-amd64/helm /usr/local/bin/helm && \
    rm -rf linux-amd64 helm.tar.gz

# Verify installations
RUN skopeo --version && \
    helm version --client