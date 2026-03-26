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
    response=$(curl -s -w "%{http_code}" "https://api.github.com/repos/CleverRaven/Cataclysm-DDA/releases?per_page=1")
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')
    if [ "$http_code" -ne 200 ]; then
        log_error "GitHub API request failed (HTTP $http_code)"
        exit 1
    fi
    latest_tag=$(echo "$body" | jq -r '.[0].tag_name')
    if [ -z "$latest_tag" ] || [ "$latest_tag" = "null" ]; then
        log_error "Failed to parse latest tag"
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
    if ! git diff-index --quiet HEAD --; then
        log_warn "Local modifications detected"
        if [ "$YES_MODE" = false ]; then
            read -p "Force checkout (lose changes)? (y/N) " answer
            if [[ ! "$answer" =~ ^[Yy]$ ]]; then
                log_info "Aborted"
                exit 0
            fi
        else
            log_info "Auto mode, forcing checkout"
        fi
        git checkout --force "tags/$TAG"
    else
        git checkout "tags/$TAG"
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