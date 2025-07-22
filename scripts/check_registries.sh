#!/bin/bash

set -o errexit
set -o nounset
#set -o pipefail

#helm repo add bitnami https://charts.bitnami.com/bitnami
# helm repo update
# helm pull bitnami/nginx --version 15.14.0
# helm push nginx-15.14.0.tgz oci://localhost:5000/charts/

# # test
# helm pull oci://localhost:5000/charts/nginx
# helm pull oci://localhost:5000/charts/nginx --version 15.14.0

readonly CONFIG_FILE="/sync-config.yaml"
REGISTRY_URL=$(yq '.registry.url' "${CONFIG_FILE}")
REGISTRY_USER=$(yq '.registry.user' "${CONFIG_FILE}")
REGISTRY_PASS=$(yq '.registry.password' "${CONFIG_FILE}")

check_registry_images() {
	echo "--- Checking Registry Images against Config ---"

	declare -A expected_images # Images listed in sync-config.yaml
	declare -A existing_images   # Images actually found in the registry

	# 1. Get expected images from sync-config.yaml
	# For Docker
	echo "  > Reading expected Docker images from ${CONFIG_FILE}..."
	local image_count=$(yq '.dockerImages | length' "${CONFIG_FILE}")
	for i in $(seq 0 $((image_count - 1))); do
		local source_image=$(yq ".dockerImages[$i].source" "${CONFIG_FILE}")
		local dest_path=$(yq ".dockerImages[$i].destinationPath" "${CONFIG_FILE}")
		local version=$(yq ".dockerImages[$i].version" "${CONFIG_FILE}")
		local expected_dest_image="${dest_path}:${version}"
		# echo ${expected_dest_image}
		expected_images["${expected_dest_image}"]=1 # Store as key
	done
	# For Helm
	local image_count=$(yq '.helmCharts | length' "${CONFIG_FILE}")
	for i in $(seq 0 $((image_count - 1))); do
		local chart_name=$(yq ".helmCharts[$i].chartName" "${CONFIG_FILE}")
		local chart_version=$(yq ".helmCharts[$i].chartVersion" "${CONFIG_FILE}")
		local dest_path=$(yq ".helmCharts[$i].destinationPath" "${CONFIG_FILE}")
		local expected_dest_image="${dest_path}${chart_name}:${chart_version}"
		# echo ${expected_dest_image}
		expected_images["${expected_dest_image}"]=1
	done

	# 2. Get existing images from the registry
	echo "  > Fetching repository catalog from http://${REGISTRY_URL}/v2/_catalog..."
	# Fetch list of repositories from the registry catalog
	local repos=$(curl -s -u "${REGISTRY_USER}:${REGISTRY_PASS}" "http://${REGISTRY_URL}/v2/_catalog" | jq -r '.repositories[]')

	if [ -z "$repos" ]; then
		echo "  No repositories found in registry or failed to connect to ${REGISTRY_URL}. Skipping detailed check."
	else
		for repo in $repos; do
			echo "  > Fetching tags for repository: ${repo}..."
			# Fetch list of tags for the current repository
			local tags=$(curl -s -u "${REGISTRY_USER}:${REGISTRY_PASS}" "http://${REGISTRY_URL}/v2/${repo}/tags/list" | jq -r '.tags[]')
			# Construct full image names (repo:tag) and add to existing_images array
			for tag in $tags; do
				local existing_image="${repo}:${tag}"
				existing_images["${existing_image}"]=1
			done
		done
	fi

	# 3. Compare: Identify missing images (in config, not in registry)
	echo ""
	echo "--- Missing Images (in config, not in registry) ---"
	local missing_count=0
	for expected_image in "${!expected_images[@]}"; do
		# Check if the expected image exists in the existing_images array
		if [[ ! -v existing_images["${expected_image}"] ]]; then
			echo "  MISSING: ${expected_image}"
			missing_count=$((missing_count + 1))
		fi
	done
	if [ "$missing_count" -eq 0 ]; then
		echo "  All expected images are present in the registry."
	else
		echo "  Total missing images: ${missing_count}"
	fi

	# 4. Compare: Identify unexpected images (in registry, not in config)
	echo ""
	echo "--- Unexpected Images (in registry, not in config) ---"
	local unexpected_count=0
	for actual_image in "${!existing_images[@]}"; do
		# Check if the actual image exists in the expected_images array
		if [[ ! -v expected_images["${actual_image}"] ]]; then
			echo "  UNEXPECTED: ${actual_image}"
			unexpected_count=$((unexpected_count + 1))
		fi
	done
	if [ "$unexpected_count" -eq 0 ]; then
		echo "  No unexpected images found in the registry (based on config)."
	else
		echo "  Total unexpected images: ${unexpected_count}"
	fi

	echo "--- Registry Image Check Complete ---"
}

check_registry_images
