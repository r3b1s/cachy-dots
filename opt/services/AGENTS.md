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
  * **User services** (e.g., Paseo) run under the user's session (`systemctl --user`):
    * User unit installed to `~/.config/systemd/user/<service>.service`
    * Environment variables configured via unit `Environment=` directives
    * Managed without sudo
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
