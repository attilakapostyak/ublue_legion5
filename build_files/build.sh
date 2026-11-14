#!/bin/bash
# Runs once inside the image build (see Containerfile).
#
# Only add things here that have to be part of the OS itself: drivers, kernel
# modules, system services, system-wide configuration. Everything else has a
# better home (see README.md):
#   CLI tools          -> apps/cli.Brewfile
#   Desktop apps       -> apps/flatpaks.Brewfile
#   Dev toolchains     -> distrobox/<box>/Containerfile

set -ouex pipefail

### Packages
# Aurora already ships git, jq, htop, vim, tmux, podman, distrobox and just.
# Add RPMs like this:
#   dnf5 install -y <package>
#
# Packages from a third-party repo: enable it, install, then disable it so it
# doesn't stay active on the running system:
#   dnf5 -y copr enable <owner>/<project>
#   dnf5 install -y <package>
#   dnf5 -y copr disable <owner>/<project>

### Niri session (optional second desktop next to KDE Plasma)
# Niri compositor + DankMaterialShell (bar, dock, launcher, notifications,
# network/bluetooth/audio controls). GNOME portal = screen sharing in Niri.
# Weak deps off: keeps out gnome-keyring (KWallet stays the only password
# store), waybar, alacritty and other extras that would clash with Plasma.
dnf5 install -y --setopt=install_weak_deps=False \
    niri \
    DankMaterialShell \
    xdg-desktop-portal-gnome

# Start DMS with Niri only. dms.service is tied to graphical-session.target,
# which Plasma starts too, so it must not be enabled the default way.
mkdir -p /usr/lib/systemd/user/niri.service.wants
ln -s ../dms.service /usr/lib/systemd/user/niri.service.wants/dms.service

### Services
systemctl enable podman.socket

### Image signature verification
# CI signs every image with cosign (.github/workflows/build.yml). Ship the
# public key and a container policy so the system can verify updates of this
# image. Activate enforcement once with `just os-switch-signed`.
install -Dm0644 /ctx/cosign.pub /usr/lib/pki/containers/ublue_legion5.pub

cat >/etc/containers/registries.d/ublue_legion5.yaml <<'EOF'
docker:
  ghcr.io/attilakapostyak/ublue_legion5:
    use-sigstore-attachments: true
EOF

jq '.transports.docker["ghcr.io/attilakapostyak/ublue_legion5"] = [{
      "type": "sigstoreSigned",
      "keyPath": "/usr/lib/pki/containers/ublue_legion5.pub",
      "signedIdentity": {"type": "matchRepository"}
    }]' /etc/containers/policy.json >/tmp/policy.json
install -m0644 /tmp/policy.json /etc/containers/policy.json

### Cleanup
# dnf leaves state in /run, which must be empty in a bootc image
rm -rf /run/dnf
