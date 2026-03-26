#!/data/data/com.termux/files/usr/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[信息]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[警告]${NC} $1"; }
log_error() { echo -e "${RED}[错误]${NC} $1"; }
log_step()  { echo -e "${BLUE}[步骤]${NC} $1"; }

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
                log_warn "命令失败，重试 $retry/$max_retries ..."
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
            log_warn "下载失败，重试 $retry/$max_retries ..."
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
            log_info "文件不存在，开始下载..."
            if ! download_with_retry "$url" "$file"; then
                log_warn "下载失败，重试 $((retry+1))/$max_retries"
                retry=$((retry + 1))
                continue
            fi
        fi

        log_info "校验 SHA256..."
        echo "$expected_sha256  $file" | sha256sum -c -
        if [ $? -eq 0 ]; then
            return 0
        else
            log_warn "SHA256 校验失败，删除损坏文件..."
            rm -f "$file"
            retry=$((retry + 1))
            if [ $retry -lt $max_retries ]; then
                log_info "重新下载 ($retry/$max_retries)..."
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
            log_info "已修复 $clangpp"
        fi
        chmod +x "$ndk_bin"/*
    fi
}

check_disk_space() {
    local required_mb="${1:-15360}"
    local yes_mode="${2:-false}"
    local available_mb=$(df -m "$HOME" | awk 'NR==2 {print $4}')
    if [ "$available_mb" -lt "$required_mb" ]; then
        log_warn "可用空间 ${available_mb}MB，低于建议值 ${required_mb}MB"
        if [ "$yes_mode" = false ]; then
            read -p "是否继续？(y/N) " answer
            [[ ! "$answer" =~ ^[Yy]$ ]] && exit 1
        fi
    fi
}

find_build_tools_version() {
    local build_tools_dir="$ANDROID_HOME/build-tools"
    if [ ! -d "$build_tools_dir" ]; then
        log_error "SDK build-tools 目录不存在: $build_tools_dir"
        return 1
    fi
    local versions=()
    for d in "$build_tools_dir"/*/; do
        if [ -f "${d}aapt2" ]; then
            versions+=("$(basename "$d")")
        fi
    done
    if [ ${#versions[@]} -eq 0 ]; then
        log_error "未找到包含 aapt2 的 build-tools 目录"
        return 1
    fi
    printf "%s\n" "${versions[@]}" | sort -V | tail -1
}

find_platform_version() {
    local platforms_dir="$ANDROID_HOME/platforms"
    if [ ! -d "$platforms_dir" ]; then
        log_error "SDK platforms 目录不存在: $platforms_dir"
        return 1
    fi
    local versions=()
    for d in "$platforms_dir"/android-*/; do
        if [ -f "${d}android.jar" ]; then
            versions+=("$(basename "$d" | sed 's/android-//')")
        fi
    done
    if [ ${#versions[@]} -eq 0 ]; then
        log_error "未找到有效的 platform 目录"
        return 1
    fi
    printf "%s\n" "${versions[@]}" | sort -n | tail -1
}