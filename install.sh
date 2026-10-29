#!/data/data/com.termux/files/usr/bin/bash
set -e

REPO_URL="${CDDA_REPO_URL:-https://github.com/dwvwvvwvwb/cdda-termux-builder.git}"
INSTALL_DIR="${CDDA_BUILDER_DIR:-$HOME/cdda-termux-builder}"

if ! command -v git &>/dev/null; then
    pkg install -y git
fi

if [ -d "$INSTALL_DIR/.git" ]; then
    cd "$INSTALL_DIR"
    git pull --ff-only
else
    git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
    cd "$INSTALL_DIR"
fi

if [ $# -eq 0 ]; then
    exec ./scripts/cdda.sh all --yes latest
else
    exec ./scripts/cdda.sh "$@"
fi