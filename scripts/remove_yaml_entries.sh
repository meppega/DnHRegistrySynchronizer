#!/bin/bash

# remove_yaml_entries: Removes a Docker image or Helm chart entry from a YAML configuration file.
# Arguments:
#   $1: Path to the YAML config file.
#   $2: Type of entry to remove ('image' or 'chart').
#   Remaining arguments are specific to the entry type:
#     For 'image': --registry-path <path> --version <version>
#     For 'chart': --chart-name <name> --chart-version <version>
#
# This script uses common.sh's `log_info`, `log_warning`, `log_error`, and `file_exists_readable`.

set -o errexit
set -o nounset
set -o pipefail

source "$(dirname "${BASH_SOURCE[0]}")/libs/common.sh"

remove_yaml_entries() {
	local config_file="$1"
	local entry_type="$2"
	shift 2 # Remove the first two arguments (config_file and entry_type)

	log_info "Attempting to remove entry of type '${entry_type}' from config: ${config_file}" "remove_yaml_entries"

	if ! file_exists_readable "$config_file"; then
		log_error "Configuration file '${config_file}' not found or not readable. Skipping removal." "remove_yaml_entries"
		return 1 # Indicate an error
	fi

	case "${entry_type}" in
	image)
		local img_reg_path=""
		local img_version=""

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
				log_warning "Unknown option for image type: '$1'. Ignoring." "remove_yaml_entries"
				;;
			esac
			shift
		done

		# Validate required arguments for image type
		if [[ -z ${img_reg_path} || -z ${img_version} ]]; then
			log_error "--registry-path and --version are required for 'image' type. Skipping deletion." "remove_yaml_entries"
			return 1 # Indicate an error
		fi

		log_info "Searching for Docker image entry with path: '${img_reg_path}' and version: '${img_version}'." "remove_yaml_entries"

		# Find the index of the image to remove.
		# This yq expression identifies entries that match both destinationPath and version.
		local image_indices
		image_indices=$(yq e '.dockerImages | to_entries | .[] | select(.value.destinationPath == "'"${img_reg_path}"'" and .value.version == "'"${img_version}"'") | .key' "${config_file}")

		if [[ -z ${image_indices} ]]; then
			log_warning "Docker image with path '${img_reg_path}' and version '${img_version}' not found in '${config_file}'. Skipping deletion." "remove_yaml_entries"
			return 0 # Not found is not an error for removal, just means nothing to do.
		else
			log_info "Found Docker image(s) at index(es): ${image_indices}. Deleting..." "remove_yaml_entries"
			# Use yq to filter out matching entries, effectively removing them and re-indexing the array.
			yq e '.dockerImages |= (map(select(.destinationPath != "'"${img_reg_path}"'" or .version != "'"${img_version}"'")) // [])' -i "${config_file}"
			log_info "Docker image entry/entries removed and array compacted successfully." "remove_yaml_entries"
		fi
		;;

	chart)
		local chart_name=""
		local chart_version=""

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
				log_warning "Unknown option for chart type: '$1'. Ignoring." "remove_yaml_entries"
				;;
			esac
			shift
		done

		# Validate required arguments for chart type
		if [[ -z ${chart_name} || -z ${chart_version} ]]; then
			log_error "--chart-name and --chart-version are required for 'chart' type. Skipping deletion." "remove_yaml_entries"
			return 1 # Indicate an error
		fi

		log_info "Searching for Helm chart entry with name: '${chart_name}' and version: '${chart_version}'." "remove_yaml_entries"

		# Find the index of the chart to remove.
		# This yq expression identifies entries that match both chartName and chartVersion.
		local chart_indices
		chart_indices=$(yq e '.helmCharts | to_entries | .[] | select(.value.chartName == "'"${chart_name}"'" and .value.chartVersion == "'"${chart_version}"'") | .key' "${config_file}")

		if [[ -z ${chart_indices} ]]; then
			log_warning "Helm chart with name '${chart_name}' and version '${chart_version}' not found in '${config_file}'. Skipping deletion." "remove_yaml_entries"
			return 0 # Not found is not an error for removal, just means nothing to do.
		else
			log_info "Found Helm chart(s) at index(es): ${chart_indices}. Deleting..." "remove_yaml_entries"
			# Use yq to filter out matching entries, effectively removing them and re-indexing the array.
			yq e '.helmCharts |= (map(select(.chartName != "'"${chart_name}"'" or .chartVersion != "'"${chart_version}"'")) // [])' -i "${config_file}"
			log_info "Helm chart entry/entries removed and array compacted successfully." "remove_yaml_entries"
		fi
		;;

	*)
		log_error "Invalid entry type '${entry_type}'. Must be 'image' or 'chart'. Skipping." "remove_yaml_entries"
		return 1 # Indicate an error
		;;
	esac

	log_info "Finished attempting to remove entry. Review ${config_file} for changes." "remove_yaml_entries"
	# The original script commented out 'cat "${config_file}"', so we won't print the file content by default.
}

# # This conditional block ensures the function is called only swhen the script is executed directly.
# if [[ "$(basename "$0")" == "remove_yaml_entries.sh" || "$(basename "$0")" == "remove_yaml_entries" ]]; then
# 	remove_yaml_entries "$@"
# fi
