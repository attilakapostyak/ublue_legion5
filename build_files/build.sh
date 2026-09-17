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

#### Enable system services

systemctl enable podman.socket
