#!/data/data/com.termux/files/usr/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/cdda-common.sh"

show_help() {
    cat <<EOF
用法: $0 [命令] [选项]

命令:
  setup [--yes]    安装系统依赖和 SDK/NDK（首次运行）
  config [--yes] [tag]  配置项目（tag 可以是具体标签名或 "latest" 获取最新）
  build [--clean] [--yes] 构建 APK（--clean 可清理后构建）
  all [--yes] [tag]      依次执行 setup, config, build
  clean                  仅清理构建产物
  help                   显示帮助

环境变量:
  WORK_DIR        源码目录（默认 ~/Cataclysm-DDA）
  BUILD_VARIANT   构建变体 release/debug（默认 release）
  NOTIFY          是否发送通知 true/false（默认 true）

示例:
  $0 all --yes latest         # 从最新发布版本开始完整构建（自动确认）
  $0 config --yes cdda-experimental-2026-03-24-2310  # 切换到指定标签并配置（自动覆盖）
  $0 build --clean            # 先清理再构建
  $0 clean                    # 仅清理构建产物
EOF
}

# 解析全局 --yes 参数
YES_FLAG=""
ARGS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --yes|-y)
            YES_FLAG="--yes"
            shift
            ;;
        *)
            ARGS+=("$1")
            shift
            ;;
    esac
done
set -- "${ARGS[@]}"  # 重新设置参数，过滤掉 --yes

case "$1" in
    setup)
        shift
        "$SCRIPT_DIR/cdda-setup.sh" $YES_FLAG "$@"
        ;;
    config)
        shift
        "$SCRIPT_DIR/cdda-config.sh" $YES_FLAG "$@"
        ;;
    build)
        shift
        "$SCRIPT_DIR/cdda-build.sh" "$@" $YES_FLAG
        ;;
    all)
        shift
        "$SCRIPT_DIR/cdda-setup.sh" $YES_FLAG
        "$SCRIPT_DIR/cdda-config.sh" $YES_FLAG "$@"
        "$SCRIPT_DIR/cdda-build.sh" $YES_FLAG
        ;;
    clean)
        shift
        "$SCRIPT_DIR/cdda-build.sh" --clean-only
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        show_help
        exit 1
        ;;
esac