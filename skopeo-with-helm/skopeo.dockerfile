FROM quay.io/skopeo/stable:1.19.0

ARG HELM_VERSION=3.14.4

RUN microdnf update -y && \
    microdnf install -y \
        wget \
        tar \
        gzip \
    && microdnf clean all \
    && rm -rf /var/cache/yum

WORKDIR /tmp
RUN wget "https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz" -O helm.tar.gz && \
    tar -zxvf helm.tar.gz && \
    mv linux-amd64/helm /usr/local/bin/helm && \
    rm -rf linux-amd64 helm.tar.gz