These dotfiles set up an i3 desktop on [CachyOS](https://cachyos.org/). Vanilla Arch works too: the Cachy repos
are then missing, and the pinned packages fall back to chaotic-aur. Hyprland with dux-shell is an opt-in second
session, and one of the two is active at a time (see "Sessions"). There are two install profiles: `install.sh`
(workstation: everything, on bare metal or in a VM) and `install_vm.sh` (vm: a lean desktop for a guest).

## Working on this repo

- **Never run the installers on the machine you edit on.** `install.sh`, `install_vm.sh`, `sync.sh`, `opt/*`,
  `root/install.sh` and `podman-services/*` change the system: pacman upgrades, `/etc`, ufw, the login shell,
  links in `~`. Run them on a test VM (see "Testing"). Locally, use only `bash -n`, `shellcheck` and the scripts'
  `-n`/`--dry-run`.
- **The code documents itself; this file holds what it cannot show.** Every script's header comment is its
  `--help`. `install/packages.sh` comments every package, and `install/lib.sh` lists the installer modules. `opt/`
  has its own guides: [opt/AGENTS.md](opt/AGENTS.md), [opt/services/AGENTS.md](opt/services/AGENTS.md) and
  [opt/install-from-source/AGENTS.md](opt/install-from-source/AGENTS.md). Keep this file in step when behaviour
  changes.

## Conventions

- **Scripts.** Installers are bash with `set -euo pipefail`; a few small `bin/` helpers are POSIX `sh`. The
  header comment is the text `-h`/`--help` prints, so keep it current. Installers take `-n`/`--dry-run`
  (commands go through `run`, which prints them instead), and most opt-in ones take `--remove`.
  Messages go through `say`/`warn`. A failure that should not stop the run sets `FAILED=1`, and the run exits
  non-zero at the end.
- **Idempotent.** Every step is safe to re-run and writes only when its target differs (`cmp -s`). Edits to
  files the repo does not own go in a managed block between `# >>> cachy-dots >>>` and `# <<< cachy-dots <<<`
  (`~/.bashrc`, `~/.ssh/config`, `/etc/nix/nix.conf`, `/etc/environment`; the `pacman.conf` blocks name their
  repo). Re-runs rewrite the block and never touch the rest of the file. A real file in the way of a link is
  moved to `<name>.bak.<time>`.
- **Links.** Configs are linked file by file (`link()` in `install/links.sh`), never as whole directories, so
  runtime state written next to a config stays out of the repo. Per-host files are copied once and never
  overwritten: `i3/templates/04-monitors.conf`, `hypr/cachy.lua` and `git/config` (only on a host with no global
  git config, since `git config --global` would write through a link into the repo).
- **Root-owned files are copies, never links into the repo** (root must not run or read what the user can
  edit): `install -o root -g root`, with sudoers drop-ins checked by `visudo -c` first.
- **Guards.** Optional steps check `command -v` or `pacman -Qq` and skip themselves; that is how a profile drops
  a feature. Configs use the same idiom: `sh -c 'command -v x >/dev/null && exec x'`.
- **Prose** in comments and docs uses British spelling (colour, centre). Commits are conventional with a scope:
  `feat(hyprland): …`, `fix(moonlight): …`, `docs(agents): …`.

## Layout

| Path | Holds |
| --- | --- |
| `install.sh`, `install_vm.sh`, `install/` | the installer: entry scripts name the profile, `install/` holds the steps |
| `sync.sh` | brings an installed system up to date after a pull, installing nothing |
| `bin/` | scripts linked into `~/.local/bin` (the i3-only ones are session links) |
| `vm/` | guest-only scripts, linked by the vm profile only |
| `i3/`, `hypr/`, `dms/` | the two sessions; `dms/settings.json` is a snapshot of dux's settings |
| `theme/`, `hooks/theme-set.d/` | the theme engine (`bin/x11-theme`), and hooks it runs after a switch |
| `alacritty/`, `kitty/`, `qutebrowser/`, `nvim/`, ... | one directory per app |
| `shell/`, `env/` | bash integration (`~/.config/shell`, `~/.xprofile`), telemetry opt-outs |
| `firefox/`, `chromium/` | browser policies |
| `xorg/`, `systemd/`, `ssh/` | root drop-ins: copied by the installer, or (`ssh/`) by hand |
| `applications/` | launcher entries for repo scripts |
| `opt/` | opt-in scripts and services, never run by `install.sh` |
| `podman-services/` | rootless Podman Quadlets (Syncthing over NetBird), opt-in |
| `root/` | dots for root: `sudo ./root/install.sh` copies them into `/root` |

## Repos and packages

- **Packages are named plainly, never as `cachyos-extra-v3/foo`.** The CachyOS installer lists its repos above
  `[core]`/`[extra]`, so pacman already prefers a Cachy build, and which level (v3, v4, znver4) that is depends
  on the CPU. `check_cachy_repos()` only checks the order (`pacman-conf --repo-list`) and warns; it never
  rewrites `pacman.conf`. With several providers, `--noconfirm` takes the first, which pacman lists in repo
  order, so the Cachy one.
- **Pins** (`PINNED` in `install/packages.sh`) are installed by qualified name from the first repo that has them:
  a Cachy repo, then Arch, then chaotic-aur, never the plain AUR when chaotic-aur has the package. A pin whose
  repos all lack it is skipped with a warning, and the run exits non-zero; nothing is substituted.
  `PINNED_REPLACES` lists the plain packages a pin conflicts with (`qutebrowser`, `i3lock`, `vesktop`), which are
  removed first because `--noconfirm` answers pacman's conflict prompt with no.
- **chaotic-aur** (`setup_chaotic_aur()`) is set up as its docs say, and appended at the **end** of
  `pacman.conf`, so it can never shadow a Cachy or Arch build. It is the only source of `qutebrowser-git` and
  `yaru-icon-theme`, and the fallback for `yay`, `i3lock-color` and `vesktop`. The opt-in `blesh-git` and
  `kanata` come from it too.
- **The AUR is used for `voxtype-bin` only** (`AUR_PKGS`). `install_aur()` takes it from a pacman repo when one
  has it, and otherwise builds it with `yay` as the invoking user (makepkg refuses root). `bin/default-browser`
  installs `brave-origin-bin` on demand: `cachyos/` when a Cachy repo has it, else the AUR.
- **Other repos are opt-in and also go last:** Omarchy's (`opt/omarchy-repo.sh`; take its packages by qualified
  name, since some share a name with Arch's or chaotic-aur's), and on vanilla Arch LizardByte's for Sunshine
  (`opt/services/sunshine/install.sh`, `SigLevel = Optional`).
