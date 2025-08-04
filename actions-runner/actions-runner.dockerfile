FROM acrrreuwglobal.azurecr.io/actions-runner:2.326.0

#You use this mode when you need zero interaction while installing or upgrading the system via apt
ENV DEBIAN_FRONTEND=noninteractive

#user
USER root

#log dir, possibly wont be used
#RUN mkdir -p /var/log/arisu && chown runner:runner /var/log/arisu

# Set the locale
ENV TZ=Europe/Warsaw \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

RUN apt-get update && apt-get install language-pack-en-base -y && \
    locale-gen en_US.UTF-8 && \
    update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Use apt-fast for parallel downloads
RUN apt-get update -y \
    && apt-get install -y software-properties-common \
    && add-apt-repository -y ppa:git-core/ppa \
    && add-apt-repository -y ppa:apt-fast/stable \
    && apt-get update -y \
    && apt-get install -y apt-fast

# Install basic command-line utilities
RUN apt-fast update \
 && apt-fast install -y --no-install-recommends \
    apt-transport-https \
    build-essential \
    ca-certificates \
    curl \
    dirmngr \
    dnsutils \
    file \
    ftp \
    git \
    gnupg2 \
    htop \
    iproute2 \
    iputils-ping \
    jq \
    libcurl4-openssl-dev \
    locales \
    lsb-release \
    make \
    openssh-client \
    openssl \
    rsync\
    shellcheck \
    software-properties-common \
    ssmtp \
    sudo \
    telnet \
    time \
    unzip \
    wget \
    zip \
    gh \
    tzdata \
    skopeo

# COPY actions-runners/runners-images/pracuj-local-dc-atm-ca.crt /usr/local/share/ca-certificates/
# COPY actions-runners/runners-images/pracuj-local-ca.crt /usr/local/share/ca-certificates/
# RUN update-ca-certificates

#powershell
RUN wget https://github.com/PowerShell/PowerShell/releases/download/v7.4.2/powershell_7.4.2-1.deb_amd64.deb \
    && dpkg -i powershell_7.4.2-1.deb_amd64.deb \
    && apt-get install -f \
    && rm powershell_7.4.2-1.deb_amd64.deb
RUN echo "alias powershell=pwsh" >> ~/.bash_profile

#Install yq via snap
RUN wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 \
    && chmod a+x /usr/local/bin/yq

#nodejs
RUN mkdir -p /etc/apt/keyrings \
  && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
  && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_21.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list \
  && apt-get update \
  && apt-get install -y nodejs

#az cli
RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# Install kubectl
RUN curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl \
    && chmod +x ./kubectl \
    && mv ./kubectl /usr/local/bin/kubectl

# Install Helm
RUN curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Install terraform
RUN wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | tee /usr/share/keyrings/hashicorp-archive-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
    https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list \
    && apt-fast update \
    && apt-fast install -y terraform

# Install tfsec
RUN curl -s https://raw.githubusercontent.com/aquasecurity/tfsec/master/scripts/install_linux.sh | bash

#editorconfig
RUN curl -O -L -C - https://github.com/editorconfig-checker/editorconfig-checker/releases/download/v3.0.1/ec-linux-amd64.tar.gz \
    && tar xzf ec-linux-amd64.tar.gz \
    && mv ./bin/ec-linux-amd64 /usr/local/bin/ec

#sonar scanner
RUN wget https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-6.1.0.4477-linux-x64.zip \
    && unzip sonar-scanner-cli-6.1.0.4477-linux-x64.zip \
    && mv ./sonar-scanner-6.1.0.4477-linux-x64 /opt/sonar-scanner \
    && ln -s /opt/sonar-scanner/bin/sonar-scanner /usr/local/bin/sonar-scanner

# Install dotnet
ENV DOTNET_CLI_TELEMETRY_OPTOUT=1
ENV PATH="${PATH}:/home/runner/.dotnet/tools"

RUN apt-fast install -y dotnet-runtime-8.0

# Install trivy
RUN curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin v0.59.0

# Clean system
RUN apt-fast clean \
    &&  rm -rf /var/lib/apt/lists/* \
    &&  apt-fast autoremove -y

#user
USER runner