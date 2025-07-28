#!/bin/bash

# includes
source "/ARISU/scripts/error_handling.sh"
source "/ARISU/scripts/remove_yaml_entries.sh"
source "/ARISU/scripts/add_yaml_entries.sh"
source "/ARISU/scripts/check_registries.sh"
source "/ARISU/scripts/sync_registries.sh"
source "/ARISU/scripts/validate_manifests.sh"

CONFIG_FILE="/ARISU/config/sync-config.yaml"

REGISTRY_URL=$(yq '.registry.url' "${CONFIG_FILE}")
REGISTRY_USER=$(yq '.registry.user' "${CONFIG_FILE}")
REGISTRY_PASS=$(yq '.registry.password' "${CONFIG_FILE}")

SCRIPT_NAME=$(/usr/bin/basename "${BASH_SOURCE[0]}")|| exit 100
FULL_PATH=$(/usr/bin/realpath "${BASH_SOURCE[0]}")|| exit 100
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

loop_through_yaml_config_for_skopeo "${CONFIG_FILE}" "${REGISTRY_URL}"

echo "--- Syncing Helm Charts ---"

loop_through_yaml_config_for_helm "${CONFIG_FILE}" "${REGISTRY_URL}"

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
