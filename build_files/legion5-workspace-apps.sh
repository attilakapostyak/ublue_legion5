#!/bin/bash
# Puts the first window of each app below on workspace N of the monitor it
# opened on (the focused one), however the app was started. Further windows
# of an app that already has one open where you are. Nothing is started
# here; it only moves windows.
#
# Niri window rules can't do this: open-on-workspace takes one fixed
# workspace name. So this follows niri's event stream and moves new windows
# (legion5-workspace-apps.service, a user unit that runs with niri).

set -uo pipefail

# Niri app ID (`niri msg windows`) -> workspace number
declare -A target=(
    [Vivaldi-flatpak]=1
    [org.kde.konsole]=2
    [com.microsoft.VSCode]=3
    [Paseo]=4
)

declare -A app_of=()    # window ID -> app ID, every open window
declare -A is_new=()    # window ID -> 1 if it opened while this runs
declare -A handled=()   # window ID -> 1 once considered

place() { # window ID, app ID, workspace ID it opened on
    local id=$1 app=$2 ws=$3 other ref
    for other in "${!app_of[@]}"; do
        if [[ $other != "$id" && ${app_of[$other]} == "$app" ]]; then
            return # the app already had a window
        fi
    done
    # Workspace N on the same monitor, by name (all of them are named in
    # niri/workspaces.kdl); else by number, which niri resolves on the
    # window's monitor.
    ref=$(niri msg -j workspaces | jq -r --argjson ws "$ws" --argjson n "${target[$app]}" '
        (first(.[] | select(.id == $ws)) | .output) as $out
        | first(.[] | select(.output == $out and .idx == $n) | .name) // $n')
    niri msg action move-window-to-workspace --window-id "$id" --focus true "$ref"
}

niri msg -j event-stream | jq --unbuffered -r '
    if .WindowsChanged then
        "reset", (.WindowsChanged.windows[] | ["known", .id, (.app_id // "")] | @tsv)
    elif .WindowOpenedOrChanged then
        .WindowOpenedOrChanged.window | ["window", .id, (.app_id // ""), (.workspace_id // "")] | @tsv
    elif .WindowClosed then
        ["closed", .WindowClosed.id] | @tsv
    else empty end' |
while IFS=$'\t' read -r kind id app ws; do
    case $kind in
    reset) app_of=() ;;
    known) app_of[$id]=$app ;;
    closed) unset 'app_of[$id]' 'is_new[$id]' 'handled[$id]' ;;
    window)
        [[ -v app_of[$id] ]] || is_new[$id]=1
        app_of[$id]=$app
        if [[ -n ${is_new[$id]:-} && -z ${handled[$id]:-} && -n $app && -n $ws ]]; then
            handled[$id]=1
            [[ -n ${target[$app]:-} ]] && place "$id" "$app" "$ws"
        fi
        ;;
    esac
done
exit 1 # niri went away; systemd restarts this unless the session ended
