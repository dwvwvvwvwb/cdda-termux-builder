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

if [ "$TAG" = "latest" ]; then
    log_step "$(get_txt "Fetching latest release tag...")"
    command -v curl &>/dev/null || { log_error "$(get_txt "curl is required")"; exit 1; }
    command -v jq &>/dev/null || { log_error "$(get_txt "jq is required")"; exit 1; }

    API_URL="https://api.github.com/repos/CleverRaven/Cataclysm-DDA/releases?per_page=1"

    # Token is optional: public repos allow anonymous access, but rate limits differ.
    #   With token:    5000 requests/hour (per token)
    #   Without token: 60 requests/hour (per IP), and shared IPs are easily rate-limited
    curl_args=(
        -sS
        -w "\n__CODE__%{http_code}"
        --connect-timeout 15
        --max-time 60
        -H "Accept: application/vnd.github+json"
    )
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        curl_args+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
        log_info "$(get_txt "Using GITHUB_TOKEN for authentication")"
    else
        log_warn "$(get_txt "GITHUB_TOKEN is not set; falling back to anonymous requests")"
        log_warn "$(get_txt "Anonymous rate limit is only 60 requests/hour (per IP); shared IPs may be rate-limited")"
        log_warn "$(get_txt "Consider: export GITHUB_TOKEN=ghp_xxx to avoid unexpected 403s")"
    fi

    if response=$(curl "${curl_args[@]}" "$API_URL" 2>&1); then
        curl_rc=0
    else
        curl_rc=$?
    fi

    # ===== Network-layer failure: curl exited non-zero, no trustworthy HTTP response =====
    if [ "$curl_rc" -ne 0 ]; then
        case "$curl_rc" in
            6) reason="$(get_txt "DNS resolution failed (bad hostname / DNS unavailable)")" ;;
            7) reason="$(get_txt "TCP connection failed (bad port / firewall / proxy unreachable)")" ;;
            28) reason="$(get_txt "Request timed out (--connect-timeout or --max-time exceeded)")" ;;
            5) reason="$(get_txt "Could not resolve proxy host")" ;;
            35) reason="$(get_txt "TLS/SSL handshake failed (certificate issue)")" ;;
            18) reason="$(get_txt "Transfer interrupted; incomplete data")" ;;
            *) reason="$(get_txt "Other network error")" ;;
        esac
        log_error "$(printf "$(get_txt "Network-layer failure (curl exit code %s): %s")" "$curl_rc" "$reason")"
        log_error "$(get_txt "curl output:") ${response}"
        exit 1
    fi

    # ===== HTTP layer: parse status code and body =====
    http_code=$(printf '%s\n' "$response" | sed -n 's/.*__CODE__\([0-9]\{3\}\)$/\1/p')
    body=$(printf '%s' "$response" | sed 's/__CODE__[0-9]\{3\}$//')

    case "$http_code" in
        200)
            latest_tag=$(printf '%s' "$body" | jq -r '.[0].tag_name // empty')
            if [ -z "$latest_tag" ]; then
                log_error "$(get_txt "Failed to parse latest tag; API response:") $body"
                exit 1
            fi
            TAG="$latest_tag"
            log_info "$(get_txt "Latest tag:") $TAG"
            ;;
        401)
            log_error "$(get_txt "GitHub authentication failed (HTTP 401): token is invalid, expired, or revoked")"
            log_error "$(get_txt "Response:") $body"
            exit 1
            ;;
        403)
            log_error "$(get_txt "GitHub API request denied (HTTP 403): insufficient permissions or rate limit exceeded")"
            if [ -z "${GITHUB_TOKEN:-}" ]; then
                log_error "$(get_txt "Anonymous request: likely the 60/hour limit or shared-IP rate limiting")"
                log_error "$(get_txt "Suggestion: export GITHUB_TOKEN=ghp_xxx and retry")"
            else
                log_error "$(get_txt "If rate-limited, check X-RateLimit-Remaining / Retry-After response headers")"
            fi
            log_error "$(get_txt "Response:") $body"
            exit 1
            ;;
        404)
            log_error "$(get_txt "Repository or endpoint not found (HTTP 404): check repo name or token permissions")"
            log_error "$(get_txt "Response:") $body"
            exit 1
            ;;
        429)
            log_error "$(get_txt "Rate limit exceeded (HTTP 429): retry later")"
            log_error "$(get_txt "Response:") $body"
            exit 1
            ;;
        000)
            # Defensive branch: curl received no HTTP response at all.
            log_error "$(get_txt "No HTTP response received (000): network-layer failure; no server-side details available")"
            log_error "$(get_txt "Check: connectivity / DNS / proxy / firewall / TLS certificates")"
            [ -n "$body" ] && log_error "$(get_txt "curl output:") $body"
            exit 1
            ;;
        5??)
            log_error "$(printf "$(get_txt "GitHub server error (HTTP %s): retry later")" "$http_code")"
            log_error "$(get_txt "Response:") $body"
            exit 1
            ;;
        *)
            log_error "$(printf "$(get_txt "Unexpected status code (HTTP %s): neither an expected HTTP code nor 000")" "${http_code:-empty}")"
            [ -n "$body" ] && log_error "$(get_txt "Response:") $body"
            exit 1
            ;;
    esac
fi

# Clone or update repository
if [ ! -d "$WORK_DIR" ]; then
    log_info "$(printf "$(get_txt "Cloning tag %s (shallow)...")" "$TAG")"
    git clone --depth 1 --branch "$TAG" https://github.com/CleverRaven/Cataclysm-DDA.git "$WORK_DIR"
else
    log_info "$(printf "$(get_txt "Updating to tag %s ...")" "$TAG")"
    cd "$WORK_DIR"
    # Try shallow fetch of the tag itself
    if git fetch origin "+refs/tags/$TAG:refs/tags/$TAG" --depth 1 ; then
        git checkout "tags/$TAG"
    # If that fails, try fetching the commit the tag points to
    elif git fetch origin "+refs/tags/$TAG^{}:refs/tags/$TAG" --depth 1 ; then
        git checkout "tags/$TAG"
    else
        log_error "$(printf "$(get_txt "Cannot fetch tag %s with shallow clone.")" "$TAG")"
        log_error "$(printf "$(get_txt "Please delete '%s' and re-run, or use a full clone manually.")" "$WORK_DIR")"
        exit 1
    fi
fi

# Configure local.properties
cd "$WORK_DIR/android" || { log_error "$(get_txt "android directory missing")"; exit 1; }
log_step "$(get_txt "Writing local.properties ...")"
cat > local.properties <<EOF
j=$(nproc)
sdk.dir=$ANDROID_HOME
ndk.dir=$ANDROID_NDK_HOME
override_ndkVersion=$NDK_VERSION
override_compileSdkVersion=$(find_platform_version)
override_targetSdkVersion=$(find_platform_version)
EOF

log_info "$(get_txt "Project configuration complete!")"
