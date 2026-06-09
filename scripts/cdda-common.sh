#!/data/data/com.termux/files/usr/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "${BLUE}[STEP]${NC} $1"; }

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
                log_warn "Command failed, retrying $retry/$max_retries ..."
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
            log_warn "Download failed, retrying $retry/$max_retries ..."
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
            log_info "File does not exist, downloading..."
            if ! download_with_retry "$url" "$file"; then
                log_warn "Download failed, retry $((retry+1))/$max_retries"
                retry=$((retry + 1))
                continue
            fi
        fi

        log_info "Verifying SHA256..."
        echo "$expected_sha256  $file" | sha256sum -c -
        if [ $? -eq 0 ]; then
            return 0
        else
            log_warn "SHA256 mismatch, deleting corrupted file..."
            rm -f "$file"
            retry=$((retry + 1))
            if [ $retry -lt $max_retries ]; then
                log_info "Re-downloading ($retry/$max_retries)..."
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
            log_info "Fixed $clangpp"
        fi
        chmod +x "$ndk_bin"/*
    fi
}

check_disk_space() {
    local required_mb="${1:-15360}"
    local yes_mode="${2:-false}"
    local available_kb=$(df -k "$HOME" 2>/dev/null | awk 'NR==2 {print $4}')
    if [ -z "$available_kb" ]; then
        log_warn "Cannot determine disk space, skipping check"
        return 0
    fi
    local available_mb=$((available_kb / 1024))
    if [ "$available_mb" -lt "$required_mb" ]; then
        log_warn "Available space ${available_mb}MB is less than recommended ${required_mb}MB"
        if [ "$yes_mode" = false ]; then
            set +e
            read -p "Continue anyway? (y/N) " answer
            local read_ret=$?
            set -e
            if [ $read_ret -ne 0 ]; then
                log_error "Input read failed, exiting"
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
        log_error "SDK build-tools directory does not exist: $build_tools_dir"
        return 1
    fi
    local versions=()
    for d in "$build_tools_dir"/*/; do
        if [ -f "${d}aapt2" ]; then
            versions+=("$(basename "$d")")
        fi
    done
    if [ ${#versions[@]} -eq 0 ]; then
        log_error "No build-tools directory containing aapt2 found"
        return 1
    fi
    printf "%s\n" "${versions[@]}" | sort -V | tail -1
}

find_platform_version() {
    local platforms_dir="$ANDROID_HOME/platforms"
    if [ ! -d "$platforms_dir" ]; then
        log_error "SDK platforms directory does not exist: $platforms_dir"
        return 1
    fi
    local versions=()
    for d in "$platforms_dir"/android-*/; do
        if [ -f "${d}android.jar" ]; then
            versions+=("$(basename "$d" | sed 's/android-//')")
        fi
    done
    if [ ${#versions[@]} -eq 0 ]; then
        log_error "No valid platform directory found"
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
        log_error "cmake is not installed, please run: pkg install cmake"
        return 1
    fi
    if ! command -v ninja &>/dev/null; then
        log_error "ninja is not installed, please run: pkg install ninja"
        return 1
    fi

    mkdir -p "$target_bin_dir"

    # Create symbolic links (overwrite if exist)
    ln -sf "$(command -v cmake)" "$target_bin_dir/cmake"
    ln -sf "$(command -v ninja)" "$target_bin_dir/ninja"

    log_info "Created cmake/ninja symlinks for SDK at: $target_bin_dir"
}