- **Never `-S` against a stale database.** A fresh repo, or anything missing, triggers a full `pacman -Syu`
  first; `-Sy` followed by `-S` is a partial upgrade. Every pacman transaction also takes a snapper snapshot
  pair on CachyOS (`cachyos-snapper-support`), so the installer batches: one `-U` for the chaotic keyring and
  mirrorlist, the `-Syu`, then one `-S` for everything missing, pins included. Only an AUR build or a Qt
  fix-up adds another.
- **Qt.** Cachy can lag Arch on a Qt minor, and every `qt6-*` module must match `qt6-base`'s minor (they link
  its versioned private API). `sync_qt_stack()` runs after every install and takes lagging modules from `extra`;
  `install/pacman.sh` explains the rule. A Qt app installed by hand while Cachy is mid-rebuild can pull a stale
  module; `./install.sh --packages-only` fixes it.

## Installer, profiles and sync

- **Flow.** `install.sh`/`install_vm.sh` set `PROFILE`, source `install/lib.sh` and run `install_main`
  (`install/flow.sh`, the steps in order). Flags: `--packages-only`, `--links-only`, `-n`.
- **Profiles.** The lists in `packages.sh` stay complete; `install/profile-<name>.sh` names what a profile leaves
  out (`PROFILE_SKIP_PKGS`, `PROFILE_SKIP_PINNED`, `PROFILE_SKIP_AUR`, and `PROFILE_SKIP_FEATURES`, checked with
  `want <feature>`), and `apply_profile()` removes it. The workstation skips only `vm-scripts`. The vm profile's
  list lives in `profile-vm.sh` alone; it also forces the guest agents (`PROFILE_FORCE_VM`) and sets
  `PROFILE_NO_SLEEP` (`setup_no_sleep()`: a logind drop-in, masked sleep targets, X without blanking). Each run
  records the profile in `~/.config/cachy-dots/profile`, and `sync.sh` follows it.
