#!/data/data/com.termux/files/usr/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/cdda-common.sh"

WORK_DIR="${WORK_DIR:-$HOME/Cataclysm-DDA}"
BUILD_VARIANT="${BUILD_VARIANT:-release}"
NOTIFY="${NOTIFY:-true}"
MAX_RETRY=3

DO_CLEAN=false
YES_MODE=false
while [ $# -gt 0 ]; do
    case "$1" in
        --clean-only)
            DO_CLEAN_ONLY=true
            shift
            ;;
        --clean)
            DO_CLEAN=true
            shift
            ;;
        --yes|-y)
            YES_MODE=true
            shift
            ;;
        *)
            shift
            ;;
    esac
done

send_notification() {
    local title="$1"
    local content="$2"
    local apk_path="$3"
    if [ "$NOTIFY" = "true" ] && command -v termux-notification &>/dev/null; then
        if [ -n "$apk_path" ] && [ -f "$apk_path" ] && command -v termux-share &>/dev/null; then
            local safe_path=$(echo "$apk_path" | sed 's/"/\\"/g')
            termux-notification --title "$title" --content "$content" --priority high --action "termux-share \"$safe_path\""
        else
            termux-notification --title "$title" --content "$content" --priority high
        fi
    fi
}

retry_build() {
    local retry=0
    local success=0
    while [ $retry -lt $MAX_RETRY ]; do
        if build_android_core; then
            success=1
            break
        else
            retry=$((retry + 1))
            if [ $retry -lt $MAX_RETRY ]; then
                log_warn "Build failed, retrying $retry/$MAX_RETRY ..."
                sleep 3
            fi
        fi
    done
    if [ $success -eq 1 ]; then
        log_info "Build succeeded!"
        return 0
    else
        log_error "Build failed after $MAX_RETRY retries"
        send_notification "CDDA Build Failed" "Check logs" ""
        return 1
    fi
}

build_android_core() {
    [ -x "$WORK_DIR/android/gradlew" ] || chmod +x "$WORK_DIR/android/gradlew"

    if [ "$DO_CLEAN_ONLY" = true ]; then
        log_info "Performing clean only..."
        cd "$WORK_DIR/android" && ./gradlew clean -Pversion_header_path="$WORK_DIR/src/version.h"
        exit 0
    fi
    if [ "$DO_CLEAN" = true ]; then
        log_info "Cleaning..."
        (cd "$WORK_DIR/android" && ./gradlew clean -Pversion_header_path="$WORK_DIR/src/version.h")
    fi

    export NDK_HOST_TAG=linux-x86_64

    if [ -z "$JAVA_HOME" ]; then
        if command -v java >/dev/null 2>&1; then
            java_path=$(readlink -f $(which java))
            JAVA_HOME=$(dirname $(dirname "$java_path"))
            export JAVA_HOME
            log_info "Auto-set JAVA_HOME=$JAVA_HOME"
        else
            log_error "java not found, ensure openjdk is installed"
            return 1
        fi
    fi

    cd "$WORK_DIR/android" || return 1

    local gradle_file="app/build.gradle"
    local gradle_bak="app/build.gradle.bak"
    cp "$gradle_file" "$gradle_bak"
    trap 'if [ -f "$gradle_bak" ]; then mv "$gradle_bak" "$gradle_file"; fi' EXIT

    local build_tools_version=$(find_build_tools_version) || return 1
    if grep -q "buildToolsVersion" "$gradle_file"; then
        sed -i "s/buildToolsVersion \".*\"/buildToolsVersion \"$build_tools_version\"/" "$gradle_file"
    else
        sed -i "/android {/a\    buildToolsVersion \"$build_tools_version\"" "$gradle_file"
    fi

    local aapt2_path="$ANDROID_HOME/build-tools/$build_tools_version/aapt2"
    if [ ! -x "$aapt2_path" ]; then
        log_error "aapt2 not executable: $aapt2_path"
        return 1
    fi

    clean_old_logs
    local build_log="${BUILD_LOGS_DIR}/build_android_$(date +%Y%m%d_%H%M%S).log"
    log_info "Building $BUILD_VARIANT variant, log: $build_log"

    ./gradlew "assemble${BUILD_VARIANT^}" \
        -Pandroid.aapt2FromMavenOverride="$aapt2_path" \
        -Pabi_arm_32=false \
        -Pabi_arm_64=true \
        -Pandroid.cppFlags='"-Wno-unknown-warning-option"' \
        -Pversion_header_path="$WORK_DIR/src/version.h" \
        2>&1 | tee "$build_log"

    local gradle_exit=${PIPESTATUS[0]}
    if [ $gradle_exit -ne 0 ]; then
        log_error "Build failed, see log: $build_log"
        return 1
    fi

    local apk_file=""
    local variant_lower="${BUILD_VARIANT,,}"

    if [ -d "app/build/outputs/apk/experimental/$variant_lower" ]; then
        apk_file=$(find "app/build/outputs/apk/experimental/$variant_lower" -name "*.apk" -type f -size +1M 2>/dev/null | head -1)
    fi
    if [ -z "$apk_file" ] && [ -d "app/build/outputs/apk/stable/$variant_lower" ]; then
        apk_file=$(find "app/build/outputs/apk/stable/$variant_lower" -name "*.apk" -type f -size +1M 2>/dev/null | head -1)
    fi
    if [ -z "$apk_file" ]; then
        apk_file=$(find "app/build/outputs/apk" -name "*.apk" -type f -size +1M 2>/dev/null | head -1)
    fi

    if [ -z "$apk_file" ]; then
        log_error "No valid APK found (size >1MB)"
        return 1
    fi

    local apk_abs_path=$(realpath "$apk_file")
    log_info "Build successful! APK location: $apk_abs_path"
    send_notification "CDDA Build Complete" "APK generated" "$apk_abs_path"
    return 0
}

retry_build
