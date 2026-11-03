#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PY=""
for c in python3 python; do
    if command -v "$c" >/dev/null 2>&1; then PY="$c"; break; fi
done

if [ -z "$PY" ]; then
    echo "i18n tool is for maintaining locales/*.po; not needed for normal builds." >&2
    echo "To maintain translations, install Python first:" >&2
    echo "  pkg install python" >&2
    exit 1
fi

exec "$PY" "$SCRIPT_DIR/i18n.py" "$@"