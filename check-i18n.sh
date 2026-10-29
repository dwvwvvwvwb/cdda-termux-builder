#!/data/data/com.termux/files/usr/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCALES_DIR="$SCRIPT_DIR/../locales"

msgids=$(grep -rhoE 'get_txt "[^"]*"' "$SCRIPT_DIR"/*.sh \
  | sed 's/^get_txt "//; s/"$//' \
  | sort -u)

fail=0
for po in "$LOCALES_DIR"/*.po; do
    [ -f "$po" ] || continue
    lang="$(basename "$po" .po)"

    missing=$(comm -23 <(echo "$msgids") \
      <(grep -oE '^msgid "[^"]*"' "$po" \
        | sed 's/^msgid "//; s/"$//' \
        | grep -v '^$' \
        | sort -u))

    if [ -n "$missing" ]; then
        echo "== $lang: missing msgid =="
        echo "$missing"
        fail=1
    else
        echo "== $lang: OK =="
    fi
done

echo "Note: multi-line help text (HELP_EN) must be verified manually."
exit $fail