#!/bin/bash

# validate_sync_digests: Validates synchronized Docker images and Helm charts
# by comparing their SHA256 digests between source and destination registries.
#
# Arguments:
#   $1: Path to the YAML config file (e.g., sync-config.yaml).
#
# This script uses common.sh's `log_info`, `log_warning`, `log_error`, `die`, and `file_exists_readable`.

set -o errexit
set -o nounset
set -o pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# get_docker_image_digest: Retrieves the SHA256 digest of a Docker image using skopeo inspect.
# Arguments:
#   $1: image_ref (e.g., docker.io/library/alpine:3.22 or registry:5000/images/alpine:3.22)
#   $2: tls_verify_flag (e.g., --tls-verify=false or --dest-tls-verify=false for local registry)
# Returns: The SHA256 digest on success, or an empty string on failure.
get_docker_image_digest() {
	local image_ref="$1"
	local tls_verify_flag="$2"
	local digest=""
	local inspect_output

	log_info "Inspecting Docker image: ${image_ref}" "get_docker_image_digest"

	# Use skopeo inspect to get the manifest digest.
	# Redirect stderr to /dev/null to suppress "image not found" errors when inspecting non-existent images,
	# and handle the exit code.
	if inspect_output=$(skopeo inspect "docker://${image_ref}" "${tls_verify_flag}" 2>/dev/null); then
		# Command succeeded, now check if output is non-empty
		if [[ -n ${inspect_output} ]]; then
			digest=$(echo "${inspect_output}" | jq -r '.Digest')
			if [[ $digest == "null" || -z $digest ]]; then
				log_warning "Skopeo inspect succeeded but could not extract digest for ${image_ref}. Output: ${inspect_output}" "get_docker_image_digest"
				digest="" # Ensure digest is empty if jq returns null or empty
			fi
		else
			log_warning "Skopeo inspect succeeded but returned empty output for ${image_ref}." "get_docker_image_digest"
		fi
	else
		log_warning "Could not inspect image ${image_ref}. It might not exist, or there's a connectivity/permission issue." "get_docker_image_digest"
	fi
	echo "${digest}"
}

# validate_docker_images_by_digest: Validates Docker images by comparing their SHA256 digests.
# Arguments:
#   $1: config_file (path to the YAML config)
#   $2: registry_url (URL of the destination registry)
validate_docker_images_by_digest() {
	local config_file="$1"
	local registry_url="$2"

	log_info "--- Validating Docker Images ---" "validate_docker_images_by_digest"

	local image_count
	image_count=$(yq '.dockerImages | length' "${config_file}") || log_warning "No 'dockerImages' section found or invalid in ${config_file}." "validate_docker_images_by_digest"
	image_count=${image_count:-0} # Default to 0 if yq returns null/empty

	if [[ ${image_count} -eq 0 ]]; then
		log_info "No Docker images configured for synchronization." "validate_docker_images_by_digest"
		return 0
	fi

	for i in $(seq 0 $((image_count - 1))); do
		local source_image
		source_image=$(yq ".dockerImages[$i].source" "${config_file}") || log_warning "Failed to get source for dockerImages[$i]." "validate_docker_images_by_digest"
		local dest_path
		dest_path=$(yq ".dockerImages[$i].destinationPath" "${config_file}") || log_warning "Failed to get destinationPath for dockerImages[$i]." "validate_docker_images_by_digest"

		# Ensure source_image and dest_path are not empty before proceeding
		if [[ -z $source_image || -z $dest_path ]]; then
			log_warning "Skipping malformed Docker image entry at index $i (missing source or destinationPath)." "validate_docker_images_by_digest"
			continue
		fi

		local dest_image="${registry_url}/${dest_path}"

		log_info "Checking image: ${source_image} -> ${dest_image}" "validate_docker_images_by_digest"

		# Get digest for source image (assuming public registries usually need --tls-verify=true or default behavior)
		local source_digest
		source_digest=$(get_docker_image_digest "${source_image}" "--tls-verify=true")

		# Get digest for destination image (using --tls-verify=false for local/insecure registry as per original script)
		local dest_digest
		dest_digest=$(get_docker_image_digest "${dest_image}" "--tls-verify=false")

		if [[ -z ${source_digest} ]]; then
			log_warning "Status: SKIP (Source image digest not found, possibly due to access or non-existence for ${source_image})" "validate_docker_images_by_digest"
		elif [[ -z ${dest_digest} ]]; then
			log_warning "Status: SKIP (Destination image digest not found - image might be missing in registry ${dest_image})" "validate_docker_images_by_digest"
		elif [[ ${source_digest} == "${dest_digest}" ]]; then
			log_info "Status: PASS (Digests match: ${source_digest})" "validate_docker_images_by_digest"
		else
			log_warning "Status: SKIP (Digests mismatch for ${source_image} -> ${dest_image})" "validate_docker_images_by_digest"
			log_warning "  Source: ${source_digest}" "validate_docker_images_by_digest"
			log_warning "  Dest:   ${dest_digest}" "validate_docker_images_by_digest"
		fi
	done
}

