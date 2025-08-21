#!/bin/bash

# add_yaml_entries: Adds a Docker image or Helm chart entry to a YAML configuration file.
# Arguments:
#   $1: Path to the YAML config file.
#   $2: Type of entry to add ('image' or 'chart').
#   Remaining arguments are specific to the entry type:
#     For 'image': --source <source_image> --destination <destination_path> [--version <version>]
#     For 'chart': --repo-name <repo_name> --repo-url <repo_url> --chart-name <chart_name> --chart-version <chart_version> --destination <destination_path>
#
# This script uses common.sh's `log_info`, `log_warning`, `log_error`, and `file_exists_readable`.

set -o errexit
set -o nounset
set -o pipefail

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/libs/common.sh"

add_yaml_entries() {
	local config_file="$1"
	local entry_type="$2"
	shift 2 # Remove the first two arguments (config_file and entry_type)

	log_info "Attempting to add entry of type '${entry_type}' to config: ${config_file}" "add_yaml_entries"

	if ! file_exists_readable "$config_file"; then
		log_error "Configuration file '${config_file}' not found or not readable. Skipping addition." "add_yaml_entries"
		return 1 # Indicate an error
	fi

	case "${entry_type}" in
	image)
		local source_image=""
		local dest_path=""
		local version=""

		# Parse arguments for image type
		while [[ $# -gt 0 ]]; do
			case "$1" in
			--source)
				source_image="$2"
				shift
				;;
			--destination)
				dest_path="$2"
				shift
				;;
			--version)
				version="$2"
				shift
				;;
			*)
				log_warning "Unknown option for image type: '$1'. Ignoring and continuing with other options." "add_yaml_entries"
				;;
			esac
			shift
		done

		# Validate required arguments for image type
		if [[ -z ${source_image} || -z ${dest_path} ]]; then
			log_error "--source and --destination are required for 'image' type. Skipping addition." "add_yaml_entries"
			return 1 # Indicate an error
		fi

		# Set default version if not provided
		if [[ -z ${version} ]]; then
			version="latest"
			log_info "Version not provided for image. Defaulting to '${version}'." "add_yaml_entries"
		fi

		log_info "Adding Docker image entry: Source=${source_image}, Destination=${dest_path}, Version=${version}" "add_yaml_entries"
		# Add the new entry to the dockerImages array, creating it if it doesn't exist.
		yq e ".dockerImages = (.dockerImages // []) + [{\"source\": \"${source_image}\", \"destinationPath\": \"${dest_path}\", \"version\": \"${version}\"}]" -i "${config_file}"
		log_info "Docker image added successfully." "add_yaml_entries"
		;;

	chart)
		local repo_name=""
		local repo_url=""
		local chart_name=""
		local chart_version=""
		local dest_path=""

		# Parse arguments for chart type
		while [[ $# -gt 0 ]]; do
			case "$1" in
			--repo-name)
				repo_name="$2"
				shift
				;;
			--repo-url)
				repo_url="$2"
				shift
				;;
			--chart-name)
				chart_name="$2"
				shift
				;;
			--chart-version)
				chart_version="$2"
				shift
				;;
			--destination)
				dest_path="$2"
				shift
				;;
			*)
				log_warning "Unknown option for chart type: '$1'. Ignoring and continuing with other options." "add_yaml_entries"
				;;
			esac
			shift
		done

		# Validate all required arguments for chart type
		if [[ -z ${repo_name} || -z ${repo_url} || -z ${chart_name} || -z ${chart_version} || -z ${dest_path} ]]; then
			log_error "All chart options (--repo-name, --repo-url, --chart-name, --chart-version, --destination) are required for 'chart' type. Skipping addition." "add_yaml_entries"
			return 1 # Indicate an error
		fi

		log_info "Adding Helm chart entry: RepoName=${repo_name}, RepoUrl=${repo_url}, ChartName=${chart_name}, ChartVersion=${chart_version}, Destination=${dest_path}" "add_yaml_entries"
		# Add the new entry to the helmCharts array, creating it if it doesn't exist.
		yq e ".helmCharts = (.helmCharts // []) + [{\"repoName\": \"${repo_name}\", \"repoUrl\": \"${repo_url}\", \"chartName\": \"${chart_name}\", \"chartVersion\": \"${chart_version}\", \"destinationPath\": \"${dest_path}\"}]" -i "${config_file}"
		log_info "Helm chart added successfully." "add_yaml_entries"
		;;

	*)
		log_error "Invalid entry type '${entry_type}'. Must be 'image' or 'chart'. Skipping." "add_yaml_entries"
		return 1 # Indicate an error
		;;
	esac

	log_info "Finished attempting to add entry. Review ${config_file} for changes." "add_yaml_entries"
	# The original script commented out 'cat "${config_file}"', so we won't print the file content by default.
}

# # This conditional block ensures the function is called only when the script is executed directly.
# if [[ "$(basename "$0")" == "add_yaml_entries.sh" || "$(basename "$0")" == "add_yaml_entries" ]]; then
# 	add_yaml_entries "$@"
# fi
