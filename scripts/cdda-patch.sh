#!/data/data/com.termux/files/usr/bin/bash
# Patch a self-built APK with official libmain.so + libc++_shared.so
# extracted by the libs repo. Output is an installable .apk, no extra packing.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/cdda-common.sh"

WORK_DIR="${WORK_DIR:-$HOME/Cataclysm-DDA}"
PATCH_CACHE_DIR="${PATCH_CACHE_DIR:-$HOME/.cdda_patch_cache}"
LIBS_REPO="${LIBS_REPO:-dwvwvvwvwb/cdda-termux-builder}"
LIBS_ARCH="${LIBS_ARCH:-arm64}"    # arm64 or arm32, not x64/x32
ABI="arm64-v8a"                    # keep in sync with LIBS_ARCH
TAG_STATE="$HOME/.config/cdda-termux-builder/last_tag"

case "$LIBS_ARCH" in
  arm64) ABI="arm64-v8a" ;;
  arm32) ABI="armeabi-v7a" ;;
  x64)   ABI="arm64-v8a";   LIBS_ARCH="arm64" ;;
  x32)   ABI="armeabi-v7a"; LIBS_ARCH="arm32" ;;
  *) log_error "Unknown LIBS_ARCH: $LIBS_ARCH"; exit 1 ;;
esac

TARGET_TAG=""
while [ $# -gt 0 ]; do
    case "$1" in
        --yes|-y) shift ;;
        --tag) TARGET_TAG="$2"; shift 2 ;;
        *) [ -z "$TARGET_TAG" ] && TARGET_TAG="$1"; shift ;;
    esac
done

mkdir -p "$PATCH_CACHE_DIR"

# ---------- 1. Resolve target tag ----------
if [ -z "$TARGET_TAG" ] || [ "$TARGET_TAG" = "latest" ]; then
    [ -f "$TAG_STATE" ] && TARGET_TAG="$(tr -d '[:space:]' < "$TAG_STATE")"
fi
[ -n "$TARGET_TAG" ] || { log_error "$(get_txt "No target tag; run config first or pass --tag")"; exit 1; }
log_info "$(printf "$(get_txt "Target tag: %s")" "$TARGET_TAG")"

# ---------- 2. Query libs repo release via curl ----------
curl_args=(-sS --connect-timeout 15 --max-time 60
           -H "Accept: application/vnd.github+json"
           -w "\n__CODE__%{http_code}")
if [ -n "${GITHUB_TOKEN:-}" ]; then
    curl_args+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
    log_info "$(get_txt "Using GITHUB_TOKEN for authentication")"
else
    log_warn "$(get_txt "GITHUB_TOKEN not set; anonymous 60/hour limit applies")"
fi

response=$(curl "${curl_args[@]}" \
    "https://api.github.com/repos/$LIBS_REPO/releases/tags/$TARGET_TAG" 2>&1) \
    || { log_error "$(get_txt "Network error fetching release")"; exit 1; }

http_code=$(printf '%s\n' "$response" | sed -n 's/.*__CODE__\([0-9]\{3\}\)$/\1/p')
body=$(printf '%s' "$response" | sed 's/__CODE__[0-9]\{3\}$//')

case "$http_code" in
    200) ;;
    404)
        log_error "$(printf "$(get_txt "Libs release not found for tag %s")" "$TARGET_TAG")"
        log_error "$(get_txt "Wait for the libs repo workflow, or trigger it manually")"
        exit 1
        ;;
    403)
        log_error "$(get_txt "GitHub API 403: rate limit or permissions")"
        log_error "$body"
        exit 1
        ;;
    *)
        log_error "$(printf "$(get_txt "Unexpected HTTP %s")" "$http_code")"
        log_error "$body"
        exit 1
        ;;
esac

# ---------- 3. Locate asset URL ----------
ASSET_NAME="cdda-libs-${LIBS_ARCH}-${TARGET_TAG}.7z"
ASSET_URL=$(printf '%s' "$body" | jq -r --arg n "$ASSET_NAME" \
    '.assets[] | select(.name == $n) | .browser_download_url')
[ -n "$ASSET_URL" ] && [ "$ASSET_URL" != "null" ] || {
    log_error "$(printf "$(get_txt "Asset %s not found in %s")" "$ASSET_NAME" "$TARGET_TAG")"
    log_error "$(printf '%s' "$body" | jq -r '.assets[].name' 2>/dev/null)"
    exit 1
}

# ---------- 4. Download libs archive ----------
CACHED_7Z="$PATCH_CACHE_DIR/$ASSET_NAME"
if [ ! -f "$CACHED_7Z" ]; then
    log_info "$(printf "$(get_txt "Downloading %s ...")" "$ASSET_NAME")"
    curl -L -C - --retry 3 -o "$CACHED_7Z" "$ASSET_URL" \
        || { log_error "$(get_txt "Download failed")"; rm -f "$CACHED_7Z"; exit 1; }
