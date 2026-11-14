#!/usr/bin/env bash
# AppImages that aren't available on Flathub. Run by `just apps-install`.
set -euo pipefail

mkdir -p ~/.local/bin ~/.local/share/applications && \
curl -fL "https://github.com/getpaseo/paseo/releases/download/v0.16.0-beta.2/Paseo-x86_64.AppImage" -o ~/.local/bin/Paseo.AppImage && \
chmod +x ~/.local/bin/Paseo.AppImage && \
cat > ~/.local/share/applications/paseo.desktop <<EOF
[Desktop Entry]
Name=Paseo
Exec=$HOME/.local/bin/Paseo.AppImage --appimage-extract-and-run --no-sandbox %U
Type=Application
Categories=Development;
EOF


