#!/data/data/com.termux/files/usr/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/cdda-common.sh"

WORK_DIR="${WORK_DIR:-$HOME/Cataclysm-DDA}"

YES_MODE=false
TAG=""
while [ $# -gt 0 ]; do
    case "$1" in
        --yes|-y) YES_MODE=true; shift ;;
        *) [ -z "$TAG" ] && TAG="$1"; shift ;;
    esac
done

[ -z "$TAG" ] && TAG="latest"

# Fetch latest tag if requested
if [ "$TAG" = "latest" ]; then
    log_step "Fetching latest release tag..."
    command -v curl &>/dev/null || { log_error "curl is required"; exit 1; }
    command -v jq &>/dev/null || { log_error "jq is required"; exit 1; }

    # Wrap curl in a conditional to avoid silent exit on failure
    if ! response=$(curl -s -f -w "%{http_code}" --connect-timeout 15 --max-time 60 \
        "https://api.github.com/repos/CleverRaven/Cataclysm-DDA/releases?per_page=1" 2>&1); then
        log_error "Network request failed. Please check your internet connection or proxy settings."
        exit 1
    fi

    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')

    case "$http_code" in
        200)
            latest_tag=$(echo "$body" | jq -r '.[0].tag_name')
            if [ -z "$latest_tag" ] || [ "$latest_tag" = "null" ]; then
                log_error "Failed to parse latest tag. API response may be invalid."
                exit 1
            fi
            TAG="$latest_tag"
            log_info "Latest tag: $TAG"
            ;;
        403)
            log_error "GitHub API request denied (HTTP 403)"
            log_error "Possible reasons:"
            log_error "  - Rate limit exceeded. Please wait a few minutes and try again."
            log_error "  - IP address temporarily blocked."
            log_error "If the problem persists, try using a VPN or proxy."
            exit 1
            ;;
        000)
            log_error "Network connection failed (HTTP 000)."
            log_error "Please check your network, proxy settings, or try accessing GitHub manually."
            exit 1
            ;;
        *)
            log_error "GitHub API request failed (HTTP $http_code)"
            [ -n "$body" ] && log_error "Response: $body"
            exit 1
            ;;
    esac
fi

# Clone or update repository
if [ ! -d "$WORK_DIR" ]; then
    log_info "Cloning tag $TAG (shallow)..."
    git clone --depth 1 --branch "$TAG" https://github.com/CleverRaven/Cataclysm-DDA.git "$WORK_DIR"
else
    log_info "Updating to tag $TAG ..."
    cd "$WORK_DIR"
    # Try shallow fetch of the tag itself
    if git fetch origin "+refs/tags/$TAG:refs/tags/$TAG" --depth 1 ; then
        git checkout "tags/$TAG"
    # If that fails, try fetching the commit the tag points to
    elif git fetch origin "+refs/tags/$TAG^{}:refs/tags/$TAG" --depth 1 ; then
        git checkout "tags/$TAG"
    else
        log_error "Cannot fetch tag $TAG with shallow clone."
        log_error "Please delete '$WORK_DIR' and re-run, or use a full clone manually."
        exit 1
    fi
fi

# Configure local.properties
cd "$WORK_DIR/android" || { log_error "android directory missing"; exit 1; }
log_step "Writing local.properties ..."
cat > local.properties <<EOF
j=$(nproc)
sdk.dir=$ANDROID_HOME
ndk.dir=$ANDROID_NDK_HOME
override_ndkVersion=$NDK_VERSION
override_compileSdkVersion=$(find_platform_version)
override_targetSdkVersion=$(find_platform_version)
EOF

log_info "Project configuration complete!"
