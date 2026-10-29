#!/data/data/com.termux/files/usr/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

: "${SCRIPT_DIR:?SCRIPT_DIR must be set before sourcing cdda-common.sh}"
CDDA_LOCALES_DIR="${CDDA_LOCALES_DIR:-$SCRIPT_DIR/../locales}"
CDDA_LANG_CONF="${CDDA_LANG_CONF:-$HOME/.config/cdda-termux-builder/lang}"

# 把任意形式的语言标签规范化到实际存在的 .po 文件名，或 "en"
normalize_lang() {
    local want="$1"
    want="${want%%.*}"      # zh_CN.UTF-8 → zh_CN
    want="${want//-/_}"     # zh-CN → zh_CN

    [ -z "$want" ] && { printf 'en'; return; }

    # 1. 精确匹配
    if [ -f "$CDDA_LOCALES_DIR/$want.po" ]; then
        printf '%s' "$want"
        return
    fi

    # 2. 英文是源语言，直接返回 en（不找 en_*.po）
    local base="${want%%_*}"
    [ "$base" = "en" ] && { printf 'en'; return; }

    # 3. 主语言代码匹配：zh_TW → 第一个 zh_*.po
    local f first=""
    for f in "$CDDA_LOCALES_DIR/$base"_*.po "$CDDA_LOCALES_DIR/$base.po"; do
        [ -f "$f" ] || continue
        first="$(basename "$f" .po)"
        break
    done
    if [ -n "$first" ]; then
        printf '%s' "$first"
        return
    fi

    # 4. 都找不到 → en
    printf 'en'
}

# 判定链
CDDA_LANG="${CDDA_LANG:-}"

if [ -z "$CDDA_LANG" ] && [ -f "$CDDA_LANG_CONF" ]; then
    CDDA_LANG="$(tr -d '[:space:]' < "$CDDA_LANG_CONF")"
fi

if [ -z "$CDDA_LANG" ] && command -v getprop &>/dev/null; then
    CDDA_LANG="$(getprop persist.sys.locale 2>/dev/null)"
fi

[ -z "$CDDA_LANG" ] && CDDA_LANG="${LANG:-}"

CDDA_LANG="$(normalize_lang "$CDDA_LANG")"

get_txt() {
    local msgid="$1"
    local po_file="$CDDA_LOCALES_DIR/${CDDA_LANG}.po"

    [ "$CDDA_LANG" = "en" ] && { printf '%s' "$msgid"; return; }
    [ -f "$po_file" ]       || { printf '%s' "$msgid"; return; }

    local result
    result=$(CDDA_MSGID="$msgid" awk '
        BEGIN { RS = ""; FS = "\n"; target = ENVIRON["CDDA_MSGID"] }
        function unescape(s,   out,i,n,c,c2) {
            out = ""; n = length(s)
            for (i = 1; i <= n; i++) {
                c = substr(s, i, 1)
                if (c == "\\" && i < n) {
                    i++; c2 = substr(s, i, 1)
                    if      (c2 == "n")  out = out "\n"
                    else if (c2 == "t")  out = out "\t"
                    else if (c2 == "\"") out = out "\""
                    else if (c2 == "\\") out = out "\\"
                    else                 out = out c2
                } else out = out c
            }
            return out
        }
        function unquote(s) { sub(/^"/, "", s); sub(/"$/, "", s); return s }
        {
            id = ""; str = ""; mode = 0
            for (i = 1; i <= NF; i++) {
                line = $i
                if (line ~ /^msgid /)       { mode = 1; id  = unquote(substr(line, 7)) }
                else if (line ~ /^msgstr /) { mode = 2; str = unquote(substr(line, 8)) }
                else if (line ~ /^"/) {
                    if      (mode == 1) id  = id  unquote(line)
                    else if (mode == 2) str = str unquote(line)
                }
            }
            if (unescape(id) == target) { print unescape(str); exit }
        }
    ' "$po_file")

    if [ -n "$result" ]; then
        printf '%s' "$result"
    else
        printf '%s' "$msgid"
    fi
}

TXT_INFO="$(get_txt "Info")"
TXT_WARN="$(get_txt "Warning")"
TXT_ERROR="$(get_txt "Error")"
TXT_STEP="$(get_txt "Step")"

log_info()  { echo -e "${GREEN}[${TXT_INFO}]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[${TXT_WARN}]${NC} $*"; }
log_error() { echo -e "${RED}[${TXT_ERROR}]${NC} $*"; }
log_step()  { echo -e "${BLUE}[${TXT_STEP}]${NC} $*"; }

ANDROID_HOME="${ANDROID_HOME:-$HOME/android-sdk}"
ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-$HOME/android-ndk-r29}"
NDK_VERSION="29.0.14206865"

BUILD_LOGS_DIR="${BUILD_LOGS_DIR:-$HOME/.cdda_build_logs}"
mkdir -p "$BUILD_LOGS_DIR"

clean_old_logs() {
    find "$BUILD_LOGS_DIR" -name "build_android_*.log" -type f -mtime +30 -delete 2>/dev/null || true
}

retry_command() {
    local max_retries=3
    local retry=0
    local cmd="$1"
    shift
    while [ $retry -lt $max_retries ]; do
        if eval "$cmd" "$@"; then
            return 0
        else
            retry=$((retry + 1))
            if [ $retry -lt $max_retries ]; then
                log_warn "$(printf "$(get_txt "Command failed, retrying %s/%s ...")" "$retry" "$max_retries")"
                sleep 3
            fi
        fi
    done
    return 1
}

