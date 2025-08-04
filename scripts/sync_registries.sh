#!/bin/bash

# Script to synchronize images from a yaml configuration file to a registry

set -o errexit
set -o nounset
set -o pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# check_dependencies: Ensures all required command-line tools are installed.
# It uses common.sh's `command_exists`, `log_info`, `log_error`, and `die`.
check_dependencies() {
    log_info "Checking synchronization script dependencies..."
    local deps=("yq" "skopeo" "helm" "curl" "sha256sum") # Removed duplicate yq
    local missing_deps=()

    for dep in "${deps[@]}"; do
        if ! command_exists "${dep}"; then
            missing_deps+=("$dep")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing required commands: ${missing_deps[*]}" "check_dependencies"
        die "Please install the missing dependencies before running this script."
    else
        log_info "All dependencies present for synchronization tasks."
    fi
}

# check_and_sync_helm: Synchronizes a Helm chart to the destination registry.
# Arguments: repo_name, repo_url, chart_name, chart_version, dest_registry_url
# It uses common.sh's `log_info`, `log_warning`, `log_error`, `die`, and `file_exists_readable`.
check_and_sync_helm() {
    local repo_name="$1"
    local repo_url="$2"
    local chart_name="$3"
    local chart_version="$4"
    local dest_registry_url="$5" # This is the full OCI URL like "oci://my.registry.com/charts/path"

    local chart_tgz_name="${chart_name}-${chart_version}"
    local tmp_tgz_path="/tmp/${chart_tgz_name}.tgz" # Full path for the downloaded chart

    log_info "Processing Helm chart: ${chart_name}:${chart_version} from ${repo_url}" "check_and_sync_helm"

    # Check if the chart already exists in the destination OCI registry
    # Note: 'helm show chart' doesn't reliably work with OCI registries for existence checks.
    # A more robust check might involve 'helm search repo <chart> --repo <oci_repo>' or
    # 'skopeo inspect' on the OCI artifact if Helm pushes it as an OCI artifact.
    # For now, sticking close to original logic.
    if helm show chart "${dest_registry_url}/${chart_name}" --plain-http >/dev/null 2>&1; then
        log_info "Chart '${chart_name}:${chart_version}' already exists in '${dest_registry_url}'. Skipping." "check_and_sync_helm"
        return 0 # Indicate success as chart is already there
    fi

    log_info "Chart '${chart_name}:${chart_version}' not found. Attempting to add it to '${dest_registry_url}'." "check_and_sync_helm"

    log_info "Adding Helm repository: ${repo_name} from ${repo_url}..." "check_and_sync_helm"
    helm repo add "${repo_name}" "${repo_url}" --force-update \
        || die "Failed to add Helm repository '${repo_name}' from '${repo_url}'."

    log_info "Updating Helm repository: ${repo_name}..." "check_and_sync_helm"
    helm repo update "${repo_name}" \
        || log_warning "Failed to update Helm repository '${repo_name}'. Continuing, but might use stale index." "check_and_sync_helm"

    log_info "Pulling Helm chart '${chart_name}:${chart_version}' from traditional repository..." "check_and_sync_helm"
    helm pull "${chart_name}" --repo "${repo_url}" --version "${chart_version}" --destination /tmp \
        || die "Failed to pull Helm chart '${chart_name}:${chart_version}' from '${repo_url}'."

    if ! file_exists_readable "$tmp_tgz_path"; then
        log_error "Chart TGZ file '${tmp_tgz_path}' not found or not readable after download. Skipping push." "check_and_sync_helm"
        return 1 # Indicate failure
    fi

    log_info "Pushing Helm chart '${tmp_tgz_path}' to OCI registry: '${dest_registry_url}'..." "check_and_sync_helm"
    helm push \
        "${tmp_tgz_path}" \
        "${dest_registry_url}" \
        --plain-http \
        || die "Failed to push Helm chart '${tmp_tgz_path}' to '${dest_registry_url}'."

    log_info "Cleaning up temporary chart file: ${tmp_tgz_path}" "check_and_sync_helm"
    rm -f "$tmp_tgz_path" \
        || log_warning "Failed to remove temporary chart file: ${tmp_tgz_path}. Manual cleanup may be required." "check_and_sync_helm"
}

