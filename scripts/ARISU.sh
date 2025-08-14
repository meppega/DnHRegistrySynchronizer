#!/bin/bash

# Main ARISU (Automatic recurring image synchronization utility) script
#
# Usage: ARISU.sh [OPTIONS]
#
# Options:
#   -c, --config-file <path>   Specify the path to the YAML configuration file.
#                              Default: ../config/sync-config.yaml
#   -s, --skip <script_name>   Skip a specific script/stage (e.g., 'sync', 'validate', 'check').
#                              Can be specified multiple times.
#   -r, --run <script_name>    Run only specified scripts/stages. If provided, others are skipped.
#                              Can be specified multiple times.
#                              Available stages: 'sync', 'validate', 'check'.
#   -l, --login                Perform skopeo and helm registry login. Optional.
#   -t, --tls-verify           Use TLS verification for the target registry (HTTPS).
#                              By default, local registry assumes --plain-http for helm and --tls-verify=false for skopeo.
#                              Setting this flag explicitly enables TLS verification for the target registry.
#   -h, --help                 Display this help message and exit.
#
# This script orchestrates Docker image and Helm chart synchronization and validation.
# It uses common.sh for logging and other utilities.

set -o errexit
set -o nounset
set -o pipefail

# --- Trap Setup ---
# Set a trap to call the error handler from common.sh if any command fails.
trap '_err_trap_handler' ERR

# Global configuration variables
LOG_FILE="/home/runner/arisu.log" # Alternatively docker will capture "/dev/stderr" or "/var/log/arisu/arisu.log"
# Define the name of your script for MESSAGE_ID in journald
SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}") || exit 100
# Define the full path of your script for CODE_FILE in journald
FULL_PATH=$(readlink -f "${BASH_SOURCE[0]}") || exit 100
export LOG_FILE SCRIPT_NAME FULL_PATH

# --- Sourced Libraries ---
source "$(dirname "${BASH_SOURCE[0]}")/libs/common.sh" || exit 100
source "$(dirname "${BASH_SOURCE[0]}")/remove_yaml_entries.sh" || exit 100
source "$(dirname "${BASH_SOURCE[0]}")/add_yaml_entries.sh" || exit 100
source "$(dirname "${BASH_SOURCE[0]}")/libs/check_registries.sh" || exit 100
source "$(dirname "${BASH_SOURCE[0]}")/libs/sync_registries.sh" || exit 100
source "$(dirname "${BASH_SOURCE[0]}")/libs/validate_manifests.sh" || exit 100

SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")
PROJECT_ROOT=$(readlink -f "$SCRIPT_DIR/..")
DEFAULT_CONFIG_FILE="$PROJECT_ROOT/config/sync-config.yaml"

# Global variables for options, initialized to defaults
RUN_LOGIN=false
USE_TLS_VERIFY=false # Default to --tls-verify=false for skopeo, --plain-http for helm
CONFIG_FILE="" # Will be set by getopt, defaults to DEFAULT_CONFIG_FILE
declare -a SCRIPTS_TO_RUN=()
declare -a SCRIPTS_TO_SKIP=()

# Placeholder for registry credentials (will be populated from config)
REGISTRY_URL=""
REGISTRY_USER=""
REGISTRY_PASS=""

# --- Help Function ---
display_help() {
    echo "Usage: $(basename "$0") [OPTIONS] <command> [COMMAND_OPTIONS]"
    echo "       $(basename "$0") sync --login"
    echo "       $(basename "$0") add image --source docker.io/library/alpine --destination-path images/alpine --version 3.22"
    echo ""
    echo "Global Options:"
    echo "  -c, --config-file <path>   Specify the path to the YAML configuration file."
    echo "                             Default: ../config/sync-config.yaml"
    echo "  -l, --login                Perform skopeo and helm registry login. Optional."
    echo "  -t, --tls-verify           Use TLS verification for the target registry (HTTPS)."
    echo "                             By default, local registry assumes --plain-http for helm and --tls-verify=false for skopeo."
    echo "                             Setting this flag explicitly enables TLS verification for the target registry."
    echo "  -h, --help                 Display this help message and exit."
    echo ""
    echo "Commands:"
    echo "  sync       : Synchronize Docker images and Helm charts as per config."
    echo "  validate   : Validate synchronized Docker images and Helm charts by digest comparison."
    echo "  check      : Perform registry content checks."
    # echo "  add        : Add an 'image' or 'chart' entry to the config file. Use 'ARISU.sh add --help'."
    # echo "  remove     : Remove an 'image' or 'chart' entry from the config file. Use 'ARISU.sh remove --help'."
    echo ""
    exit 0
}

