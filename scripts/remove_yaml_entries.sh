#!/bin/bash

# Script to remove a Docker image or Helm chart entry from sync-config.yaml automatically.
# This script assumes all required parameters are provided via command-line arguments.

set -o errexit
set -o nounset
#set -o pipefail

remove_yaml_entries() {
	# Parse the type of entry to remove
	local config_file="$1"
	local entry_type="$2"
	shift 2 # Remove two arguments

	# Check if yq is installed
	# if ! command -v yq &>/dev/null; then
	# 	echo "Error: yq is not installed. Please install it to use this script."
	# 	exit 1
	# fi

	# Check if config file exists
	if [ ! -f "${config_file}" ]; then
		echo "Error: Configuration file ${config_file} not found."
		exit 1
	fi

	case "${entry_type}" in
	image)
		# Initialize variables
		local img_reg_path=""
		local img_version=""
		local image_indices

		# Parse arguments for image type
		while [[ $# -gt 0 ]]; do
			case "$1" in
			--registry-path)
				img_reg_path="$2"
				shift
				;;
			--version)
				img_version="$2"
				shift
				;;
			*)
				echo "Warning: Unknown option for image type: $2. Ignoring." >&2
				;;
			esac
			shift
		done

		# Validate source_image is not empty
		if [ -z "${img_reg_path}" ] || [ -z "${img_version}" ]; then
			echo "Error: --registry-path and --version are required for image type." >&2
			exit 1
		fi

		echo "Attempting to remove Docker image entry with source: ${img_reg_path}"
		# Find the index of the image to remove
		# Corrected yq expression
		image_indices=$(yq e '.dockerImages | to_entries | .[] | select(.value.destinationPath == "'"${img_reg_path}"'" and .value.version == "'"${img_version}"'") | .key' "${config_file}")

		if [ -z "${image_indices}" ]; then # Check for empty string, as 'null' is not output by this yq
			echo "Error: Docker image with source '${img_reg_path}':'${img_version}' not found in ${config_file}." >&2
			exit 1
		else
			echo "Found image(s) at index(es): ${image_indices}. Deleting..."
			# Loop through indices in reverse order
			yq e '.dockerImages = (.dockerImages | .[] | select(.destinationPath != "'"${img_reg_path}"'" or .version != "'"${img_version}"'"))' -i "${config_file}"
			# for INDEX in ${image_indices}; do
			#     yq e "del(.dockerImages[${INDEX}])" -i "${config_file}"
			#     echo "Deleted Docker image at index ${INDEX}."
			# done

			# echo "Cleaning up null entries in dockerImages array..."
			# yq e '.dockerImages = (.dockerImages | .[] | select(. != null))' -i "${config_file}"
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
				echo "Warning: Unknown option for chart type: $2. Ignoring." >&2
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
		chart_indices=$(yq e '.helmCharts | to_entries | .[] | select(.value.chartName == "'"${chart_name}"'" and .value.chartVersion == "'"${chart_version}"'") | .key' "${config_file}")

		if [ -z "${chart_indices}" ]; then # Check for empty string
			echo "Error: Helm chart with name '${chart_name}' and version '${chart_version}' not found in ${config_file}." >&2
			exit 1
		else
			echo "Found chart(s) at index(es): ${chart_indices}. Deleting..."
			# Loop through indices in reverse order
			# for INDEX in ${chart_indices}; do
			#     yq e "del(.helmCharts[${INDEX}])" -i "${config_file}"
			#     echo "Deleted Helm chart at index ${INDEX}."
			# done
			# yq e '.helmCharts = (.helmCharts | .[] | select(.chartName != "'"${chart_name}"'" or .chartVersion != "'"${chart_version}"'"))' -i "${config_file}"
			yq e '.helmCharts = (.helmCharts | .[] | select(not (.chartName != "'"${chart_name}"'" or .chartVersion != "'"${chart_version}"'")))' -i "${config_file}"

			# echo "Cleaning up null entries in helmCharts array..."
			# yq e '.helmCharts = (.helmCharts | .[] | select(. != null))' -i "${config_file}"
			echo "Helm chart(s) removed and array compacted successfully."
		fi
		;;
	*)
		echo "Error: Invalid entry type '${entry_type}'. Must be 'image' or 'chart'." >&2
		exit 1
		;;
	esac

	echo "Updated ${config_file}:"
	cat "${config_file}"
}

RUNNING="$(basename $0)"

if [[ "$RUNNING" == "remove_yaml_entries" ]]
then
  remove_yaml_entries "$@"
fi