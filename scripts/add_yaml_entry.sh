#!/bin/bash
# Script to add a Docker image or Helm chart entry to sync-config.yaml

set -o errexit
set -o nounset
#set -o pipefail

readonly CONFIG_FILE="/sync-config.yaml"

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
if ! command -v yq &>/dev/null; then
	echo "Error: yq is not installed. Please install it to use this script."
	exit 1
fi

# Check if config file exists
if [ ! -f "${CONFIG_FILE}" ]; then
	echo "Error: Configuration file ${CONFIG_FILE} not found."
	exit 1
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
			usage
			;;
		esac
		shift
	done

	if [ -z "${source_image}" ] || [ -z "${dest_path}" ]; then
		echo "Error: --source and --destination are required for image entries."
		usage
		exit 1
	fi

	if [ -z "${version}" ]; then
		version="latest"
	fi

	echo "Adding Docker image entry: Source=${source_image}, Destination=${dest_path}, Version=${latest}"
	yq e ".dockerImages += [{\"source\": \"${source_image}\", \"destinationPath\": \"${dest_path}\"}, \"version\": \"${version}\"}]" -i "${CONFIG_FILE}"
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
			echo "Unknown option: $1"
			usage
			;;
		esac
		shift
	done

	if [ -z "${repo_name}" ] || [ -z "${repo_url}" ] || [ -z "${chart_name}" ] || [ -z "${chart_version}" ] || [ -z "${dest_path}" ]; then
		echo "Error: All chart options (--repo-name, --repo-url, --chart-name, --chart-version, --destination) are required for chart entries."
		usage
	fi

	echo "Adding Helm chart entry: RepoName=${repo_name}, RepoUrl=${repo_url}, ChartName=${chart_name}, ChartVersion=${chart_version}, Destination=${dest_path}"
	yq e ".helmCharts += [{\"repoName\": \"${repo_name}\", \"repoUrl\": \"${repo_url}\", \"chartName\": \"${chart_name}\", \"chartVersion\": \"${chart_version}\", \"destinationPath\": \"${dest_path}\"}]" -i "${CONFIG_FILE}"
	echo "Helm chart added successfully."
	;;
*)
	usage
	;;
esac

echo "Updated ${CONFIG_FILE}:"
cat "${CONFIG_FILE}"
