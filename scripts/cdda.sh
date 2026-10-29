#!/data/data/com.termux/files/usr/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/cdda-common.sh"

HELP_EN='Usage: ./cdda.sh [command] [options]

Commands:
  setup [--yes]              Install system dependencies, NDK, and SDK.
  config [--yes] [tag]       Configure project (tag can be "latest" or a specific tag).
  build [--clean] [--yes]    Build APK (--clean cleans before build).
  all [--yes] [tag]          Run setup, config, build in sequence.
  clean                      Only clean build artifacts.
  lang [zh_CN|en]            Set or show the UI language.
  help                       Show this help.

Environment:
  WORK_DIR        Source directory (default: ~/Cataclysm-DDA)
  BUILD_VARIANT   release or debug (default: release)
  NOTIFY          true/false (default: true)
  CDDA_LANG       UI language: en/zh_CN (default: auto-detect)
  GITHUB_TOKEN    Optional GitHub Personal Access Token

Examples:
  ./cdda.sh all --yes latest
  ./cdda.sh config --yes cdda-experimental-2026-03-24-2310
  ./cdda.sh build --clean
  ./cdda.sh clean
  ./cdda.sh lang zh_CN'

show_help() {
    printf '%s\n' "$(get_txt "$HELP_EN")"
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
        "$SCRIPT_DIR/cdda-build.sh" --clean-only
        ;;
    lang)
        shift
        case "${1:-}" in
            "")
                echo "Current: ${CDDA_LANG}"
                echo "Available:"
                for f in "$CDDA_LOCALES_DIR"/*.po; do
                    [ -f "$f" ] || continue
                    echo "  $(basename "$f" .po)"
                done
                echo "  en  (built-in, no .po needed)"
                ;;
            *)
                if [ "$1" = "en" ] || [ -f "$CDDA_LOCALES_DIR/$1.po" ]; then
                    mkdir -p "$(dirname "$CDDA_LANG_CONF")"
                    echo "$1" > "$CDDA_LANG_CONF"
                    echo "Language set to $1"
                else
                    echo "Language '$1' not available."
                    echo "Run '$0 lang' to list available languages."
                    exit 1
                fi
                ;;
        esac
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        show_help
        exit 1
        ;;
esac