else
    log_info "$(printf "$(get_txt "Using cached %s")" "$CACHED_7Z")"
fi

# ---------- 5. Extract ----------
EXTRACT_DIR="$PATCH_CACHE_DIR/extracted-$TARGET_TAG"
rm -rf "$EXTRACT_DIR"; mkdir -p "$EXTRACT_DIR"
command -v 7zz >/dev/null || command -v 7z >/dev/null \
    || { log_error "$(get_txt "7z not found; pkg install 7zip or p7zip")"; exit 1; }
SEVENZ=$(command -v 7zz || command -v 7z)
"$SEVENZ" x -y -o"$EXTRACT_DIR" "$CACHED_7Z" >/dev/null
[ -f "$EXTRACT_DIR/libmain.so" ]       || { log_error "$(get_txt "libmain.so missing in archive")"; exit 1; }
[ -f "$EXTRACT_DIR/libc++_shared.so" ] || { log_error "$(get_txt "libc++_shared.so missing in archive")"; exit 1; }

# ---------- 6. Locate self-built APK ----------
SELF_APK=$(find "$WORK_DIR/android/app/build/outputs/apk" -name "*.apk" -type f -size +1M 2>/dev/null | head -1)
[ -n "$SELF_APK" ] || { log_error "$(get_txt "No self-built APK; run build first")"; exit 1; }
log_info "$(printf "$(get_txt "Self-built APK: %s")" "$SELF_APK")"

# ---------- 7. Replace .so and drop old signature ----------
WORK_APK="$PATCH_CACHE_DIR/work-$TARGET_TAG.apk"
cp "$SELF_APK" "$WORK_APK"

zip -d -q "$WORK_APK" \
    "lib/$ABI/libmain.so" "lib/$ABI/libc++_shared.so" \
    "META-INF/*.RSA" "META-INF/*.SF" "META-INF/MANIFEST.MF" 2>/dev/null || true

TMP=$(mktemp -d)
mkdir -p "$TMP/lib/$ABI"
cp "$EXTRACT_DIR/libmain.so"       "$TMP/lib/$ABI/"
cp "$EXTRACT_DIR/libc++_shared.so" "$TMP/lib/$ABI/"
(cd "$TMP" && zip -u -q "$WORK_APK" "lib/$ABI/libmain.so" "lib/$ABI/libc++_shared.so")
rm -rf "$TMP"

# ---------- 8. zipalign + re-sign ----------
PATCHED_APK="$PATCH_CACHE_DIR/cdda-termux-patched-$TARGET_TAG.apk"
rm -f "$PATCHED_APK"

BUILD_TOOLS="$(find_build_tools_version)"
ZIPALIGN="$ANDROID_HOME/build-tools/$BUILD_TOOLS/zipalign"
APKSIGNER="$ANDROID_HOME/build-tools/$BUILD_TOOLS/apksigner"

if [ -x "$ZIPALIGN" ]; then
    "$ZIPALIGN" -f 4 "$WORK_APK" "${WORK_APK%.apk}-aligned.apk"
    SIGN_IN="${WORK_APK%.apk}-aligned.apk"
else
    log_warn "$(get_txt "zipalign not found, skipping")"
    SIGN_IN="$WORK_APK"
fi

KEYSTORE_PROPS="$WORK_DIR/android/keystore.properties"
if [ -f "$KEYSTORE_PROPS" ] && [ -x "$APKSIGNER" ]; then
    store_file=$(grep '^storeFile=' "$KEYSTORE_PROPS" | cut -d= -f2-)
    store_pass=$(grep '^storePassword=' "$KEYSTORE_PROPS" | cut -d= -f2-)
    key_alias=$(grep '^keyAlias=' "$KEYSTORE_PROPS" | cut -d= -f2-)
    key_pass=$(grep '^keyPassword=' "$KEYSTORE_PROPS" | cut -d= -f2-)
    case "$store_file" in
        /*) ;;
        *) store_file="$WORK_DIR/android/$store_file" ;;
    esac
    log_info "$(get_txt "Signing patched APK ...")"
    "$APKSIGNER" sign \
        --ks "$store_file" \
        --ks-pass "pass:$store_pass" \
        --key-pass "pass:$key_pass" \
        --out "$PATCHED_APK" \
        "$SIGN_IN"
else
    log_warn "$(get_txt "keystore.properties or apksigner missing; patched APK unsigned")"
    cp "$SIGN_IN" "$PATCHED_APK"
fi

# ---------- 9. Cleanup intermediates ----------
rm -f "$WORK_APK" "${WORK_APK%.apk}-aligned.apk"

# ---------- 10. Report ----------
log_info "$(get_txt "Patch complete!")"
log_info "Output: $PATCHED_APK"
log_info "Install with: termux-open $PATCHED_APK"