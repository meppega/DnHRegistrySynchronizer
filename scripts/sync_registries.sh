#!/bin/bash

#set -eu
#set -o pipefail
set -o errexit
set -o nounset

CONFIG_FILE="/ARISU/config/sync-config.yaml"

REGISTRY_URL=$(yq '.registry.url' "${CONFIG_FILE}")
REGISTRY_USER=$(yq '.registry.user' "${CONFIG_FILE}")
REGISTRY_PASS=$(yq '.registry.password' "${CONFIG_FILE}")

. "/ARISU/scripts/remove_yaml_entries.sh"

#Function to check if all necessary dependencies are installed
check_dependencies() {
    local deps=("yq" "skopeo" "helm" "curl" "jq" "sha256sum")
    for dep in "${deps[@]}"; do
        if ! command -v "${dep}" &> /dev/null; then
            echo "${LINENO}: Error: Required command '$dep' \
				is not installed. Please install it."
            exit 1
        fi
    done
	echo "All dependencies present"
}

#TODO: add comparing if images are different
check_and_sync_helm() {
	local repo_name="$1"
	local repo_url="$2"
	local chart_name="$3"
	local chart_version="$4"
	local dest_repo="$5"
	local file_name="${chart_name}-${chart_version}"

	if helm show chart "${dest_repo}${chart_name}" --plain-http >/dev/null 2>&1; then
		echo "Chart ${dest_repo}${chart_name} exists. Skipping."
		return
	fi

	echo "Chart does not exist. Adding ${dest_repo}${chart_name}"

	echo "  > Adding Helm repository: ${repo_name} ..."
	helm repo add "${repo_name}" "${repo_url}" --force-update
	helm repo update

	echo "  > Pulling Helm chart from traditional repository..."
	helm pull "${chart_name}" --repo "${repo_url}" --version "${chart_version}" --destination /tmp

	if [ ! -f "/tmp/${file_name}.tgz" ]; then
		echo "Error: Chart ${HELM_CHART}.tgz failed to download. Skipping."
		return
	fi

	helm push \
		"/tmp/${file_name}.tgz" \
		"${dest_repo}" \
		--plain-http

	rm -f "/tmp/*.tgz"
}

check_and_sync_skopeo() {
	local source_image="$1"
	local dest_image="$2"
    local version="$3"

	echo "Checking if ${dest_image} : ${version} exists in registry..."
	if skopeo inspect "docker://${dest_image}:${version}" --tls-verify=false >/dev/null 2>&1; then
		echo "${dest_image}:${version} already exists. Running sync."
            
        #TODO: add yaml file for synchronization
        # skopeo sync \
        #     --src docker \
        #     --dest docker \
        #     "docker://${source_image}:${version}" \
        #     "docker://${dest_image}:${version}" \
        #     --dest-tls-verify=false
		return
	fi

	echo "${dest_image}:${version} not found. Copying..."
	skopeo copy \
        "docker://${source_image}:${version}" \
        "docker://${dest_image}:${version}" \
        --dest-tls-verify=false
        #--preserve-digests \
        #\ --multi-arch all \
        # --dest-precompute-digests
}

loop_through_yaml_config_for_helm() {
	local config_file="$1"
	local registry_url="$2"

    local chart_count=0
    local repo_name=""
    local repo_url=""
    local chart_name=""
    local chart_vertion="" 
    local dest_path=""

    chart_count=$(yq '.helmCharts | length' "${config_file}")

	for i in $(seq 0 $((chart_count - 1))); do
		repo_name=$(yq ".helmCharts[$i].repoName" "${config_file}")
		repo_url=$(yq ".helmCharts[$i].repoUrl" "${config_file}")
		chart_name=$(yq ".helmCharts[$i].chartName" "${config_file}")
		chart_vertion=$(yq ".helmCharts[$i].chartVersion" "${config_file}")
		dest_path=$(yq ".helmCharts[$i].destinationPath" "${config_file}")

		check_and_sync_helm \
			"${repo_name}" \
			"${repo_url}" \
			"${chart_name}" \
			"${chart_vertion}" \
			"oci://${registry_url}/${dest_path}"
	done
}

loop_through_yaml_config_for_skopeo() {
	local config_file="$1"
	local registry_url="$2"

    local image_count=0
    local source_image=""
    local dest_path=""
    local version=""

    image_count=$(yq '.dockerImages | length' "${config_file}")

	for i in $(seq 0 $((image_count - 1))); do
		source_image=$(yq ".dockerImages[$i].source" "${config_file}")
		dest_path=$(yq ".dockerImages[$i].destinationPath" "${config_file}")
        version=$(yq ".dockerImages[$i].version" "${config_file}")

		check_and_sync_skopeo "${source_image}" "${registry_url}/${dest_path}" "${version}"
	done
}

# Run dependency check
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

# /check_registries.sh
# exec /validate_manifests.sh

remove_yaml_entries "${CONFIG_FILE}" image \
	--registry-path "images/alpine" \
	--version "3.22"
/ARISU/scripts/add_yaml_entries.sh image \
	--source "docker.io/library/alpine:3.22" \
	--destination "images/alpine" \
	--version "3.22"

remove_yaml_entries "${CONFIG_FILE}" chart \
    --chart-name "nginx" \
    --chart-version "15.14.0"
/ARISU/scripts/add_yaml_entries.sh chart \
    --repo-name "bitnami" \
    --repo-url "https://charts.bitnami.com/bitnami" \
    --chart-name "nginx" \
    --chart-version "15.14.0" \
    --destination "charts/"
