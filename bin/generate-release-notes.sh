#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

STACK_VERSION="${1:-}"
IMAGE_REPO="${2:-}"
FROM_TAG="${3:-}"
BASE_NAME=$(basename "${BASH_SOURCE[0]}")

if [[ -z "$STACK_VERSION" ]] || [[ -z "$IMAGE_REPO" ]]; then
    >&2 echo "usage: ${BASE_NAME} STACK_VERSION IMAGE_REPO [FROM_TAG]"
    exit 1
fi

# --- Conventional commits section ---
print_commits() {
    local from_tag="$1"
    local features="" fixes="" breaking=""
    local log_range

    if [[ -n "$from_tag" ]]; then
        log_range="${from_tag}..HEAD"
    else
        log_range="HEAD"
    fi

    local re_breaking='^(feat|fix)(\([^)]*\))?!:'
    local re_breaking_trailer='^BREAKING[[:space:]]CHANGE'
    local re_feat='^feat(\([^)]*\))?:'
    local re_fix='^fix(\([^)]*\))?:'

    while IFS= read -r subject; do
        [[ -z "$subject" ]] && continue
        if [[ "$subject" =~ $re_breaking ]] || [[ "$subject" =~ $re_breaking_trailer ]]; then
            msg="${subject#*: }"
            breaking="${breaking}- ${msg}"$'\n'
        elif [[ "$subject" =~ $re_feat ]]; then
            msg="${subject#*: }"
            features="${features}- ${msg}"$'\n'
        elif [[ "$subject" =~ $re_fix ]]; then
            msg="${subject#*: }"
            fixes="${fixes}- ${msg}"$'\n'
        fi
    done < <(git log "${log_range}" --format='%s' --no-merges 2>/dev/null)

    if [[ -n "$features" ]] || [[ -n "$fixes" ]] || [[ -n "$breaking" ]]; then
        echo "## Changes"
        echo ""
        if [[ -n "$features" ]]; then
            echo "### Features"
            echo ""
            echo -n "$features"
            echo ""
        fi
        if [[ -n "$fixes" ]]; then
            echo "### Fixes"
            echo ""
            echo -n "$fixes"
            echo ""
        fi
        if [[ -n "$breaking" ]]; then
            echo "### Breaking Changes"
            echo ""
            echo -n "$breaking"
            echo ""
        fi
    fi
}

# Compare two package version files and output pipe-delimited change lines.
# Output format: "status|package|old_version|new_version"
diff_packages() {
    local old_file="$1"
    local new_file="$2"
    awk -F= '
        NR==FNR { old[$1]=$2; next }
        {
            pkg=$1; ver=$2
            if (pkg in old) {
                if (old[pkg] != ver) print "updated|" pkg "|" old[pkg] "|" ver
                delete old[pkg]
            } else {
                print "added|" pkg "||" ver
            }
        }
        END {
            for (pkg in old) print "removed|" pkg "|" old[pkg] "|"
        }
    ' "$old_file" "$new_file" | sort -t'|' -k2
}

# Extract package versions from an image using amd64 as the reference architecture.
extract_packages() {
    local image="$1"
    docker run --rm --platform linux/amd64 "${image}" \
        dpkg-query --show --showformat='${Package}=${Version}\n' | sort
}

STABLE_RUN="${IMAGE_REPO}:${STACK_VERSION}"
NIGHTLY_RUN="${IMAGE_REPO}:${STACK_VERSION}.nightly"
STABLE_BUILD="${IMAGE_REPO}:${STACK_VERSION}-build"
NIGHTLY_BUILD="${IMAGE_REPO}:${STACK_VERSION}-build.nightly"

# Check if stable image exists (first release case)
if ! docker pull --platform linux/amd64 "${STABLE_RUN}" >/dev/null 2>&1; then
    print_commits "$FROM_TAG"
    echo "## Package Changelog"
    echo ""
    echo "This is the first release. No package diff available."
    exit 0
fi

docker pull --platform linux/amd64 "${NIGHTLY_RUN}" >/dev/null 2>&1
docker pull --platform linux/amd64 "${STABLE_BUILD}" >/dev/null 2>&1
docker pull --platform linux/amd64 "${NIGHTLY_BUILD}" >/dev/null 2>&1

old_run="$(mktemp)"
new_run="$(mktemp)"
old_build="$(mktemp)"
new_build="$(mktemp)"
trap 'rm -f "$old_run" "$new_run" "$old_build" "$new_build"' EXIT

extract_packages "${STABLE_RUN}" > "$old_run"
extract_packages "${NIGHTLY_RUN}" > "$new_run"
extract_packages "${STABLE_BUILD}" > "$old_build"
extract_packages "${NIGHTLY_BUILD}" > "$new_build"

run_changes="$(diff_packages "$old_run" "$new_run")"
build_changes="$(diff_packages "$old_build" "$new_build")"

# Track which packages changed in the run image (to identify build-time-only changes)
declare -A run_pkgs
if [[ -n "$run_changes" ]]; then
    while IFS='|' read -r _status pkg _old _new; do
        [[ -n "$pkg" ]] && run_pkgs["$pkg"]=1
    done <<< "$run_changes"
fi

run_section=""
while IFS='|' read -r status pkg old_ver new_ver; do
    [[ -z "$pkg" ]] && continue
    case "$status" in
        added)   run_section="${run_section}- **Added** \`${pkg}\` (${new_ver})"$'\n' ;;
        removed) run_section="${run_section}- **Removed** \`${pkg}\` (was ${old_ver})"$'\n' ;;
        updated) run_section="${run_section}- \`${pkg}\`: ${old_ver} → ${new_ver}"$'\n' ;;
    esac
done <<< "${run_changes}"

build_only_section=""
while IFS='|' read -r status pkg old_ver new_ver; do
    [[ -z "$pkg" ]] && continue
    # Skip packages that already appear in the run image diff
    [[ "${run_pkgs[$pkg]+_}" ]] && continue
    case "$status" in
        added)   build_only_section="${build_only_section}- **Added** \`${pkg}\` (${new_ver})"$'\n' ;;
        removed) build_only_section="${build_only_section}- **Removed** \`${pkg}\` (was ${old_ver})"$'\n' ;;
        updated) build_only_section="${build_only_section}- \`${pkg}\`: ${old_ver} → ${new_ver}"$'\n' ;;
    esac
done <<< "${build_changes}"

print_commits "$FROM_TAG"

echo "## Package Changelog"
echo ""

if [[ -n "$run_section" ]]; then
    echo "### Run image (\`heroku-${STACK_VERSION}\`)"
    echo ""
    echo -n "$run_section"
    echo ""
fi

if [[ -n "$build_only_section" ]]; then
    echo "### Build time only (\`heroku-${STACK_VERSION}-build\`)"
    echo ""
    echo -n "$build_only_section"
    echo ""
fi

if [[ -z "$run_section" ]] && [[ -z "$build_only_section" ]]; then
    echo "No package changes."
    echo ""
fi
