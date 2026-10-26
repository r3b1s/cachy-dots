# Services (`opt/services/`)

This directory contains setup scripts, systemd service units, and configuration files
for opt-in background services and daemons. None of these are installed or enabled
by default.

## Pattern and Layout

Each service lives in its own dedicated directory:

```text
opt/services/
├── AGENTS.md                  # This guide
└── <service>/
    ├── install.sh | setup.sh  # Provisioning and teardown script
    ├── <service>.service      # Systemd unit (system or user)
    └── ...                    # Service configs, sysusers, udev rules
```

### Conventions

* **Non-destructive & Opt-In:** Services are never enabled automatically by `install.sh`. Users explicitly opt in by running the service's setup script.
* **Separation of System vs. User Services:**
  * **System services** (e.g., Kanata) require root privileges and manage system-wide device access, modules, or hardware:
    * System unit installed to `/etc/systemd/system/<service>.service`
    * Dedicated unprivileged user configured via `/etc/sysusers.d/<service>.conf`
    * Device nodes/permissions configured via `/etc/udev/rules.d/`
  * **User services** (e.g., Paseo, Sunshine) run under the user's session (`systemctl --user`):
    * User unit installed to `~/.config/systemd/user/<service>.service`
    * Environment variables configured via unit `Environment=` directives
    * Managed without sudo
* **Modular Session Autostart Pattern:**
  * To avoid poluting base repository dotfiles (`hypr/cachy.lua` and `i3/conf.d/05-autostart.conf`) with autostarts for opt-in services, each graphical session provides a per-host modular hook:
    * **Hyprland**: `~/.config/hypr/cachy.lua` (copied once per host via `import_cachy_lua`) dynamically checks for and loads `~/.config/hypr/cachy-services.lua` during `hyprland.start`. Service scripts add `hl.exec_cmd("systemctl --user start <service>.service")`.
    * **i3**: `~/.config/i3/config` includes `conf.d/*.conf`. Service scripts add `exec --no-startup-id systemctl --user start <service>.service` to `~/.config/i3/conf.d/06-services.conf`.
  * Services that require a running graphical display server (e.g. Sunshine) omit `WantedBy=default.target` from their systemd service file so they never start on headless/TTY/SSH logins. Instead, they are started by these session autostart hooks. Systemd's `Restart=on-failure` monitors and restarts the service if it crashes during the session.
* **Clean Uninstallation:** Every script should support `--remove` to disable/stop the service, remove the unit file, and delete system configuration files.
* **Dry-Run Support:** Scripts support `-n|--dry-run` and `-h|--help`.

## Current Services

### 1. `kanata/`
Hardware-level keyboard remapping daemon (`opt/services/kanata/install.sh`).
* Package: `chaotic-aur/kanata`
* Unit: System service (`kanata.service`) running as unprivileged user `kanata`
* Permissions: `/etc/sysusers.d/kanata.conf` (user in `input` and `uinput` groups), `/etc/udev/rules.d/99-kanata-uinput.rules`, `/etc/modules-load.d/kanata.conf` (`uinput` kernel module)
* Layout: `/etc/kanata/enthium.kbd`

### 2. `paseo/`
Supervisor daemon and web UI for AI coding agent environments (`opt/services/paseo/setup.sh`).
* CLI: `@getpaseo/cli` installed via `mise` (`npm` backend)
* Unit: Systemd user service (`~/.config/systemd/user/paseo.service`)
* Features: Foreground runner mode, local web UI on port 6767, remote relay disabled by default
* Desktop app: `appimage.sh` installs the latest release's `Paseo-x86_64.AppImage` (checked against the sha256
  GitHub publishes) through `bin/install-appimage`, renamed `Paseo-<version>-x86_64.AppImage`: upstream's name has
  no version, from which `install-appimage` would make "Paseo x86 64". It then rewrites `paseo.desktop` from the
  entry inside the AppImage (hicolor icons, `--class`, `StartupWMClass`, the `paseo://` handler) and removes the
  Paseo AppImages it replaces, with their entries. Starting it needs `fuse2` (`libfuse.so.2`).