download_with_retry() {
    local url="$1"
    local output="$2"
    local max_retries=3
    local retry=0
    while [ $retry -lt $max_retries ]; do
        if curl -L -C - --retry 3 -o "$output" "$url"; then
            return 0
        else
            retry=$((retry + 1))
            log_warn "$(printf "$(get_txt "Download failed, retrying %s/%s ...")" "$retry" "$max_retries")"
            sleep 3
        fi
    done
    return 1
}

verify_checksum_and_retry() {
    local file="$1"
    local expected_sha256="$2"
    local url="$3"
    local max_retries=3
    local retry=0

    while [ $retry -lt $max_retries ]; do
        if [ ! -f "$file" ]; then
            log_info "$(get_txt "File does not exist, downloading...")"
            if ! download_with_retry "$url" "$file"; then
                log_warn "$(printf "$(get_txt "Download failed, retry %s/%s")" "$((retry+1))" "$max_retries")"
                retry=$((retry + 1))
                continue
            fi
        fi

        log_info "$(get_txt "Verifying SHA256...")"
        echo "$expected_sha256  $file" | sha256sum -c -
        if [ $? -eq 0 ]; then
            return 0
        else
            log_warn "$(get_txt "SHA256 mismatch, deleting corrupted file...")"
            rm -f "$file"
            retry=$((retry + 1))
            if [ $retry -lt $max_retries ]; then
                log_info "$(printf "$(get_txt "Re-downloading (%s/%s)...")" "$retry" "$max_retries")"
            fi
        fi
    done
    return 1
}

fix_ndk_clangpp() {
    local ndk_bin="$1"
    local clangpp="$ndk_bin/clang++"
    if [ -d "$ndk_bin" ]; then
        if [ ! -x "$clangpp" ] || [ ! -s "$clangpp" ]; then
            rm -f "$clangpp"
            ln -s clang "$clangpp"
            log_info "$(printf "$(get_txt "Fixed %s")" "$clangpp")"
        fi
        chmod +x "$ndk_bin"/*
    fi
}

check_disk_space() {
    local required_mb="${1:-15360}"
    local yes_mode="${2:-false}"
    local available_kb=$(df -k "$HOME" 2>/dev/null | awk 'NR==2 {print $4}')
    if [ -z "$available_kb" ]; then
        log_warn "$(get_txt "Cannot determine disk space, skipping check")"
        return 0
    fi
    local available_mb=$((available_kb / 1024))
    if [ "$available_mb" -lt "$required_mb" ]; then
        log_warn "$(printf "$(get_txt "Available space %sMB is less than recommended %sMB")" "$available_mb" "$required_mb")"
        if [ "$yes_mode" = false ]; then
            set +e
            read -p "$(get_txt "Continue anyway?") (y/N) " answer
            local read_ret=$?
            set -e
            if [ $read_ret -ne 0 ]; then
                log_error "$(get_txt "Input read failed, exiting")"
                exit 1
            fi
            if [[ ! "$answer" =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
    fi
}

find_build_tools_version() {
    local build_tools_dir="$ANDROID_HOME/build-tools"
    if [ ! -d "$build_tools_dir" ]; then
        log_error "$(printf "$(get_txt "SDK build-tools directory does not exist: %s")" "$build_tools_dir")"
        return 1
    fi
    local versions=()
    for d in "$build_tools_dir"/*/; do
        if [ -f "${d}aapt2" ]; then
            versions+=("$(basename "$d")")
        fi
    done
    if [ ${#versions[@]} -eq 0 ]; then
        log_error "$(get_txt "No build-tools directory containing aapt2 found")"
        return 1
    fi
    printf "%s\n" "${versions[@]}" | sort -V | tail -1
}

find_platform_version() {
    local platforms_dir="$ANDROID_HOME/platforms"
    if [ ! -d "$platforms_dir" ]; then
        log_error "$(printf "$(get_txt "SDK platforms directory does not exist: %s")" "$platforms_dir")"
        return 1
    fi
    local versions=()
    for d in "$platforms_dir"/android-*/; do
        if [ -f "${d}android.jar" ]; then
            versions+=("$(basename "$d" | sed 's/android-//')")
        fi
    done
    if [ ${#versions[@]} -eq 0 ]; then
        log_error "$(get_txt "No valid platform directory found")"
        return 1
    fi
    printf "%s\n" "${versions[@]}" | sort -n | tail -1
}

# Setup symlinks for cmake and ninja required by SDK
setup_cmake_ninja_symlinks() {
    local sdk_cmake_dir="$ANDROID_HOME/cmake"
    local target_version="3.22.1"          # version expected by CDDA build scripts
    local target_bin_dir="$sdk_cmake_dir/$target_version/bin"

    # Check if cmake and ninja are available in Termux
    if ! command -v cmake &>/dev/null; then
        log_error "$(get_txt "cmake is not installed, please run: pkg install cmake")"
        return 1
    fi
    if ! command -v ninja &>/dev/null; then
        log_error "$(get_txt "ninja is not installed, please run: pkg install ninja")"
        return 1
    fi

    mkdir -p "$target_bin_dir"

    # Create symbolic links (overwrite if exist)
    ln -sf "$(command -v cmake)" "$target_bin_dir/cmake"
    ln -sf "$(command -v ninja)" "$target_bin_dir/ninja"

    log_info "$(printf "$(get_txt "Created cmake/ninja symlinks for SDK at: %s")" "$target_bin_dir")"
}