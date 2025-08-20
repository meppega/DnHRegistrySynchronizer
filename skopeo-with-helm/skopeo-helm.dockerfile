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
        ca-certificates \
    && microdnf clean all \
    && rm -rf /var/cache/yum

WORKDIR /tmp

RUN wget "https://github.com/anchore/syft/releases/latest/download/syft_1.31.0_linux_amd64.tar.gz" \ 
    -O /tmp/syft.tar.gz && \
    tar -zxvf /tmp/syft.tar.gz && \
    mv /tmp/syft /usr/local/bin/syft && \
    rm /tmp/syft.tar.gz

RUN wget "https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz" -O helm.tar.gz && \
    tar -zxvf helm.tar.gz && \
    mv linux-amd64/helm /usr/local/bin/helm && \
    rm -rf linux-amd64 helm.tar.gz

RUN wget "https://github.com/bitnami/charts-syncer/releases/download/v2.1.3/charts-syncer_2.1.3_linux_x86_64.tar.gz" \
    -O /tmp/charts-syncer.tar.gz && \
    tar -zxvf /tmp/charts-syncer.tar.gz && \ 
    mv /tmp/charts-syncer /usr/local/bin/ && \
    rm /tmp/charts-syncer.tar.gz

# Create a non-root user and switch to it
RUN useradd -m -s /bin/bash runner && \
    chown -R runner:runner /tmp

USER runner
# Set the working directory for the runner
WORKDIR /home/runner

# Optional: Set environment variables for the user
ENV HOME=/home/runner