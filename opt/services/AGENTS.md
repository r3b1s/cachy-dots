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
  * To avoid polluting base repository dotfiles (`hypr/cachy.lua` and `i3/conf.d/05-autostart.conf`) with autostarts for opt-in services, each graphical session provides a per-host modular hook:
    * **Hyprland**: `~/.config/hypr/cachy.lua` (copied once per host via `import_cachy_lua`) dynamically checks for and loads `~/.config/hypr/cachy-services.lua` during `hyprland.start`. Service scripts add `hl.exec_cmd("systemctl --user start <service>.service")`.
    * **i3**: `~/.config/i3/config` includes `conf.d/*.conf`. Service scripts add `exec --no-startup-id systemctl --user start <service>.service` to `~/.config/i3/conf.d/06-services.conf`.
  * A daemon that is not a systemd unit (voxtype) adds one command instead, kept in a repo script, so the hook line never changes: quoted shell inside an i3 `exec` and a Lua string breaks easily, and `cachy.lua` loads `cachy-services.lua` through `pcall`, so an error there silently drops every hook in it.
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
A stack of self-hosted services under [Incus](https://linuxcontainers.org/incus/), one NixOS guest each,
published on the NetBird address: [Rakazo](https://github.com/elie222/rakazo), and
[Executor](https://github.com/UsefulSoftwareCo/executor) (an MCP gateway) with Thunderbird ESR and its MCP
add-on. `host-setup.sh` runs once with sudo; `apply.sh` does the rest as the user and is re-run after any change.
The `incus-admin` group it adds applies to new logins only: a terminal inherits the desktop session's groups, so
log out once, or use `newgrp incus-admin` in a terminal. Never `sudo incus console`: root cannot open a window on
the user's display.
The scripts' headers and the Nix modules have the details; this is what they cannot show.
* **One description.** `stack.toml` and `services/<name>/service.toml` are the registry, read by both
  `render.py` (Incus objects: per service a bridge, its ACL and a profile) and `flake.nix` (one
  `nixosConfigurations.<name>` per directory). A service's `index` is its address plan: bridge
  `<prefix>-<name>` on `10.70.<index>.0/24` (host `.1`, guest `.2`) and, when published, port
  `14800 + index`. Adding a service is a new directory. `apply.sh --render` prints what would be applied.
* **The edge** (a NixOS container running Caddy) is the only way in. Incus NAT proxy devices forward each
  published port on wt0's address to it, Caddy terminates TLS and proxies to the guest. Nothing listens on
  127.0.0.1: the host's own connections to its NetBird address take the same path, so every client, the host
  and Rakazo included, uses the one origin `https://<NetBird address>:<port>` that Better Auth (in Rakazo and
  Executor) insists on. It also means that with NetBird down the host loses the stack too.
* **The CA** lives in `~/.local/share/cachy-stack/ca`, name-constrained to the NetBird address; only the leaf
  goes to the edge, and every guest gets `ca.crt`. A new NetBird address means a new CA, which clients must
  trust again. Node clients: `NODE_EXTRA_CA_CERTS`.
* **ACLs.** Incus evaluates an ACL's reject rules before its allow rules, so "reject private, allow this host"
  cannot be written: each ACL rejects by default and allows the public IPv4 space (all of it minus
  `stack.toml`'s `private` list, computed) plus each exception. Incus's NAT proxy rewrites the destination
  before the ACL sees it, so `uses = ["executor"]` allows the edge's address and port, not the NetBird one.
  Incus's baseline DHCP and DNS rules come before the ACLs. ufw would drop the bridges' DHCP, DNS and
  forwarding, hence `host-setup.sh`'s block in `/etc/ufw/before.rules` for `cs-+`.
* **Guests** start from `images:nixos/26.05`; `apply.sh` copies this directory in as `/etc/cachy-stack` and
  runs `nixos-rebuild switch --flake` there (builds in the guest: about 2 GiB of RAM, or it is OOM-killed).
  The traps it works around: the agent answers before the guest has DNS, so it waits for that; commands
  through a VM's incus-agent get no NixOS `PATH` (`gexec`); containers
  need `security.nesting`, and Nix's sandbox cannot mount `/proc` under LXCFS, so containers build without it;
  Incus's `zzz-lxc-service.conf` clears `LoadCredential` in every container unit, so Caddy's key is copied
  into a `RuntimeDirectory` instead; a switch stops `restartIfChanged = false` units (the display manager) without
  starting them, so `apply.sh` starts `default.target` after each one. `modules/common.nix` matches the uplink
  by name: matched by type, networkd also takes Docker's veths (ether links) and pulls them off their bridges,
  and containers on one network cannot reach each other. Runtime facts and secrets stay out of
  the flake: `/var/lib/cachy-stack/{ca.crt,origin.env}`, written by `apply.sh`.
* **Executor** runs upstream's self-host image with the host network. Agents use a personal access token as
  `Authorization: Bearer` on `/mcp`; adding an MCP server by URL works only for servers with no sign-in or
  OAuth. A private address needs `EXECUTOR_APPS_ALLOW_PRIVATE_FETCH`, plain HTTP also
  `EXECUTOR_URL_ALLOW_HTTP_ORIGINS`, and a loopback URL is accepted but never works. Its tool index fills
  lazily: `search` before the first `call` on a new organisation.
* **Thunderbird** (ESR) runs in an i3 session that LightDM logs `tbird` into at boot (`services/executor/i3.conf`,
  a subset of `i3/conf.d`'s chords), with Firefox ESR as the default browser; sign in to the accounts with
  `incus console cs-executor --type=vga`. Thunderbird hands Gmail's and Microsoft's OAuth sign-in to the default
  browser and takes the answer on a localhost listener, all inside the guest. It is a `systemd --user` unit
  started by i3 and restarted whenever it exits (the MCP add-on lives in it), so there is no logout, and it must
  never get a primary password. NixOS gives every unit a minimal `PATH`, and GIO hides applications whose
  program is not on `PATH`, so the unit carries the system's: without it Thunderbird finds no browser and asks
  "Choose an application". The MCP add-on is pinned by hash with `update_url` stripped (it named the author's own
  server, from which Thunderbird would update a fully privileged add-on) and force-installed by policy with
  updates off. Its token changes on every start, so `tb-mcp-shim` adds it, on the guest's own address, speaking
  HTTP/1.1: Executor reuses its connection between a probe's requests, and a server that closes it after each
  response (HTTP/1.0) fails the import at random. An import tried while Thunderbird restarts fails with "could
  not respond right now".
* **Proton** goes through Proton Mail Bridge (`proton-bridge.service`, headless, as `tbird`), on
  `127.0.0.1:1143`/`1025`. With no D-Bus session it falls back from the Secret Service to `pass`, keyed by a
  GPG key without a passphrase (the guest's disk is the secret). The unit waits for the store; log in once
  with `incus exec cs-executor -t -- proton-bridge-login` (`login`, then `info` for the password Thunderbird
  uses, then `exit`; a paid plan). nixpkgs' Bridge can trail Proton's releases.
* **Clients** trust the CA: `sudo trust anchor --store ~/.local/share/cachy-stack/ca/ca.crt` covers curl and
  browsers (NSS goes through p11-kit here); Node-based agents need `NODE_EXTRA_CA_CERTS`. Executor's first
  visitor becomes its owner, so create the account as soon as it is up.
* **Rakazo** is upstream's Docker deployment, not a Nix rewrite: `install-images.sh` and its Compose file,
  pinned by tag and hash, run `--local` by `rakazo.service` (`rakazo-up.sh`, which owns a few `.env` keys and an
  override). Upstream's bot-computer egress script is run as a NixOS unit (`--apply`), since it would install
  its own unit under the read-only `/etc/systemd/system`. Bot DNS goes to Quad9: the guest's resolver is a
  private address those rules drop. `signups` in its `service.toml` closes sign-up once your account exists.
  The secrets stay in the guest's `/var/lib/rakazo/.env`; back up its `ENCRYPTION_KEY`.

### 5. `voxtype/`
Push-to-talk dictation, `$mod+d` in both sessions (`opt/services/voxtype/install.sh`, `--remove`).
* Package: `voxtype-bin`, built from the AUR with `yay` (no pacman repo has it); a repo build wins if one appears.
* Config: `config.toml` in this folder, linked to `~/.config/voxtype/config.toml`.
* Lifecycle: no unit. The hooks run `~/.local/bin/dictate daemon` (`bin/dictate`, linked by every install),
  which replaces a daemon left by the other session once it has exited (voxtype's lock), waits up to 5 s for
  WirePlumber's default sink, judged by `wpctl get-volume`'s output, as its exit status is 0 even with no sink
  (a sound output opened before it may be negotiated at 1 Hz, and the start and stop sounds go silent), then
  execs `voxtype -q daemon`.
* A host's `~/.config/hypr/cachy.lua` copied before voxtype was opt-in starts the daemon itself; the installer
  warns about it, since the copy is never overwritten. `sync.sh` warns when voxtype is installed without its hooks or config link.
