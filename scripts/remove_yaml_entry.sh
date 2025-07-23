#!/bin/bash
# Script to remove a Docker image or Helm chart entry from sync-config.yaml automatically.
# This script assumes all required parameters are provided via command-line arguments.

set -o errexit
set -o nounset
#set -o pipefail

# Use the full path for CONFIG_FILE as mounted in Docker Compose
# If you mount to /app/sync-config.yaml in docker-compose.yml:
readonly CONFIG_FILE="/sync-config.yaml"
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
local entry_type="$1"
shift # Remove the first argument (type)

case "${entry_type}" in
image)
	# Initialize variables
	local source_image=""

	# Parse arguments for image type
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--source)
			source_image="$2"
			shift
			;;
		*)
			echo "Warning: Unknown option for image type: $1. Ignoring." >&2
			;;
		esac
		shift
	done

	# Validate source_image is not empty
	if [ -z "${source_image}" ]; then
		echo "Error: --source is required for image type." >&2
		exit 1
	fi

	echo "Attempting to remove Docker image entry with source: ${source_image}"
	# Find the index of the image to remove
	# Corrected yq expression
	IMAGE_INDICES=$(yq e '.dockerImages | to_entries | .[] | select(.value.source == "'"${source_image}"'") | .key' "${CONFIG_FILE}")

	if [ -z "${IMAGE_INDICES}" ]; then # Check for empty string, as 'null' is not output by this yq
		echo "Error: Docker image with source '${source_image}' not found in ${CONFIG_FILE}." >&2
		exit 1
	else
		echo "Found image(s) at index(es): ${IMAGE_INDICES}. Deleting..."
		# Loop through indices in reverse order
		yq e '.dockerImages = (.dockerImages | .[] | select(.source != "'"${source_image}"'"))' -i "${CONFIG_FILE}"
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
	local chart_name=""
	local chart_version=""
	local chart_indices

	# Parse arguments for chart type
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--chart-name)
			chart_name="$2"
			shift
			;;
		--chart-version)
			chart_version="$2"
			shift
			;;
		*)
			echo "Warning: Unknown option for chart type: $1. Ignoring." >&2
			;;
		esac
		shift
	done

	# Validate chart_name and chart_version are not empty
	if [ -z "${chart_name}" ] || [ -z "${chart_version}" ]; then
		echo "Error: --chart-name and --chart-version are required for chart type." >&2
		exit 1
	fi

	echo "Attempting to remove Helm chart entry: ChartName=${chart_name}, ChartVersion=${chart_version}"
	# Find the index of the chart to remove
	# Corrected yq expression
	chart_indices=$(yq e '.helmCharts | to_entries | .[] | select(.value.chartName == "'"${chart_name}"'" and .value.chartVersion == "'"${chart_version}"'") | .key' "${CONFIG_FILE}")

	if [ -z "${chart_indices}" ]; then # Check for empty string
		echo "Error: Helm chart with name '${chart_name}' and version '${chart_version}' not found in ${CONFIG_FILE}." >&2
		exit 1
	else
		echo "Found chart(s) at index(es): ${chart_indices}. Deleting..."
		# Loop through indices in reverse order
		# for INDEX in ${chart_indices}; do
		#     yq e "del(.helmCharts[${INDEX}])" -i "${CONFIG_FILE}"
		#     echo "Deleted Helm chart at index ${INDEX}."
		# done
		# yq e '.helmCharts = (.helmCharts | .[] | select(.chartName != "'"${chart_name}"'" or .chartVersion != "'"${chart_version}"'"))' -i "${CONFIG_FILE}"
		yq e '.helmCharts = (.helmCharts | .[] | select(not (.chartName == "'"${chart_name}"'" and .chartVersion == "'"${chart_version}"'")))' -i "${CONFIG_FILE}"

		# echo "Cleaning up null entries in helmCharts array..."
		# yq e '.helmCharts = (.helmCharts | .[] | select(. != null))' -i "${CONFIG_FILE}"
		echo "Helm chart(s) removed and array compacted successfully."
	fi
	;;
*)
	echo "Error: Invalid entry type '${entry_type}'. Must be 'image' or 'chart'." >&2
	exit 1
	;;
esac

echo "Updated ${CONFIG_FILE}:"
cat "${CONFIG_FILE}"
