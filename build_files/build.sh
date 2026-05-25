#!/bin/bash

set -ouex pipefail

### Install packages

# Packages can be installed from any enabled yum repo on the image.
# RPMfusion repos are available by default in ublue main images
# List of rpmfusion packages can be found here:
# https://mirrors.rpmfusion.org/mirrorlist?path=free/fedora/updates/43/x86_64/repoview/index.html&protocol=https&redirect=1

# Standard packages from Fedora / RPMFusion repos
dnf5 install -y \
    chezmoi \
    tmux \
    neovim \
    mc 

# Use a COPR Example:
#
# dnf5 -y copr enable ublue-os/staging
# dnf5 -y install package
# Disable COPRs so they don't end up enabled on the final image:
# dnf5 -y copr disable ublue-os/staging

# Vivaldi
dnf5 config-manager addrepo --from-repofile=https://repo.vivaldi.com/stable/vivaldi-fedora.repo
dnf5 install -y vivaldi-stable

# Google Chrome (direct RPM — repo is self-updating once installed)
dnf5 install -y https://dl.google.com/linux/direct/google-chrome-stable_current_x86_64.rpm

# Visual Studio Code
rpm --import https://packages.microsoft.com/keys/microsoft.asc
sh -c 'echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" > /etc/yum.repos.d/vscode.repo'
dnf5 install -y code

# Bitwarden desktop (direct RPM from GitHub releases)
BITWARDEN_RPM_URL=$(curl -sSL https://api.github.com/repos/bitwarden/clients/releases \
    | grep -o 'https://[^"]*x86_64\.rpm' | grep '/desktop-' | head -1)
dnf5 install -y "${BITWARDEN_RPM_URL}"

printf '%s\n' \
'[slack]' \
'name=Slack' \
'baseurl=https://packagecloud.io/slacktechnologies/slack/fedora/21/$basearch' \
'enabled=1' \
'gpgcheck=0' \
'repo_gpgcheck=0' \
'gpgkey=https://packagecloud.io/slacktechnologies/slack/gpgkey' \
'sslverify=1' \
'metadata_expire=300' | tee /etc/yum.repos.d/slack.repo > /dev/null
dnf5 install -y slack

#### Example for enabling a System Unit File

systemctl enable podman.socket
