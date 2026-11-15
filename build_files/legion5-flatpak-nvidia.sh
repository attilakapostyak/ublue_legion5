#!/bin/bash
# Runs at every boot once the network is up (legion5-flatpak-nvidia.service).
#
# Flatpak apps (Vivaldi, ...) can only use the NVIDIA GPU through a Flatpak
# extension that matches the host driver version exactly. After a driver
# update, or on a fresh install, it's missing and the apps draw and decode
# video on the CPU. This installs it when it's missing and does nothing
# otherwise.

set -euo pipefail

if [[ ! -r /sys/module/nvidia/version ]]; then
    echo "NVIDIA driver is not loaded, nothing to do."
    exit 0
fi

version="$(tr . - </sys/module/nvidia/version)"
installed="$(flatpak list --system --runtime --columns=application)"
missing=()
for ext in "org.freedesktop.Platform.GL.nvidia-$version" "org.freedesktop.Platform.GL32.nvidia-$version"; do
    grep -qxF "$ext" <<<"$installed" || missing+=("$ext")
done

if ((${#missing[@]} == 0)); then
    echo "Flatpak NVIDIA extension for driver $version is installed."
    exit 0
fi

echo "Installing ${missing[*]}"
flatpak install --system -y --noninteractive flathub "${missing[@]}"
echo "Installed. Restart Flatpak apps that were already running."
