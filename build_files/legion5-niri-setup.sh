#!/bin/bash
# Runs at every Niri login, before DMS starts (legion5-niri-setup.service,
# a user unit wanted by niri.service). Safe to run any number of times.
#
# 1. Includes the Niri settings shipped in the image
#    (/usr/share/ublue_legion5/niri/*.kdl) from ~/.config/niri/config.kdl.
# 2. Installs and enables the DMS calculator plugin for the launcher.
#
# Never leaves an invalid Niri config behind: if the result doesn't validate,
# the previous config.kdl is restored.

set -uo pipefail

config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
niri_dir="$config_home/niri"
cfg="$niri_dir/config.kdl"
share=/usr/share/ublue_legion5/niri

### Niri settings
# Niri writes its default config.kdl on the first start; give it a moment
for _ in {1..20}; do
    [[ -f "$cfg" ]] && break
    sleep 0.5
done

if [[ ! -f "$cfg" ]]; then
    echo "No $cfg, skipping the Niri settings."
else
    backup="$(mktemp)"
    cp "$cfg" "$backup"
    changed=0

    # Older setups copied the files into ~/.config/niri (`just niri-setup`).
    # Replace those relative includes with the files from the image.
    if grep -qE '^include "(legion5|workspaces|binds)\.kdl"$' "$cfg"; then
        sed -i -E \
            -e '/^\/\/ (Legion 5 hardware settings, managed|Managed) by ublue_legion5/d' \
            -e '/^include "(legion5|workspaces|binds)\.kdl"$/d' "$cfg"
        rm -f "$niri_dir"/{legion5,workspaces,binds}.kdl
        changed=1
        echo "Removed the old copied Niri settings."
    fi

    for file in "$share"/*.kdl; do
        line="include \"$file\""
        if ! grep -qxF "$line" "$cfg"; then
            printf '\n// Added by the ublue_legion5 image (legion5-niri-setup)\n%s\n' "$line" >>"$cfg"
            changed=1
            echo "Added $line"
        fi
    done

    if ((changed)); then
        if niri validate -c "$cfg" >/dev/null 2>&1; then
            cp "$backup" "$cfg.bak-legion5"
            echo "Niri config updated (previous version: $cfg.bak-legion5)."
        else
            cp "$backup" "$cfg"
            echo "The updated Niri config did not validate; restored the previous one." >&2
        fi
    else
        echo "Niri settings already included."
    fi
    rm -f "$backup"
fi

### DMS calculator plugin (launcher on Mod+Space)
dms_dir="$config_home/DankMaterialShell"
if [[ ! -d "$dms_dir/plugins/calculator" ]]; then
    # Needs the network; if it fails, the next login tries again
    timeout 60 dms plugins install calculator ||
        echo "Could not install the DMS calculator plugin, will retry at the next login." >&2
fi
if [[ -d "$dms_dir/plugins/calculator" ]]; then
    settings="$dms_dir/plugin_settings.json"
    [[ -s "$settings" ]] || echo '{}' >"$settings"
    # Enabled, and no "=" prefix needed: typing "2+2" calculates
    jq '.calculator += {enabled: true, noTrigger: true, trigger: ""}' "$settings" >"$settings.tmp" &&
        mv "$settings.tmp" "$settings"
fi
exit 0
