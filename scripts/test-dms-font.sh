#!/bin/bash
# Isolated settings migration tests; no DMS process or host fonts needed.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
export HOME="$sandbox/home" XDG_CONFIG_HOME="$sandbox/config"
mkdir -p "$sandbox/bin" "$XDG_CONFIG_HOME/DankMaterialShell"
printf '#!/bin/bash\n[[ "$*" == *"/usr/share/quickshell/dms/assets/fonts/inter/InterVariable.ttf"* ]] || exit 1\n[[ "${TEST_SCAN_FAIL:-0}" == 0 ]] || exit 1\nprintf "%%s\\n" "${TEST_FONT_FAMILY:-Inter Variable}"\n' >"$sandbox/bin/fc-scan"
chmod +x "$sandbox/bin/fc-scan"
export PATH="$sandbox/bin:$PATH"
dms="$XDG_CONFIG_HOME/DankMaterialShell"
settings="$dms/settings.json"
apply() { bash "$root/build_files/legion5-dms-font.sh"; }

# Users with the previous Adwaita migration must receive Inter without losing
# their text scale, mono font, color theme or earlier font backup.
printf '%s\n' '{"fontFamily":"Adwaita Sans","fontWeight":500,"fontScale":1.25,"monoFontFamily":"Fira Code","currentThemeName":"custom"}' >"$settings"
touch "$dms/.legion5-dms-font-v1"
printf 'older backup\n' >"$settings.bak-legion5-font"
cp "$settings" "$sandbox/original"
apply
jq -e '.fontFamily == "Inter Variable" and .fontWeight == 500 and .fontScale == 1.25
    and .monoFontFamily == "Fira Code" and .currentThemeName == "custom"' "$settings" >/dev/null
cmp "$sandbox/original" "$settings.bak-legion5-font-inter"
grep -qx 'older backup' "$settings.bak-legion5-font"
[[ -e "$dms/.legion5-dms-font-v2" ]]

# Subsequent user changes and the migration backup survive later logins.
printf '%s\n' '{"fontFamily":"Cantarell","fontWeight":400}' >"$settings"
apply
jq -e '.fontFamily == "Cantarell" and .fontWeight == 400' "$settings" >/dev/null
cmp "$sandbox/original" "$settings.bak-legion5-font-inter"

# Wrong-family font and unreadable/missing file: no settings or success marker.
export XDG_CONFIG_HOME="$sandbox/missing" TEST_FONT_FAMILY='Noto Sans'
if apply 2>/dev/null; then echo 'FAIL: accepted the wrong font' >&2; exit 1; fi
unset TEST_FONT_FAMILY
export TEST_SCAN_FAIL=1
if apply 2>/dev/null; then echo 'FAIL: accepted a failed font scan' >&2; exit 1; fi
[[ ! -e "$XDG_CONFIG_HOME/DankMaterialShell/settings.json" ]]
[[ ! -e "$XDG_CONFIG_HOME/DankMaterialShell/.legion5-dms-font-v2" ]]
unset TEST_SCAN_FAIL

# Fresh user with default config location.
unset XDG_CONFIG_HOME
apply
jq -e '.fontFamily == "Inter Variable" and .fontWeight == 500
    and (has("fontScale") | not)' "$HOME/.config/DankMaterialShell/settings.json" >/dev/null

# Malformed input is preserved; a subsequent retry can succeed.
export XDG_CONFIG_HOME="$sandbox/invalid"
dms="$XDG_CONFIG_HOME/DankMaterialShell"
mkdir -p "$dms"
printf '{broken\n' >"$dms/settings.json"
cp "$dms/settings.json" "$sandbox/broken"
if apply 2>/dev/null; then echo 'FAIL: accepted malformed JSON' >&2; exit 1; fi
cmp "$sandbox/broken" "$dms/settings.json"
[[ ! -e "$dms/.legion5-dms-font-v2" ]]
printf '{}\n' >"$dms/settings.json"
apply
[[ -e "$dms/.legion5-dms-font-v2" ]]
echo 'DMS font tests passed.'
