# ublue_legion5

My personal OS image for a Lenovo Legion 5: [Aurora](https://getaurora.dev)
(KDE Plasma, Fedora Atomic) with the developer tools (DX) and the open NVIDIA
driver, customized with a [bootc](https://github.com/bootc-dev/bootc)
`Containerfile`. Based on the
[Universal Blue image template](https://github.com/ublue-os/image-template).

Everything is managed with [`just`](https://just.systems). Run `just` in this
directory to list the recipes.

## Where does software go?

The OS is read-only. Software lives in one of four layers. Each layer is
declared in a file in this repo:

| What | Where | Declared in | Applied with |
|---|---|---|---|
| Drivers, kernel modules, system services, system-wide config | **OS image** | `build_files/build.sh` | push + `just os-update` + reboot |
| Command-line tools for everyday use on the host | **Homebrew** | `apps/cli.Brewfile` | `just apps-install` |
| Desktop (GUI) applications | **Flatpak** (Flathub) | `apps/flatpaks.Brewfile` | `just apps-install` |
| Development: compilers, runtimes, AI coding agents, anything you'd `dnf install` | **Distrobox** | `distrobox/<box>/Containerfile` | `just box-update` |

How to choose:

1. Is it a GUI app? Use **Flatpak**.
2. Is it a CLI tool you use outside of development (editor, password manager,
   monitoring)? Use **Homebrew**.
3. Is it part of a development environment, or does it need `dnf`? Use
   **Distrobox**.
4. Does it need root, a kernel module, a systemd service or a system-wide
   change? Use the **OS image**. Add to the image only as a last resort,
   because every change needs a rebuild and a reboot.

Put each tool in exactly one layer. Aurora already ships `git`, `jq`, `htop`,
`vim`, `tmux`, `podman`, `distrobox`, `just` and VS Code. Don't add those again.

> **Why Homebrew for Flatpaks?** `brew bundle` reads `flatpak "..."` lines and
> runs `flatpak install --system` for you. Aurora manages its own default apps
> the same way (`/usr/share/ublue-os/homebrew/system-flatpaks.Brewfile`). This
> gives one tool and one file format for installing, checking and cleaning up.

## Updates

Aurora updates the OS image, Flatpaks, Homebrew packages and the packages
inside your boxes automatically in the background (`uupd.timer`). OS updates
are applied on the next reboot. GitHub Actions rebuilds this image every day,
so upstream Aurora fixes reach it within a day.

Manual commands:

```sh
just os-update      # download the newest image now, reboot to apply
just box-update     # rebuild the distrobox images from scratch and recreate the boxes
just apps-install   # install and upgrade everything in apps/*.Brewfile
```

## OS image

The image is defined by `Containerfile` (base image) and
`build_files/build.sh` (customizations). GitHub Actions
(`.github/workflows/build.yml`) builds it on every push that touches those
files, plus once a day. It then pushes it to
`ghcr.io/attilakapostyak/ublue_legion5` and signs it with cosign.

> GitHub pauses scheduled workflows after 60 days without commits. If daily
> builds stop, re-enable the workflow in the Actions tab or push a commit.

To change the OS:

1. Edit `build_files/build.sh`, for example `dnf5 install -y <package>`.
2. Optional: test it locally.
   - `just os-build` checks that it builds.
   - `just os-switch-local` builds it and boots it on the next reboot.
3. Commit and push. Wait for the GitHub Actions build to finish.
4. Run `just os-update`, then reboot.

If something breaks, run `just os-rollback` and reboot to get the previous
deployment back. Run `just os-status` to see which deployments exist.

After testing a local build with `just os-switch-local`, go back to the GHCR
image with `just os-switch-signed`.

### Signature verification

The image includes the public key (`cosign.pub`) and a container policy for
`ghcr.io/attilakapostyak/ublue_legion5`. Turn on enforcement once, after
booting an image built from this repo:

```sh
just os-switch-signed
```

From then on, every update is verified against the key, and `just os-status`
shows `ostree-image-signed`. The private key is stored in the GitHub secret
`SIGNING_SECRET`. Never commit `cosign.key`.

## Apps

```sh
just apps-install          # install everything in apps/*.Brewfile
just apps-check            # show what's listed but not installed
just apps-cleanup          # show what's installed but not listed (dry run)
just apps-cleanup --force  # uninstall what's installed but not listed
```

- **Add an app:** add a line to `apps/flatpaks.Brewfile`
  (`flatpak "<app id>"`, find IDs with `flatpak search` or on
  [Flathub](https://flathub.org)) or `apps/cli.Brewfile` (`brew "<formula>"`).
  Then run `just apps-install`.
- **Remove an app:** delete its line, check `just apps-cleanup`, then run
  `just apps-cleanup --force`. Aurora's default Flatpaks are always kept.

## Distrobox

Boxes are containers that share your home directory with the host. Use them
for development.

- `distrobox/fedora_main/Containerfile`: the main development box with CLI
  basics, Node.js, Rust, Claude Code, Codex, opencode, pi and Paseo. It's
  based on `fedora-toolbox` and matches the host's Fedora version.
- `distrobox/distrobox.ini`: which boxes exist and their options.

```sh
just box-update      # rebuild all images with the latest packages and recreate the boxes
just box-build       # rebuild the images using the cache (quick, after editing a Containerfile)
just box-create      # recreate the boxes from distrobox.ini
just box-enter       # open a shell in fedora_main (or: just box-enter <name>)
just box-list
just box-rm
```

Tools in a box are installed into the image, not into your home. Change them
by editing the Containerfile and running `just box-update`. Anything you
`dnf install` by hand inside a box is lost when the box is recreated. Your
files and settings in `$HOME` (`~/.claude`, `~/.codex`, `~/.cargo`, ...) are
kept.

Self-updaters (Claude Code, opencode) are turned off in the box, because
`/usr/local` is read-only for your user. `just box-update` installs the latest
versions. For the same reason, update pi with `just box-update`, not
`pi update`. Extensions you add with `pi install` go to `~/.pi` and are kept.

**npm tools** (coding agents and other dev CLIs) go on the `npm install -g`
line in `distrobox/fedora_main/Containerfile`. Don't install them with
`npm -g` on the host.

**Paseo** runs and manages the coding agents in the box. Start its daemon
inside the box with `paseo`. The box shares the host's network, so you can
open its web UI in a host browser or pair the mobile app.

To run a host tool from inside a box, use `distrobox-host-exec <command>`. For
example, `distrobox-host-exec bw` runs the host's Bitwarden CLI.

**Add a box:**

1. Create `distrobox/<name>/Containerfile`. Copy the top of
   `fedora_main/Containerfile` to start from the same Fedora image.
2. Add `<name>` to `boxes` at the top of the `Justfile`.
3. Add a `[<name>]` section to `distrobox/distrobox.ini`.
4. Run `just box-update`.

## Setting up a new machine

1. Install Aurora, or use the ISO from the "Build disk images" workflow (see
   below).
2. Switch to this image and reboot:
   `sudo bootc switch ghcr.io/attilakapostyak/ublue_legion5:latest`
3. Clone this repo and run `just os-switch-signed`, then reboot.
4. Run `just setup` to install the apps and build the boxes.

## Disk images

`.github/workflows/build-disk.yml` builds an installer ISO
(`disk_config/iso.toml`) and a qcow2 VM image (`disk_config/disk.toml`) from
the published image. Start it manually from the Actions tab. The files show up
as workflow artifacts, or in S3 if you configure the `S3_*` secrets.

## Repository layout

```
Containerfile                 OS image: base image + build step
build_files/build.sh          OS image customizations
cosign.pub                    public key for image signature verification
apps/cli.Brewfile             host CLI tools (Homebrew)
apps/flatpaks.Brewfile        desktop apps (Flatpak via brew bundle)
distrobox/distrobox.ini       box definitions
distrobox/<box>/Containerfile box images
disk_config/                  ISO / VM image settings for bootc-image-builder
.github/workflows/            image build (daily + on push) and disk image build
Justfile                      all commands
```