- **Beyond packages** the installer: makes bash the login shell (CachyOS defaults to fish, and `shell/` is
  bash-only; fish stays installed, unconfigured); enables `ly@tty1`, `bluetooth` and `power-profiles-daemon`;
  starts `spice-vdagentd.socket` in a VM (the guest agents are static, udev-started units, installed only in a
  VM); sets up nix (`nix-daemon.socket` and `.service`, the `nix-users` group, a managed block of `extra-*`
  settings in `nix.conf`, no channels); writes `TERMINAL=alacritty` into `/etc/environment`; sets ufw to deny
  incoming (SSH rate-limited first when sshd is enabled); copies the touchpad and policy files; installs the
  theme helper; writes the GTK settings and dark mode; applies a theme; sets the default apps; fetches voxtype's
  model; and validates the active session's config.
- **sshd is not touched.** `setup_ssh()` scaffolds `~/.ssh`, an empty `authorized_keys` and a managed
  `~/.ssh/config` block for github.com and gitlab.com, appended only when neither host has an entry yet. The
  hardened drop-in `ssh/sshd_config.d/10-cachy-safe.conf` is copied by hand; it turns password logins off, so a
  key must be in `authorized_keys` first.
- **`sync.sh`** installs nothing, enables nothing and stays off the network (unless `--themes`). It makes the
  links, applies the session, removes dangling links into the repo, writes the root copies when they differ
  (`--no-root` skips them), re-renders the theme (i3 only), re-applies the default apps, validates, and lists
  missing packages. Services, the firewall and AUR builds stay `install.sh`'s job.
- **A kernel upgraded during the run** leaves the running kernel without modules: ufw cannot load until a reboot,
  so `setup_firewall` warns instead of stopping and the run ends with "reboot needed".

## Sessions: i3 and Hyprland

i3 is the default. Hyprland with [dux-shell](https://github.com/duxlabs-dev/dux-shell) ("dux"; its binary is
`dms`) is installed by `opt/hyprland.sh`. `bin/cachy-session status | i3 | hyprland [-n]` switches by running
`apply_session` (`install/session.sh`), and records the choice in `~/.config/cachy-dots/session`, which
`install.sh` and `sync.sh` follow. Nothing running changes: log out and pick the session in ly. Pick "Hyprland",
not "Hyprland (uwsm-managed)": uwsm is not installed.

- **What a switch does** (`install/session.sh`): it removes the other session's links (each only while it still
  points where the session put it) and makes this one's; under i3 that is `i3/`, `~/.xprofile`, dunst's config
  and the `I3_ONLY_BIN` scripts, under Hyprland `binds-user.lua` and `hyprland-mimeapps.list`. It points the
  **slots**, one link per app both sessions theme: terminal colours and font, satty, `gtk.css` (under Hyprland a
  real file importing `dank-colors.css`), Neovim's `theme.lua`, and the `FileManager1` D-Bus activation link. It
  also sets the icon theme, Vesktop's enabled theme (only while Vesktop is closed), the matugen drop-in, and
  Sunshine's `capture` key. Under Hyprland it masks `dunst` and `blueman-applet` and writes a stub
  `~/.config/i3/config` that only shows i3-nagbar. A switch there and back leaves the links byte-identical.
- **dux owns the Hyprland config.** `opt/hyprland.sh` runs `dms setup headless --compositor hyprland
  --no-systemd` once, while `~/.config/hypr/hyprland.lua` is missing. Without `--terminal`, because a terminal
  config would be written through the links into this repo. The repo adds `hypr/dms/binds-user.lua` (a link),
  `hypr/hyprland-mimeapps.list` (a link), a per-host copy of `hypr/cachy.lua`, and one `require("cachy")` line
  that `cachy-session` appends to `hyprland.lua` (and re-adds if `dms setup --force` dropped it).
- **dux itself** comes from its GitHub releases, every file pinned by sha256 in the `DUX` table of
  `opt/hyprland.sh` and installed root-owned under `/usr/local`, so `dms update` cannot replace it; bump the pins
  to upgrade. Not the AUR, and not chaotic-aur's `dms-shell-git`.
