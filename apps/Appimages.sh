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

# Double Commander: not on Flathub and no AppImage upstream, so use the
# portable Qt6 tarball (Qt6 comes from Aurora/KDE). The tarball's
# settings/doublecmd.inf turns on portable mode (config inside the program
# directory, wiped on every reinstall); deleting it makes Double Commander
# keep its settings in ~/.config/doublecmd instead.
DOUBLECMD_VERSION=1.2.11
tmp=$(mktemp -d)
curl -fL "https://github.com/doublecmd/doublecmd/releases/download/v${DOUBLECMD_VERSION}/doublecmd-${DOUBLECMD_VERSION}.qt6.x86_64.tar.xz" -o "$tmp/doublecmd.tar.xz"
tar -xJf "$tmp/doublecmd.tar.xz" -C "$tmp"
mkdir -p ~/.local/opt
rm -rf ~/.local/opt/doublecmd
mv "$tmp/doublecmd" ~/.local/opt/doublecmd
rm -f ~/.local/opt/doublecmd/settings/doublecmd.inf
rm -rf "$tmp"
ln -sfn ~/.local/opt/doublecmd/doublecmd ~/.local/bin/doublecmd
cat > ~/.local/share/applications/doublecmd.desktop <<EOF2
[Desktop Entry]
Name=Double Commander
GenericName=File Manager
Comment=Twin-panel file manager
Exec=$HOME/.local/opt/doublecmd/doublecmd %F
Icon=$HOME/.local/opt/doublecmd/doublecmd.png
Terminal=false
Type=Application
Categories=Utility;FileTools;FileManager;
MimeType=inode/directory;
EOF2
