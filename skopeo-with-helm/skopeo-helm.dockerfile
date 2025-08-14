FROM quay.io/skopeo/stable:v1.19.0

ARG HELM_VERSION=3.14.4
# ARG YQ_VERSION=3.1.0-3

RUN microdnf update -y && \
    microdnf install -y \
        wget \
        tar \
        gzip \
        yq \
        curl \
        util-linux \
        jq \
    && microdnf clean all \
    && rm -rf /var/cache/yum

WORKDIR /tmp

RUN wget "https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz" -O helm.tar.gz && \
    tar -zxvf helm.tar.gz && \
    mv linux-amd64/helm /usr/local/bin/helm && \
    rm -rf linux-amd64 helm.tar.gz

# Create a non-root user and switch to it
RUN useradd -m -s /bin/bash runner && \
    chown -R runner:runner /tmp

USER runner
# Set the working directory for the runner
WORKDIR /home/runner

# Optional: Set environment variables for the user
ENV HOME=/home/runner