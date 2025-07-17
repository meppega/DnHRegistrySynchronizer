#!/bin/bash
# Script to remove a Docker image or Helm chart entry from sync-config.yaml

set -e

CONFIG_FILE="/sync-config.yaml"

# Function to display usage instructions
usage() {
    echo "Usage: $0 <type> [options]"
    echo ""
    echo "Types:"
    echo "  image    Remove a Docker image entry"
    echo "  chart    Remove a Helm chart entry"
    echo ""
    echo "Options for 'image':"
    echo "  --source <source_image> (required for removal, e.g., docker.io/library/alpine:3.22)"
    echo ""
    echo "Options for 'chart':"
    echo "  --chart-name <chart_name>        (required for removal, e.g., nginx)"
    echo "  --chart-version <chart_version>  (required for removal, e.g., 15.14.0)"
    echo ""
    echo "Example: Remove a Docker image"
    echo "  $0 image --source docker.io/library/alpine:3.22"
    echo ""
    echo "Example: Remove a Helm chart"
    echo "  $0 chart --chart-name nginx --chart-version 15.14.0"
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

# Parse the type of entry to remove
ENTRY_TYPE="$1"
shift # Remove the first argument (type)

case "${ENTRY_TYPE}" in
    image)
        SOURCE_IMAGE=""
        while [[ "$#" -gt 0 ]]; do
            case "$1" in
                --source)
                    SOURCE_IMAGE="$2"
                    shift
                    ;;
                *)
                    echo "Unknown option: $1"
                    usage
                    ;;
            esac
            shift
        done

        if [ -z "${SOURCE_IMAGE}" ]; then
            echo "Error: --source is required for removing image entries."
            usage
        fi

        echo "Attempting to remove Docker image entry with source: ${SOURCE_IMAGE}"
        # Find the index of the image to remove
        INDEX=$(yq e '.dockerImages | map(.source == "'"${SOURCE_IMAGE}"'") | index(true)' "${CONFIG_FILE}")

        if [ "${INDEX}" = "null" ]; then
            echo "Error: Docker image with source '${SOURCE_IMAGE}' not found in ${CONFIG_FILE}."
        else
            yq e "del(.dockerImages[${INDEX}])" -i "${CONFIG_FILE}"
            echo "Docker image removed successfully."
        fi
        ;;
    chart)
        CHART_NAME=""
        CHART_VERSION=""
        while [[ "$#" -gt 0 ]]; do
            case "$1" in
                --chart-name)
                    CHART_NAME="$2"
                    shift
                    ;;
                --chart-version)
                    CHART_VERSION="$2"
                    shift
                    ;;
                *)
                    echo "Unknown option: $1"
                    usage
                    ;;
            esac
            shift
        done

        if [ -z "${CHART_NAME}" ] || [ -z "${CHART_VERSION}" ]; then
            echo "Error: --chart-name and --chart-version are required for removing chart entries."
            usage
        fi

        echo "Attempting to remove Helm chart entry: ChartName=${CHART_NAME}, ChartVersion=${CHART_VERSION}"
        # Find the index of the chart to remove
        INDEX=$(yq e '.helmCharts | map(.chartName == "'"${CHART_NAME}"'" and .chartVersion == "'"${CHART_VERSION}"'") | index(true)' "${CONFIG_FILE}")

        if [ "${INDEX}" = "null" ]; then
            echo "Error: Helm chart with name '${CHART_NAME}' and version '${CHART_VERSION}' not found in ${CONFIG_FILE}."
        else
            yq e "del(.helmCharts[${INDEX}])" -i "${CONFIG_FILE}"
            echo "Helm chart removed successfully."
        fi
        ;;
    *)
        usage
        ;;
esac

echo "Updated ${CONFIG_FILE}:"
cat "${CONFIG_FILE}"
