#!/usr/bin/env bash

set -euo pipefail

should_release=false

for variant in "" "-build"; do
  nightly_tag="${DOCKER_IMAGE_NAME}:24${variant}.nightly"
  stable_tag="${DOCKER_IMAGE_NAME}:24${variant}"

  nightly_digest=$(crane digest "${nightly_tag}" 2>/dev/null || echo "")
  stable_digest=$(crane digest "${stable_tag}" 2>/dev/null || echo "")

  if [[ -z "${nightly_digest}" ]]; then
    echo "Nightly image ${nightly_tag} does not exist, skipping release"
    echo "should-release=false" >> "$GITHUB_OUTPUT"
    exit 0
  fi

  if [[ -z "${stable_digest}" ]] || [[ "${nightly_digest}" != "${stable_digest}" ]]; then
    should_release=true
  fi
done

latest_tag=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
if [[ -z "$latest_tag" ]]; then
  next_tag="v1"
  from_tag=""
else
  tag_number="${latest_tag#v}"
  next_number=$((tag_number + 1))
  next_tag="v${next_number}"
  from_tag="$latest_tag"
fi

{
  echo "should-release=${should_release}"
  echo "next-tag=${next_tag}"
  echo "from-tag=${from_tag}"
} >> "$GITHUB_OUTPUT"
echo "Should release: ${should_release}, Next tag: ${next_tag}, From tag: ${from_tag}"
