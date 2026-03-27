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
    local apk_dir="$3"
    if [ "$NOTIFY" = "true" ] && command -v termux-notification &>/dev/null; then
        local cmd="termux-notification --title \"$title\" --content \"$content\" --priority high"
        if [ -n "$apk_dir" ] && [ -d "$apk_dir" ]; then
            cmd="$cmd --action \"cd $apk_dir && termux-open .\""
        fi
        eval "$cmd"
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
                log_warn "构建失败，重试 $retry/$MAX_RETRY ..."
                sleep 3
            fi
        fi
    done
    if [ $success -eq 1 ]; then
        log_info "构建成功！"
        return 0
    else
        log_error "重试 $MAX_RETRY 次后仍然失败"
        send_notification "CDDA 构建失败" "请检查日志" ""
        return 1
    fi
}

build_android_core() {
    [ -x "$WORK_DIR/android/gradlew" ] || chmod +x "$WORK_DIR/android/gradlew"

    if [ "$DO_CLEAN" = true ]; then
        log_info "执行清理..."
        (cd "$WORK_DIR/android" && ./gradlew clean)
    fi

    export NDK_HOST_TAG=linux-x86_64

    if [ -z "$JAVA_HOME" ]; then
        if command -v java >/dev/null 2>&1; then
            java_path=$(readlink -f $(which java))
            JAVA_HOME=$(dirname $(dirname "$java_path"))
            export JAVA_HOME
            log_info "自动设置 JAVA_HOME=$JAVA_HOME"
        else
            log_error "找不到 java 命令，请确保已安装 openjdk"
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
        log_error "aapt2 不可执行: $aapt2_path"
        return 1
    fi

    clean_old_logs
    local build_log="${BUILD_LOGS_DIR}/build_android_$(date +%Y%m%d_%H%M%S).log"
    log_info "开始构建 $BUILD_VARIANT 版本，日志: $build_log"

    ./gradlew "assemble${BUILD_VARIANT^}" \
        -Pandroid.aapt2FromMavenOverride="$aapt2_path" \
        -Pabi_arm_32=false \
        -Pabi_arm_64=true \
        -Pandroid.cppFlags='"-Wno-unknown-warning-option"' \
        -Pversion_header_path="$WORK_DIR/src/version.h" \
        2>&1 | tee "$build_log"

    local gradle_exit=${PIPESTATUS[0]}
    if [ $gradle_exit -ne 0 ]; then
        log_error "构建失败，请查看日志: $build_log"
        return 1
    fi

    local apk_dir="app/build/outputs/apk"
    local variant_lower="${BUILD_VARIANT,,}"
    if [ "$variant_lower" = "debug" ]; then
        apk_dir="$apk_dir/debug"
    else
        local subdirs=($(ls -t "$apk_dir" 2>/dev/null | grep -E '^(stable|experimental)$' | head -1))
        if [ -n "$subdirs" ]; then
            apk_dir="$apk_dir/$subdirs/$variant_lower"
        else
            apk_dir="$apk_dir/$variant_lower"
        fi
    fi
    local apk_file=$(find "$apk_dir" -name "*.apk" -type f -size +1M 2>/dev/null | head -1)

    if [ -z "$apk_file" ]; then
        log_error "未找到有效的 APK 文件（大小 >1MB）"
        return 1
    fi
    log_info "构建成功！APK 位置: $apk_file"
    local final_apk_dir=$(dirname "$apk_file")
    send_notification "CDDA 构建完成" "APK 已生成" "$final_apk_dir"
    return 0
}

retry_build