- **`binds-user.lua`** is dux's override file, loaded after its stock `binds.lua`. Each override is an
  `hl.unbind` + `hl.bind` pair, and the i3 meaning wins, except where dux has its own app (`$mod+p` opens dux's
  process list). Keep the file in the form dux's keybind editor writes (sorted, one statement per line, its
  header the only comment): dux's Settings rewrite it through the link, and git should then show only that
  change.
- **Layout-specific chords** follow the reference config (quattro-dots), not i3. The master-layout chords
  (`$mod+s`, `$mod+Shift+s`, `$mod+n`, `$mod+Shift+n`) do nothing in dux's default dwindle layout; the layout
  is left to dux's settings on purpose, and nothing in `hypr/cachy.lua` sets `general.layout`. `$mod+f`
  maximizes (`bin/maximize`); `+Shift` fullscreens without telling the client, `+Ctrl` tells the client while the
  window stays tiled, `+Alt` does both, `+Shift+Ctrl` resets the window. Not bound yet: next wallpaper, the 2000K
  nightlight, i3's restart chord, `$mod+Shift+BackSpace` and `$mod+Mod1+BackSpace`.
- **`hypr/cachy.lua`** holds what dux's editor would drop: the session environment (`~/.local/bin` on PATH,
  `XDG_SESSION_TYPE=wayland`, the telemetry opt-outs); the startup programs, whose own units hang off
  `graphical-session.target`, which this session never reaches (voxtype, `dfiles`, `dcal`, `dsearch`, and
  `~/.config/hypr/cachy-services.lua` for opt-in services); the window rules; and the `passthru`, `gaps` and
  `dictate_suppress` submaps.
- **Named workspaces.** A name is the chord that reaches it: Super is implied, another modifier is a
  three-letter prefix joined by `_` (`sft_p` is `$mod+Shift+p`, `ctl_m` is `$mod+Ctrl+m`), and a symbol key is
  its keysym (`slash`, `equal`; `plus` predates the prefixes). In i3 they are named workspaces; in Hyprland,
  special workspaces with the same names. `bin/ws-app` toggles one and launches its app only when it is empty.
  Under Hyprland it launches with `hl.dsp.exec_cmd(cmd, { workspace = "special:<name>" })`; a workspace rule's
  `on_created_empty` cannot live in `binds-user.lua`. Its launch rule places only the first window, so apps
  that reopen windows also get a window rule (Hyprland) or an `assign` (i3) whose name must match the bind's:
  Vesktop (a loading window precedes the main one), Dux Calendar (its daemon makes the window) and Moonlight.
- **Moonlight** (`$mod+Ctrl+m`, `ctl_m`): the client closes when a stream starts and returns when it ends, so
  every window of its class goes to `special:ctl_m`, and the stream window (title `<host> - Moonlight`) is also
  fullscreen with idle inhibited. The class rule has `suppress_event = "fullscreenoutput"`: in Moonlight's
  exclusive "Fullscreen" mode the stream asks for fullscreen on a named output, and Hyprland would move it to that
  output's regular workspace.
- **dux's settings snapshot**, `dms/settings.json`, is merged **under** the host's file once by
  `opt/dux-settings.sh` (the host's values win; `--reset` makes the snapshot win and keeps a backup). It must
  hold nothing that depends on how many displays a host has (`hideOnLastDisplay`/`showOnLastDisplay` once hid
  the bar on a one-monitor PC), nor `dmsWindowsFloatingSeeded`; keep `configVersion`, or dux re-runs every
  migration. It is a copy because dux rewrites the file. Left out on purpose: `hypr/dms/outputs.lua` and
  `colors.lua`.
- **Apps follow dux's colours** through a user matugen template. `cachy-session` writes a drop-in to
  `~/.config/matugen/dms/configs/cachy-dots.toml` (never your own `matugen/config.toml`). dux then renders
  `hypr/matugen/omarchy-colors.toml` into an omarchy-style palette, whose `post_hook` runs `x11-theme from-dux`
  to render the repo's templates. `theme.dux` marks that render, and `cachy-session i3` re-renders the i3
  theme. Neovim uses dux's own `dms` colourscheme (`hypr/nvim-theme.lua`; `opt/hyprland.sh` turns dux's Neovim
  template on), and Vesktop dux's `dank-discord.css`. satty keeps its own palette (`satty/config-wayland.toml`).