### 3. `sunshine/`
Self-hosted GameStream server for Moonlight (`opt/services/sunshine/install.sh`).
* Package source:
  * CachyOS: strictly `cachyos/sunshine` (no fallbacks)
  * Arch Linux: strictly `lizardbyte/sunshine` via LizardByte's official pacman repo (`https://github.com/LizardByte/pacman-repo/releases/latest/download`) (no fallbacks)
* Unit: Systemd user service (`~/.config/systemd/user/sunshine.service`, targetless / no `WantedBy=default.target` to avoid premature headless crashes)
* Lifecycle: Started by graphical session hooks (`06-services.conf` in i3, `cachy-services.lua` in Hyprland) via `systemctl --user start sunshine.service`. Supervised by systemd (`Restart=on-failure`). When switching sessions (`cachy-session`), `point_sunshine` updates `~/.config/sunshine/sunshine.conf` (`capture = x11` for i3, `capture = wlr` for Hyprland).

### 4. `rakazo/`
[Rakazo](https://github.com/elie222/rakazo) in an Arch Linux VM of its own (`opt/services/rakazo/`). The
scripts' headers have the details; this is what they cannot show.
* **Two steps, one root.** `host-setup.sh` is the only part that needs root, run once (the pattern hitkit
  uses): the libvirt network `rakazo` (bridge `rakazo0`, `10.41.41.0/30`, the host `.1`, one static DHCP lease
  `.2` for the VM's MAC), `allow rakazo0` in a managed block of `/etc/qemu/bridge.conf`, `rakazo-guard.service`,
  the ufw rules, `virtnetworkd.service` enabled and lingering. `install.sh` runs as the user: the VM lives in
  `qemu:///session` (a QEMU escape lands in the user's account, not root's), plugged into the bridge by the
  setuid `qemu-bridge-helper`. Note that a user in the `libvirt` group is root-equivalent anyway.
* **Network calls use `network:///system`.** `qemu:///system` goes through `virtqemud`, which a host with
  only the network daemon does not run.
* **The guard** is an nftables table of its own (`inet cachy_rakazo`), so it holds with ufw off: from `rakazo0`
  the host takes DHCP and DNS and nothing else, forwarding goes to public IPv4 only, and nothing opens a
  connection into the bridge. `install.sh` refuses to start the VM without it.
* **Access** is the host's: `rakazo-web.socket` (user unit, `FreeBind=yes` so it binds before NetBird is up)
  listens on `127.0.0.1:15173` and wt0's address and hands off to `systemd-socket-proxyd`, which forwards to
  the VM's port 5173. ufw opens the port on `wt0` only. Port 5173 on the host is Vite's.
* **One origin.** Rakazo takes a single `WEB_ORIGIN`/`BETTER_AUTH_URL`, and Better Auth refuses a sign-in
  from any other, so the origin is the NetBird address, also on the host. Re-run `install.sh` when it changes.
* **The release** is the newest `vX.Y.Z` that GHCR has for both `app` and `computer`; GitHub's releases are the
  desktop app's and can be ahead of the images. The compose files come from the same git tag, not `main`.
* **The guest** (`guest.sh`, piped over SSH as one `main` so nothing eats the rest of it from stdin): rootful
  Docker, because upstream's bot-computer egress rules need the `DOCKER-USER` chain (rootless forces
  `SANDBOX_COMPUTER_EGRESS=open`). Bot DNS goes to Quad9 (9.9.9.9, then 149.112.112.112), because the VM's
  resolver is the host's dnsmasq, a private address those rules drop. The secrets stay in the VM's
  `/home/rakazo/rakazo/.env`.
* **Signups** are open on a fresh install; `install.sh --close-signups` sets `SIGNUPS_ENABLED=false` once your
  account exists. Upstream reads it on every start.
