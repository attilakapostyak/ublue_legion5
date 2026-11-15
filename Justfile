# Run `just` to list all recipes. README.md explains the workflow.

image := "ghcr.io/attilakapostyak/ublue_legion5"
local_image := "localhost/ublue_legion5"

# Distrobox images to build, one per directory in distrobox/
boxes := "fedora_main"

[private]
default:
    @just --list

# First-time setup after installing the image: apps + distrobox, then check the system
setup: apps-install box-update doctor

# ---------------------------------------------------------------------------
# OS image (Containerfile + build_files/build.sh, built by GitHub Actions)
# ---------------------------------------------------------------------------

# Show the booted, staged and rollback deployments
[group('os')]
os-status:
    rpm-ostree status

# Download the newest image from GHCR; it's applied on the next reboot
[group('os')]
os-update:
    sudo bootc upgrade

# Go back to the previous deployment on the next reboot
[group('os')]
os-rollback:
    sudo bootc rollback

# Build the image locally to check that your changes build
[group('os')]
os-build:
    podman build --pull=newer -t {{ local_image }}:latest .

# Build the image locally and boot it on the next reboot (test before pushing)
[group('os')]
os-switch-local:
    sudo podman build --pull=newer -t {{ local_image }}:latest .
    sudo bootc switch --transport containers-storage {{ local_image }}:latest

# Track the image on GHCR and verify its signature on every update
[group('os')]
os-switch-signed:
    #!/usr/bin/env bash
    set -euo pipefail
    # The policy comes from build_files/build.sh, so the booted image must have it
    if ! jq -e '.transports.docker["{{ image }}"]' /etc/containers/policy.json >/dev/null; then
        echo "No signature policy for {{ image }} on this system." >&2
        echo "Boot an image built from this repo first (just os-update, reboot), then rerun." >&2
        exit 1
    fi
    sudo bootc switch --enforce-container-sigpolicy {{ image }}:latest

# ---------------------------------------------------------------------------
# Apps (apps/cli.Brewfile, apps/flatpaks.Brewfile and apps/Appimages.sh)
# ---------------------------------------------------------------------------