- **dux's apps over third-party ones.** Dux Files is the file manager under Hyprland: `$mod+e`, folders (through
  `hyprland-mimeapps.list`, read only when `XDG_CURRENT_DESKTOP` is Hyprland), `FileManager1`, and the file
  chooser (`dfiles portal install`, seeded from the system portal config so its defaults survive). Nautilus
  stays i3's. No rofi under Hyprland: pickers use `dms dmenu`.
- **Shared scripts** pick their backend from `XDG_SESSION_TYPE`: `screenshot` (maim/xclip, or
  `dms screenshot`/wl-copy), `dictate` (xclip/`xdotool --clearmodifiers`, or wl-copy/wtype plus the
  `dictate_suppress` submap, since wtype cannot release held modifiers), `ws-app`, and `default-browser` (rofi,
  or `dms dmenu`).
- **The user manager outlives a logout** for a few seconds, still holding the previous session's activation
  environment and portals. Each session resets them at login: `05-autostart.conf` exports i3's variables, unsets
  Hyprland's and stops the portals; `cachy.lua` does the reverse.
- **Sunshine's capture method follows the session** (`point_sunshine`): `capture = x11` under i3, `wlr` under
  Hyprland, and only that key of `~/.config/sunshine/sunshine.conf` is edited. With `x11` under Hyprland,
  Sunshine fails at start. A running Sunshine keeps its method until it restarts. The service itself is in
  [opt/services/AGENTS.md](opt/services/AGENTS.md).
- **Daemons that outlive a session** (voxtype is no X client) are replaced at login (`pkill -x`), since they
  would carry the other session's environment.

## i3

- **Login.** ly is the display manager (`ly@tty1`), with its packaged config: theming was removed after a theme
  made its fields unreadable, and autologin is deliberately off. ly reads `i3.desktop` from i3-wm. Fallback from
  a tty: `startx /usr/bin/i3`; a bare `startx` runs Arch's xinitrc (twm and xclock). `xorg-server` and
  `xorg-xinit` are explicit packages because i3-wm depends on neither.
- **Config.** `i3/config` lists the `conf.d/` modules. `~/.config/i3` is a real directory with each file linked;
  `conf.d/04-monitors.conf` is a per-host copy of `i3/templates/04-monitors.conf` (the xrandr layout, examples
  only), and `conf.d/06-services.conf` is written per host by `opt/services` scripts.
- **i3 traps.** The first of two identical `bindsym`s wins and there is no unbind, so never bind a chord twice.
  `i3 -C` validates the file but not the command body of a `bindsym`. After a `;`, each command needs its own
  `exec`. `exec` runs its command through `/bin/sh -c`. Separate `exec` and `exec_always` lines run
  concurrently.
- **Display and wallpaper.** The resolution and layout come from the host's `04-monitors.conf`.
  `bin/x11-display` (`x11-monitor` pins 1920x1080 in a VM, autorandr on bare metal) still exists, but its
  `exec_always` line is commented out. The wallpaper is `x11-wallpaper watch` (plain `exec`): it paints at login
  and repaints whenever the monitor layout changes. That matters because feh paints a root pixmap of the
  screen's size at that moment, and one painted before `04-monitors.conf`'s xrandr finishes is tiled across the
  grown screen. `$mod+Shift+r` reloads i3 and reshuffles the wallpaper, and `$mod+Ctrl+w` picks the next.
- **VM.** `vm/x11-autoresize` (vm profile only) follows the host window: with a virtio GPU, QEMU reports the
  window size as the monitor's preferred mode and nothing applies it. The script listens for i3's `output` IPC
  event and runs `xrandr --auto`; the wallpaper watcher repaints after it. `spice-vdagent` does the clipboard
  only, and its daemon accepts agents only from the active login session.
