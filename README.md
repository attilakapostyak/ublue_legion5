# ublue_legion5

My personal OS image for a Lenovo Legion 5: [Aurora](https://getaurora.dev)
(KDE Plasma, Fedora Atomic) with the developer tools (DX) and the open NVIDIA
driver, customized with a [bootc](https://github.com/bootc-dev/bootc)
`Containerfile`. Based on the
[Universal Blue image template](https://github.com/ublue-os/image-template).

Everything is managed with [`just`](https://just.systems). Run `just` in this
directory to list the recipes.

## Reinstall from zero

1. Install Aurora from its ISO.
2. Switch to this image and reboot:
   ```sh
   sudo bootc switch ghcr.io/attilakapostyak/ublue_legion5:latest
   ```
3. Turn on signature verification and reboot again:
   ```sh
   git clone git@github.com:attilakapostyak/ublue_legion5.git && cd ublue_legion5
   just os-switch-signed
   ```
   If a blue "MOK management" screen appears: **Enroll MOK → Continue →
   Yes**, password `universalblue`.
4. Log in to Niri, then install apps and boxes and check the system:
   ```sh
   just setup
   ```

That's all. The image handles the NVIDIA, Flatpak and Niri setup itself.
The BIOS graphics mode must be **Discrete**; it's stored in the firmware, so
a reinstall keeps it, and `just doctor` warns if it isn't. Details:
[Setting up a new machine](#setting-up-a-new-machine). Something broken: run
`just doctor`, then see [Troubleshooting](#troubleshooting).

## Where does software go?

The OS is read-only. Software lives in one of four layers. Each layer is
declared in a file in this repo:

| What | Where | Declared in | Applied with |
|---|---|---|---|
| Drivers, kernel modules, system services, system-wide config | **OS image** | `build_files/build.sh` | push + `just os-update` + reboot |
| Command-line tools for everyday use on the host | **Homebrew** | `apps/cli.Brewfile` | `just apps-install` |
| Desktop (GUI) applications | **Flatpak** (Flathub) | `apps/flatpaks.Brewfile` | `just apps-install` |
| Desktop apps not on Flathub | **AppImage** (`~/.local/bin`) or upstream tarball (`~/.local/opt`) | `apps/Appimages.sh` | `just apps-install` |
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
just apps-install   # install and upgrade everything in apps/*.Brewfile and apps/Appimages.sh
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
just apps-install          # install everything in apps/*.Brewfile and apps/Appimages.sh
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

## Niri session

The image also ships [Niri](https://github.com/niri-wm/niri), a scrollable
tiling compositor, with DankMaterialShell (DMS) as its desktop shell: bar,
dock, launcher, notifications, Wi-Fi/Bluetooth/audio controls. KDE Plasma
stays the default desktop. To use Niri, pick **Niri** in the session menu on
the login screen; the login screen remembers your last choice.

- DMS starts automatically in Niri sessions only (`build_files/build.sh` ties
  it to `niri.service`). Don't run `systemctl --user enable dms`: that would
  also start it in Plasma, with two notification daemons and two bars.
- Leave DMS's GTK/Qt/KDE theming options off. They write to `~/.config` and
  would change Plasma's look too.
- Your settings live in your home directory: `~/.config/niri/config.kdl`
  (created on Niri's first start) and DMS's settings in `~/.config`. Keep them
  in chezmoi. Rolling back the OS image doesn't undo changes there.
- Try it with a separate test user first, so your own `~/.config` stays
  untouched until you know what you want.
- Settings for this laptop ship in the image (`build_files/niri/*.kdl`,
  installed to `/usr/share/ublue_legion5/niri/`). At every Niri login,
  `legion5-niri-setup` adds an `include` line for each file to
  `~/.config/niri/config.kdl` if it's missing, and installs the DMS
  calculator plugin. Nothing to run by hand. To change a setting, edit the
  file in `build_files/niri/` and update the image.
  - `legion5.kdl` makes Niri render on the NVIDIA GPU; see
    [Troubleshooting](#troubleshooting).
  - `workspaces.kdl` gives each monitor ten fixed workspaces on
    `Mod+1` ... `Mod+0` (`Mod+Ctrl+<number>` moves a window there). The
    external monitors are matched by make, model and serial; edit the file
    when a monitor is replaced.
  - `binds.kdl` adds key bindings. `Mod+Space` opens the DMS launcher: type
    to start an app, or type a calculation such as `2+2` and press Enter to
    copy the result. The calculator is a third-party DMS plugin
    ([DankCalculator](https://github.com/rochacbruno/DankCalculator)).
- Niri needs a GPU rendering device (`/dev/dri/renderD*`). It doesn't work in
  Hyper-V VMs, which only have a display device; Plasma does, using software
  rendering.

## Setting up a new machine

The image sets up the hardware itself. What a person has to do:

1. **Once per laptop:** in the BIOS (F2 at the Lenovo logo), set the graphics
   mode to **Discrete** (Configuration → Graphics Device; the exact name may
   differ). In hybrid mode the firmware sometimes leaves the NVIDIA GPU
   uninitialized and the external monitors stay dead. The setting is stored
   in the firmware, so a reinstall keeps it; a BIOS reset doesn't.
2. Install Aurora, or use the ISO from the "Build disk images" workflow (see
   below).
3. Switch to this image and reboot:
   `sudo bootc switch ghcr.io/attilakapostyak/ublue_legion5:latest`
4. Clone this repo, run `just os-switch-signed` and reboot.
5. **If** a blue "MOK management" screen appears during that reboot: choose
   **Enroll MOK → Continue → Yes**, password `universalblue`. The image
   queued the Secure Boot key for the NVIDIA driver because it wasn't
   enrolled; the firmware only accepts it with a person at the keyboard. A
   reinstall normally keeps the key, so the screen doesn't appear.
6. Log in, run `just setup` (apps and boxes) and `just doctor`.

Done automatically by the image, no command needed:

| What | How | Log |
|---|---|---|
| Queue the Secure Boot key if it isn't enrolled | `legion5-mok-enroll.service`, every boot | `journalctl -b -u legion5-mok-enroll` |
| Flatpak NVIDIA extension matching the driver (else Flatpak apps use the CPU) | `legion5-flatpak-nvidia.service`, every boot, retries without network | `journalctl -b -u legion5-flatpak-nvidia` |
| Niri settings and DMS calculator | `legion5-niri-setup.service` (user), every Niri login | `journalctl --user -b -u legion5-niri-setup` |

## Troubleshooting

`just doctor` checks for the problems below and prints the fix.

**External monitors (HDMI, USB-C) are not detected.** Both outputs are wired
to the NVIDIA GPU, so they only work when the NVIDIA driver is loaded. With
Secure Boot on, the kernel only loads the driver if the Universal Blue signing
key is enrolled in the firmware. The kernel log then shows
`Loading of module with unavailable key is rejected`. The image queues the
key at boot (`legion5-mok-enroll.service`); reboot and confirm it on the blue
MOK screen (step 5 of the setup above). The key is stored in the firmware, so
it survives a reinstall, but not a firmware reset or a new mainboard.

**External monitors are dead although the key is enrolled.** In hybrid
graphics mode the firmware sometimes hands over the NVIDIA GPU uninitialized.
The kernel log shows `pci 0000:01:00.0: BAR 1 [mem 0x00000000-0x0fffffff
64bit pref]` (256 MB; a good boot shows `0x1ffffffff`, 8 GB) and `NVRM:
RmInitAdapter failed`, and `just doctor` reports "driver is loaded but failed
to start the GPU". Seen with driver 620 on kernel 7.2, on every boot that
followed a session in which the NVIDIA GPU worked. Fix: set the BIOS graphics
mode to Discrete (step 1 of the setup above). Until then, shut down and start
again. Don't detach and reattach the driver: the GPU then looks started but
can't show a picture, and the login screen hangs.

**Flatpak apps (Vivaldi, ...) are slow, video stutters.** Flatpak apps need an
extension that matches the host NVIDIA driver exactly; with the wrong one they
draw on the CPU. `legion5-flatpak-nvidia.service` installs it at boot after a
driver update. Apps that were already running keep using the CPU until you
quit them completely (Vivaldi: `Ctrl+Q`) and start them again.

**External monitors show corrupted boxes and horizontal lines in Niri.** In
hybrid mode Niri renders on the Intel GPU and copies each frame to the NVIDIA
GPU, which corrupts the picture. `build_files/niri/legion5.kdl` makes Niri
render on the NVIDIA GPU.

## Disk images

`.github/workflows/build-disk.yml` builds an installer ISO
(`disk_config/iso.toml`) and a qcow2 VM image (`disk_config/disk.toml`) from
the published image. Start it manually from the Actions tab. The files show up
as workflow artifacts, or in S3 if you configure the `S3_*` secrets.

## Repository layout

```
Containerfile                 OS image: base image + build step
build_files/build.sh          OS image customizations (incl. the Niri session)
build_files/legion5-*.sh      boot/login fixes: Secure Boot key, Flatpak NVIDIA, Niri settings
build_files/niri/*.kdl        Niri settings: NVIDIA rendering, workspaces, key bindings
cosign.pub                    public key for image signature verification
apps/cli.Brewfile             host CLI tools (Homebrew)
apps/flatpaks.Brewfile        desktop apps (Flatpak via brew bundle)
apps/Appimages.sh             desktop apps not on Flathub (AppImages)
distrobox/distrobox.ini       box definitions
distrobox/<box>/Containerfile box images
disk_config/                  ISO / VM image settings for bootc-image-builder
.github/workflows/            image build (daily + on push) and disk image build
Justfile                      all commands
```