# Install everything listed in apps/*.Brewfile (also upgrades outdated ones) and the AppImages in apps/Appimages.sh
[group('apps')]
apps-install:
    #!/usr/bin/env bash
    set -euo pipefail
    for file in apps/*.Brewfile; do
        brew bundle install --file="$file"
    done
    bash apps/Appimages.sh

# Show anything listed in apps/*.Brewfile that isn't installed
[group('apps')]
apps-check:
    #!/usr/bin/env bash
    set -uo pipefail
    status=0
    for file in apps/*.Brewfile; do
        echo "==> $file"
        brew bundle check --verbose --file="$file" || status=1
    done
    exit "$status"

# List installed apps not in apps/*.Brewfile; `just apps-cleanup --force` removes them
[group('apps')]
apps-cleanup force="":
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -n "{{ force }}" && "{{ force }}" != "--force" ]]; then
        echo "Usage: just apps-cleanup [--force]" >&2
        exit 1
    fi
    # Aurora's default Flatpaks are added to the keep list so they're never removed
    keep="$(mktemp)"
    trap 'rm -f "$keep"' EXIT
    cat apps/*.Brewfile /usr/share/ublue-os/homebrew/system-*flatpaks.Brewfile >"$keep"
    if [[ -n "{{ force }}" ]]; then
        brew bundle cleanup --file="$keep" --force
    else
        # The dry run exits 1 when it finds something to remove; that's not an error here
        brew bundle cleanup --file="$keep" || true
    fi

# ---------------------------------------------------------------------------
# Distrobox (distrobox/<box>/Containerfile and distrobox/distrobox.ini)
# ---------------------------------------------------------------------------

# Build the distrobox images; `just box-build fresh` re-pulls Fedora and skips the cache
[group('distrobox')]
box-build mode="":
    #!/usr/bin/env bash
    set -euo pipefail
    args=(--build-arg "FEDORA_VERSION=$(rpm -E %fedora)")
    case "{{ mode }}" in
        "") pull=missing ;;
        fresh) pull=always; args+=(--no-cache) ;;
        *) echo "Usage: just box-build [fresh]" >&2; exit 1 ;;
    esac
    for box in {{ boxes }}; do
        podman build "${args[@]}" --pull="$pull" -t "localhost/$box:latest" "distrobox/$box"
    done

# Create the boxes in distrobox/distrobox.ini, replacing existing ones
[group('distrobox')]
box-create:
    distrobox assemble create --file distrobox/distrobox.ini

# Rebuild all images with the latest packages and recreate the boxes
[group('distrobox')]
box-update: (box-build "fresh") box-create
    podman image prune -f

# Open a shell in a box
[group('distrobox')]
box-enter name="fedora_main":
    distrobox enter {{ name }}

# List all boxes
[group('distrobox')]
box-list:
    distrobox list

# Delete the boxes in distrobox/distrobox.ini (your home directory is untouched)
[group('distrobox')]
box-rm:
    distrobox assemble rm --file distrobox/distrobox.ini

# ---------------------------------------------------------------------------
# Maintenance
# ---------------------------------------------------------------------------

# Check the known problems on this laptop: Secure Boot key, BIOS mode, NVIDIA, Flatpak GPU, Niri
[group('maintenance')]
doctor:
    #!/usr/bin/env bash
    set -uo pipefail
    status=0
    ok() { echo "ok    $1"; }
    bad() { echo "FAIL  $1"; echo "      fix: $2"; status=1; }

    # The image fixes these itself at boot/login (build_files/legion5-*.sh).
    # This shows whether that worked.

    # Without the key, Secure Boot rejects nvidia.ko and the external monitors stay dark
    # mokutil exits 1 even when the key is enrolled, so look at its output
    key_state="$(mokutil --test-key /etc/pki/akmods/certs/akmods-ublue.der 2>/dev/null || true)"
    if [[ "$(mokutil --sb-state 2>/dev/null)" != *enabled* ]]; then
        ok "Secure Boot is off, no key needed"
    elif [[ "$key_state" == *"already enrolled"* ]]; then
        ok "Universal Blue Secure Boot key is enrolled"
    elif [[ "$key_state" == *"enrollment request"* ]]; then
        bad "Universal Blue Secure Boot key is queued but not enrolled yet" "reboot; on the blue MOK screen: Enroll MOK -> Continue -> Yes, password universalblue"
    else
        bad "Universal Blue Secure Boot key is not enrolled" "journalctl -b -u legion5-mok-enroll"
    fi

    # In hybrid mode the firmware sometimes leaves the NVIDIA GPU uninitialized
    if [[ -e /sys/bus/pci/devices/0000:00:02.0 ]]; then
        bad "BIOS graphics mode is Hybrid (the NVIDIA GPU may fail to start)" "BIOS (F2) -> Graphics Device -> Discrete"
    else
        ok "BIOS graphics mode is Discrete"
    fi

    # The driver can be bound and still have failed to start the GPU, so
    # check for the display device it creates, not for the driver
    if compgen -G "/sys/bus/pci/devices/0000:01:00.0/drm/card*" >/dev/null; then
        ok "NVIDIA GPU is running (HDMI and USB-C outputs work)"
    elif [[ "$(basename "$(readlink /sys/bus/pci/devices/0000:01:00.0/driver 2>/dev/null)")" == nvidia ]]; then
        bad "NVIDIA driver is loaded but failed to start the GPU (HDMI and USB-C outputs are dead)" "shut down and start again (see Troubleshooting in README.md)"
    else
        bad "NVIDIA driver is not loaded (HDMI and USB-C outputs are dead)" "journalctl -k -b | grep -iE 'nvidia|rejected'"
    fi

    # Flatpak apps (Vivaldi, ...) need an extension matching the host NVIDIA
    # driver, or they draw and decode video on the CPU
    if [[ -r /sys/module/nvidia/version ]]; then
        nv="$(tr . - </sys/module/nvidia/version)"
        if flatpak list --runtime --columns=application | grep -qx "org.freedesktop.Platform.GL.nvidia-$nv"; then
            ok "Flatpak NVIDIA extension matches the driver ($nv)"
        else
            bad "Flatpak NVIDIA extension for driver $nv is missing (Flatpak apps use the CPU)" "journalctl -b -u legion5-flatpak-nvidia (it retries every 2 minutes)"
        fi
    fi

    # Niri settings from the image, included by legion5-niri-setup at login
    cfg="${XDG_CONFIG_HOME:-$HOME/.config}/niri/config.kdl"
    if ! compgen -G "/usr/share/ublue_legion5/niri/*.kdl" >/dev/null; then
        bad "The running image has no Niri settings" "just os-update, then reboot"
    elif [[ ! -f "$cfg" ]]; then
        ok "Niri has not been started yet (settings are applied at the first Niri login)"
    else
        for file in /usr/share/ublue_legion5/niri/*.kdl; do
            if grep -qxF "include \"$file\"" "$cfg"; then
                ok "Niri includes $file"
            else
                bad "Niri does not include $file" "log out of Niri and back in; details: journalctl --user -b -u legion5-niri-setup"
            fi
        done
    fi
    exit "$status"

# Remove dangling container images left over from rebuilds
[group('maintenance')]
prune:
    podman image prune -f
    sudo podman image prune -f

# Check shell scripts and Justfile formatting
[group('maintenance')]
lint:
    shellcheck build_files/*.sh
    just --fmt --check