- **Session environment** (`shell/xprofile` -> `~/.xprofile`): `~/.local/bin` on PATH, the telemetry opt-outs,
  `QT_QPA_PLATFORMTHEME=gtk3`, `Xft.dpi: 96` (same font size on every panel), `TERMINAL` published as the
  `i3wm.terminal` resource (`set_from_resource $terminal`, alacritty when unset), and `:GNOME` appended to
  `XDG_CURRENT_DESKTOP`. That last one is needed because the GTK portal backend declares `UseIn=gnome`, and
  without it qutebrowser and sandboxed apps read light mode. Check the portal with `busctl --user call
  org.freedesktop.portal.Desktop /org/freedesktop/portal/desktop org.freedesktop.portal.Settings ReadOne ss
  org.gnome.desktop.interface color-scheme`.
- **Desktop tools.** Each script's header has the details.
  - CopyQ history in rofi (`x11-clipboard`; image thumbnails in `$XDG_RUNTIME_DIR`, never on disk).
  - Screenshots with maim, annotated in satty (Enter copies through xclip).
  - Locking: `x11-idle init` runs `xss-lock --transfer-sleep-lock` (so `x11-lock` execs `i3lock --nofork`); with
    no xss-lock (vm profile) it turns the screensaver and DPMS off instead.
  - Idle inhibit (`x11-idle toggle`): a logind `idle:sleep` inhibitor, not `shutdown`, which would block the
    power menu's poweroff; shown as a dzen2 pill on the bar.
  - Nightlight: one-shot `gammastep -O`, no daemon.
  - `x11-focus` warps the pointer only when the focus moved.
  - The power menu leaves out lock and suspend where they cannot work.
  - `blueman-applet` starts only with an adapter.
  - No compositor, by choice.

## Theming

`bin/x11-theme` applies Omarchy themes to the i3 stack, with Omarchy's formats and paths
(`~/.config/omarchy/themes/`, rendered into `~/.local/state/omarchy/current/theme/`), so any Omarchy theme repo
and Omarchy-style hooks work. Under Hyprland it refuses every command that changes something, except
`from-dux`.

- **Engine.** `theme/` mirrors Omarchy's layout, so `OMARCHY_PATH=theme/` runs the vendored
  `omarchy-theme-color` and `omarchy-theme-set-templates` **unmodified** (`theme/VENDORED.md`). A switch renders
  each `theme/default/themed/*.tpl` (and `~/.config/omarchy/themed/*.tpl`) that the theme does not ship itself.
  Three templates are links to their app's directory (i3status-rust, satty, Vesktop). The template script
  returns 1 for themes with a `shell.*.toml` but no `shell.toml`; that is ignored, and success is checked by
  `i3.conf` and `gtk.css` existing.
- **Untrusted themes** (a `.git`, or the `.x11-theme-source` mark) are staged without following symlinks, and
  without their Lua, terminal configs or `vscode.json`, which run code or name programs.
- **A theme must always be applied**: i3 includes the rendered `i3.conf`, and i3bar runs the rendered status
  config. The first install clones `r3b1s/omarchy-pinkrot-theme`, falling back to the built-in
  `theme/themes/pinkrot/colors.toml`; later runs do `x11-theme update` (fast-forward only).
- **Commands:** `install <git-url>`, `install-omarchy [name|--list|--all]` (a sparse clone of `omacom/omarchy`,
  branch `quattro`, theme names read from the repo), `set`, `refresh`, `update`, `list`, `current`, `remove`,
  `menu`, `add-wallpaper`, `apply-chromium`, `from-dux`. Wallpapers come from the theme's `backgrounds/` plus
  `~/.config/omarchy/backgrounds/<theme>/`, with `~/.config/wallpapers/` as the fallback. The rofi grids use
  thumbnails cached by `bin/x11-thumb`.