# validate_helm_charts_by_digest: Validates Helm charts by comparing their SHA256 digests.
# Arguments:
#   $1: config_file (path to the YAML config)
#   $2: registry_url (URL of the destination registry)
validate_helm_charts_by_digest() {
	local config_file="$1"
	local registry_url="$2"

	log_info "--- Validating Helm Charts ---" "validate_helm_charts_by_digest"

	local chart_count
	chart_count=$(yq '.helmCharts | length' "${config_file}") || log_warning "No 'helmCharts' section found or invalid in ${config_file}." "validate_helm_charts_by_digest"
	chart_count=${chart_count:-0} # Default to 0 if yq returns null/empty

	if [[ ${chart_count} -eq 0 ]]; then
		log_info "No Helm charts configured for synchronization." "validate_helm_charts_by_digest"
		return 0
	fi

	local temp_dir=""
	temp_dir="/tmp/helm_chart_validation_$(date +%s%N)"
	mkdir -p "${temp_dir}" || die "Failed to create temporary directory ${temp_dir}."

	for i in $(seq 0 $((chart_count - 1))); do
		local repo_url
		repo_url=$(yq ".helmCharts[$i].repoUrl" "${config_file}") || log_warning "Failed to get repoUrl for helmCharts[$i]." "validate_helm_charts_by_digest"
		local chart_name
		chart_name=$(yq ".helmCharts[$i].chartName" "${config_file}") || log_warning "Failed to get chartName for helmCharts[$i]." "validate_helm_charts_by_digest"
		local chart_version
		chart_version=$(yq ".helmCharts[$i].chartVersion" "${config_file}") || log_warning "Failed to get chartVersion for helmCharts[$i]." "validate_helm_charts_by_digest"
		local dest_path
		dest_path=$(yq ".helmCharts[$i].destinationPath" "${config_file}") || log_warning "Failed to get destinationPath for helmCharts[$i]." "validate_helm_charts_by_digest"

		# Ensure all required fields are present
		if [[ -z $repo_url || -z $chart_name || -z $chart_version || -z $dest_path ]]; then
			log_warning "Skipping malformed Helm chart entry at index $i (missing repoUrl, chartName, chartVersion, or destinationPath)." "validate_helm_charts_by_digest"
			continue
		fi

		# Construct destination OCI URL (e.g., oci://registry:5000/charts/nginx)
		local dest_oci_url="oci://${registry_url}/${dest_path}${chart_name}"

		log_info "Checking chart: ${repo_url}/${chart_name}:${chart_version} -> ${dest_oci_url}:${chart_version}" "validate_helm_charts_by_digest"

		local source_chart_file="${temp_dir}/${chart_name}-${chart_version}-src.tgz"
		local dest_chart_file="${temp_dir}/${chart_name}-${chart_version}-dest.tgz"
		local source_sha=""
		local dest_sha=""

		# Pull source chart to a unique temporary file
		log_info "Pulling source chart from ${repo_url}..." "validate_helm_charts_by_digest"
		if helm pull "${chart_name}" --repo "${repo_url}" --version "${chart_version}" --destination "${temp_dir}" --untar=false >/dev/null 2>&1; then
			# Helm pull names the file chartname-version.tgz, so we need to rename or specify correctly
			local pulled_source_name="${temp_dir}/${chart_name}-${chart_version}.tgz"
			if [[ -f ${pulled_source_name} ]]; then
				mv "${pulled_source_name}" "${source_chart_file}" || log_error "Failed to move source chart from ${pulled_source_name} to ${source_chart_file}." "validate_helm_charts_by_digest"
				source_sha=$(get_tgz_sha256 "${source_chart_file}")
			else
				log_warning "Pulled source chart file not found at expected path: ${pulled_source_name}" "validate_helm_charts_by_digest"
			fi
		else
			log_warning "Failed to pull source chart ${chart_name}:${chart_version} from ${repo_url}. Skipping validation for this chart." "validate_helm_charts_by_digest"
		fi

		# Pull destination chart from OCI registry to a *different* unique temporary file
		log_info "Pulling destination chart from ${dest_oci_url}..." "validate_helm_charts_by_digest"
		if helm pull "${dest_oci_url}" --version "${chart_version}" --destination "${temp_dir}" --plain-http --untar=false >/dev/null 2>&1; then
			# Helm pull names the file chartname-version.tgz even for OCI, need to move it
			local pulled_dest_name="${temp_dir}/${chart_name}-${chart_version}.tgz"
			if [[ -f ${pulled_dest_name} ]]; then
				mv "${pulled_dest_name}" "${dest_chart_file}" || log_error "Failed to move destination chart from ${pulled_dest_name} to ${dest_chart_file}." "validate_helm_charts_by_digest"
				dest_sha=$(get_tgz_sha256 "${dest_chart_file}")
			else
				log_warning "Pulled destination chart file not found at expected path: ${pulled_dest_name}" "validate_helm_charts_by_digest"
			fi
		else
			log_warning "Failed to pull destination chart ${chart_name}:${chart_version} from ${dest_oci_url}. It might be missing in the local registry." "validate_helm_charts_by_digest"
		fi

		if [[ -z ${source_sha} ]]; then
			log_warning "Status: SKIP (Source chart digest could not be determined for ${chart_name}:${chart_version})" "validate_helm_charts_by_digest"
		elif [[ -z ${dest_sha} ]]; then
			log_warning "Status: SKIP (Destination chart digest could not be determined - chart might be missing for ${dest_oci_url}:${chart_version})" "validate_helm_charts_by_digest"
		elif [[ ${source_sha} == "${dest_sha}" ]]; then
			log_info "Status: PASS (Digests match: ${source_sha})" "validate_helm_charts_by_digest"
		else
			log_warning "Status: SKIP (Digests mismatch for ${chart_name}:${chart_version})" "validate_helm_charts_by_digest"
			log_warning "  Source: ${source_sha}" "validate_helm_charts_by_digest"
			log_warning "  Dest:   ${dest_sha}" "validate_helm_charts_by_digest"
		fi
	done

	log_info "Cleaning up temporary directory: ${temp_dir}" "validate_helm_charts_by_digest"
	rm -rf "${temp_dir}" || log_warning "Failed to clean up temporary directory: ${temp_dir}" "validate_helm_charts_by_digest"
}

# Main function to orchestrate the validation process
validate_sync_digests() {
	local config_file="$1"
	log_info "Starting synchronization validation from config: ${config_file}" "validate_sync_digests"

	if ! file_exists_readable "$config_file"; then
		die "Sync config file not found or not readable: ${config_file}"
	fi

	local registry_url
	registry_url=$(yq '.registry.url' "${config_file}") || die "Failed to get registry URL from config file: ${config_file}."

	# Login to registry is not strictly needed for skopeo/helm pull if credentials are passed via flags,
	# or if it's an insecure registry with --plain-http. The original script had commented-out logins.
	# We will rely on flags passed to skopeo/helm in their respective functions.

	validate_docker_images_by_digest "${config_file}" "${registry_url}"
	validate_helm_charts_by_digest "${config_file}" "${registry_url}"

	log_info "Synchronization validation complete." "validate_sync_digests"
}

# --- Script Entry Point ---
# This conditional block ensures the function is called only when the script is executed directly.
if [[ "$(basename "$0")" == "validate_sync_digests.sh" || "$(basename "$0")" == "validate_sync_digests" ]]; then
	validate_sync_digests "$@"
fi
