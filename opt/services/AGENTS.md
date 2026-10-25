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

### 3. `sunshine/`
Self-hosted GameStream server for Moonlight (`opt/services/sunshine/install.sh`).
* Package source:
  * CachyOS: strictly `cachyos/sunshine` (no fallbacks)
  * Arch Linux: strictly `lizardbyte/sunshine` via LizardByte's official pacman repo (`https://github.com/LizardByte/pacman-repo/releases/latest/download`) (no fallbacks)
* Unit: Systemd user service (`~/.config/systemd/user/sunshine.service`, targetless / no `WantedBy=default.target` to avoid premature headless crashes)
* Lifecycle: Started by graphical session hooks (`06-services.conf` in i3, `cachy-services.lua` in Hyprland) via `systemctl --user start sunshine.service`. Supervised by systemd (`Restart=on-failure`). When switching sessions (`cachy-session`), `point_sunshine` updates `~/.config/sunshine/sunshine.conf` (`capture = x11` for i3, `capture = wlr` for Hyprland).