# check_and_sync_skopeo: Synchronizes a Docker image using Skopeo.
# Arguments: source_image (e.g., library/nginx), dest_registry_base (e.g., my.registry.com/path), version
# It uses common.sh's `log_info`, `log_error`, and `die`.
check_and_sync_skopeo() {
    local source_image="$1"
    local dest_registry_base="$2"
    local version="$3"

    local full_source_image_ref="docker://${source_image}:${version}"
    # Use ##*/ to get only the image name (e.g., nginx from library/nginx)
    local full_dest_image_ref="docker://${dest_registry_base}/${source_image##*/}:${version}"

    log_info "Checking if '${full_dest_image_ref}' exists in destination registry..." "check_and_sync_skopeo"

    # Skopeo inspect to check existence
    if skopeo inspect "${full_dest_image_ref}" --tls-verify=false >/dev/null 2>&1; then
        log_info "'${full_dest_image_ref}' already exists. Skipping copy." "check_and_sync_skopeo"
        # TODO: Add logic for synchronization/diff if needed, perhaps by comparing digests
        # log_info "Running sync logic for existing image..."
        # skopeo sync ...
        return 0 # Indicate success as image is already there
    fi

    log_info "'${full_dest_image_ref}' not found. Copying image..." "check_and_sync_skopeo"
    skopeo copy \
        "${full_source_image_ref}" \
        "${full_dest_image_ref}" \
        --dest-tls-verify=false \
        --all \
        --preserve-digests \
        || die "Failed to copy image '${full_source_image_ref}' to '${full_dest_image_ref}'."

    log_info "Successfully copied '${full_source_image_ref}' to '${full_dest_image_ref}'." "check_and_sync_skopeo"
}

# loop_through_yaml_config_for_helm: Parses YAML for Helm charts and syncs them.
# Arguments: config_file (path to the YAML config)
# It uses common.sh's `log_info`, `log_warning`, `log_error`, `die`, and `file_exists_readable`.
loop_through_yaml_config_for_helm() {
    local config_file="$1"
    log_info "Starting Helm chart synchronization from config: ${config_file}" "loop_through_yaml_config_for_helm"

    if ! file_exists_readable "$config_file"; then
        die "Helm chart config file not found or not readable: ${config_file}"
    fi

    local registry_url
    # Use || die to ensure critical yq parsing errors immediately stop the script.
    registry_url=$(yq '.registry.url' "${config_file}") || die "Failed to get registry URL from config file: ${config_file}."

    # Login to registry if credentials are provided. This is usually done once per script.
    # local registry_user
    # registry_user=$(yq '.registry.user' "${config_file}") || log_warning "Registry user not found in config." "loop_through_yaml_config_for_helm"
    # local registry_pass
    # registry_pass=$(yq '.registry.password' "${config_file}") || log_warning "Registry password not found in config." "loop_through_yaml_config_for_helm"

    # if [[ -n "$registry_user" && -n "$registry_pass" ]]; then
    #     log_info "Attempting to log into OCI registry: ${registry_url}..." "loop_through_yaml_config_for_helm"
    #     # Note: Helm registry login with --plain-http may not be directly supported, usually needs TLS
    #     # helm registry login "${registry_url}" -u "${registry_user}" -p "${registry_pass}" || die "Failed to log into Helm OCI registry."
    #     # Consider using skopeo login or docker login if it's a Docker-compatible registry for OCI artifacts.
    # fi


    local chart_count
    chart_count=$(yq '.helmCharts | length' "${config_file}") || die "Failed to get helmCharts length from config file: ${config_file}."

    if [[ "$chart_count" -eq 0 ]]; then
        log_warning "No Helm charts found in '${config_file}' to synchronize." "loop_through_yaml_config_for_helm"
        return 0
    fi

    for i in $(seq 0 $((chart_count - 1))); do
        log_info "Processing Helm chart entry $((i + 1))/${chart_count}." "loop_through_yaml_config_for_helm"

        local repo_name="" chart_name="" chart_version="" dest_path="" repo_url="" # Initialize locals to avoid unset errors if yq fails
        
        repo_name=$(yq ".helmCharts[$i].repoName" "${config_file}")      || log_error "Failed to get repoName for chart index $i." "loop_through_yaml_config_for_helm"
        repo_url=$(yq ".helmCharts[$i].repoUrl" "${config_file}")        || log_error "Failed to get repoUrl for chart index $i." "loop_through_yaml_config_for_helm"
        chart_name=$(yq ".helmCharts[$i].chartName" "${config_file}")    || log_error "Failed to get chartName for chart index $i." "loop_through_yaml_config_for_helm"
        chart_version=$(yq ".helmCharts[$i].chartVersion" "${config_file}") || log_error "Failed to get chartVersion for chart index $i." "loop_through_yaml_config_for_helm"
        dest_path=$(yq ".helmCharts[$i].destinationPath" "${config_file}") || log_error "Failed to get destinationPath for chart index $i." "loop_through_yaml_config_for_helm"

        # Check if any critical parsing failed for this chart entry
        if [[ -z "$repo_name" || -z "$repo_url" || -z "$chart_name" || -z "$chart_version" || -z "$dest_path" ]]; then
            log_error "Skipping Helm chart entry $i due to missing critical configuration fields." "loop_through_yaml_config_for_helm"
            continue # Skip to the next chart entry
        fi

        # Pass "oci://${registry_url}/${dest_path}" as the destination for check_and_sync_helm
        check_and_sync_helm \
            "${repo_name}" \
            "${repo_url}" \
            "${chart_name}" \
            "${chart_version}" \
            "oci://${registry_url}/${dest_path}" \
            || log_error "Failed to synchronize Helm chart ${chart_name}:${chart_version}. See above for details." "loop_through_yaml_config_for_helm"
    done
    log_info "Finished Helm chart synchronization." "loop_through_yaml_config_for_helm"
}

