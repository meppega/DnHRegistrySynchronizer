#!/bin/bash
# Script to add a Docker image or Helm chart entry to sync-config.yaml

set -e

CONFIG_FILE="/sync-config.yaml"

# Function to display usage instructions
usage() {
    echo "Usage: $0 <type> [options]"
    echo ""
    echo "Types:"
    echo "  image    Add a Docker image entry"
    echo "  chart    Add a Helm chart entry"
    echo ""
    echo "Options for 'image':"
    echo "  --source <source_image>          (e.g., docker.io/library/alpine:3.22)"
    echo "  --destination <destination_path> (e.g., images/alpine:3.22)"
    echo ""
    echo "Options for 'chart':"
    echo "  --repo-name <repo_name>          (e.g., bitnami)"
    echo "  --repo-url <repo_url>            (e.g., https://charts.bitnami.com/bitnami)"
    echo "  --chart-name <chart_name>        (e.g., nginx)"
    echo "  --chart-version <chart_version>  (e.g., 15.14.0)"
    echo "  --destination <destination_path> (e.g., charts/)"
    echo ""
    echo "Example: Add a Docker image"
    echo "  $0 image --source docker.io/library/ubuntu:latest --destination images/ubuntu:latest"
    echo ""
    echo "Example: Add a Helm chart"
    echo "  $0 chart --repo-name myrepo --repo-url https://mycharts.com --chart-name myapp --chart-version 1.0.0 --destination mycharts/"
    exit 1
}

# Check if yq is installed
if ! command -v yq &> /dev/null; then
    echo "Error: yq is not installed. Please install it to use this script."
    exit 1
fi

# Check if config file exists
if [ ! -f "${CONFIG_FILE}" ]; then
    echo "Error: Configuration file ${CONFIG_FILE} not found."
    exit 1
fi

# Parse the type of entry to add
ENTRY_TYPE="$1"
shift # Remove the first argument (type)

case "${ENTRY_TYPE}" in
    image)
        SOURCE_IMAGE=""
        DEST_PATH=""
        while [[ "$#" -gt 0 ]]; do
            case "$1" in
                --source)
                    SOURCE_IMAGE="$2"
                    shift
                    ;;
                --destination)
                    DEST_PATH="$2"
                    shift
                    ;;
                *)
                    echo "Unknown option: $1"
                    usage
                    ;;
            esac
            shift
        done

        if [ -z "${SOURCE_IMAGE}" ] || [ -z "${DEST_PATH}" ]; then
            echo "Error: --source and --destination are required for image entries."
            usage
        fi

        echo "Adding Docker image entry: Source=${SOURCE_IMAGE}, Destination=${DEST_PATH}"
        yq e ".dockerImages += [{\"source\": \"${SOURCE_IMAGE}\", \"destinationPath\": \"${DEST_PATH}\"}]" -i "${CONFIG_FILE}"
        echo "Docker image added successfully."
        ;;
    chart)
        REPO_NAME=""
        REPO_URL=""
        CHART_NAME=""
        CHART_VERSION=""
        DEST_PATH=""
        while [[ "$#" -gt 0 ]]; do
            case "$1" in
                --repo-name)
                    REPO_NAME="$2"
                    shift
                    ;;
                --repo-url)
                    REPO_URL="$2"
                    shift
                    ;;
                --chart-name)
                    CHART_NAME="$2"
                    shift
                    ;;
                --chart-version)
                    CHART_VERSION="$2"
                    shift
                    ;;
                --destination)
                    DEST_PATH="$2"
                    shift
                    ;;
                *)
                    echo "Unknown option: $1"
                    usage
                    ;;
            esac
            shift
        done

        if [ -z "${REPO_NAME}" ] || [ -z "${REPO_URL}" ] || [ -z "${CHART_NAME}" ] || [ -z "${CHART_VERSION}" ] || [ -z "${DEST_PATH}" ]; then
            echo "Error: All chart options (--repo-name, --repo-url, --chart-name, --chart-version, --destination) are required for chart entries."
            usage
        fi

        echo "Adding Helm chart entry: RepoName=${REPO_NAME}, RepoUrl=${REPO_URL}, ChartName=${CHART_NAME}, ChartVersion=${CHART_VERSION}, Destination=${DEST_PATH}"
        yq e ".helmCharts += [{\"repoName\": \"${REPO_NAME}\", \"repoUrl\": \"${REPO_URL}\", \"chartName\": \"${CHART_NAME}\", \"chartVersion\": \"${CHART_VERSION}\", \"destinationPath\": \"${DEST_PATH}\"}]" -i "${CONFIG_FILE}"
        echo "Helm chart added successfully."
        ;;
    *)
        usage
        ;;
esac

echo "Updated ${CONFIG_FILE}:"
cat "${CONFIG_FILE}"
