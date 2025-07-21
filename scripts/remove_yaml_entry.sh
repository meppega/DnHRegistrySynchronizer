#!/bin/bash
# Script to remove a Docker image or Helm chart entry from sync-config.yaml automatically.
# This script assumes all required parameters are provided via command-line arguments.

set -e

# Use the full path for CONFIG_FILE as mounted in Docker Compose
# If you mount to /app/sync-config.yaml in docker-compose.yml:
CONFIG_FILE="/sync-config.yaml"
# If you mount to /sync-config.yaml in docker-compose.yml:
# CONFIG_FILE="/sync-config.yaml"

# Check if yq is installed
if ! command -v yq &>/dev/null; then
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
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--source)
			SOURCE_IMAGE="$2"
			shift
			;;
		*)
			echo "Warning: Unknown option for image type: $1. Ignoring." >&2
			;;
		esac
		shift
	done

	# Validate SOURCE_IMAGE is not empty
	if [ -z "${SOURCE_IMAGE}" ]; then
		echo "Error: --source is required for image type." >&2
		exit 1
	fi

	echo "Attempting to remove Docker image entry with source: ${SOURCE_IMAGE}"
	# Find the index of the image to remove
	# Corrected yq expression
	IMAGE_INDICES=$(yq e '.dockerImages | to_entries | .[] | select(.value.source == "'"${SOURCE_IMAGE}"'") | .key' "${CONFIG_FILE}")

	if [ -z "${IMAGE_INDICES}" ]; then # Check for empty string, as 'null' is not output by this yq
		echo "Error: Docker image with source '${SOURCE_IMAGE}' not found in ${CONFIG_FILE}." >&2
		exit 1
	else
		echo "Found image(s) at index(es): ${IMAGE_INDICES}. Deleting..."
		# Loop through indices in reverse order
		yq e '.dockerImages = (.dockerImages | .[] | select(.source != "'"${SOURCE_IMAGE}"'"))' -i "${CONFIG_FILE}"
		# for INDEX in ${IMAGE_INDICES}; do
		#     yq e "del(.dockerImages[${INDEX}])" -i "${CONFIG_FILE}"
		#     echo "Deleted Docker image at index ${INDEX}."
		# done

		# echo "Cleaning up null entries in dockerImages array..."
		# yq e '.dockerImages = (.dockerImages | .[] | select(. != null))' -i "${CONFIG_FILE}"
		echo "Docker image(s) removed and array compacted successfully."
	fi
	;;
chart)
	# Initialize variables
	CHART_NAME=""
	CHART_VERSION=""

	# Parse arguments for chart type
	while [[ $# -gt 0 ]]; do
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
			echo "Warning: Unknown option for chart type: $1. Ignoring." >&2
			;;
		esac
		shift
	done

	# Validate CHART_NAME and CHART_VERSION are not empty
	if [ -z "${CHART_NAME}" ] || [ -z "${CHART_VERSION}" ]; then
		echo "Error: --chart-name and --chart-version are required for chart type." >&2
		exit 1
	fi

	echo "Attempting to remove Helm chart entry: ChartName=${CHART_NAME}, ChartVersion=${CHART_VERSION}"
	# Find the index of the chart to remove
	# Corrected yq expression
	CHART_INDICES=$(yq e '.helmCharts | to_entries | .[] | select(.value.chartName == "'"${CHART_NAME}"'" and .value.chartVersion == "'"${CHART_VERSION}"'") | .key' "${CONFIG_FILE}")

	if [ -z "${CHART_INDICES}" ]; then # Check for empty string
		echo "Error: Helm chart with name '${CHART_NAME}' and version '${CHART_VERSION}' not found in ${CONFIG_FILE}." >&2
		exit 1
	else
		echo "Found chart(s) at index(es): ${CHART_INDICES}. Deleting..."
		# Loop through indices in reverse order
		# for INDEX in ${CHART_INDICES}; do
		#     yq e "del(.helmCharts[${INDEX}])" -i "${CONFIG_FILE}"
		#     echo "Deleted Helm chart at index ${INDEX}."
		# done
		# yq e '.helmCharts = (.helmCharts | .[] | select(.chartName != "'"${CHART_NAME}"'" or .chartVersion != "'"${CHART_VERSION}"'"))' -i "${CONFIG_FILE}"
		yq e '.helmCharts = (.helmCharts | .[] | select(not (.chartName == "'"${CHART_NAME}"'" and .chartVersion == "'"${CHART_VERSION}"'")))' -i "${CONFIG_FILE}"

		# echo "Cleaning up null entries in helmCharts array..."
		# yq e '.helmCharts = (.helmCharts | .[] | select(. != null))' -i "${CONFIG_FILE}"
		echo "Helm chart(s) removed and array compacted successfully."
	fi
	;;
*)
	echo "Error: Invalid entry type '${ENTRY_TYPE}'. Must be 'image' or 'chart'." >&2
	exit 1
	;;
esac

echo "Updated ${CONFIG_FILE}:"
cat "${CONFIG_FILE}"
