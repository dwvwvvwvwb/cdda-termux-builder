#!/data/data/com.termux/files/usr/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/cdda-common.sh"

NDK_SHA256="21ca4237997da6c601eda6de48418609d6d8308b26c631620ae57cf1fa06c4c7"
SDK_SHA256="5b3535d4533fbd788ef976a4ce4c3050f19150fe9d0bb092263045317c46f463"

YES_MODE=false
while [ $# -gt 0 ]; do
    case "$1" in
        --yes|-y)
            YES_MODE=true
            shift
            ;;
        *)
            shift
            ;;
    esac
done

check_disk_space 15360 "$YES_MODE"

log_step "Updating package list..."
retry_command "pkg update -y" || {
    log_error "Failed to update package list, check network"
    exit 1
}

log_step "Installing required packages..."
retry_command "pkg install -y" git make clang curl jq 7zip gettext openjdk-17 coreutils which cmake ninja ccache || {
    log_error "Failed to install required packages"
    exit 1
}

log_step "Checking NDK and SDK..."

NDK_FILE="ndk.7z"
NDK_URL="https://github.com/lzhiyong/termux-ndk/releases/download/android-ndk/android-ndk-r29-aarch64.7z"
if [ -n "$ANDROID_NDK_HOME" ] && [ -d "$ANDROID_NDK_HOME" ] && [ -f "$ANDROID_NDK_HOME/ndk-build" ]; then
    log_info "NDK already exists: $ANDROID_NDK_HOME"
else
    log_info "Downloading NDK..."
    if ! verify_checksum_and_retry "$NDK_FILE" "$NDK_SHA256" "$NDK_URL"; then
        log_error "NDK download or checksum failed"
        exit 1
    fi

    log_info "Extracting NDK..."
    target_dir=$(dirname "$ANDROID_NDK_HOME")
    7zz x "$NDK_FILE" -o"$target_dir" || log_warn "Extraction warnings (ignored)"
    if [ ! -f "$ANDROID_NDK_HOME/ndk-build" ]; then
        log_error "NDK extraction failed: ndk-build not found"
        exit 1
    fi

    fix_ndk_clangpp "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin"
    fix_ndk_clangpp "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-aarch64/bin"

    rm "$NDK_FILE"
fi

SDK_FILE="sdk.7z"
SDK_URL="https://github.com/lzhiyong/termux-ndk/releases/download/android-sdk/android-sdk-aarch64.7z"
if [ -n "$ANDROID_HOME" ] && [ -d "$ANDROID_HOME" ] && [ -d "$ANDROID_HOME/build-tools" ]; then
    log_info "SDK already exists: $ANDROID_HOME"
else
    log_info "Downloading SDK..."
    if ! verify_checksum_and_retry "$SDK_FILE" "$SDK_SHA256" "$SDK_URL"; then
        log_error "SDK download or checksum failed"
        exit 1
    fi

    log_info "Extracting SDK..."
    target_dir=$(dirname "$ANDROID_HOME")
    7zz x "$SDK_FILE" -o"$target_dir" || log_warn "Extraction warnings (ignored)"
    if [ ! -d "$ANDROID_HOME/build-tools" ]; then
        log_error "SDK extraction failed: build-tools directory not found"
        exit 1
    fi
    rm "$SDK_FILE"
fi

setup_cmake_ninja_symlinks
log_info "Environment setup complete!"