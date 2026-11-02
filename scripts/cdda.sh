#!/data/data/com.termux/files/usr/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/cdda-common.sh"

HELP_EN='Usage: ./cdda.sh [command] [options]

Commands:
  setup [--yes]              Install system dependencies, NDK, and SDK.
  config [--yes] [tag]       Configure project (tag can be "latest" or a specific tag).
  build [--clean] [--yes]    Build APK (--clean cleans before build).
  patch [--yes] [tag]        Patch built APK with official libmain.so + libc++_shared.so.
  all [--yes] [tag]          Run setup, config, build, patch in sequence.
  clean                      Only clean build artifacts.
  lang [zh_CN|en]            Set or show the UI language.
  help                       Show this help.

Environment:
  WORK_DIR        Source directory (default: ~/Cataclysm-DDA)
  BUILD_VARIANT   release or debug (default: release)
  NOTIFY          true/false (default: true)
  CDDA_LANG       UI language: en/zh_CN (default: auto-detect)
  GITHUB_TOKEN    Optional GitHub Personal Access Token
  LIBS_REPO       Repo holding extracted official libs (default: dwvwvvwvwb/cdda-termux-builder)

Examples:
  ./cdda.sh all --yes latest
  ./cdda.sh patch --yes
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
    patch)
        shift
        "$SCRIPT_DIR/cdda-patch.sh" $YES_FLAG "$@"
        ;;
    all)
        shift
        "$SCRIPT_DIR/cdda-setup.sh" $YES_FLAG
        "$SCRIPT_DIR/cdda-config.sh" $YES_FLAG "$@"
        "$SCRIPT_DIR/cdda-build.sh" $YES_FLAG
        "$SCRIPT_DIR/cdda-patch.sh" $YES_FLAG "$@"
        ;;
    clean)
        shift
        "$SCRIPT_DIR/cdda-build.sh" --clean-only
        ;;
    lang)
        shift
        case "${1:-}" in
            "")
                log_info "Current: %s" "$CDDA_LANG"
                log_info "Available:"
                for f in "$CDDA_LOCALES_DIR"/*.po; do
                    [ -f "$f" ] || continue
                    echo "  $(basename "$f" .po)"
                done
                log_info "  en  (built-in, no .po needed)"
                ;;
            *)
                if [ "$1" = "en" ] || [ -f "$CDDA_LOCALES_DIR/$1.po" ]; then
                    mkdir -p "$(dirname "$CDDA_LANG_CONF")"
                    echo "$1" > "$CDDA_LANG_CONF"
                    log_info "Language set to %s" "$1"
                else
                    log_error "Language '%s' not available." "$1"
                    log_info "Run '%s lang' to list available languages." "$0"
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