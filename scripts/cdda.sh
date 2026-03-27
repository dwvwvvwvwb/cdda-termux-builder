#!/data/data/com.termux/files/usr/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/cdda-common.sh"

show_help() {
    cat <<EOF
Usage: $0 [command] [options]

Commands:
  setup [--yes]     Install system dependencies, NDK, and SDK.
  config [--yes] [tag]   Configure project (tag can be "latest" or a specific tag).
  build [--clean] [--yes] Build APK (--clean cleans before build).
  all [--yes] [tag]       Run setup, config, build in sequence.
  clean                   Only clean build artifacts.
  help                    Show this help.

Environment:
  WORK_DIR        Source directory (default: ~/Cataclysm-DDA)
  BUILD_VARIANT   release or debug (default: release)
  NOTIFY          true/false (default: true)

Examples:
  $0 all --yes latest                # Full build from latest release, auto-confirm
  $0 config --yes cdda-experimental-2026-03-24-2310  # Switch to a specific tag
  $0 build --clean                   # Clean then build
  $0 clean                           # Clean only
EOF
}

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
set -- "${ARGS[@]}"

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
        "$SCRIPT_DIR/cdda-build.sh" --clean
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        show_help
        exit 1
        ;;
esac