# loop_through_yaml_config_for_skopeo: Parses YAML for Docker images and syncs them.
# Arguments: config_file (path to the YAML config)
# It uses common.sh's `log_info`, `log_warning`, `log_error`, `die`, and `file_exists_readable`.
loop_through_yaml_config_for_skopeo() {
    local config_file="$1"
    log_info "Starting Docker image synchronization from config: ${config_file}" "loop_through_yaml_config_for_skopeo"

    if ! file_exists_readable "$config_file"; then
        die "Docker image config file not found or not readable: ${config_file}"
    fi

    local registry_url
    registry_url=$(yq '.registry.url' "${config_file}") || die "Failed to get registry URL from config file: ${config_file}."

    # Perform Skopeo login here if necessary, using credentials from config_file
    # local registry_user
    # registry_user=$(yq '.registry.user' "${config_file}") || log_warning "Registry user not found in config." "loop_through_yaml_config_for_skopeo"
    # local registry_pass
    # registry_pass=$(yq '.registry.password' "${config_file}") || log_warning "Registry password not found in config." "loop_through_yaml_config_for_skopeo"

    # if [[ -n "$registry_user" && -n "$registry_pass" ]]; then
    #     log_info "Attempting Skopeo login to destination registry: ${registry_url}..." "loop_through_yaml_config_for_skopeo"
    #     skopeo login "${registry_url}" -u "${registry_user}" -p "${registry_pass}" --tls-verify=false \
    #         || die "Failed to login to destination registry '${registry_url}' with Skopeo."
    # fi


    local image_count
    image_count=$(yq '.dockerImages | length' "${config_file}") || die "Failed to get dockerImages length from config file: ${config_file}."

    if [[ "$image_count" -eq 0 ]]; then
        log_warning "No Docker images found in '${config_file}' to synchronize." "loop_through_yaml_config_for_skopeo"
        return 0
    fi

    for i in $(seq 0 $((image_count - 1))); do
        log_info "Processing Docker image entry $((i + 1))/${image_count}." "loop_through_yaml_config_for_skopeo"

        local source_image="" dest_path="" version="" # Initialize locals
        
        source_image=$(yq ".dockerImages[$i].source" "${config_file}")        || log_error "Failed to get source image for index $i." "loop_through_yaml_config_for_skopeo"
        dest_path=$(yq ".dockerImages[$i].destinationPath" "${config_file}")  || log_error "Failed to get destinationPath for index $i." "loop_through_yaml_config_for_skopeo"
        version=$(yq ".dockerImages[$i].version" "${config_file}")            || log_error "Failed to get version for index $i." "loop_through_yaml_config_for_skopeo"

        # Check if any critical parsing failed for this image entry
        if [[ -z "$source_image" || -z "$dest_path" || -z "$version" ]]; then
            log_error "Skipping Docker image entry $i due to missing critical configuration fields." "loop_through_yaml_config_for_skopeo"
            continue # Skip to the next image entry
        fi

        check_and_sync_skopeo \
            "${source_image}" \
            "${registry_url}/${dest_path}" \
            "${version}" \
            || log_error "Failed to synchronize Docker image ${source_image}:${version}. See above for details." "loop_through_yaml_config_for_skopeo"
    done
    log_info "Finished Docker image synchronization." "loop_through_yaml_config_for_skopeo"
}