# Optional Software, Services, and Scripts (`opt/`)

The `opt/` directory houses optional software, background services, development tools,
and host-provisioning scripts that are **not** part of the default desktop install.
Nothing here is executed or enabled automatically by `install.sh`; users explicitly opt in
based on the hardware, session, or workflow requirements of a specific host.

## Subdirectories

* **`install-from-source/`**:
  Applications and tools compiled directly from upstream source repositories/forges
  (e.g., GitHub, GitLab). Each application resides in its own subdirectory containing an
  `install.sh` and a scoped `mise.toml` that manages the required language toolchains in
  isolation from system packages. (See `opt/install-from-source/AGENTS.md`).

* **`install-from-proprietary/`**:
  Closed-source / proprietary applications that upstream ships only as a vendor binary
  (tarball, AppImage, `.deb`), with no source to build and no package in the repos
  (e.g., Google Antigravity). Each application resides in its own subdirectory containing
  an `install.sh` that downloads the vendor release, unpacks it as the invoking user, and
  installs a root-owned copy under `/usr/local`. (See `opt/install-from-proprietary/AGENTS.md`).

* **`services/`**:
  Opt-in background services, daemons, and systemd units (both system-level and user-level).
  Contains setup scripts, `.service` unit files, and supporting hardware/permission configs
  such as udev rules and sysusers files (e.g., Kanata key remapping, Paseo daemon, Sunshine GameStream server, the Incus daemon, the Rakazo service stack under it, Voxtype dictation, rootless Syncthing Quadlet). (See `opt/services/AGENTS.md`).

## Standalone Scripts

| Script | Purpose |
| :--- | :--- |
| **`arch-cloud-vm.sh`** | Provisions a clean, headless nested Arch Linux VM using QEMU/KVM/libvirt and arch-boxes cloud images for isolated testing. |
| **`arch-cloud-vm-dots.sh`** | Extends `arch-cloud-vm.sh` by adding a SPICE graphical console and a first-boot job that clones the repo and runs `./install_vm.sh`, to test dotfiles on clean systems. |
| **`arch-cloud-vm-lib.sh`** | Common library of helper functions (cloud image verification, cloud-init seed generation, overlay disk creation, virsh lifecycle) shared by the VM scripts. |
| **`blesh.sh`** | Installs `blesh-git` (Bash Line Editor) from chaotic-aur and links `shell/blerc` to `~/.blerc`. Supports `--remove`. |
| **`dux-settings.sh`** | Merges or restores the baseline dux-shell settings snapshot (`dms/settings.json`) into `~/.config/dms/settings.json`. Supports `--reset`. |
| **`fish.sh`** | Makes fish the login shell: removes CachyOS's own fish and zsh setups (with what only they needed), installs `fish`, links `fish/config.fish` (bash's aliases and functions, ported) and records the choice in `~/.config/cachy-dots/login-shell`, which `install.sh` and `sync.sh` follow. Supports `--remove` (back to bash; fish stays installed). |
| **`hibernate.sh`** | Adds hibernation to a btrfs root: a RAM-sized swap file in an `@swap` subvolume (zram stays for everyday swapping), `resume=` in Limine's command line, and a lid that suspends, then hibernates after 10 minutes. Supports `--size` and `--remove`. |
| **`hyprland.sh`** | Installs and configures the opt-in Hyprland + dux-shell session (system dependencies, pinned dux GitHub release binaries, initial config, and assets). Supports `--remove`. |
| **`noctalia.sh`** | Installs the opt-in Hyprland + Noctalia session: Hyprland, `noctalia`, and what stands in for dux's apps (`nautilus`, `hyprpicker`, `btop`). Leaves `ly` and any dux install alone, and installs no `noctalia-greeter`. Supports `--remove`. |
| **`firewalld-lib.sh`** | Helpers for the `cachy-*` firewalld zones and policies the opt-in scripts own. Sourced, never run. |
| **`lab-firewall.sh`** | Adds the firewalld zones and policies the `labbr0` lab network needs (DHCP and DNS to the host; forwarding to the internet and `tun0`, not the LAN). Sourced by `virt.sh` and `arch-cloud-vm.sh`. |
| **`omarchy-repo.sh`** | Trusts Omarchy's signing key and appends the `[omarchy]` package repo to `/etc/pacman.conf` without triggering a full system upgrade. Supports `--remove`. |
| **`omarchy-retroarch.sh`** | Installs RetroArch with the full libretro core suite, CRT shaders, and directory structures. Pulls packages from Arch, CachyOS, and Omarchy repos. Supports `--remove`. |
| **`virt.sh`** | Configures KVM/QEMU/libvirt virtualisation on the host: adds the user to the `libvirt` group, pins libvirt's nftables firewall backend, and defines the `labbr0` NAT network (10.40.40.0/24, in the `cachy-lab` zone while firewalld runs) and the `default` storage pool on `qemu:///system`. The libvirt `default` network is left undefined. |
| **`zsh.sh`** | Makes zsh the login shell, as `fish.sh` does fish: links `shell/init.zsh` and `integrations.zsh` beside bash's files, which share `shell/aliases`, and adds a managed block to `~/.zshrc`. Supports `--remove` (back to bash; zsh stays installed). |
