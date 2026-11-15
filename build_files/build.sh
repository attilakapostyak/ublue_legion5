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

### Legion 5 setup that would otherwise need manual steps after a (re)install
# Each script explains itself; all of them are safe to run on every boot or
# login and do nothing when there's nothing to do.

# Niri settings (render on NVIDIA, fixed workspaces, Mod+Space launcher),
# included from ~/.config/niri/config.kdl at every Niri login, before DMS
install -Dm0644 -t /usr/share/ublue_legion5/niri /ctx/niri/*.kdl
install -Dm0755 /ctx/legion5-niri-setup.sh /usr/libexec/legion5-niri-setup
cat >/usr/lib/systemd/user/legion5-niri-setup.service <<'EOF'
[Unit]
Description=Apply the ublue_legion5 Niri settings and DMS calculator plugin
After=niri.service
Before=dms.service

[Service]
Type=oneshot
ExecStart=/usr/libexec/legion5-niri-setup
EOF
ln -s ../legion5-niri-setup.service /usr/lib/systemd/user/niri.service.wants/legion5-niri-setup.service

# First window of Vivaldi, Konsole, VS Code and Paseo on workspace 1-4 of the
# monitor it opens on (follows niri's event stream while niri runs)
install -Dm0755 /ctx/legion5-workspace-apps.sh /usr/bin/legion5-workspace-apps
cat >/usr/lib/systemd/user/legion5-workspace-apps.service <<'EOF'
[Unit]
Description=Put the first window of Vivaldi, Konsole, VS Code and Paseo on workspaces 1-4
BindsTo=niri.service
After=niri.service

[Service]
ExecStart=/usr/bin/legion5-workspace-apps
Restart=on-failure
RestartSec=2
EOF
ln -s ../legion5-workspace-apps.service /usr/lib/systemd/user/niri.service.wants/legion5-workspace-apps.service

# Flatpak NVIDIA extension matching the driver (else Flatpak apps use the CPU)
install -Dm0755 /ctx/legion5-flatpak-nvidia.sh /usr/libexec/legion5-flatpak-nvidia
cat >/usr/lib/systemd/system/legion5-flatpak-nvidia.service <<'EOF'
[Unit]
Description=Install the Flatpak NVIDIA extension matching the driver
Wants=network-online.target
After=network-online.target
ConditionPathExists=/sys/module/nvidia/version

[Service]
Type=oneshot
ExecStart=/usr/libexec/legion5-flatpak-nvidia
# No network yet, Flathub down, ...: try again later
Restart=on-failure
RestartSec=2min

[Install]
WantedBy=multi-user.target
EOF

# Queue the Secure Boot key for the NVIDIA driver if it isn't enrolled
install -Dm0755 /ctx/legion5-mok-enroll.sh /usr/libexec/legion5-mok-enroll
cat >/usr/lib/systemd/system/legion5-mok-enroll.service <<'EOF'
[Unit]
Description=Queue the Universal Blue Secure Boot key for enrolment if needed

[Service]
Type=oneshot
ExecStart=/usr/libexec/legion5-mok-enroll

[Install]
WantedBy=multi-user.target
EOF

### Services
systemctl enable podman.socket
systemctl enable legion5-flatpak-nvidia.service legion5-mok-enroll.service

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
