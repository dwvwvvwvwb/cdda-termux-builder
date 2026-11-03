#!/data/data/com.termux/files/usr/bin/bash
set -e

REPO_URL="${CDDA_REPO_URL:-https://github.com/dwvwvvwvwb/cdda-termux-builder.git}"
INSTALL_DIR="${CDDA_BUILDER_DIR:-$HOME/cdda-termux-builder}"

# Normalize git URL to "owner/repo" so HTTPS and SSH forms compare equal.
repo_slug() {
    printf '%s' "$1" | sed -E 's#^(git@[^:]+:|[a-z]+://[^/]+/)##; s#\.git$##; s#/$##'
}

if ! command -v git &>/dev/null; then
    pkg install -y git
fi

if [ -d "$INSTALL_DIR/.git" ]; then
    # ---- Existing checkout: use as-is (no network, no update) ----
    existing_url="$(git -C "$INSTALL_DIR" remote get-url origin 2>/dev/null || true)"
    if [ -z "$existing_url" ]; then
        echo "[install] $INSTALL_DIR is a git repo but has no 'origin' remote" >&2
        echo "[install] Remove it or set CDDA_BUILDER_DIR to a fresh path" >&2
        exit 1
    fi
    if [ "$(repo_slug "$existing_url")" != "$(repo_slug "$REPO_URL")" ]; then
        echo "[install] $INSTALL_DIR points to a different repo:" >&2
        echo "[install]   origin: $(repo_slug "$existing_url")" >&2
        echo "[install]   want:   $(repo_slug "$REPO_URL")" >&2
        echo "[install] Remove it or set CDDA_BUILDER_DIR to a fresh path" >&2
        exit 1
    fi
    echo "[install] Using existing checkout at $INSTALL_DIR (no update)"
    cd "$INSTALL_DIR"

elif [ -e "$INSTALL_DIR" ]; then
    # ---- Path occupied by something else ----
    echo "[install] $INSTALL_DIR exists but is not a git checkout" >&2
    echo "[install] Remove it or set CDDA_BUILDER_DIR to a fresh path" >&2
    exit 1

else
    # ---- Fresh install ----
    echo "[install] Cloning $REPO_URL into $INSTALL_DIR"
    git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
    cd "$INSTALL_DIR"
fi

if [ $# -eq 0 ]; then
    exec ./scripts/cdda.sh all --yes latest
else
    exec ./scripts/cdda.sh "$@"
fi