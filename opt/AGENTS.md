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

* **`services/`**:
  Opt-in background services, daemons, and systemd units (both system-level and user-level).
  Contains setup scripts, `.service` unit files, and supporting hardware/permission configs
  such as udev rules and sysusers files (e.g., Kanata key remapping, Paseo daemon, Sunshine GameStream server). (See `opt/services/AGENTS.md`).

## Standalone Scripts

| Script | Purpose |
| :--- | :--- |
| **`arch-cloud-vm.sh`** | Provisions a clean, headless nested Arch Linux VM using QEMU/KVM/libvirt and arch-boxes cloud images for isolated testing. |
| **`arch-cloud-vm-dots.sh`** | Extends `arch-cloud-vm.sh` by adding a SPICE graphical console and automated execution of `./install.sh` to test dotfiles on clean systems. |
| **`arch-cloud-vm-lib.sh`** | Common library of helper functions (cloud image verification, cloud-init seed generation, overlay disk creation, virsh lifecycle) shared by the VM scripts. |
| **`blesh.sh`** | Installs `blesh-git` (Bash Line Editor) from chaotic-aur and links `shell/blerc` to `~/.blerc`. Supports `--remove`. |
| **`dux-settings.sh`** | Merges or restores the baseline dux-shell settings snapshot (`dms/settings.json`) into `~/.config/dms/settings.json`. Supports `--reset`. |
| **`hyprland.sh`** | Installs and configures the opt-in Hyprland + dux-shell session (system dependencies, pinned dux GitHub release binaries, initial config, and assets). Supports `--remove`. |
| **`lab-firewall.sh`** | Configures firewall rules (ufw/nftables) for nested VM lab subnets and bridge interfaces. |
| **`omarchy-repo.sh`** | Trusts Omarchy's signing key and appends the `[omarchy]` package repo to `/etc/pacman.conf` without triggering a full system upgrade. Supports `--remove`. |
| **`omarchy-retroarch.sh`** | Installs RetroArch with the full libretro core suite, CRT shaders, and directory structures. Pulls packages from Arch, CachyOS, and Omarchy repos. Supports `--remove`. |
| **`virt.sh`** | Configures KVM/QEMU/libvirt virtualisation on the host, adds the user to the `libvirt` and `kvm` groups, and sets up default bridge networking. |
