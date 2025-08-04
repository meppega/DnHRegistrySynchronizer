#!/bin/bash

# Main ARISU (Automatic recurring image synchronization utility) script
# TODO in depth usage

# Global configuration
export LOG_FILE="/var/log/arisu.log"
# Define the name of your script for MESSAGE_ID in journald
export SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")|| exit 100
# Define the full path of your script for CODE_FILE in journald
export FULL_PATH=$(readlink -f "${BASH_SOURCE[0]}")|| exit 100

# Includes
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"|| exit 100
source "$(dirname "${BASH_SOURCE[0]}")/remove_yaml_entries.sh"|| exit 100
source "$(dirname "${BASH_SOURCE[0]}")/add_yaml_entries.sh"|| exit 100
source "$(dirname "${BASH_SOURCE[0]}")/check_registries.sh"|| exit 100
source "$(dirname "${BASH_SOURCE[0]}")/sync_registries.sh"|| exit 100
source "$(dirname "${BASH_SOURCE[0]}")/validate_manifests.sh"|| exit 100

SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")
PROJECT_ROOT=$(readlink -f "$SCRIPT_DIR/..")
CONFIG_FILE="$PROJECT_ROOT/config/sync-config.yaml"

REGISTRY_URL=$(yq '.registry.url' "${CONFIG_FILE}")
REGISTRY_USER=$(yq '.registry.user' "${CONFIG_FILE}")
REGISTRY_PASS=$(yq '.registry.password' "${CONFIG_FILE}")

declare CACHE_DIR="/tmp/$SCRIPT_NAME/YYYYMMDD"

if [ ! -d "$CACHE_DIR" ]; then
    /usr/bin/mkdir -p -v "$CACHE_DIR"|| exit 100
fi
trap '/bin/rm -rf "$CACHE_DIR"' INT TERM

#dependency check
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
	--source "docker.io/library/alpine:3.22" \
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