- **What follows the theme:**

  | App | Mechanism | Takes effect |
  | --- | --- | --- |
  | i3, i3bar | `i3.conf.tpl` -> `$th_*` variables | `i3-msg reload` |
  | i3status-rust | `i3status-rust/config.toml.tpl` | SIGUSR2 |
  | rofi, dunst, tmux | rendered file imported by the app's config (dunst: a `dunstrc.d/` drop-in) | next open / `dunstctl reload` / `source-file` |
  | alacritty, kitty, btop | Omarchy's templates, through the colour slots | config touch / SIGUSR1 / SIGUSR2 |
  | GTK3, GTK4, Qt, ZAP | `gtk.css.tpl` -> `~/.config/gtk-{3,4}.0/gtk.css` | app restart |
  | Firefox | `firefox.userChrome.css.tpl`, `firefox.userContent.css.tpl` linked into each profile's `chrome/` | next start |
  | Chromium, Brave Origin | `BrowserThemeColor` policy through the root helper | policy re-read |
  | qutebrowser | `omarchy_theme.py` reads `colors.toml` | `:config-source` |
  | Neovim | `neovim.lua.tpl` (aether.nvim), the `theme.lua` slot | hot reload |
  | yazi, zathura, imv, mpv, satty, lock screen | rendered config or template | next start |
  | CopyQ | `copyq.ini.tpl` into the `[Theme]` section of `copyq.conf` | restarted automatically |
  | Vesktop, Obsidian | `hooks/theme-set.d/*` (each enables its theme only while the app is closed) | live / next start |
  | light/dark | `mode` -> dconf `color-scheme`, adw-gtk3 vs adw-gtk3-dark | app restart |

- **GTK has no settings daemon here**, so it ignores dconf for its theme and icons. `setup_gtk()` writes
  `~/.config/gtk-{3,4}.0/settings.ini` (`adw-gtk3-dark` for GTK3, `Adwaita` for GTK4, the icon theme). Never
  name `Adwaita-dark`: it is no GTK3 theme, and GTK silently falls back to *light* Adwaita. adw-gtk3 takes
  libadwaita's named colours, so one `gtk.css` recolours GTK3 and GTK4; it also defines GTK3's legacy
  `theme_*` names, which Qt reads through the gtk3 platform theme.
- **The generated `x11-theme` icon theme** inherits the theme's `icons.theme` (Yaru-*, from chaotic-aur) and
  recolours the tray's symbolic icons to the foreground: nm-applet's (also under their non-symbolic names,
  which it asks for), CopyQ's and blueman's. The VPN lock becomes a half-size accent badge. Vesktop's tray icon
  is a PNG in `~/.config/vesktop/userAssets/`.
- **Chromium needs root, narrowly.** `setup_theme_helper()` copies `theme/root/chromium-theme-color` to
  `/usr/local/lib/cachy-dots/` and allows exactly that path through `/etc/sudoers.d/cachy-dots-theme`. The
  helper takes one `#rrggbb` and writes `color.json` under `/etc/chromium/policies/managed/`, and under
  `/etc/brave/` only when `/usr/bin/brave-origin` exists.
- **ZAP** (`bin/zaproxy`) runs with Java's GTK look and feel, minus the `GNOME` token in
  `XDG_CURRENT_DESKTOP`: Java refuses GTK whenever that names GNOME. Its splash screen cannot be themed.
- Running GTK apps keep their colours until restarted.

## Apps

- **Firefox** is configured by `/etc/firefox/policies/policies.json` (`setup_firefox()`). The policy installs
  Vimium from AMO at the first start (needs network), uninstalls the Flame theme that earlier versions
  installed, makes Brave the default search (alias `b`), activates the default theme, and enables
  `toolkit.legacyUserProfileCustomizations.stylesheets` for the theme's userChrome. Vimium's options cannot be
  set by policy (they live in extension storage): import `firefox/vimium-options.json` once through its options
  page.
- **Chromium**: `chromium/policies/managed/brave-search.json` makes Brave the default search; only the managed
  level can.
- **qutebrowser** (`qutebrowser-git`, chaotic-aur only): `config.py` sources `omarchy_theme.py` and `vimium.py`,
  which ports `firefox/vimium-options.json`. Vimium's `scrollPageDown`/`Up` move half a page; `b` and the
  required `DEFAULT` are Brave. `startpage.html` shows the wallpaper under a dark overlay that deepens towards
  the edges.
- **Default apps** (`setup_default_apps()`, `xdg-mime`): qutebrowser, nautilus, zathura, imv, mpv. The browser
  picked in `bin/default-browser menu` is recorded in `~/.config/cachy-dots/default-browser` and kept on re-runs.
- **Neovim** is a LazyVim tree, linked file by file so `lazy-lock.json`, Mason and the like stay out of the repo.
  `lua/plugins/theme.lua` is a session slot (the aether.nvim render under i3, `hypr/nvim-theme.lua` under
  Hyprland), applied live by `omarchy-theme-hotreload.lua`. `lua/config/clipboard.lua` uses xclip, plus OSC 52
  under tmux or SSH. Markdown code fences stay visible. `colors/pinkrot.lua` is only what lazy shows while
  installing.
