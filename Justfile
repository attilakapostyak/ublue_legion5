# Run `just` to list all recipes. README.md explains the workflow.

image := "ghcr.io/attilakapostyak/ublue_legion5"
local_image := "localhost/ublue_legion5"

# Distrobox images to build, one per directory in distrobox/
boxes := "fedora_main"

[private]
default:
    @just --list

# First-time setup after installing the image: apps + distrobox
setup: apps-install box-update

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
# Apps (apps/cli.Brewfile and apps/flatpaks.Brewfile)
# ---------------------------------------------------------------------------

# Install everything listed in apps/*.Brewfile (also upgrades outdated ones)
[group('apps')]
apps-install:
    #!/usr/bin/env bash
    set -euo pipefail
    for file in apps/*.Brewfile; do
        brew bundle install --file="$file"
    done

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
