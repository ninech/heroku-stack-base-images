#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
. bin/stack-helpers.sh

REPO="${DOCKER_IMAGE_NAME:-ghcr.io/ninech/deploio-heroku}"
STACK_VERSION=${1:-"NAN"}
read -ra ARCHS <<< "${@:2}"
BASE_NAME=$(basename "${BASH_SOURCE[0]}")

print_usage(){
	>&2 echo "usage: ${BASE_NAME}  STACK_VERSION [TARGET_ARCH]..."
	>&2 cat <<-EOF

		This script builds Heroku base image groups, stores them in the local
		image store, and writes package lists for those images. A base image
		group consists of all image variants for a particular stack version.
		This script is capable of building single architecture image groups
		for all stack versions. It also supports building multi-arch image
		groups for heroku-24 (and newer). It works in the following scenarios:

		Single architecture builds -- build a base image group for a single
		target architecture. Heroku-22 and prior support 'amd64' exclusively.
		Heroku-24 and beyond additionally support 'arm64'. If targeting a
		different architecture than the host machine, Docker Desktop and the
		'containerd' snapshotter are required.

		Examples:
		${BASE_NAME} 22 amd64
		${BASE_NAME} 24 arm64

		Multi-architecture builds -- build a heroku base image index group for
		multiple target architectures. This mode is only supported for
		heroku-24 and beyond. This mode requires Docker Desktop and the
		'containerd' snapshotter, and as a result will not work in CI
		environments.

		Examples:
		${BASE_NAME} 24
		${BASE_NAME} 24 arm64 amd64

	EOF
}

[[ $STACK_VERSION =~ ^[0-9]+$ ]] || (>&2 print_usage && abort "fatal: invalid STACK_VERSION")

have_containerd_snapshotter=
if docker info -f "{{ .DriverStatus }}" | grep -qF "io.containerd.snapshotter."; then
	have_containerd_snapshotter=1;
fi

if (( ${#ARCHS[@]} == 0 )); then
	ARCHS=("amd64" "arm64")
fi
VARIANTS=("-build:")

if (( ${#ARCHS[@]} > 1 )) && [[ ! $have_containerd_snapshotter ]] ; then
	>&2 print_usage
	abort "fatal: 'containerd' snapshotter required for multi-arch builds"
fi

write_package_list() {
	local image_tag="$1"
	local dockerfile_dir="$2"
	for arch in "${ARCHS[@]}"; do
		output_file="${dockerfile_dir}/installed-packages-${arch}.txt"
		display "Generating package list: ${output_file}"
		echo "# List of packages present in the final image. Regenerate using bin/build.sh" > "$output_file"
		# We include the package status in the output so we can differentiate between fully installed
		# packages, and those that have been removed but not purged (either because we forgot to purge,
		# or because we intentionally left config files behind, such as for `ca-certificates-java`).
		docker run --rm --platform="linux/${arch}" "$image_tag" dpkg-query --show --showformat='${Package} (package status: ${db:Status-Status})\n' \
			| sed -e 's/ (package status: installed)//' >> "$output_file"
	done
}


RUN_IMAGE_TAG="${REPO}:${STACK_VERSION}"
RUN_DOCKERFILE_DIR="heroku-${STACK_VERSION}"
[[ -d "${RUN_DOCKERFILE_DIR}" ]] || abort "fatal: directory ${RUN_DOCKERFILE_DIR} not found"
DOCKER_PLATFORM="linux/${ARCHS[0]}"
for arch in "${ARCHS[@]:1}"; do
	DOCKER_PLATFORM="${DOCKER_PLATFORM},linux/${arch}"
done

display "Building ${RUN_DOCKERFILE_DIR} / ${RUN_IMAGE_TAG} image for ${DOCKER_PLATFORM}"
# The --pull option is used for the run image, so that the latest updates
# from upstream ubuntu images are included.
docker buildx build --pull --load --no-cache \
	--platform "${DOCKER_PLATFORM}" \
	--tag "${RUN_IMAGE_TAG}" "${RUN_DOCKERFILE_DIR}" | indent

write_package_list "${RUN_IMAGE_TAG}" "${RUN_DOCKERFILE_DIR}"

for VARIANT in "${VARIANTS[@]}"; do
	VARIANT_NAME=$(echo "$VARIANT" | cut -d ":" -f 1)
	DEPENDENCY_NAME=$(echo "$VARIANT" | cut -d ":" -f 2)
	VARIANT_IMAGE_TAG="${REPO}:${STACK_VERSION}${VARIANT_NAME}"
	VARIANT_DOCKERFILE_DIR="heroku-${STACK_VERSION}${VARIANT_NAME}"
	DEPENDENCY_IMAGE_TAG="${REPO}:${STACK_VERSION}${DEPENDENCY_NAME}"

	[[ -d "${VARIANT_DOCKERFILE_DIR}" ]] || abort "fatal: directory ${VARIANT_DOCKERFILE_DIR} not found"
	display "Building ${VARIANT_DOCKERFILE_DIR} / ${VARIANT_IMAGE_TAG} image for ${DOCKER_PLATFORM}"
	# The --pull option is not used for variants since they depend on images
	# built earlier in this script.
	docker buildx build --load --no-cache \
		--platform "${DOCKER_PLATFORM}" \
		--build-arg "BASE_IMAGE=${DEPENDENCY_IMAGE_TAG}" \
		--tag "${VARIANT_IMAGE_TAG}" "${VARIANT_DOCKERFILE_DIR}" | indent

	write_package_list "$VARIANT_IMAGE_TAG" "$VARIANT_DOCKERFILE_DIR"
done

display "Size breakdown..."
docker images --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}" \
	| grep -E "(ubuntu|ninech)" | sed '1!G;h;$!d' | indent