- **Voxtype** (push-to-talk, `$mod+d` -> `bin/dictate toggle`): `voxtype/config.toml` is linked, and `voxtype setup
  model` edits it in place. The daemon is started by each session, not `voxtype.service`, which hangs off
  `graphical-session.target`. Output is `mode = "clipboard"`; `post_output_command` (`dictate paste`) copies to
  PRIMARY and sends Shift+Insert. The built-in hotkey is off, so the `input` group is not needed.
- **Shell.** A managed `~/.bashrc` block sources `shell/init.sh`: PATH, telemetry, then `aliases` and
  `integrations` (mise with `set +h`, so bash does not cache paths ahead of its shims; starship wraps an existing
  `PROMPT_COMMAND`; zoxide, fzf). Definitions are guarded by `command -v`. ble.sh is opt-in (`opt/blesh.sh`) and
  loaded first when installed; test it in a real terminal, since it does not load under `bash -c`.
- **Telemetry opt-outs** (`env/telemetry.conf`) use the strict `KEY=VALUE` subset that both environment.d and
  `sh` accept, because three readers share the file: systemd --user (linked into `environment.d`), `~/.xprofile`
  and `shell/init.sh`.

## Optional: `opt/` and `podman-services/`

Nothing here runs from `install.sh`. [opt/AGENTS.md](opt/AGENTS.md) lists every script.

- `opt/hyprland.sh` and `opt/dux-settings.sh`: the Hyprland session (above).
- `opt/omarchy-repo.sh` adds Omarchy's repo, and `opt/omarchy-retroarch.sh` sets RetroArch up as Omarchy does.
  RetroArch's settings are applied once (`--reconfigure` re-applies them), and it needs a Vulkan driver
  (`vulkan-swrast` in a VM).
- `opt/virt.sh` sets up libvirt's `qemu:///system` with the `labbr0` NAT network (10.40.40.0/24) and the
  `default` storage pool; `qemu:///session` needs no setup. The `libvirt` group is root-equivalent. `opt/lab-firewall.sh` adds the ufw rules `labbr0` needs, and only while ufw is
  active; re-run it after enabling ufw.
- `opt/arch-cloud-vm.sh` and `opt/arch-cloud-vm-dots.sh` make test VMs (see "Testing").
- `opt/services/` (kanata, paseo, sunshine, rakazo) and `opt/install-from-source/` (ArtCraft) have their own AGENTS.md.
- `podman-services/syncthing/install.sh`: a rootless Syncthing Quadlet bound to the host's NetBird address.

## Testing

- **Test VMs.** `opt/arch-cloud-vm.sh` makes a vanilla Arch VM from an arch-boxes cloud image (no display;
  `--nopasswd` lets it be driven over ssh). `opt/arch-cloud-vm-dots.sh` adds a SPICE display, then clones the repo
  and runs `./install_vm.sh` at first boot (log in `/var/log/dots-provision.log`). `dots-test` has a clean
  snapshot: `virsh -c qemu:///system snapshot-revert dots-test provisioned`. Hyprland was tested on `arch0`.
- **Copy the repo with `rsync -a --delete`**, not tar: a stale `conf.d` file left behind loads and overrides.
- **ufw rate-limits port 22** (6 connections in 30 s): use one multiplexed ssh connection.
- **Test GUI apps under the session's environment** (`/proc/$(pgrep -xo i3)/environ`), not an ssh shell's.
  Start test agents with `i3-msg exec`: the vdagent ignores processes outside the active session.
- **A graphical session without typing a password**, as ly starts one: `systemd-run -p PAMName=login -p
  TTYPath=/dev/tty2 -p StandardInput=tty-force --uid=<user> /etc/ly/setup.sh /usr/bin/start-hyprland`, after
  `chvt 2`. Keys go in with `virsh send-key`, and `virsh screenshot` captures the screen.
- **Not verified on a live system:** the `opt/lab-firewall.sh` rules against a running ufw, kanata's unit
  hardening, `opt/dux-settings.sh` on a fresh host, where the idle-inhibit pill lands on screen, and the
  login wallpaper watcher (`x11-wallpaper watch`).
