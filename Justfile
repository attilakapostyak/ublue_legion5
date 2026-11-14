# Run `just` to list all recipes. README.md explains the workflow.

image := "ghcr.io/attilakapostyak/ublue_legion5"
local_image := "localhost/ublue_legion5"

# Distrobox images to build, one per directory in distrobox/
boxes := "fedora_main"

[private]
default:
    @just --list

# First-time setup after installing the image: apps + distrobox + Niri hardware settings
setup: apps-install box-update niri-setup doctor

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

# Enroll the Universal Blue key so Secure Boot lets the NVIDIA driver load (once per machine)
[group('os')]
os-enroll-key:
    #!/usr/bin/env bash
    set -euo pipefail
    key=/etc/pki/akmods/certs/akmods-ublue.der
    # mokutil exits 1 even when the key is enrolled, so look at its output
    if [[ "$(mokutil --test-key "$key" 2>/dev/null || true)" == *"already enrolled"* ]]; then
        echo "Key is already enrolled, nothing to do."
        exit 0
    fi
    # Queues the key; the firmware asks for confirmation on the next boot
    ujust enroll-secure-boot-key
    echo
    echo "Now reboot. On the blue 'MOK management' screen choose:"
    echo "  Enroll MOK -> Continue -> Yes, password: universalblue (US keyboard layout)"

# ---------------------------------------------------------------------------
# Niri (niri/*.kdl)
# ---------------------------------------------------------------------------

# Install niri/*.kdl into ~/.config/niri, include them from config.kdl, add the launcher calculator
[group('niri')]
niri-setup:
    #!/usr/bin/env bash
    set -euo pipefail
    dir="${XDG_CONFIG_HOME:-$HOME/.config}/niri"
    dms="${XDG_CONFIG_HOME:-$HOME/.config}/DankMaterialShell"
    if [[ ! -f "$dir/config.kdl" ]]; then
        echo "No $dir/config.kdl yet. Log in to Niri once, then run: just niri-setup"
        exit 0
    fi
    for file in niri/*.kdl; do
        name="$(basename "$file")"
        install -m0644 "$file" "$dir/$name"
        if ! grep -qF "include \"$name\"" "$dir/config.kdl"; then
            printf '\n// Managed by ublue_legion5 (just niri-setup)\ninclude "%s"\n' "$name" >>"$dir/config.kdl"
        fi
    done
    niri validate

    # Calculator in the DMS launcher (Mod+Space), without a trigger prefix
    if [[ ! -d "$dms/plugins/calculator" ]]; then
        dms plugins install calculator
    fi
    touch "$dms/plugin_settings.json"
    jq '(. // {}) | .calculator += {enabled: true, noTrigger: true, trigger: ""}' \
        "$dms/plugin_settings.json" >"$dms/plugin_settings.json.tmp"
    mv "$dms/plugin_settings.json.tmp" "$dms/plugin_settings.json"

    echo "Done. Log out of Niri and back in to apply."

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

# Check the known problems on this laptop: Secure Boot key, NVIDIA driver, Niri settings
[group('maintenance')]
doctor:
    #!/usr/bin/env bash
    set -uo pipefail
    status=0
    ok() { echo "ok    $1"; }
    bad() { echo "FAIL  $1"; echo "      fix: $2"; status=1; }

    # Without the key, Secure Boot rejects nvidia.ko and the external monitors stay dark
    # mokutil exits 1 even when the key is enrolled, so look at its output
    if [[ "$(mokutil --sb-state 2>/dev/null)" != *enabled* ]]; then
        ok "Secure Boot is off, no key needed"
    elif [[ "$(mokutil --test-key /etc/pki/akmods/certs/akmods-ublue.der 2>/dev/null)" == *"already enrolled"* ]]; then
        ok "Universal Blue Secure Boot key is enrolled"
    else
        bad "Universal Blue Secure Boot key is not enrolled" "just os-enroll-key, then reboot"
    fi

    if [[ "$(basename "$(readlink /sys/bus/pci/devices/0000:01:00.0/driver 2>/dev/null)")" == nvidia ]]; then
        ok "NVIDIA driver is loaded (HDMI and USB-C outputs work)"
    else
        bad "NVIDIA driver is not loaded (HDMI and USB-C outputs are dead)" "journalctl -k -b | grep -iE 'nvidia|rejected'"
    fi

    dir="${XDG_CONFIG_HOME:-$HOME/.config}/niri"
    if [[ ! -f "$dir/config.kdl" ]]; then
        ok "Niri has not been started yet (run just niri-setup after the first login)"
    else
        for file in niri/*.kdl; do
            name="$(basename "$file")"
            if grep -qF "include \"$name\"" "$dir/config.kdl" && cmp -s "$file" "$dir/$name"; then
                ok "Niri uses $file"
            else
                bad "Niri config does not include the current $file" "just niri-setup"
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
