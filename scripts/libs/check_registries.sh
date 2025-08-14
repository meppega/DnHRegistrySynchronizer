#!/bin/bash

# check_registry_images: Checks a YAML configuration file against an OCI/Docker registry
# to compare expected images/charts with actual images present in the registry.
#
# Arguments:
#   $1: Path to the YAML config file.
#
# This script uses common.sh's `log_info`, `log_warning`, `log_error`, `die`, and `file_exists_readable`.

set -o errexit
set -o nounset
set -o pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

check_registry_images() {
	local config_file="$1"
	log_info "Starting registry image check against config: ${config_file}" "check_registry_images"

	if ! file_exists_readable "$config_file"; then
		die "Configuration file '${config_file}' not found or not readable. Cannot proceed with check."
	fi

	# Retrieve registry credentials from the config file
	local REGISTRY_URL
	REGISTRY_URL=$(yq '.registry.url' "${config_file}") || die "Failed to get registry URL from config file: ${config_file}."
	REGISTRY_URL=$(echo "${REGISTRY_URL}" | sed -e 's/^"//' -e 's/"$//')

	local REGISTRY_USER
	REGISTRY_USER=$(yq '.registry.user' "${config_file}") || log_warning "Registry user not found in config. Proceeding without authentication for public registries." "check_registry_images"

	local REGISTRY_PASS
	REGISTRY_PASS=$(yq '.registry.password' "${config_file}") || log_warning "Registry password not found in config. Proceeding without authentication for public registries." "check_registry_images"

	declare -A expected_images # Stores images/charts listed in sync-config.yaml
	declare -A existing_images # Stores images/charts actually found in the registry

	# --- 1. Get expected images/charts from sync-config.yaml ---
	log_info "Reading expected Docker images and Helm charts from ${config_file}..." "check_registry_images"

	# Process Docker images
	local image_count
	image_count=$(yq '.dockerImages | length' "${config_file}") || log_warning "No 'dockerImages' section found or invalid in ${config_file}." "check_registry_images"
	image_count=${image_count:-0} # Default to 0 if yq returns null/empty

	if [[ $image_count -gt 0 ]]; then
		for i in $(seq 0 $((image_count - 1))); do
			local source_image
			source_image=$(yq ".dockerImages[$i].source" "${config_file}") || log_error "Failed to get source for dockerImages[$i]." "check_registry_images"
			source_image=$(echo "${source_image}" | sed -e 's/^"//' -e 's/"$//')
			source_image=${source_image##*/}
			local dest_path
			dest_path=$(yq ".dockerImages[$i].destinationPath" "${config_file}") || log_error "Failed to get destinationPath for dockerImages[$i]." "check_registry_images"
			dest_path=$(echo "${dest_path}" | sed -e 's/^"//' -e 's/"$//')
			local version
			version=$(yq ".dockerImages[$i].version" "${config_file}") || log_error "Failed to get version for dockerImages[$i]." "check_registry_images"
			version=$(echo "${version}" | sed -e 's/^"//' -e 's/"$//')

			if [[ -n $dest_path && -n $version && -n $source_image ]]; then
				local expected_dest_image="${dest_path}/${source_image}:${version}"
				expected_images["${expected_dest_image}"]=1
				log_info "Expected Docker image: ${expected_dest_image}" "check_registry_images"
			else
				log_warning "Skipping malformed Docker image entry at index $i (missing dest_path or version)." "check_registry_images"
			fi
		done
	else
		log_info "No Docker images found in config." "check_registry_images"
	fi

	# Process Helm charts
	local chart_count
	chart_count=$(yq '.helmCharts | length' "${config_file}") || log_warning "No 'helmCharts' section found or invalid in ${config_file}." "check_registry_images"
	chart_count=${chart_count:-0} # Default to 0 if yq returns null/empty

	if [[ $chart_count -gt 0 ]]; then
		for i in $(seq 0 $((chart_count - 1))); do
			local chart_name
			chart_name=$(yq ".helmCharts[$i].chartName" "${config_file}") || log_error "Failed to get chartName for helmCharts[$i]." "check_registry_images"
			chart_name=$(echo "${chart_name}" | sed -e 's/^"//' -e 's/"$//')
			local chart_version
			chart_version=$(yq ".helmCharts[$i].chartVersion" "${config_file}") || log_error "Failed to get chartVersion for helmCharts[$i]." "check_registry_images"
			chart_version=$(echo "${chart_version}" | sed -e 's/^"//' -e 's/"$//')
			local dest_path
			dest_path=$(yq ".helmCharts[$i].destinationPath" "${config_file}") || log_error "Failed to get destinationPath for helmCharts[$i]." "check_registry_images"
			dest_path=$(echo "${dest_path}" | sed -e 's/^"//' -e 's/"$//')

			if [[ -n $dest_path && -n $chart_name && -n $chart_version ]]; then
				# Helm charts are typically OCI artifacts, and their full path in registry is dest_path/chart_name:chart_version
				local expected_dest_chart="${dest_path}${chart_name}:${chart_version}"
				expected_images["${expected_dest_chart}"]=1
				log_info "Expected Helm chart: ${expected_dest_chart}" "check_registry_images"
			else
				log_warning "Skipping malformed Helm chart entry at index $i (missing name, version, or dest_path)." "check_registry_images"
			fi
		done
	else
		log_info "No Helm charts found in config." "check_registry_images"
	fi

	# --- 2. Get existing images from the registry ---
	log_info "Fetching repository catalog from registry: http://${REGISTRY_URL}/v2/_catalog..." "check_registry_images"
	local auth_header=""
	if [[ -n $REGISTRY_USER && -n $REGISTRY_PASS ]]; then
		auth_header="-u ${REGISTRY_USER}:${REGISTRY_PASS}"
	fi

	local repos
	repos=$(curl -s "${auth_header}" "http://${REGISTRY_URL}/v2/_catalog" | jq -r '.repositories[]')

	if [[ -z $repos ]]; then
		log_warning "No repositories found in registry '${REGISTRY_URL}' or failed to connect/authenticate. Skipping detailed registry check." "check_registry_images"
	else
		for repo in $repos; do
			log_info "Fetching tags for repository: ${repo}..." "check_registry_images"
			local tags
			tags=$(curl -s "${auth_header}" "http://${REGISTRY_URL}/v2/${repo}/tags/list" | jq -r '.tags[]')

			if [[ -n $tags ]]; then
				# Construct full image names (repo:tag) and add to existing_images array
				for tag in $tags; do
					local existing_image="${repo}:${tag}"
					existing_images["${existing_image}"]=1
					# log_debug "Found existing image: ${existing_image}" "check_registry_images" # Uncomment for verbose debugging
				done
			else
				log_warning "No tags found for repository: ${repo}." "check_registry_images"
			fi
		done
	fi

	# --- 3. Compare: Identify missing images (in config, not in registry) ---
	log_info "--- Identifying Missing Images (in config, not in registry) ---" "check_registry_images"
	local missing_count=0
	for expected_image in "${!expected_images[@]}"; do
		# Check if the expected image exists in the existing_images array
		if [[ ! -v existing_images["${expected_image}"] ]]; then
			log_warning "MISSING: ${expected_image}" "check_registry_images"
			missing_count=$((missing_count + 1))
		fi
	done
	if [[ $missing_count -eq 0 ]]; then
		log_info "All expected images are present in the registry." "check_registry_images"
	else
		log_error "Total missing images: ${missing_count}" "check_registry_images"
	fi

	# --- 4. Compare: Identify unexpected images (in registry, not in config) ---
	log_info "--- Identifying Unexpected Images (in registry, not in config) ---" "check_registry_images"
	local unexpected_count=0
	for actual_image in "${!existing_images[@]}"; do
		# Check if the actual image exists in the expected_images array
		if [[ ! -v expected_images["${actual_image}"] ]]; then
			log_warning "UNEXPECTED: ${actual_image}" "check_registry_images"
			unexpected_count=$((unexpected_count + 1))
		fi
	done
	if [[ $unexpected_count -eq 0 ]]; then
		log_info "No unexpected images found in the registry (based on config)." "check_registry_images"
	else
		log_warning "Total unexpected images: ${unexpected_count}" "check_registry_images"
	fi

	log_info "Registry image check complete." "check_registry_images"
}

# This conditional block ensures the function is called only when the script is executed directly.
if [[ "$(basename "$0")" == "check_registry_images.sh" || "$(basename "$0")" == "check_registry_images" ]]; then
	# The original script had a typo: `check_registries` instead of `check_registry_images`
	# Correcting this to call the defined function.
	check_registry_images "$@"
fi
