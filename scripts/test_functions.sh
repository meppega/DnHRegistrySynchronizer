#!/bin/bash

set -e

#helm repo add bitnami https://charts.bitnami.com/bitnami
# helm repo update
# helm pull bitnami/nginx --version 15.14.0
# helm push nginx-15.14.0.tgz oci://localhost:5000/charts/

# # test
# helm pull oci://localhost:5000/charts/nginx
# helm pull oci://localhost:5000/charts/nginx --version 15.14.0

CONFIG_FILE="/sync-config.yaml"
REGISTRY_URL=$(yq '.registry.url' "${CONFIG_FILE}")

check_registry_images() {
	echo "--- Checking Registry Images against Config ---"

	declare -A expected_images # Images listed in sync-config.yaml
	declare -A actual_images   # Images actually found in the registry

	# 1. Get expected images from sync-config.yaml
	# For Docker
	echo "  > Reading expected Docker images from ${CONFIG_FILE}..."
	image_count=$(yq '.dockerImages | length' "${CONFIG_FILE}")
	for i in $(seq 0 $((image_count - 1))); do
		SOURCE_IMAGE=$(yq ".dockerImages[$i].source" "${CONFIG_FILE}")
		DEST_PATH=$(yq ".dockerImages[$i].destinationPath" "${CONFIG_FILE}")
		EXPECTED_DEST_IMAGE="${DEST_PATH}"
		# echo ${EXPECTED_DEST_IMAGE}
		expected_images["${EXPECTED_DEST_IMAGE}"]=1 # Store as key for quick existence check
	done
	# For Helm
	image_count=$(yq '.helmCharts | length' "${CONFIG_FILE}")
	for i in $(seq 0 $((image_count - 1))); do
		CHART_NAME=$(yq ".helmCharts[$i].chartName" "${CONFIG_FILE}")
		CHART_VERSION=$(yq ".helmCharts[$i].chartVersion" "${CONFIG_FILE}")
		DEST_PATH=$(yq ".helmCharts[$i].destinationPath" "${CONFIG_FILE}")
		EXPECTED_DEST_IMAGE="${DEST_PATH}${CHART_NAME}:${CHART_VERSION}"
		# echo ${EXPECTED_DEST_IMAGE}
		expected_images["${EXPECTED_DEST_IMAGE}"]=1
	done

	# 2. Get actual images from the local registry using Docker Registry API
	echo "  > Fetching repository catalog from http://${REGISTRY_URL}/v2/_catalog..."
	# Fetch list of repositories from the registry catalog
	REPOS=$(curl -s -u "${REGISTRY_USER}:${REGISTRY_PASS}" "http://${REGISTRY_URL}/v2/_catalog" | jq -r '.repositories[]')

	if [ -z "$REPOS" ]; then
		echo "  No repositories found in registry or failed to connect to ${REGISTRY_URL}. Skipping detailed check."
	else
		# Iterate through each repository to get its tags
		for REPO in $REPOS; do
			echo "  > Fetching tags for repository: ${REPO}..."
			# Fetch list of tags for the current repository
			TAGS=$(curl -s -u "${REGISTRY_USER}:${REGISTRY_PASS}" "http://${REGISTRY_URL}/v2/${REPO}/tags/list" | jq -r '.tags[]')
			# Construct full image names (repo:tag) and add to actual_images array
			for TAG in $TAGS; do
				ACTUAL_IMAGE="${REPO}:${TAG}"
				actual_images["${ACTUAL_IMAGE}"]=1
			done
		done
	fi

	# 3. Compare: Identify missing images (in config, not in registry)
	echo ""
	echo "--- Missing Images (in config, not in registry) ---"
	MISSING_COUNT=0
	for expected_image in "${!expected_images[@]}"; do
		# Check if the expected image exists in the actual_images array
		if [[ ! -v actual_images["${expected_image}"] ]]; then
			echo "  MISSING: ${expected_image}"
			MISSING_COUNT=$((MISSING_COUNT + 1))
		fi
	done
	if [ "$MISSING_COUNT" -eq 0 ]; then
		echo "  All expected images are present in the registry."
	else
		echo "  Total missing images: ${MISSING_COUNT}"
	fi

	# 4. Compare: Identify unexpected images (in registry, not in config)
	echo ""
	echo "--- Unexpected Images (in registry, not in config) ---"
	UNEXPECTED_COUNT=0
	for actual_image in "${!actual_images[@]}"; do
		# Check if the actual image exists in the expected_images array
		if [[ ! -v expected_images["${actual_image}"] ]]; then
			echo "  UNEXPECTED: ${actual_image}"
			UNEXPECTED_COUNT=$((UNEXPECTED_COUNT + 1))
		fi
	done
	if [ "$UNEXPECTED_COUNT" -eq 0 ]; then
		echo "  No unexpected images found in the registry (based on config)."
	else
		echo "  Total unexpected images: ${UNEXPECTED_COUNT}"
	fi

	echo "--- Registry Image Check Complete ---"
}

check_registry_images
