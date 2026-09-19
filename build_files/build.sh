#!/bin/bash

set -ouex pipefail

### Install host packages

# Remove the obsolete Slack RPM repository from earlier image revisions.
# Slack is now installed from Flathub through manifests/Brewfile.
rm -f /etc/yum.repos.d/slack.repo

# Double Commander does not currently have a published Flathub package.
# Keep this RPM in the image until a maintained Flatpak becomes available.
dnf5 install -y \
    doublecmd

#### Hyprland desktop (baked in + default DE) ####

# Stable Hyprland ecosystem from the lionheartp/Hyprland COPR. This repository
# packages *tagged* Hyprland releases (currently 0.56.x, which uses the Lua
# config format) plus the satellite tools, all from one coherent source. The
# .repo file is intentionally left enabled so bootc / rpm-ostree upgrades keep
# the stack current.
dnf5 -y copr enable lionheartp/Hyprland

# Core compositor + Hyprland satellites (from the COPR).
#   hyprland            : the compositor + /usr/share/wayland-sessions/hyprland.desktop
#   hyprlock/hypridle   : lock screen + idle daemon
#   hyprpicker          : screen color picker
#   hyprsunset          : per-session gamma/blue-light
#   xdg-desktop-portal-hyprland : Wayland portals / screen sharing
#   hyprpolkitagent     : graphical authentication agent
dnf5 install -y \
    hyprland \
    hyprlock \
    hypridle \
    hyprpicker \
    hyprsunset \
    xdg-desktop-portal-hyprland \
    hyprpolkitagent

# Desktop companions (from Fedora repos).
dnf5 install -y \
    waybar \
    mako \
    grim \
    slurp \
    wl-clipboard \
    kitty \
    brightnessctl \
    playerctl \
    pamixer \
    network-manager-applet \
    blueman \
    polkit \
    xdg-desktop-portal \
    xdg-desktop-portal-gtk

# Make Hyprland the default desktop session for SDDM (the Aurora login
# manager). Plasma stays installed as a selectable fallback; users can still
# pick it from the session menu.
mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/95-hyprland-default.conf <<'EOF'
[General]
Session=hyprland
EOF

#### Enable system services

systemctl enable podman.socket
