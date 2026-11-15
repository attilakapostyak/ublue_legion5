#!/bin/bash
# Apply the shell-only macOS Dark palette before DMS starts. Run once per user;
# later theme choices are left alone. The managed palette itself follows the image.
# An optional source path makes it possible to preview the theme from this repo.
set -euo pipefail

config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
state_home="${XDG_STATE_HOME:-$HOME/.local/state}"
dms_dir="$config_home/DankMaterialShell"
source_theme="${1:-/usr/share/ublue_legion5/dms/macos-dark.json}"
theme="$dms_dir/themes/legion5-macos-dark.json"
marker="$dms_dir/.legion5-macos-dark-v1"

# Validate before touching any settings.
jq -e '.dark | type == "object" and has("primary") and has("surface")' \
    "$source_theme" >/dev/null
mkdir -p "$dms_dir/themes" "$state_home/DankMaterialShell"
install -m0644 "$source_theme" "$theme"
[[ ! -e "$marker" ]] || exit 0

# Stage both merges first, so a malformed settings/session file leaves both alone.
settings="$dms_dir/settings.json"
session="$state_home/DankMaterialShell/session.json"
settings_tmp="$(mktemp "$settings.XXXXXX")"
session_tmp="$(mktemp "$session.XXXXXX")"
trap 'rm -f "$settings_tmp" "$session_tmp"' EXIT

merge_json() {
    local file="$1" filter="$2" output="$3"
    if [[ -e "$file" ]]; then
        jq -e --arg theme "$theme" \
            "if type == \"object\" then $filter else error(\"Expected a JSON object\") end" \
            "$file" >"$output"
    else
        printf '{}\n' | jq -e --arg theme "$theme" "$filter" >"$output"
    fi
}

merge_json "$settings" '. + {
    currentThemeName: "custom",
    currentThemeCategory: "generic",
    customThemeFile: $theme,
    gtkThemingEnabled: false,
    qtThemingEnabled: false,
    syncModeWithPortal: false,
    runDmsMatugenTemplates: false,
    runUserMatugenTemplates: false
}' "$settings_tmp"
merge_json "$session" '. + {
    isLightMode: false,
    themeModeAutoEnabled: false
}' "$session_tmp"

# Keep the original files for undoing this migration, even if a later run retries.
for file in "$settings" "$session"; do
    if [[ -e "$file" && ! -e "$file.bak-legion5-theme" ]]; then
        cp -p "$file" "$file.bak-legion5-theme"
    fi
done
mv "$settings_tmp" "$settings"
mv "$session_tmp" "$session"
touch "$marker"
echo "Applied macOS Dark to DMS (application and Plasma themes unchanged)."