# --- Check script run/skip status ---
should_run_script() {
    local script_name="$1"

    # If --run is specified, only run scripts explicitly listed
    if [[ ${#SCRIPTS_TO_RUN[@]} -gt 0 ]]; then
        for run_name in "${SCRIPTS_TO_RUN[@]}"; do
            if [[ "$script_name" == "$run_name" ]]; then
                return 0 # Should run
            fi
        done
        return 1 # Not in --run list, so skip
    fi

    # If --skip is specified, skip scripts explicitly listed
    if [[ ${#SCRIPTS_TO_SKIP[@]} -gt 0 ]]; then
        for skip_name in "${SCRIPTS_TO_SKIP[@]}"; do
            if [[ "$script_name" == "$skip_name" ]]; then
                return 1 # Should skip
            fi
        done
    fi

    return 0 # Default: run
}


# --- Main Logic ---
main() {
    # Process command line arguments
    local PARSED_OPTIONS
    # Use array for long options for robustness with getopt
    local LONG_OPTIONS="config-file:,skip:,run:,login,tls-verify,help"
 
    if ! PARSED_OPTIONS=$(getopt -o c:s:r:lth --long "${LONG_OPTIONS}" -n "$SCRIPT_NAME" -- "$@"); then
        # getopt failed, meaning invalid options were provided
        display_help >&2
    fi

    eval set -- "$PARSED_OPTIONS"

    while true; do
        case "$1" in
            -c|--config-file)
                CONFIG_FILE="$2"
                shift 2
                ;;
            -s|--skip)
                SCRIPTS_TO_SKIP+=("$2")
                shift 2
                ;;
            -r|--run)
                SCRIPTS_TO_RUN+=("$2")
                shift 2
                ;;
            -l|--login)
                RUN_LOGIN=true
                shift
                ;;
            -t|--tls-verify)
                USE_TLS_VERIFY=true
                shift
                ;;
            -h|--help)
                display_help
                ;;
            --)
                shift
                break
                ;;
            *)
                die "Internal error! Unhandled option: $1" "main"
                ;;
        esac
    done

    # Set CONFIG_FILE to default if not specified via command line
    CONFIG_FILE="${CONFIG_FILE:-$DEFAULT_CONFIG_FILE}"

    log_info "Synchronization process started by '${SCRIPT_NAME}'."

    # Pre-checks for log directory and cache directory (critical, so they stay outside conditional runs)
    local LOG_DIR
	LOG_DIR=$(dirname "$LOG_FILE")
    if [[ ! -d $LOG_DIR ]]; then
        mkdir -p "$LOG_DIR" || die "Failed to create log directory: $LOG_DIR."
    fi
    if [[ ! -w $LOG_DIR ]]; then
        die "Log directory '$LOG_DIR' is not writable. Please check permissions."
    fi

    # Define CACHE_DIR dynamically for each run
    # local CACHE_DIR
	# CACHE_DIR="/tmp/${SCRIPT_NAME}_$(date +%Y%m%d%H%M%S)"
    # if ! mkdir -p -v "$CACHE_DIR"; then
    #     die "Failed to create cache directory: $CACHE_DIR." "main"
    # fi
    # Set trap to clean up cache directory on exit (INT, TERM, or normal exit)
    # trap '/bin/rm -rf "$CACHE_DIR"' EXIT INT TERM

    check_dependencies # This should always run to ensure tools are present

    # Get registry credentials from config file
    REGISTRY_URL=$(yq '.registry.url' "${CONFIG_FILE}" || die "Failed to get registry URL from config file: ${CONFIG_FILE}.")
    REGISTRY_USER=$(yq '.registry.user' "${CONFIG_FILE}" || log_warning "Registry user not found in config. Assuming anonymous access or environment variable login." "main")
    REGISTRY_PASS=$(yq '.registry.password' "${CONFIG_FILE}" || log_warning "Registry password not found in config. Assuming anonymous access or environment variable login." "main")

    local SKOPEO_TLS_FLAG="--tls-verify=false"
    local HELM_TLS_FLAG="--plain-http"

    if [[ "${USE_TLS_VERIFY}" == true ]]; then
        SKOPEO_TLS_FLAG="--tls-verify=true"
        HELM_TLS_FLAG="" # No --plain-http for TLS
        log_info "Using TLS verification for target registry." "main"
    else
        log_info "Using no TLS verification (--tls-verify=false, --plain-http) for target registry." "main"
    fi

    # Optional Registry Login
    if [[ "${RUN_LOGIN}" == true ]]; then
        log_info "Attempting registry login for Skopeo and Helm..." "main"

        if [[ -n "${REGISTRY_USER}" && -n "${REGISTRY_PASS}" ]]; then
            # Skopeo login
            log_info "Logging into Skopeo registry: ${REGISTRY_URL}..." "main"
            echo "${REGISTRY_PASS}" | skopeo login "${REGISTRY_URL}" --username "${REGISTRY_USER}" --password-stdin ${SKOPEO_TLS_FLAG} || log_warning "Skopeo login failed. Continuing without explicit login." "main"

            # Helm login
            log_info "Logging into Helm registry: ${REGISTRY_URL}..." "main"
            helm registry login "${REGISTRY_URL}" --username "${REGISTRY_USER}" --password "${REGISTRY_PASS}" ${HELM_TLS_FLAG} || log_warning "Helm registry login failed. Continuing without explicit login." "main"
        else
            log_warning "Registry user or password not specified in config. Cannot perform explicit login." "main"
        fi
    fi

    log_info "Starting synchronization stages." "main"

    # --- Conditional Script Execution ---

    if should_run_script "sync"; then
        echo "--- Syncing Docker images and Helm Charts ---"
        loop_through_yaml_config_for_skopeo "${CONFIG_FILE}"  #"${REGISTRY_URL}" "${SKOPEO_TLS_FLAG}" "${HELM_TLS_FLAG}" "${CACHE_DIR}"
        loop_through_yaml_config_for_helm "${CONFIG_FILE}"
    else
        log_info "Skipping 'sync' stage." "main"
    fi

    if should_run_script "validate"; then
        echo "--- Validating Manifests ---"
        validate_sync_digests "${CONFIG_FILE}" #"${REGISTRY_URL}" "${SKOPEO_TLS_FLAG}" "${HELM_TLS_FLAG}" "${CACHE_DIR}"
    else
        log_info "Skipping 'validate' stage." "main"
    fi

    # Example calls for remove_yaml_entries and add_yaml_entries (Optional)
    # These typically modify the config, so they are not part of core sync/validation
    # but rather utility operations. You might want to remove these or make them
    # more generic if they are part of a regular workflow.
    # if should_run_script "remove"; then
    #     echo "--- Removing YAML entries (Example) ---"
    #     local _output
    #     if ! _output=$(remove_yaml_entries "${CONFIG_FILE}" image \
    #         --registry-path "images/alpine" \
    #         --version "3.22" 2>&1); then
    #         log_error "Deleting image entry failed: ${_output}" "main"
    #     fi
    #     if ! _output=$(remove_yaml_entries "${CONFIG_FILE}" chart \
    #         --chart-name "nginx" \
    #         --chart-version "15.14.0" 2>&1); then
    #         log_error "Deleting chart entry failed: ${_output}" "main"
    #     fi
    # else
    #     log_info "Skipping 'remove' stage." "main"
    # fi

    # if should_run_script "add"; then
    #     echo "--- Adding YAML entries (Example) ---"
    #     local _output
    #     if ! _output=$(add_yaml_entries "${CONFIG_FILE}" image \
    #         --source "docker.io/library/alpine" \
    #         --destination-path "images/alpine" \
    #         --version "3.22" 2>&1); then
    #         log_error "Adding image entry failed: ${_output}" "main"
    #     fi
    #     if ! _output=$(add_yaml_entries "${CONFIG_FILE}" chart \
    #         --repo-name "bitnami" \
    #         --repo-url "https://charts.bitnami.com/bitnami" \
    #         --chart-name "nginx" \
    #         --chart-version "15.14.0" \
    #         --destination-path "charts/" 2>&1); then
    #         log_error "Adding chart entry failed: ${_output}" "main"
    #     fi
    # else
    #     log_info "Skipping 'add' stage." "main"
    # fi

    if should_run_script "check"; then
        echo "--- Checking Registry Contents ---"
        check_registry_images "${CONFIG_FILE}" #"${REGISTRY_URL}" "${SKOPEO_TLS_FLAG}" "${HELM_TLS_FLAG}"
    else
        log_info "Skipping 'check' stage." "main"
    fi

    log_info "Synchronization process completed successfully." "main"
}

# --- Execute the main function ---
main "$@"