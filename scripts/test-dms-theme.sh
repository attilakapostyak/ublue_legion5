#!/bin/bash
# No compositor or DMS process needed; all writes stay in a temporary home.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
export HOME="$sandbox/home"
export XDG_CONFIG_HOME="$sandbox/config"
export XDG_STATE_HOME="$sandbox/state"
dms="$XDG_CONFIG_HOME/DankMaterialShell"
state="$XDG_STATE_HOME/DankMaterialShell"
apply() { bash "$root/build_files/legion5-dms-theme.sh" "$root/build_files/dms/macos-dark.json"; }

# Existing users: preserve unrelated settings, layout, wallpaper and originals.
mkdir -p "$dms" "$state"
printf '%s\n' '{"currentThemeName":"purple","fontScale":1.25,"barConfigs":[{"id":"mine"}],"gtkThemingEnabled":true}' >"$dms/settings.json"
printf '%s\n' '{"isLightMode":true,"themeModeAutoEnabled":true,"wallpaperPath":"/my/wallpaper"}' >"$state/session.json"
cp "$dms/settings.json" "$sandbox/original-settings"
cp "$state/session.json" "$sandbox/original-session"
apply
jq -e '.currentThemeName == "custom" and .currentThemeCategory == "generic"
    and .fontScale == 1.25 and .barConfigs == [{"id":"mine"}]
    and .gtkThemingEnabled == false and .qtThemingEnabled == false
    and .syncModeWithPortal == false and .runDmsMatugenTemplates == false
    and .runUserMatugenTemplates == false' "$dms/settings.json" >/dev/null
jq -e '.isLightMode == false and .themeModeAutoEnabled == false
    and .wallpaperPath == "/my/wallpaper"' "$state/session.json" >/dev/null
cmp "$sandbox/original-settings" "$dms/settings.json.bak-legion5-theme"
cmp "$sandbox/original-session" "$state/session.json.bak-legion5-theme"
theme="$(jq -r '.customThemeFile' "$dms/settings.json")"
cmp "$theme" "$root/build_files/dms/macos-dark.json"
jq -e '.dark | [.primary, .primaryText, .primaryContainer, .secondary,
    .surface, .surfaceText, .surfaceVariant, .surfaceVariantText, .surfaceTint,
    .background, .backgroundText, .outline, .surfaceContainer,
    .surfaceContainerHigh, .surfaceContainerHighest, .error, .warning, .success]
    | all(.[]; test("^#[0-9A-Fa-f]{6}$"))' "$theme" >/dev/null

# Repeated logins must not undo subsequent user choices.
printf '%s\n' '{"currentThemeName":"green"}' >"$dms/settings.json"
apply
jq -e '.currentThemeName == "green"' "$dms/settings.json" >/dev/null
cmp "$sandbox/original-settings" "$dms/settings.json.bak-legion5-theme"

# Fresh home and default (non-XDG-overridden) locations.
unset XDG_CONFIG_HOME XDG_STATE_HOME
apply
jq -e '.currentThemeName == "custom"' "$HOME/.config/DankMaterialShell/settings.json" >/dev/null
jq -e '.isLightMode == false' "$HOME/.local/state/DankMaterialShell/session.json" >/dev/null

# Malformed session: no partial settings migration, no marker; retry succeeds.
export XDG_CONFIG_HOME="$sandbox/bad-config" XDG_STATE_HOME="$sandbox/bad-state"
dms="$XDG_CONFIG_HOME/DankMaterialShell"
state="$XDG_STATE_HOME/DankMaterialShell"
mkdir -p "$dms" "$state"
printf '%s\n' '{"currentThemeName":"purple"}' >"$dms/settings.json"
printf '%s\n' '{broken' >"$state/session.json"
cp "$dms/settings.json" "$sandbox/before-failure"
if apply 2>/dev/null; then
    echo "FAIL: accepted malformed JSON" >&2
    exit 1
fi
cmp "$sandbox/before-failure" "$dms/settings.json"
[[ ! -e "$dms/.legion5-macos-dark-v1" ]]
printf '{}\n' >"$state/session.json"
apply
[[ -e "$dms/.legion5-macos-dark-v1" ]]
# Niri decorations must use the same accent/status/outline colors as the shell.
for mapping in 'active-color primary' 'inactive-color outlineVariant' 'urgent-color error'; do
    read -r property role <<<"$mapping"
    color="$(jq -r --arg role "$role" '.dark[$role]' "$root/build_files/dms/macos-dark.json")"
    [[ "$(grep -cF "$property \"$color\"" "$root/build_files/niri/macos-dark.kdl")" == 3 ]]
done
echo "DMS theme tests passed."
