#!/usr/bin/env bash
# User-level app defaults, applied after installation by just apps-install.
# Run on the host, without sudo, so these settings belong to the desktop user.
set -euo pipefail

browser=com.vivaldi.Vivaldi.desktop
if ! flatpak info com.vivaldi.Vivaldi >/dev/null 2>&1; then
    echo "Vivaldi is not installed. Run 'just apps-install' on the host first." >&2
    exit 1
fi

# Use the Flatpak desktop ID, not the RPM's vivaldi-stable.desktop.
xdg-settings set default-web-browser "$browser"
for mime in x-scheme-handler/http x-scheme-handler/https text/html application/xhtml+xml; do
    xdg-mime default "$browser" "$mime"
done

# Plasma also keeps a browser preference separate from MIME associations.
if command -v kwriteconfig6 >/dev/null 2>&1; then
    kwriteconfig6 --file kdeglobals --group General --key BrowserApplication "$browser"
fi
printf 'Default browser: %s\n' "$browser"
