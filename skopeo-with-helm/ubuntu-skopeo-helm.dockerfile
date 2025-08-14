FROM ubuntu:24.04

ARG HELM_VERSION=3.14.4

USER root

# Set the locale
ENV TZ=Europe/Warsaw \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

# Use apt-fast for parallel downloads
RUN apt-get update -y \
    && apt-get install -y software-properties-common \
    && add-apt-repository -y ppa:git-core/ppa \
    && add-apt-repository -y ppa:apt-fast/stable \
    && apt-get update -y \
    && apt-get install -y apt-fast

RUN apt-fast update \
    && apt-fast install -y --no-install-recommends \
    yq \
    skopeo \
    wget \
    curl \
    util-linux \
    jq

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