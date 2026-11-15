#!/bin/bash
# Runs at boot, before the login screen (nvidia-gpu-retry.service).
#
# With NVIDIA driver 620 the GPU sometimes fails to start at boot ("NVRM:
# RmInitAdapter failed" in the kernel log). The driver stays attached but
# creates no display device, so the HDMI and USB-C outputs are dead. Detaching
# and reattaching the driver starts the GPU. This script does that, so the
# desktop session finds a working GPU when it starts.
#
# It does nothing when the GPU started normally or when the driver is absent.

set -uo pipefail

gpu_started() { compgen -G "$1/drm/card*" >/dev/null; }

# The NVIDIA modules load a few seconds into boot. Wait for them.
for _ in {1..30}; do
    [[ -d /sys/module/nvidia_drm ]] && break
    sleep 0.5
done
if [[ ! -d /sys/module/nvidia_drm ]]; then
    echo "NVIDIA driver is not loaded, nothing to do."
    exit 0
fi

status=0
for dev in /sys/bus/pci/drivers/nvidia/0000:*; do
    [[ -e "$dev" ]] || continue
    addr="$(basename "$dev")"

    # The display device appears shortly after the driver attaches
    for _ in {1..10}; do
        gpu_started "$dev" && break
        sleep 0.5
    done
    if gpu_started "$dev"; then
        echo "$addr: GPU started normally."
        continue
    fi

    for attempt in 1 2 3; do
        echo "$addr: GPU did not start, reattaching the driver (attempt $attempt)."
        echo "$addr" >/sys/bus/pci/drivers/nvidia/unbind
        sleep 1
        echo "$addr" >/sys/bus/pci/drivers/nvidia/bind
        for _ in {1..10}; do
            gpu_started "/sys/bus/pci/devices/$addr" && break
            sleep 0.5
        done
        gpu_started "/sys/bus/pci/devices/$addr" && break
    done

    if gpu_started "/sys/bus/pci/devices/$addr"; then
        echo "$addr: GPU started after reattaching the driver."
    else
        echo "$addr: GPU still not started." >&2
        status=1
    fi
done
exit "$status"
