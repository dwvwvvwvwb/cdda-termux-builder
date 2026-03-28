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
    command -v curl &>/dev/null || { log_error "curl required"; exit 1; }
    command -v jq &>/dev/null || { log_error "jq required"; exit 1; }
    response=$(curl -s -f -w "%{http_code}" --connect-timeout 10 --max-time 30 \
        "https://api.github.com/repos/CleverRaven/Cataclysm-DDA/releases?per_page=1" 2>&1)
    [ $? -ne 0 ] && { log_error "Network request failed"; exit 1; }
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')
    [ "$http_code" -ne 200 ] && { log_error "GitHub API failed (HTTP $http_code)"; exit 1; }
    latest_tag=$(echo "$body" | jq -r '.[0].tag_name')
    [ -z "$latest_tag" ] || [ "$latest_tag" = "null" ] && { log_error "Failed to parse latest tag"; exit 1; }
    TAG="$latest_tag"
    log_info "Latest tag: $TAG"
fi

# Clone or update repository
if [ ! -d "$WORK_DIR" ]; then
    log_info "Cloning tag $TAG (shallow)..."
    git clone --depth 1 --branch "$TAG" https://github.com/CleverRaven/Cataclysm-DDA.git "$WORK_DIR"
else
    log_info "Updating to tag $TAG ..."
    cd "$WORK_DIR"
    # Try shallow fetch of the tag itself
    if git fetch origin "+refs/tags/$TAG:refs/tags/$TAG" --depth 1 2>/dev/null; then
        git checkout "tags/$TAG"
    # If that fails, try fetching the commit the tag points to
    elif git fetch origin "+refs/tags/$TAG^{}:refs/tags/$TAG" --depth 1 2>/dev/null; then
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
sdk.dir=$ANDROID_HOME
ndk.dir=$ANDROID_NDK_HOME
override_ndkVersion=$NDK_VERSION
override_compileSdkVersion=$(find_platform_version)
override_targetSdkVersion=$(find_platform_version)
EOF

log_info "Project configuration complete!"
