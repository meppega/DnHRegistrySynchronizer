#!/bin/bash
# Script to remove a Docker image or Helm chart entry from sync-config.yaml automatically.
# This script assumes all required parameters are provided via command-line arguments.

set -e

CONFIG_FILE="/sync-config.yaml"

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
        # Initialize variables
        SOURCE_IMAGE=""

        # Parse arguments for image type
        while [[ "$#" -gt 0 ]]; do
            case "$1" in
                --source)
                    SOURCE_IMAGE="$2"
                    shift
                    ;;
                *)
                    # Unknown options will be ignored or can be handled as an error if strictness is needed
                    echo "Warning: Unknown option for image type: $1. Ignoring." >&2
                    ;;
            esac
            shift
        done

        # No user interaction checks; assume arguments are valid and present
        echo "Attempting to remove Docker image entry with source: ${SOURCE_IMAGE}"
        # Find the index of the image to remove
        INDEX=$(yq e '.dockerImages | map(.source == "'"${SOURCE_IMAGE}"'") | index(true)' "${CONFIG_FILE}")

        if [ "${INDEX}" = "null" ]; then
            echo "Error: Docker image with source '${SOURCE_IMAGE}' not found in ${CONFIG_FILE}." >&2
            exit 1 # Exit with error if not found
        else
            yq e "del(.dockerImages[${INDEX}])" -i "${CONFIG_FILE}"
            echo "Docker image removed successfully."
        fi
        ;;
    chart)
        # Initialize variables
        CHART_NAME=""
        CHART_VERSION=""

        # Parse arguments for chart type
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
                    # Unknown options will be ignored or can be handled as an error if strictness is needed
                    echo "Warning: Unknown option for chart type: $1. Ignoring." >&2
                    ;;
            esac
            shift
        done

        # No user interaction checks; assume arguments are valid and present
        echo "Attempting to remove Helm chart entry: ChartName=${CHART_NAME}, ChartVersion=${CHART_VERSION}"
        # Find the index of the chart to remove
        INDEX=$(yq e '.helmCharts | map(.chartName == "'"${CHART_NAME}"'" and .chartVersion == "'"${CHART_VERSION}"'") | index(true)' "${CONFIG_FILE}")

        if [ "${INDEX}" = "null" ]; then
            echo "Error: Helm chart with name '${CHART_NAME}' and version '${CHART_VERSION}' not found in ${CONFIG_FILE}." >&2
            exit 1 # Exit with error if not found
        else
            yq e "del(.helmCharts[${INDEX}])" -i "${CONFIG_FILE}"
            echo "Helm chart removed successfully."
        fi
        ;;
    *)
        echo "Error: Invalid entry type '${ENTRY_TYPE}'. Must be 'image' or 'chart'." >&2
        exit 1
        ;;
esac

echo "Updated ${CONFIG_FILE}:"
cat "${CONFIG_FILE}"
