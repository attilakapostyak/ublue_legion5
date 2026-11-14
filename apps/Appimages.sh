#!/usr/bin/env bash
# AppImages that aren't available on Flathub. Run by `just apps-install`.
set -euo pipefail

# Keep the version in sync with @getpaseo/cli in distrobox/fedora_main/Containerfile.
mkdir -p ~/.local/bin ~/.local/share/applications && \
curl -fL "https://github.com/getpaseo/paseo/releases/download/v0.16.0-beta.2/Paseo-x86_64.AppImage" -o ~/.local/bin/Paseo.AppImage && \
chmod +x ~/.local/bin/Paseo.AppImage && \
cat > ~/.local/bin/paseo-desktop <<'EOF'
#!/usr/bin/env bash
# Paseo Desktop runs on the host, but the coding agents live in the fedora_main
# box. Start the daemon inside the box first: Desktop attaches to a daemon that
# is already running, and only starts its own (host, no agents) when none is.
distrobox enter fedora_main -- /usr/local/bin/paseo daemon start \
    || echo "paseo-desktop: could not start the daemon in fedora_main" >&2
exec "$HOME/.local/bin/Paseo.AppImage" --appimage-extract-and-run --no-sandbox "$@"
EOF
chmod +x ~/.local/bin/paseo-desktop && \
cat > ~/.local/share/applications/paseo.desktop <<EOF
[Desktop Entry]
Name=Paseo
Exec=$HOME/.local/bin/paseo-desktop %U
Type=Application
Categories=Development;
EOF
