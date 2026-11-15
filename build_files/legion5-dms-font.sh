#!/bin/bash
# Readable Inter shell typography. Apply once, independently of the color
# migration. v2 replaces the earlier Adwaita choice without resetting later choices.
# Run with DMS stopped to avoid racing its settings writer.
set -euo pipefail

dms_dir="${XDG_CONFIG_HOME:-$HOME/.config}/DankMaterialShell"
settings="$dms_dir/settings.json"
marker="$dms_dir/.legion5-dms-font-v2"
[[ ! -e "$marker" ]] || exit 0

# DMS's StyledText loads this packaged font with FontLoader when the family is
# "Inter Variable". Inspect the actual file: fc-match alone could report a fallback
# or miss the bundled font because it is outside fontconfig's search directories.
inter_font=/usr/share/quickshell/dms/assets/fonts/inter/InterVariable.ttf
if ! fc-scan --format '%{family}\n' "$inter_font" | grep -x 'Inter Variable' >/dev/null; then
    echo "DMS's bundled Inter Variable font is missing or invalid; leaving typography unchanged." >&2
    exit 1
fi
mkdir -p "$dms_dir"
tmp="$(mktemp "$settings.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
filter='if type == "object" then . + {fontFamily: "Inter Variable", fontWeight: 500}
    else error("Expected a JSON object") end'
if [[ -e "$settings" ]]; then
    jq -e "$filter" "$settings" >"$tmp"
    [[ -e "$settings.bak-legion5-font-inter" ]] || cp -p "$settings" "$settings.bak-legion5-font-inter"
else
    printf '{}\n' | jq -e "$filter" >"$tmp"
fi
mv "$tmp" "$settings"
touch "$marker"
echo "Applied verified Inter Variable Medium to DMS (text scale and app fonts unchanged)."
