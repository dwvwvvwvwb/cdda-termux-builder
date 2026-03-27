#!/data/data/com.termux/files/usr/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/cdda-common.sh"

WORK_DIR="${WORK_DIR:-$HOME/Cataclysm-DDA}"

YES_MODE=false
TAG=""
while [ $# -gt 0 ]; do
    case "$1" in
        --yes|-y)
            YES_MODE=true
            shift
            ;;
        *)
            if [ -z "$TAG" ]; then
                TAG="$1"
            fi
            shift
            ;;
    esac
done

if [ -z "$TAG" ]; then
    TAG="latest"
fi

if [ "$TAG" = "latest" ]; then
    log_step "Fetching latest release tag..."
    if ! command -v curl &>/dev/null || ! command -v jq &>/dev/null; then
        log_error "curl and jq required to fetch latest tag, please run setup first"
        exit 1
    fi
    response=$(curl -s -f -w "%{http_code}" --connect-timeout 10 --max-time 30 \
        "https://api.github.com/repos/CleverRaven/Cataclysm-DDA/releases?per_page=1" 2>&1)
    curl_exit=$?
    if [ $curl_exit -ne 0 ]; then
        log_error "Network request failed, please check your connection"
        exit 1
    fi
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')
    if [ "$http_code" -ne 200 ]; then
        log_error "GitHub API request failed (HTTP $http_code)"
        log_info "You can manually specify a tag: ./cdda.sh config <tag>"
        exit 1
    fi
    latest_tag=$(echo "$body" | jq -r '.[0].tag_name')
    if [ -z "$latest_tag" ] || [ "$latest_tag" = "null" ]; then
        log_error "Failed to parse latest tag, check network or try again later"
        exit 1
    fi
    TAG="$latest_tag"
    log_info "Latest tag: $TAG"
fi

if [ ! -d "$WORK_DIR" ]; then
    log_info "Cloning CDDA source (shallow clone)..."
    git clone --depth 1 https://github.com/CleverRaven/Cataclysm-DDA.git "$WORK_DIR"
fi

if [ -n "$TAG" ]; then
    log_info "Switching to tag $TAG ..."
    cd "$WORK_DIR"
    if ! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1; then
        log_info "Tag not found locally, trying to fetch..."
        if git fetch origin "tags/$TAG" --depth 1 2>/dev/null; then
            log_info "Tag fetched successfully"
        else
            log_error "Shallow clone cannot fetch tag $TAG."
            log_error "This may happen if the tag is not in the latest commit history."
            log_error "Please delete the directory '$WORK_DIR' and re-run, or do a full clone manually:"
            log_error "  rm -rf '$WORK_DIR'"
            log_error "  git clone https://github.com/CleverRaven/Cataclysm-DDA.git '$WORK_DIR'"
            log_error "  cd '$WORK_DIR' && git fetch --tags && git checkout tags/$TAG"
            exit 1
        fi
    fi
    if ! git checkout "tags/$TAG" 2>/dev/null; then
        log_error "Failed to checkout tag $TAG, please verify the tag exists"
        exit 1
    fi
fi

cd "$WORK_DIR/android" || { log_error "android directory not found"; exit 1; }

log_step "Writing local.properties ..."
cat > local.properties <<EOF
sdk.dir=$ANDROID_HOME
ndk.dir=$ANDROID_NDK_HOME
override_ndkVersion=$NDK_VERSION
override_compileSdkVersion=$(find_platform_version)
override_targetSdkVersion=$(find_platform_version)
EOF

log_info "Project configuration complete!"