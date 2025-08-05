#!/bin/bash

# Main ARISU (Automatic recurring image synchronization utility) script
# TODO in depth usage

set -o errexit
set -o nounset
set -o pipefail

# --- Trap Setup ---
# Set a trap to call the error handler from common.sh if any command fails.
# This should be set *after* sourcing common.sh to ensure _err_trap_handler is defined.
# Using 'return 0' within the trap ensures 'set -e' doesn't cause a double-exit
# if _err_trap_handler already exits the script. For this pattern, it's safer
# to ensure the handler *always* exits.
trap '_err_trap_handler' ERR

# Global configuration
export LOG_FILE="/home/runner/arisu.log" # Alternatively docker will capture "/dev/stderr" or "/var/log/arisu/arisu.log"
# Define the name of your script for MESSAGE_ID in journald
export SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}") || exit 100
# Define the full path of your script for CODE_FILE in journald
export FULL_PATH=$(readlink -f "${BASH_SOURCE[0]}") || exit 100

# Includes
source "$(dirname "${BASH_SOURCE[0]}")/libs/common.sh" || exit 100
source "$(dirname "${BASH_SOURCE[0]}")/libs/remove_yaml_entries.sh" || exit 100
source "$(dirname "${BASH_SOURCE[0]}")/libs/add_yaml_entries.sh" || exit 100
source "$(dirname "${BASH_SOURCE[0]}")/libs/check_registries.sh" || exit 100
source "$(dirname "${BASH_SOURCE[0]}")/libs/sync_registries.sh" || exit 100
source "$(dirname "${BASH_SOURCE[0]}")/libs/validate_manifests.sh" || exit 100

SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")
PROJECT_ROOT=$(readlink -f "$SCRIPT_DIR/..")
CONFIG_FILE="$PROJECT_ROOT/config/sync-config.yaml"

REGISTRY_URL=$(yq '.registry.url' "${CONFIG_FILE}")
REGISTRY_USER=$(yq '.registry.user' "${CONFIG_FILE}")
REGISTRY_PASS=$(yq '.registry.password' "${CONFIG_FILE}")

declare CACHE_DIR="/tmp/$SCRIPT_NAME/YYYYMMDD"

# Ensure the log file directory exists and is writable
LOG_DIR=$(dirname "$LOG_FILE")
if [[ ! -d $LOG_DIR ]]; then
	mkdir -p "$LOG_DIR" || {
		echo "CRITICAL: Failed to create log directory: $LOG_DIR. Exiting."
		exit 1
	}
fi
if [[ ! -w $LOG_DIR ]]; then
	echo "CRITICAL: Log directory '$LOG_DIR' is not writable. Please check permissions. Exiting."
	exit 1
fi

if [ ! -d "$CACHE_DIR" ]; then
	/usr/bin/mkdir -p -v "$CACHE_DIR" || exit 100
fi
trap '/bin/rm -rf "$CACHE_DIR"' INT TERM

main() {

	log_info "Synchronization process started by '${SCRIPT_NAME}'."

	check_dependencies

	# logging skopeo in
	#echo "$REGISTRY_PASS" | skopeo login "$REGISTRY_URL" --username "$REGISTRY_USER" --password-stdin
	# helm login
	# helm registry login ...

	echo "--- Syncing Docker images ---"

	# check_and_sync_skopeo "docker.io/library/alpine" "$REGISTRY_URL/alpine" "3.22"
	# check_and_sync_skopeo "docker.io/library/alpine" "$REGISTRY_URL/alpine" "3.16"
	# check_and_sync_skopeo "docker.io/grafana/grafana" "$REGISTRY_URL/charts/grafana" "12.0.2"

	loop_through_yaml_config_for_skopeo "${CONFIG_FILE}"

	echo "--- Syncing Helm Charts ---"

	loop_through_yaml_config_for_helm "${CONFIG_FILE}"

	log_info "Synchronization process completed successfully."

	sleep 1
	echo "Done."

	_output=""
	if ! _output=$(remove_yaml_entries "${CONFIG_FILE}" image \
		--registry-path "images/alpine" \
		--version "3.22" 2>&1); then
		echo "Deleting chart failed"
		echo "${_output}"
	fi
	if ! _output=$(add_yaml_entries "${CONFIG_FILE}" image \
		--source "docker.io/library/alpine" \
		--destination "images/alpine" \
		--version "3.22" 2>&1); then
		echo "Adding image failed"
		echo "${_output}"
	fi

	if ! _output=$(remove_yaml_entries "${CONFIG_FILE}" chart \
		--chart-name "nginx" \
		--chart-version "15.14.0" 2>&1); then
		echo "Deleting chart failed"
		echo "${_output}"
	fi
	if ! _output=$(add_yaml_entries "${CONFIG_FILE}" chart \
		--repo-name "bitnami" \
		--repo-url "https://charts.bitnami.com/bitnami" \
		--chart-name "nginx" \
		--chart-version "15.14.0" \
		--destination "charts/" 2>&1); then
		echo "Adding chart failed"
		echo "${_output}"
	fi

	check_registry_images "${CONFIG_FILE}"

	validate_sync_digests "${CONFIG_FILE}"

}

# --- Execute the main function ---
main "$@"
