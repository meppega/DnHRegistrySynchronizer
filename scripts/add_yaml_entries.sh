#!/bin/bash
# Script to add a Docker image or Helm chart entry to sync-config.yaml
# Function to display usage instructions
#"Usage: $0 <type> [options]"
#""
#"Types:"
#"  image    Add a Docker image entry"
#"  chart    Add a Helm chart entry"
#""
#"Options for 'image':"
#"  --source <source_image>          (e.g., docker.io/library/alpine:3.22)"
#"  --destination <destination_path> (e.g., images/alpine:3.22)"
#""
#"Options for 'chart':"
#"  --repo-name <repo_name>          (e.g., bitnami)"
#"  --repo-url <repo_url>            (e.g., https://charts.bitnami.com/bitnami)"
#"  --chart-name <chart_name>        (e.g., nginx)"
#"  --chart-version <chart_version>  (e.g., 15.14.0)"
#"  --destination <destination_path> (e.g., charts/)"
#""
#"Example: Add a Docker image"
#"  $0 image --source docker.io/library/ubuntu:latest --destination images/ubuntu:latest"
#""
#"Example: Add a Helm chart"
#"  $0 chart --repo-name myrepo --repo-url https://mycharts.com --chart-name myapp --chart-version 1.0.0 --destination mycharts/"
	
set -o errexit
set -o nounset
#set -o pipefail

add_yaml_entries() {
	# Parse the type of entry to remove
	local config_file="$1"
	local entry_type="$2"
	shift 2 # Remove two arguments

	# Check if config file exists
	if [ ! -f "${config_file}" ]; then
		echo "Configuration file ${config_file} not found."
		return 1
	fi

	# Parse the type of entry to add
	local entry_type="$1"
	shift # Remove the first argument (type)

	case "${entry_type}" in
	image)
		local source_image=""
		local dest_path=""
		local version=""

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
				echo "Unknown option: $1"
				return 1
				;;
			esac
			shift
		done

		if [ -z "${source_image}" ] || [ -z "${dest_path}" ]; then
			echo "--source and --destination are required for image entries. Skipping."
			return 1
		fi

		if [ -z "${version}" ]; then
			version="latest"
		fi

		echo "Adding Docker image entry: Source=${source_image}, Destination=${dest_path}, Version=${version}"
		yq e ".dockerImages += [{\"source\": \"${source_image}\", \"destinationPath\": \"${dest_path}\"}, \"version\": \"${version}\"}]" -i "${config_file}"
		echo "Docker image added successfully."
		;;
	chart)
		local repo_name=""
		local repo_url=""
		local chart_name=""
		local chart_version=""
		local dest_path=""
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
				echo "Unknown option: $1. Skipping."
				return 1
				;;
			esac
			shift
		done

		if [ -z "${repo_name}" ] || [ -z "${repo_url}" ] || [ -z "${chart_name}" ] || [ -z "${chart_version}" ] || [ -z "${dest_path}" ]; then
			echo "All chart options (--repo-name, --repo-url, --chart-name, --chart-version, --destination) are required for chart entries. Skipping"
			return 1
		fi

		echo "Adding Helm chart entry: RepoName=${repo_name}, RepoUrl=${repo_url}, ChartName=${chart_name}, ChartVersion=${chart_version}, Destination=${dest_path}"
		yq e ".helmCharts += [{\"repoName\": \"${repo_name}\", \"repoUrl\": \"${repo_url}\", \"chartName\": \"${chart_name}\", \"chartVersion\": \"${chart_version}\", \"destinationPath\": \"${dest_path}\"}]" -i "${config_file}"
		echo "Helm chart added successfully."
		;;
	*)
		return 1
		;;
	esac

	echo "Updated ${config_file}:"
	cat "${config_file}"
}

RUNNING="$(basename $0)"

if [ "$RUNNING" = "add_yaml_entries" ]
then
    add_yaml_entries "$@"
fi