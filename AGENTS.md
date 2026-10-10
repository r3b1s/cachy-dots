These dotfiles set up a custom i3 desktop on a headless [CachyOS](https://cachyos.org/) VM (qemu/kvm/libvirt).
They are a port of `athena-dots` (the AthenaOS version), kept as a separate repo for now.

CachyOS is downstream of Arch and has all the official Arch repos. On top of them it adds its own repos,
rebuilt for newer CPUs: `cachyos-v3`/`-v4`/`-znver4`, `cachyos-core-*`, `cachyos-extra-*` and the
architecture-independent `cachyos`. A Cachy repo is preferred for every package that has one.

Never test the scripts on the AthenaOS machine this repo is edited on; the test host is a separate Cachy VM.

## Repos

- **Packages are named plainly in `install.sh`, never as `cachyos-extra-v3/foo`.** The CachyOS installer
  writes its repos *above* `[core]`/`[extra]` in `/etc/pacman.conf`, so pacman already prefers the Cachy
  build whenever one exists. Which level (v3, v4, znver4) that is depends on the CPU, so hard-coding one would
  break on other hardware. `check_cachy_repos()` only verifies the ordering (via `pacman-conf --repo-list`)
  and warns; it never rewrites the repo section. On the test VM nearly everything resolves to
  `cachyos-extra-v3`/`cachyos-core-v3`; the rest (`autotiling`, `rofimoji`, `starship`, `obsidian`,
  `ttf-jetbrains-mono-nerd`, …) has no Cachy build and comes from `extra`. When a dependency has several
  providers, `--noconfirm` takes provider 1, which pacman lists in repo order, so the Cachy one.
- **chaotic-aur is added for `qutebrowser-git` only** (and `blesh-git` if opted in, see "Shell"). No Cachy
  repo builds `qutebrowser-git`. `setup_chaotic_aur()` follows the chaotic-aur docs (key, then
  `chaotic-keyring` + `chaotic-mirrorlist` from its CDN) and appends `[chaotic-aur]` at the **end** of
  `pacman.conf`, below the Cachy and Arch repos, so it can never shadow their builds. A freshly added repo has
  no sync database, and the only supported way to get one is a full `pacman -Syu`, so that is what runs (a
  bare `-Sy` followed by `-S` would be a partial upgrade). It only runs when `chaotic-aur.db` is missing.
- **Cachy can lag Arch on a Qt minor, which breaks Qt apps.** Qt modules link against `qt6-base`'s
  *private* API, versioned per release (`Qt_6_PRIVATE_API`, `QtPrivate_6_11_2`), so every module must be on
  `qt6-base`'s minor; pacman cannot enforce it because the dependencies are unversioned. When Arch moves to a
  new Qt minor, Cachy rebuilds piecemeal and the mix breaks. Both directions were hit on 2026-10-07:
  qutebrowser died (``version `Qt_6.12' not found``) because extra's `python-pyqt6` (no Cachy build) was built
  for 6.12 while `cachyos-extra-v3` still had `qt6-base` 6.11.2; hours later Cachy had `qt6-base` 6.12 but
  `qt6-svg` 6.11.2, so CopyQ died (`undefined symbol ... QtPrivate_6_11_2`) on a pure-Cachy install.
  `sync_qt_stack()` runs after every install: the newest `qt6-base` wins whichever repo it is in, and every
  installed `qt6-*` module below its minor is taken from `extra` when extra has it at that minor. Modules extra
  itself ships older (`qt6-webengine` trails `qt6-base` by design) are left alone. It heals itself: Cachy
  versions a rebuild as Arch's pkgrel plus `.1` (`6.12.0-1` -> `6.12.0-1.1`), so the next `-Syu` after Cachy
  catches up moves each module back. A Qt app installed by hand in that window can still pull a stale module
  from Cachy; re-running `./install.sh --packages-only` fixes it.
- **Every pacman transaction is also a snapper snapshot pair** (`cachyos-snapper-support`, the
  `==> root: N` lines in pacman's output). The installer therefore batches: one `-U` for the chaotic
  packages, the `-Syu`, then a single `-S` for everything else, including the two pinned packages.

## packages

`install.sh` is the source of truth; this is what it installs, and why.

| Area | Packages |
| --- | --- |
| Window manager and layout | `i3-wm`, `i3status-rust` (bar), `autotiling` |
| Launcher, notifications | `rofi`, `rofimoji` (emoji picker, `$mod+Ctrl+e`), `dunst`, `libnotify` |
| Terminals, editor, monitors | `alacritty` (default), `kitty`, `neovim`, `btop` |
| Browsers | `chromium`, `qutebrowser-git`, `firefox` |
| X and the session | `xorg-server`, `xorg-xinit`, `xorg-xauth`, `xorg-xrandr`, `ly` |
| Shell and prompt | `starship`, `eza`, `zoxide`, `fzf`, `bat`, `bash-completion` |
| Terminal multiplexer | `tmux` (config in `tmux/`) |
| Sync and notes | `rclone`, `obsidian` |
| Clipboard, screenshots | `copyq` (history, `bin/x11-clipboard`), `satty` (annotation), `maim`, `xclip` |
| Lock, nightlight | `i3lock-color` (`cachyos/`, else `chaotic-aur/`) + `xss-lock` + `xorg-xset` (the idle timer), `gammastep` |
| Bluetooth | `blueman`, `bluez`, `bluez-utils` (`bluetooth.service` enabled) |
| Files, build | `nautilus` + `gvfs`, `yazi` (+ previewers: `7zip`, `poppler`, `ffmpegthumbnailer`, `resvg`, `imagemagick`, `fd`, `ripgrep`), `base-devel` |
| Theming | `adw-gtk-theme` (adw-gtk3), `chaotic-aur/yaru-icon-theme`; see "Theming" |
| Pentest | `zaproxy` (themed via `bin/zaproxy`) |
| Dictation | `aur/voxtype-bin` (see "Voxtype"), `xdotool` (pastes the transcript, and warps the pointer for `bin/x11-focus`) |
| Pinned (see `PINNED` in `install.sh`) | `chaotic-aur/qutebrowser-git` and `chaotic-aur/yaru-icon-theme` (one repo each); `yay`, `i3lock-color` and `vesktop` (`cachyos/` first, then `chaotic-aur/`) |

Notes on particular entries:

- **The AUR is used for exactly one package, `voxtype-bin`** (`AUR_PKGS` in `install.sh`, built by `yay`, which
  is pinned from Cachy or chaotic-aur). `install_aur()` takes it from a pacman repo when one has it (so a
  later chaotic-aur or Cachy build wins), and only otherwise runs `yay` as the invoking user (makepkg
  refuses root). The AUR package is maintained by voxtype's authors; its two signing keys (`validpgpkeys`
  in the PKGBUILD) are imported best effort first. `brave-origin-bin` is the other AUR/Cachy package, but it
  is installed on demand by `bin/x11-default-browser`, not by `install.sh`.
- **`qutebrowser-git` is chaotic-aur only**, with no fallback. `install.sh` checks
  `pacman -Si chaotic-aur/qutebrowser-git`, and if that fails it warns, finishes the rest, and exits
  non-zero rather than substituting extra's `qutebrowser`. If a conflicting `qutebrowser` is installed it is
  removed first.
- **`yay` comes from Cachy's own `[cachyos]` repo** when it is there, else `chaotic-aur/yay` (vanilla Arch).
  Each pin is installed by its qualified name, so pacman cannot take another repo's build. If no listed repo
  has it, the run warns, finishes the rest, and exits non-zero. An already-installed `yay` is left alone.
  (`[cachyos]` also has `paru`.)
- **Package source priority:** a Cachy repo, then the official Arch repos, then chaotic-aur, and never the
  plain AUR when chaotic-aur has the package. `i3lock-color` is `cachyos/i3lock-color`, else
  `chaotic-aur/i3lock-color`. It conflicts with `extra/i3lock`, which is removed first, like `qutebrowser` for
  `qutebrowser-git` (`PINNED_REPLACES` in `install.sh` lists these pairs).
- **Vanilla Arch was tested** on a nested VM (`opt/arch-cloud-vm.sh`, the latest arch-boxes image): the
  installer runs there, the pins fall back to chaotic-aur, and the i3 session starts on Xvfb with the bar,
  wallpaper and theme switching working. A full upgrade can install a new kernel whose modules the running
  kernel no longer has: until a reboot, ufw cannot load its rules, so `setup_firewall` warns instead of
  stopping, and the run ends with a "reboot needed" warning.
- **No `fish` or `xonsh`.** CachyOS itself ships fish as the default login shell; it stays installed, but
  nothing here configures it (see "Shell").
- **`nix` is for project-specific environments** (`nix-shell`, `nix develop`). `enable_nix()` in `install.sh`
  enables `nix-daemon.socket` **and** `nix-daemon.service` (so the daemon is up at boot, not only on demand),
  adds the user to `nix-users` when that group exists, and keeps one managed `# >>> cachy-dots >>>` block at
  the end of `/etc/nix/nix.conf`: `extra-experimental-features = nix-command flakes` and
  `extra-trusted-users = <user>`. The `extra-` forms append to whatever the packaged file or a hand edit sets
  instead of replacing it (checked with `nix config show` on nix 2.35); the block is rewritten on re-runs, the
  rest of the file is never touched, and a running daemon is restarted when the block changed. No channels.
- **`libnotify` is load-bearing**, not a convenience: `dunst` lists it as an optdep for `dunstify`, and every
  OSD in `bin/` calls `dunstify`.
- **`xorg-server` and `xorg-xinit` are explicit** because `i3-wm` does not depend on either. They are what
  `startx` needs, and what `ly` runs against.
- **`chromium`** is installed alongside `qutebrowser-git` because both follow the system colour scheme.
- **`firefox`** is configured by enterprise policy, not by copying profile files; see below.
- **`ttf-jetbrains-mono-nerd`** is the font named by kitty, alacritty, i3, ly and the bar.

## Starting i3

The VM has no desktop environment. `ly` is the display manager: install.sh enables `ly@tty1.service`, and
at boot you get a login prompt on the virtual console. Pick `i3` as the session; it comes from i3-wm's
`/usr/share/xsessions/i3.desktop`, which ly reads, so no extra session file is needed.

ly reads exactly one config file, `/etc/ly/config.ini`. The path is compiled into it and there is **no**
`~/.config/ly/config.ini` fallback, so a per-user config does nothing. `install_ly_theme()` therefore merges
`ly/overlay.ini` (non-colour settings) into that system file, keeping the packaged original at
`/etc/ly/config.ini.cachy-orig` and always re-merging from it, so repeat runs are idempotent; it then runs
`x11-theme apply-ly` to put the theme's colours back. The colours follow the theme: x11-theme renders
`ly.ini.tpl` and writes its keys through the root helper `ly-theme-colors` (see "Theming"); ly shows them at
its next start. A `pacman -Syu` that upgrades ly restores the packaged file (or leaves a `.pacnew`); re-run
the installer to put the overlay and colours back.
Autologin is deliberately not enabled: log in interactively.

`xorg-xinit` and `xorg-xauth` are still installed, so `startx /usr/bin/i3` works from a tty as a fallback
when ly will not come up. Do not run a bare `startx` without naming i3: Arch's
`/etc/X11/xinit/xinitrc` falls back to `twm` and `xclock`.

`i3-wm` does not depend on `xorg-server`, which is why the X packages are in the list explicitly.

The display is SPICE (virt-manager's graphical console), paired with `spice-vdagent` for the clipboard
(not for resize, see below); the test VM's GPU is virtio (`Virtio 1.0 GPU`, `/dev/dri/card1`), driven by xorg-server's built-in
`modesetting` driver. `spice-vdagentd.socket` and `qemu-guest-agent` are static units that udev starts when
their virtio ports appear, so `enable_services()` only starts the socket (no reboot needed) and enables nothing.

**Resizing with the host window** is done by `vm/x11-autoresize` (plain `exec` in `05-autostart.conf`),
not by spice-vdagent. With a virtio GPU and no QXL, QEMU reports the host window size as the monitor's
*preferred mode* (EDID); `xrandr` lists it with a `+`, and the vdagent never receives a monitors-config message
(checked with `spice-vdagentd -d -d` while the clipboard worked in both directions, on 2026-10-10). Xorg lists
the new mode but nothing switches to it, which is why a fresh login came up at the right size and a live resize
did nothing. The script subscribes to i3's IPC `output` event (`i3-msg -t subscribe -m '["output"]'`, fired on
every such change, so no polling and no extra package), waits for 0.4 s of quiet, runs `xrandr --output X
--auto` unless the used mode is already the preferred one, then repaints the wallpaper with
`x11-wallpaper current`. The "already in place" check is what stops the event raised by the switch itself
from looping. It restarts its subscription after an i3 restart. A debugging trap: the daemon only opens the
virtio port for an agent in the *active login session*, so an agent started over ssh is ignored
(`Session for pid N: 16` against `Active session: c4`); start test agents with `i3-msg exec`.
Tested on a live VM by resizing the virt-viewer window.
It is **vm profile only**: `install_links` links `vm/*` into `~/.local/bin` only when `want vm-scripts`, which the
workstation profile turns off (`PROFILE_SKIP_FEATURES`), and the i3 line is
`sh -c 'command -v x11-autoresize >/dev/null && exec x11-autoresize'`, so it does nothing where the script is
absent (the repo's usual `command -v` idiom; an `include` of a missing file would warn instead).

The resolution is pinned to 1920x1080 by `bin/x11-monitor`, run from `05-autostart.conf`'s `exec_always`.
A headless VM otherwise comes up at whatever size the last SPICE client asked for. If the GPU offers
1080p already, the script just selects it; otherwise it adds a CEA 1080p60 modeline first. Passing another
size, e.g. `$bin/x11-monitor 2560x1440`, works only if the output already lists that mode.

Nothing more than the resolution: the script selects the mode and rate, and does nothing else. Earlier
versions also switched off extra and stale outputs, forced `--pos 0x0` and resized the framebuffer, chasing a
wallpaper that appeared to tile. None of that was the cause and some of it made it worse.

The actual cause: `05-autostart.conf` ran `x11-monitor` and `x11-wallpaper` as **two** `exec_always` lines,
which i3 starts concurrently. feh painted while the GPU was still at its preferred mode, 1280x800, leaving a
1280x800 root pixmap; `x11-monitor` then switched to 1920x1080, and X tiled that stale pixmap across the
larger root window. On the VM the left and right halves of the screen matched to within 0.00/255 after
painting at 1280x800 and growing to 1920x1080, and differed by 8.80 once the two were run in sequence. They
are now one line, sequenced with `&&` in an explicit `sh -c`, because i3's `exec` does not use a shell.

`bin/x11-wallpaper` is a plain `feh --bg-fill`, with no `--bg-size` and no root-window reset.

## Firefox

`setup_firefox()` in `install.sh` installs `firefox/policies.json` to
`/etc/firefox/policies/policies.json`, the documented system-wide location on Linux. The install-directory
alternative under `/usr/lib/firefox/distribution` is read too, but a package upgrade would clobber it.

The policy does three things:

- `Extensions.Install` fetches Vimium (`vimium-ff`, id `{d7742d87-e61d-4b78-b8a1-b469842139fa}`, read out
  of the XPI) from AMO at Firefox's first start, so that run needs network. `Extensions.Uninstall` removes
  the Flame theme (`nova-flame@mozilla.org`) that earlier versions of the policy installed: the frame is
  themed from the palette by userChrome.css now, so Flame was dead weight.
- `SearchEngines` adds Brave (`https://search.brave.com/search?q={searchTerms}`, alias `b`) and sets
  `Default` to it, so search.brave.com is the default engine on a fresh profile.
- `Preferences` sets `extensions.activeThemeID` to `default-theme@mozilla.org` (status `default`, so it can
  still be changed in the UI), and `toolkit.legacyUserProfileCustomizations.stylesheets`, without which
  Firefox ignores userChrome.css and userContent.css.

## Chromium

`setup_chromium()` in `install.sh` installs `chromium/policies/managed/brave-search.json` to
`/etc/chromium/policies/managed/`. Managed (not recommended/) is the only level that sets a default
engine: it locks Brave (`https://search.brave.com/search?q={searchTerms}`) as `DefaultSearchProvider`.
The built-in "Rose" theme has no policy equivalent, so `seed_chromium_rose()` seeds
`browser.theme.color_scheme = 2` into `~/.config/chromium/Default/Preferences` only when no theme choice
exists yet, never overwriting a user-picked theme. Takes effect on next launch.

## sshd

`install.sh` does not touch sshd: it neither enables nor configures it, and it never writes `authorized_keys`.
CachyOS may already run it, and on the arch-boxes cloud image it is enabled, but neither is the repo's doing.
The hardening drop-in, `ssh/sshd_config.d/10-cachy-safe.conf` (pubkey only, no passwords or interactive
login, no root), is opt-in: copy it to `/etc/ssh/sshd_config.d/` yourself. Put your key in
`~/.ssh/authorized_keys` first, because the drop-in turns password logins off. Arch's `sshd_config` Includes
`sshd_config.d/*.conf` at its top and sshd keeps the first value, so the drop-in overrides the main file.

**Vimium's options cannot be installed by policy.** Its settings live in the extension's own browser
storage, and the only import path is the Restore control on `chrome-extension://<id>/options.html`. No
Firefox policy can write extension storage, and the profile's IndexedDB cannot be authored from outside.
`install.sh` therefore copies `firefox/vimium-options.json` to `~/.config/firefox/vimium-options.json` for a
one-time manual import. See "qutebrowser" below for the same settings applied where they can be scripted.

## qutebrowser

`qutebrowser/config.py` sources `omarchy_theme.py` (colours from the active theme; see "Theming") and
`vimium.py` (Vimium parity). `vimium.py` is
generated from `firefox/vimium-options.json` and carries the Vimium shortcuts and search keywords in
qutebrowser's syntax: `config.bind()` instead of `map` lines, and a dict with a `{}` placeholder instead of
`keyword: URL` lines with `%s`.

Three things were checked in Vimium's source rather than assumed:

- `scrollPageDown`/`scrollPageUp` move by **half** a viewport, not a whole one, so they map to
  `scroll-page 0 0.5` / `-0.5`.
- All four mappings already coincide with qutebrowser's defaults (`J`/`K` are `tab-next`/`tab-prev`), so
  those binds pin existing behaviour rather than change it.
- A duplicate keyword resolves to the **last** definition, because Vimium assigns into an object while
  parsing. The options file defined `b` twice, for Brave and then Bing, so `b` was Bing.

Two things were resolved in the source options file rather than worked around here. The duplicate `b` line
for Bing is gone, leaving Brave as `b` in both browsers, and `mb` now uses `%s` rather than `%st`, which had
been appending a literal `t` to every query (`mb foo` searched for `foot`). Bing is therefore no longer
available under `b`; add it under its own keyword if wanted.

qutebrowser requires a `DEFAULT` search engine and the options file has none, so `DEFAULT` is Brave, the
same URL as `b`.

`startpage.html` shows the desktop wallpaper (`../wallpapers/current`) under a dark overlay: the whole image
is dimmed (35% black at the centre) and darkens towards the edges (88% at the corners), so the page cannot be
mistaken for the desktop it shares its image with. (It used to be a vignette over an undimmed centre.)

## Voxtype

Push-to-talk dictation. `voxtype/config.toml` is quattro-dots' config ported from Hyprland to X11, linked to
`~/.config/voxtype/config.toml` (`voxtype setup model` edits it in place, so changes land in the repo).

- **Install:** `aur/voxtype-bin` (see "packages"), then `voxtype setup --download` fetches the `base.en`
  model the config names, once (`setup_voxtype()`; needs network, a failure only warns).
- **Daemon:** `exec voxtype -q daemon` from `05-autostart.conf`, guarded by `command -v`. The packaged
  `voxtype.service` is wanted by `graphical-session.target`, which a bare i3 session never reaches.
- **Toggle:** `$mod+d` -> `bin/x11-voxtype toggle` (`voxtype record toggle`, plus a dunst notification
  in place of omarchy-osd); the `sup_d` workspace that used to hold `$mod+d` is gone. The built-in hotkey is off, as in
  quattro-dots, so the `input` group is not needed.
- **Output:** `mode = "clipboard"` (voxtype's chain is wl-copy, then xclip, so on X11 it is xclip). Its
  `post_output_command` is `bin/x11-voxtype paste`: copy CLIPBOARD to PRIMARY too (alacritty's Shift+Insert
  pastes PRIMARY, GTK's pastes CLIPBOARD), then `xdotool key --clearmodifiers shift+Insert`. quattro-dots'
  Hyprland submap that swallowed the keyboard while text was typed has no port; `--clearmodifiers` covers a
  still-held `$mod`.
- **Not tested on a live session** when it was written: voxtype was not installed on the machine the repo was
  edited on. The output driver chain was read from voxtype's `src/output/mod.rs`, not run.

## Neovim

`nvim/` is a LazyVim tree ported from the Omarchy host (`init.lua`, `lua/config/lazy.lua`,
`lua/config/options.lua`, `lua/config/keymaps.lua`, `lua/config/autocmds.lua`). Theming works as on
omarchy: `lua/plugins/theme.lua` is a link (made by install.sh, not in the repo) to the rendered
`~/.local/state/omarchy/current/theme/neovim.lua`, omarchy's template for `aether.nvim` (v3) filled with the
active palette, and `omarchy-theme-hotreload.lua` (from quattro-dots) re-applies it in running instances when
lazy.nvim's change detection sees the link's target replaced (its notification is turned off in
`lazy.lua`). `colors/pinkrot.lua` is kept only as the colourscheme lazy shows while installing. Verified
headless: `colors_name` is `aether` and Normal's background is the theme's. Portable keeps: `snacks-animated-scrolling-off.lua`,
`disable-news-alert.lua`. `link_nvim_tree()` links each file individually so runtime state
(`lazyvim.json`, `lazy-lock.json`, `:Mason`, spell, shada) stays out of the repo.

Deltas from the Omarchy source: `lua/config/options.lua` adds `vim.opt.wrap = true`;
`lua/config/clipboard.lua` replaces `remote_clipboard.lua`'s Wayland path (`wl-copy`/`wl-paste`) with X11
(`xclip`, already a dependency) while keeping the OSC 52 emit under tmux/SSH; `Visual` is high-contrast
(`#f17e97` on `#050007`) instead of the low-contrast `#24101a` wash.

One trap in the colours file itself: it set `vim.g.colors_name` before `highlight clear`, and that command
resets `g:colors_name`, so it read back as nil even though the colours applied. The assignment now comes
after, and `:colorscheme` reports `pinkrot` again.

## Installer layout and profiles

`install.sh` and `install_vm.sh` are thin entry scripts: each names its profile (`PROFILE=workstation|vm`),
sources `install/lib.sh`, and runs `parse_args` and `install_main`. The functions that used to be one file
now live in `install/`, by purpose (the function names, and the `install.sh` references in this file, are
unchanged; read them as "in `install/`"):

| Module | Holds |
| --- | --- |
| `common.sh` | `say`/`warn`/`run`, `SUDO`, `TARGET_USER`, `FAILED`, `as_user`, `parse_args`, profile handling (`want`, `apply_profile`) |
| `packages.sh` | `PKGS`, `PINNED`, `PINNED_REPLACES`, `AUR_PKGS`, the guest-agent packages |
| `repos.sh` | `check_cachy_repos`, `setup_chaotic_aur` |
| `pacman.sh` | `install_packages`, `install_aur`, `sync_qt_stack` |
| `system.sh` | login shell, ly overlay, nix, services, firewall, touchpad, keyring check, `validate_i3` |
| `browsers.sh` | Firefox and Chromium policies, `setup_default_apps` |
| `theme.sh` | root helpers, GTK, dark mode, `setup_theme` |
| `links.sh` | `link`, `install_links`, the bashrc block, the nvim tree |
| `voxtype.sh` | the speech model |
| `flow.sh` | `install_main`: the steps in order, and `record_profile` |
| `profile-<name>.sh` | what a profile leaves out |

The split was checked to change nothing for the workstation: sourcing the old single file and the new
modules gave identical function bodies and package arrays (`declare -f`/`declare -p` diff, apart from the new
helpers and `main` becoming `install_main`).

**Profiles.** The lists in `packages.sh` stay complete; `apply_profile()` removes what the profile names:
`PROFILE_SKIP_PKGS`, `PROFILE_SKIP_PINNED` (by package name, either repo's), `PROFILE_SKIP_AUR`, and
`PROFILE_SKIP_FEATURES` (checked with `want <feature>`; today `touchpad`, and `vm-scripts`, which the workstation skips: `vm/*` is linked only by the vm profile). Steps whose package is gone
skip themselves, since each is guarded by `pacman -Qq` or `command -v` (the Firefox and Chromium policies,
bluetooth, power-profiles-daemon, nix, voxtype). The workstation skips only `vm-scripts` and still adds the guest agents
only when `systemd-detect-virt` says VM. The **vm** profile (`install_vm.sh`, `install/profile-vm.sh`, the only
place its list is kept) forces the guest agents and leaves out: rclone,
`xss-lock` and `i3lock-color` (no locker, see below),
blueman/bluez/bluez-utils, brightnessctl, power-profiles-daemon, gammastep, autorandr/arandr,
tesseract-data-eng, vesktop, voxtype-bin, and the touchpad config. Firefox, Chromium, Obsidian, ZAP, nix and
yay stay in (their policies, the nix.conf block and the daemon are set up as on the workstation). That list is a first guess; edit the
file. Each run writes the profile to `~/.config/cachy-dots/profile`, and `sync.sh` reads it (or `PROFILE=`),
so a VM is synced as a VM.

**A guest never sleeps.** The vm profile sets `PROFILE_NO_SLEEP=1`, which runs `setup_no_sleep()` (install and
`sync.sh`): `systemd/10-cachy-dots-awake.conf` into `/etc/systemd/logind.conf.d/` (`IdleAction=ignore`, lid and
suspend/hibernate keys ignored; the power key is left alone; read at logind's next start, so after a reboot),
`sleep`, `suspend`, `hibernate`, `hybrid-sleep` and `suspend-then-hibernate` targets masked, and
`xorg/20-no-blanking.conf` into `/etc/X11/xorg.conf.d/` (`BlankTime`, `StandbyTime`, `SuspendTime`, `OffTime` all 0).
With no locker either, nothing but a person ends the i3 session. ly autologin is still not enabled, so a reboot
lands at the login prompt. A VM installed before this still has `xss-lock`; the step warns and names the
`pacman -Rns` that removes it (removing packages is not its job).

**VM scripts.** `opt/arch-cloud-vm.sh` makes the bare cloud-image VM (no display); its fork
`opt/arch-cloud-vm-dots.sh` adds a SPICE display and installs the dots. The shared steps (checks, verified
image, overlay, key and password, seed, domain, report) live in `opt/arch-cloud-vm-lib.sh`, which both source;
a script sets its defaults, parses its own flags, hands the rest to `acv_option`, and runs `acv_check`,
`acv_image`, `acv_credentials`, `acv_seed`, `acv_domain`, `acv_report`. The fork injects extra cloud-config
(`ACV_USERDATA_EXTRA`) and extra devices (`ACV_DEVICES_EXTRA`) through two variables. Both take `--ssh-key PUBKEY`
(a `.pub` path or the key itself) to put that key in `authorized_keys` instead of generating
`~/.ssh/arch-cloud-<name>-ed25519`; it is validated with `ssh-keygen -l` before anything is created. The fork's
display is a virtio GPU with the vdagent and guest-agent channels and a USB tablet; its cloud-init first-boot job
(`/usr/local/sbin/dots-provision`, log `/var/log/dots-provision.log`, exit status
`/var/lib/dots-provision.status`) runs `pacman -Syu git`, clones this repo into `~/Dotfiles/cachy-dots` and runs
`./install_vm.sh` as the user, with sudo passwordless only until it finishes. **Run end to end** on 2026-10-10
(`--name dots-vm-test --ssh-key <pub>`): the clone and install ran, the status file read 1 only because of the
known ufw/reboot warning (cloud-init therefore reports `error`), and after a reboot `ly@tty1` was active,
`i3 -C` passed, the sudoers drop-in was gone, and `/dev/virtio-ports` had both channels. `virsh domdisplay` says
"No graphical display found" because the SPICE listen is `none` (virt-manager connects over its socket).

**Tested** on a fresh Arch cloud-image VM, `dots-test`, made with
`opt/arch-cloud-vm.sh --name dots-test --user arch --memory 6144 --vcpus 4 --disk 30G --nopasswd`
(`--nopasswd` is cloud-init's `NOPASSWD:ALL`, so the VM can be driven over ssh; there is no one to type a
password). Its libvirt snapshot `provisioned` (internal, taken shut off, right after cloud-init finished)
is the clean state: `virsh -c qemu:///system snapshot-revert dots-test provisioned`, start it, copy the repo
over (`tar` through ssh: the image has no rsync) and run the installer. Results: `install_vm.sh` completes on
vanilla Arch (it exits 1 only for the known ufw warning, since the upgraded kernel's modules are not loaded
until a reboot); after the reboot `ly@tty1` is active and `i3 -C` passes; none of the skipped packages (as the list stood then, which also skipped firefox, chromium, obsidian,
zaproxy and nix) is installed (tesseract itself still comes in as a dependency of zathura's mupdf); `sync.sh` follows the
recorded profile; and `install.sh -n` on the same VM plans exactly the packages the vm profile left out.
The test also found that vanilla Arch has no `git`, which `x11-theme install` needs: it is now in `PKGS`.
One more fix from it: `setup_firewall`'s final `ufw status | sed` was unguarded and, under `pipefail`, ended the
whole run when ufw could not start.

## Layout and install

- `i3/` — `config` + numbered `conf.d/` modules (see header of `i3/config`).
- One top-level dir per app (`kitty/`, `alacritty/`, `rofi/`, `dunst/`, `starship/`, …), plus `shell/` (bash integration), `bin/` (helper scripts → `~/.local/bin`).
- Wallpapers come from the active theme's `backgrounds/` plus `~/.config/omarchy/backgrounds/<theme>/` (yours,
  as on omarchy); `~/.config/wallpapers/` is only the fallback when a theme has none. `bin/x11-wallpaper`
  picks a random one on every i3 start and reload, `next` cycles (`$mod+Ctrl+w`), and it keeps
  `~/.local/state/omarchy/current/background` and `~/.config/wallpapers/current` (qutebrowser's startpage)
  pointing at the image.
- `$mod+Shift+r` reloads i3 and then re-runs the wallpaper. Both halves need their own `exec`: i3 treats
  everything after a `;` as a new command, so a bare `$bin/x11-wallpaper` is rejected at runtime with
  "Expected one of these tokens: ... 'exec' ...". Note `i3 -C` validates the config file but **not** the
  command body of a `bindsym`, so it accepts that mistake silently and the bind does nothing.
- `install.sh` checks the Cachy repos, adds chaotic-aur, refreshes the package databases with a full `pacman -Syu` when anything is missing, installs the missing packages (pacman; a failure is retried once after another sync, then reported without stopping the run), switches the
  login shell to bash, starts `spice-vdagentd.socket`, symlinks the dots, then validates with `i3 -C`. It is
  the source of truth for the package list; keep it in sync with this file.
- GTK ignores `org.gnome.desktop.interface` for the theme and icon theme: it reads XSETTINGS, which needs a
  settings daemon, and there is none in a bare i3 session. `setup_gtk()` in `install.sh` therefore writes
  `~/.config/gtk-{3,4}.0/settings.ini` with `gtk-theme-name` (`adw-gtk3-dark` for GTK3, `Adwaita` for GTK4),
  `gtk-application-prefer-dark-theme=1` and icon theme `x11-theme`; x11-theme flips the variant and
  prefer-dark for light themes. Two traps, both verified on the VM. First, never name `Adwaita-dark`: it is
  not a real GTK3 theme, and naming it makes GTK fall back to **light** Adwaita without complaint (menu
  background `#F6F5F4` versus `#353535`). Second, the `icon-theme` dconf key is ignored here too, so the icon
  theme has to be named in settings.ini.
- The `x11-theme` icon theme in `~/.local/share/icons/` is generated by `x11-theme` on every switch: it
  inherits the theme's `icons.theme` (Yaru-*), and carries the package's symbolic NetworkManager icons
  recoloured to the theme foreground. nm-applet asks for the plain (non-`-symbolic`) names, so each is
  written under both, which is what replaces its pastel hardware glyph in the i3bar tray. The glyph renders at
  the 0.35 opacity baked into Adwaita's SVG, so it is dimmer than the bar text.
- System dark mode: `setup_dark_theme()` in `install.sh` sets dconf `color-scheme=prefer-dark` and
  `gtk-theme=adw-gtk3-dark`, and (with a `DISPLAY`) restarts the `xdg-desktop-portal{,-gtk}` user services, which are
  static, D-Bus-activated units with nothing to enable. Those exist for the things
  that ask a portal rather than reading settings themselves, which is sandboxed apps and Qt6 (qutebrowser).
  GTK's own dark mode does **not** come from here: see the settings.ini bullet above. The portal backend is
  gated on `XDG_CURRENT_DESKTOP`, exported from `shell/xprofile` (-> `~/.xprofile`) because i3 has no
  `set_environment` directive. The GTK backend's descriptor, `portals/gtk.portal`, declares `UseIn=gnome`,
  which is why that variable names GNOME at all. Check it with
  `busctl --user call org.freedesktop.portal.Desktop /org/freedesktop/portal/desktop
  org.freedesktop.portal.Settings ReadOne ss org.gnome.desktop.interface color-scheme`, which should answer
  `"prefer-dark"`. Over ssh on Cachy the systemd user instance provides a session bus, so the dconf half
  still runs; the GTK portal backend cannot start without a display, so it is left to start on demand in the
  i3 session. With no session bus at all (a bare tty), the dconf half is skipped with instructions.
- Guest is qemu/kvm/libvirt today, but the dots now also carry what bare metal needs (lock, nightlight,
  bluetooth; see "Desktop tools"). Still no picom, brightness or screen recording.
- Colours come from the active theme for almost everything (see "Theming"); the exceptions with static
  pinkrot colours are gone: starship uses only named ANSI colours, so it follows the terminal's palette,
  which the theme sets.
- Default terminal is alacritty (`set $terminal` in `i3/config`). Kitty stays installed and follows the
  theme, but nothing in the config launches it and its remote-control socket is off.
- `install.sh` links whole dirs for i3, kitty, alacritty, rofi, shell; individual files for dunst (`dunstrc`;
  the theme drop-in goes beside it in `dunstrc.d/`), qutebrowser (`config.py`, `omarchy_theme.py`,
  `vimium.py`, `startpage.html`), btop, nvim (full LazyVim tree via
  `link_nvim_tree()`), tmux (`tmux/tmux.conf` -> `~/.config/tmux/tmux.conf`), satty
  (`satty/config.toml`), voxtype (`voxtype/config.toml`), the telemetry opt-outs (`env/telemetry.conf` -> `~/.config/environment.d/`), chromium policy
  (`chromium/policies/managed/*.json` -> `/etc/chromium/policies/managed/`) and `starship/starship.toml` ->
  `~/.config/starship.toml` (those apps write runtime state next to their config). `shell/xprofile` is
  linked separately to `~/.xprofile`, which is outside `~/.config`; `bin/*` goes to `~/.local/bin`. The ly theme is merged
  into `/etc/ly/config.ini` instead
  of linked, and the GTK icon theme is generated into `~/.local/share/icons/`.
- **`sync.sh`** (repo root) brings an installed system up to date after a `git pull` or an edit, without
  installing anything, enabling a service or touching the network: it sources `install/lib.sh` for the functions
  (nothing runs on sourcing; `link()` stays silent for links that are already right), takes the profile from
  `~/.config/cachy-dots/profile`, and runs `install_links` (new links, repointed ones, backups of real files in the way), removes links
  into the repo whose file is gone, `setup_gtk`, the root copies that only write when they differ
  (`setup_theme_helper`, `install_ly_theme`, `setup_firefox`, `setup_chromium`, `setup_touchpad`, the nix.conf
  block, which restarts `nix-daemon.service` only if it changed), `x11-theme refresh`, `setup_default_apps`
  and `i3 -C`, then lists packages the repo wants that are missing and points at `install.sh`. Flags: `-n`,
  `--no-root` (skip the `/etc` and `/usr/local` copies, no sudo), `--themes` (`x11-theme update`, which pulls).
  New things that `install.sh` does beyond these (services, firewall, voxtype model, AUR builds) stay its job.
- See "Shell" below for `shell/` and the login shell.
- mise is activated in `shell/integrations` (with `set +h`, or bash caches binary paths ahead of the
  shims). No global or project mise config is managed by this repo; put one in `mise/config.toml` if wanted.
- `root/` holds dots for the root user and has its own `root/install.sh` (`sudo ./root/install.sh`).
  It is opt-in: the top-level `install.sh` never runs it. It COPIES (never symlinks) into `/root`, since
  root must not read user-writable files, and backs up differing existing files. Its `appendrc` carries the
  same eza/zoxide/fzf aliases plus root-only extras (`wipehist`, `compress`, ssh port forwards `fip`/`dip`/`lip`).

## Shell

- **The login shell is switched to bash.** CachyOS makes fish the login shell, and every integration in
  `shell/` is bash-only, so alacritty would start fish and never load them. `setup_login_shell()` runs
  `sudo chsh -s /bin/bash <user>` when the passwd entry says otherwise (as root, chsh does not prompt). fish
  itself stays installed; it is Cachy's package (`cachyos-fish-config`), not ours.
- `shell/` is sourced by a managed `# >>> cachy-dots >>>` block appended to `~/.bashrc` (idempotent, bash
  only), after Cachy's stock PS1, which starship replaces. `init.sh` puts `~/.local/bin` on PATH (Cachy's
  stock `~/.bashrc` does not; `shell/xprofile` does the same for the i3 session), then sources `aliases`
  (eza, zoxide `cd`/`zd`, fzf `ff`/`eff`/`sff`, `..`/`...`/`....`) and `integrations` (mise activation,
  bash-completion, starship, zoxide, fzf key bindings). Definitions are guarded by `command -v`, so a missing
  tool silently disables its aliases. starship wraps an existing scalar `PROMPT_COMMAND` (mise's hook) in
  `STARSHIP_PROMPT_COMMAND` and runs it from `starship_precmd`, so mise still fires.
- **ble.sh is opt-in.** `install.sh` neither installs it nor links `~/.blerc`. `opt/blesh.sh` installs
  `chaotic-aur/blesh-git` (run `install.sh` first; it adds chaotic-aur) and links `shell/blerc` to
  `~/.blerc`; `opt/blesh.sh --remove` undoes both. `shell/init.sh` sources `/usr/share/blesh/ble.sh` first
  whenever it is installed, as the AthenaOS image's `~/.bashrc` did, so starship then registers through
  `blehook`. ble.sh does not load under `bash -c` or without a tty, so test it in a real terminal. `blerc`
  turns off the vi-mode `-- INSERT --` indicator with the deferred `bleopt keymap_vi_mode_show:=` form, since
  `~/.blerc` is sourced before the option is declared.

## Desktop tools

These were left out while the dots only targeted disposable VMs; they are for daily use on bare metal.

- **Clipboard history: CopyQ, driven from rofi.** `05-autostart.conf` starts `copyq` (it keeps the history
  and a tray icon). `bin/x11-clipboard history` (`$mod+Ctrl+v`) lists the history in rofi; the chosen item goes
  back on the clipboard and to the top. Image items get a thumbnail as their rofi row icon: CopyQ's script
  writes each to `$XDG_RUNTIME_DIR/x11-clipboard/<index>.png` (tmpfs, rebuilt each time, so history images
  never land on persistent disk). Those rows are icon-tall, so the menu overrides the theme's 16 lines with 7.
  `bin/x11-clipboard wipe` (`$mod+Shift+Ctrl+Mod1+v`) clears the clipboard and primary selection first, so
  CopyQ has nothing current to re-add, then removes every item. Testing over ssh: the `xclip` helpers it
  leaves owning the selections keep an ssh session's output open, so ssh appears to hang; from i3 it does not.
- **Screenshots.** `$mod+;` is unchanged (maim region to the clipboard). `$mod+Shift+;` captures a region and
  `$mod+Ctrl+;` the whole screen into **satty** for annotation; a `for_window` rule floats it full-screen.
  `satty/config.toml`: Enter copies (via `xclip`, not satty's default `wl-copy`) and closes, Ctrl+S saves to
  `~/Pictures/Screenshots`, Escape discards; keys 1-6 pick the pinkrot palette.
- **Lock: i3lock-color + xss-lock.** `bin/x11-lock` (`$mod+Ctrl+Escape`, and "lock" in the `$mod+Escape`
  menu) runs i3lock-color blurred, with a ring and clock in the theme's colours, and refuses to stack a second locker.
  It tells you (dunst) when i3lock is not installed, and the power menu then leaves "lock" out, as it leaves out
  "suspend" when `suspend.target` is masked. `bin/x11-idle init` (plain `exec` in `05-autostart.conf`) sets
  `xset s 600 600 +dpms` and runs `xss-lock --transfer-sleep-lock` in the foreground: it locks before suspend,
  holding suspend until the locker is up (which is why `x11-lock` execs `i3lock --nofork`), and when the X
  screensaver fires, 10 idle minutes. Where `xss-lock` is not installed (the vm profile) `init` runs
  `xset s off s noblank -dpms` instead, so nothing locks and the display never blanks.
- **Idle inhibit: `$mod+Ctrl+i`** runs `bin/x11-idle toggle`. On, it switches the X screensaver and DPMS off and holds
  a logind inhibitor lock (`systemd-inhibit --what=idle:sleep --mode=block sleep infinity`, in its own session so
  its pid is also the process group to kill; the pid is in `$XDG_RUNTIME_DIR/x11-idle.pid`, which dies with the
  login session). With the screensaver off, xss-lock sees no idle event, so nothing locks; the inhibitor stops
  automatic suspend, hibernation and logind's idle action. It does **not** inhibit `handle-lid-switch` (logind
  ignores sleep inhibitors for the lid anyway), and a deliberate suspend, poweroff or lock from the power menu
  still works. A `shutdown` lock was left out on purpose: in `block` mode it would refuse the menu's own
  poweroff. Off, it restores the timers (`xset s 600 600 +dpms`, or off again without xss-lock). The cup is a
  `dzen2` pill (`-p`, orange with the background colour as text, `JetBrainsMono Nerd Font:size=11`) centred on the
  first visible i3bar, whose geometry comes from `xdotool getwindowgeometry`: i3bar draws its status line only at
  the right edge, so no i3status-rs block could sit in the middle. dzen2 windows are override-redirect, i.e.
  unmanaged by i3, so it overlays the bar's empty space; clicking it runs `x11-idle off`. It sits at the geometry
  the bar had when inhibit was switched on (toggle again after a resolution change). Checked with a stub
  `systemd-inhibit` and `xset` (the sandbox the script was written in has no system bus, X or dzen2); **the
  placement and the glyph rendering have not been seen on a screen.**
- **Nightlight.** `bin/x11-nightlight` (`$mod+Ctrl+n`) toggles `gammastep -m randr -O 4000` (one-shot: it sets
  the gamma ramps and exits, X keeps them, so no daemon runs). `NIGHTLIGHT_TEMP` changes the warmth. The
  virtio GPU on the test VM supports gamma ramps (`xrandr --verbose` shows `Gamma: 1.0:1.3:1.6` when on).
- **Bluetooth.** `blueman-manager` is in rofi's drun list; `blueman-applet` starts only when
  `/sys/class/bluetooth` has an adapter. `bluetooth.service` is enabled; its unit is conditioned on the same
  directory, so on a VM it is enabled but never starts.
- **File managers:** nautilus on `$mod+e`, yazi in a terminal on `$mod+Shift+e`. yazi's image previews in
  alacritty would need `ueberzugpp`; not installed.
- **Pointer follows focus.** `$mod+hjkl` and `$mod+arrows` run `bin/x11-focus <dir>` instead of `focus <dir>`:
  it focuses, then warps the pointer (`xdotool mousemove`) to the centre of the window that took the focus.
  Nothing moves when the focus did not change (an edge of the workspace), so the pointer is not yanked by a
  key that did nothing. Only these binds warp; focusing by mouse, workspace switches and `focus parent/child`
  do not. i3's own `mouse_warping` only warps between outputs.
- **Microphone mute.** `XF86AudioMicMute` and `$mod+Shift+m` run `x11-volume mic-mute` (`pactl
  set-source-mute @DEFAULT_SOURCE@ toggle`, with a dunst OSD). The bar has a second `sound` block with
  `device_kind = "source"` after the volume one; muted it shows the crossed-out microphone icon and "muted"
  (the level is absent while muted), live it shows the level. Right-clicking the block toggles it too.
- **Audio devices from the bar.** Left-clicking the volume block opens `pavucontrol --tab=3` (Output Devices)
  and the microphone block `pavucontrol --tab=4` (Input Devices), to pick the default device and set levels;
  the blocks keep their own right click (mute) and wheel (volume). `pavucontrol` is in `PKGS` (it was only
  installed by hand before) and its window floats. It talks to PipeWire through `pipewire-pulse`.
- **Default browser.** `$mod+Escape` -> "Default Browser" opens `bin/x11-default-browser menu`:
  qutebrowser (the default), firefox, chromium, brave-origin. `set` runs `xdg-settings` and `xdg-mime`
  for web links and HTML, and records the choice in `~/.config/cachy-dots/default-browser`, which
  `setup_default_apps()` honours so a re-run of `install.sh` does not put qutebrowser back. brave-origin is
  installed when missing: `cachyos/brave-origin-bin` when a Cachy repo has it (`pacman -Si cachyos/...`),
  else `aur/brave-origin-bin` through yay. Installing needs sudo, so from rofi (no tty) the script reopens
  itself in alacritty. `$mod+b` launches the default browser (`x11-default-browser launch`) and
  `$mod+Shift+Ctrl+b` the same in private browsing (`--target private-window`, `--private-window`,
  `--incognito`); `$mod+Shift+b`, `$mod+Ctrl+b` and `$mod+Mod1+b` launch qutebrowser, firefox and chromium
  whatever the default is. `$mod+u` (the browser workspace) is always qutebrowser.
- **Telemetry opt-outs: `env/telemetry.conf`.** One `KEY=VALUE` file (the strict subset that both
  environment.d(5) and `sh` accept), merged from quattro-dots' `shell/envs` and its environment.d file. It is
  linked to `~/.config/environment.d/telemetry.conf` for systemd --user (read when the user manager starts,
  i.e. at login), and the same path is sourced with `set -a` by `shell/xprofile` (the i3 session) and
  `shell/init.sh` (terminals). Delete a line to restore a tool's default; note `NPM_CONFIG_AUDIT=false`.

## Theming

Omarchy themes, applied to this i3 stack by `bin/x11-theme`, with omarchy's own formats and paths so any
omarchy theme repo works and omarchy-style hooks (quattro-dots' qutebrowser and vesktop ones) run unchanged.
No quickshell, nothing else from omarchy's shell.

- **Commands.** `x11-theme install <git-url>` clones a theme repo into `~/.config/omarchy/themes/<name>` and
  applies it (name rules as omarchy's: `omarchy-foo-theme` -> `foo`). `x11-theme install-omarchy [name]`
  fetches one of omarchy's built-in themes (they live inside omarchy's repo, 279 MB in all, so a blobless
  sparse shallow clone into a temp dir checks out only `themes/<name>`); with no name it lists them.
  `set`, `refresh` (re-render after editing a template), `list`, `current`, `remove`, and `menu`: the
  theme switcher, an omarchy-style rofi grid of each theme's `preview.png` (`$mod+Shift+Ctrl+space`).
  `x11-wallpaper menu` is the same grid for the current theme's backgrounds (`$mod+Ctrl+space`), and
  `$mod+Ctrl+w` cycles them. Both grids show cached 480x270 PNG thumbnails from `bin/x11-thumb`
  (`~/.cache/x11-thumb`, keyed by path and mtime): rofi decodes icons at full size, so 4K wallpapers would
  crawl, and `.webp` needs a gdk-pixbuf loader that is not installed. Those two chords displaced the rofi
  window switcher (now `$mod+Mod1+space`) and `focus mode_toggle` (now `$mod+Shift+Ctrl+Mod1+space`); the
  latter had to move in `10-core.conf`, since i3 takes the first of two identical binds.
- **Engine.** `theme/` mirrors omarchy's layout so `OMARCHY_PATH=theme/` runs omarchy's
  `omarchy-theme-color` (palette resolver: aliases, derived shades, light/dark `mode`) and
  `omarchy-theme-set-templates` (fills `{{ key }}`, `{{ key_strip }}`, `{{ key_rgb }}`,
  `{{ mix a b N% }}`) **unmodified**; provenance in `theme/VENDORED.md`. A switch stages the theme in
  `~/.local/state/omarchy/current/next-theme`, renders every `theme/default/themed/*.tpl` (and
  `~/.config/omarchy/themed/*.tpl`) that the theme does not ship itself, then swaps it in as
  `.../current/theme` and writes `theme.name`. The template script returns 1 for themes with a
  `shell.*.toml` but no `shell.toml` (tokyo-night); omarchy ignores that and so do we, checking that
  `i3.conf` and `gtk.css` were rendered instead.
- **Untrusted themes.** A theme with a `.git` (or the `.x11-theme-source` mark `install-omarchy` writes) is
  staged as omarchy stages one: no symlinks followed, and no Lua, terminal configs or `vscode.json` (they run
  code or name programs); our templates render those files instead. Your own theme directory, or a symlink to
  a working copy, is copied as is.
- **Built-in pinkrot.** `theme/themes/pinkrot/colors.toml` is the omarchy-pinkrot palette, so a theme can be
  applied offline. `install.sh` (`setup_theme`) installs the full theme from
  `r3b1s/omarchy-pinkrot-theme` on first run (backgrounds, previews) and falls back to that; later runs
  `x11-theme update`, which fast-forwards every theme installed from git (reporting, never resetting, one
  with local changes) and re-renders the current theme. So a fresh install gets whatever is pushed to that
  repo, and a re-run picks up later pushes. A theme must always be applied: i3 includes `i3.conf` and i3bar runs the rendered
  status config from the state directory (i3 only warns about a missing include; i3status-rs shows an error).
- **What follows the theme, and how:**

  | App | Mechanism | Live? |
  | --- | --- | --- |
  | i3 windows, i3bar | `i3.conf.tpl` -> `$th_*` vars, included by `i3/config`; `01-colors.conf`, `15-bar.conf` | `i3-msg reload` |
  | i3status-rust | `i3status-rust/config.toml.tpl` is itself a template (linked into `theme/default/themed/`); each block is a hue mixed into the background, stronger from idle to critical (the network block shares volume's `orange`; the battery block (sysfs, green) is hidden on machines with no battery, via `missing_format = ""`) | SIGUSR2 (in-place restart) |
  | rofi | `rofi.rasi.tpl`, `@import`ed by `rofi/config.rasi` | next open |
  | dunst | `dunst.conf.tpl` -> `~/.config/dunst/dunstrc.d/90-theme.conf` drop-in | `dunstctl reload` |
  | alacritty, kitty, btop | omarchy's own templates; alacritty `import`, kitty `include`, btop `themes/current.theme` link | touch config / SIGUSR1 / SIGUSR2 |
  | qutebrowser | `qutebrowser/omarchy_theme.py` (from quattro-dots) reads `colors.toml` | `:config-source` |
  | GTK3, GTK4, Firefox, virt-manager, Qt | `gtk.css.tpl` -> `~/.config/gtk-{3,4}.0/gtk.css` (see below) | app restart |
  | icons | generated `x11-theme` icon theme inherits the theme's `icons.theme` (Yaru-red ...) | app restart |
  | Chromium | `BrowserThemeColor` policy from the theme's `chromium.theme` | Chromium re-reads policy |
  | wallpaper | the theme's `backgrounds/` (+ `~/.config/omarchy/backgrounds/<theme>/`) | immediate |
  | lock screen | `bin/x11-lock` reads `colors.toml` | next lock |
  | Neovim | omarchy's `neovim.lua.tpl` (aether.nvim), linked as `lua/plugins/theme.lua` | hot-reload plugin |
  | tmux | `tmux.conf.tpl`, `source-file -q`'d by `tmux/tmux.conf` | `tmux source-file` |
  | yazi | omaxian's `yazi.toml.tpl` as the `omarchy` flavour (`yazi/theme.toml` selects it) | next start |
  | satty | `satty/config.toml.tpl` (palette from the theme), linked like the bar config | next start |
  | CopyQ | `copyq.ini.tpl` -> the `[Theme]` section of `copyq.conf` (stop, edit, restart) | restart (automatic) |
  | tray icons | one style: a monochrome symbolic glyph in the theme foreground, at full strength (see below) | nm-applet and CopyQ restarted automatically; Vesktop at its next start |
  | ly | `ly.ini.tpl` -> `/etc/ly/config.ini` via the `ly-theme-colors` root helper | next login screen |
  | ZAP | `bin/zaproxy` runs it with Java's GTK look and feel, i.e. through `gtk.css` | restart ZAP |
  | Vesktop | quattro-dots' `hooks/theme-set.d/vesktop` composes the rendered `quattro-vesktop.palette.css` (`vesktop/palette.css.tpl`) with `vesktop/discord.css` into `~/.config/vesktop/themes/quattro-dots.theme.css` | live (Vencord watches its themes folder) |
  | light/dark | `mode` -> dconf `color-scheme`, adw-gtk3 vs adw-gtk3-dark, `prefer-dark` | app restart |

- **GTK, Firefox and Qt from one file.** GTK3 uses **adw-gtk3** (`adw-gtk-theme`), which draws GTK3 like
  libadwaita and takes the same named colours, so one `gtk.css` with `@define-color window_bg_color` & co.
  recolours GTK4/libadwaita (nautilus) and GTK3 (virt-manager, verified with gtk3-widget-factory) alike.
  Firefox's **default ("system") theme follows GTK3**, so the policy now activates `default-theme@mozilla.org`
  (Flame is no longer installed). Qt reads its palette from GTK3 through qt6-base's gtk3
  platform theme (`QT_QPA_PLATFORMTHEME=gtk3` in `shell/xprofile`); for that the CSS also defines GTK3's
  legacy `theme_*` names, without which Qt's selection stayed GTK's blue.
- **Chromium needs root, narrowly.** The policy lives in root-owned `/etc/chromium/policies/managed/`.
  `setup_theme_helper()` copies `theme/root/chromium-theme-color` to `/usr/local/lib/cachy-dots/` (root:root
  755, never a link into the repo) and adds `/etc/sudoers.d/cachy-dots-theme`, validated with `visudo -c`,
  allowing exactly that path without a password. The helper accepts one `#rrggbb` and writes only
  `color.json` (`BrowserThemeColor` + `BrowserColorScheme: device`); this is what omarchy does too.
- **Root helpers.** Two root files follow the theme, each through its own root-owned helper COPIED to
  `/usr/local/lib/cachy-dots/` (`chromium-theme-color`, `ly-theme-colors`), with one sudoers file
  (`/etc/sudoers.d/cachy-dots-theme`, `visudo -c`'d) allowing exactly those two paths without a password.
  `ly-theme-colors` takes only ly's colour keys, each `0xAARRGGBB`, and changes nothing else.
- **ZAP.** Its `GuiBootstrap` honours `swing.defaultlaf` unless a look and feel is picked in ZAP's own
  Options > Display (which then wins). `bin/zaproxy`, ahead of `/usr/bin/zaproxy` on PATH, sets it through
  `JDK_JAVA_OPTIONS` (only that `java` launch, unlike `_JAVA_OPTIONS`) and runs `zap.sh` directly, since
  `/usr/bin/zaproxy` drops its arguments. **Java refuses the GTK look and feel ("Cannot load
  ...GTKLookAndFeel") whenever `XDG_CURRENT_DESKTOP` names GNOME**, which `~/.xprofile` appends for the
  portal; `i3:GNOME`, `GNOME` and `GNOME:i3` all fail, `i3` works. The wrapper drops the GNOME token for ZAP
  alone. An earlier test from ssh passed only because that shell lacked the variable: test GUI apps under
  the session's own environment (`/proc/$(pgrep -xo i3)/environ`).
- **Tray icons** are generated by `tint_icons`/`tint_vesktop` in x11-theme so the i3bar tray reads as one
  set. The tray (XEmbed) and Qt never apply GTK's runtime recolouring of symbolic icons, so the symbolic
  SVGs get their fixed grey (`#474747`, `#2e3436`, `#bebebe`, `#222222`) replaced by the foreground:
  nm-applet's `nm-*-symbolic` glyphs (under both names; it asks for the plain ones), lifted from their baked-in
  0.35 opacity to full except `nm-signal-*`, where the faint bars mean signal strength; CopyQ (`copyq` in the
  icon theme) is Adwaita's `edit-cut`; blueman's `blueman-tray/-active/-disabled` are Adwaita's bluetooth
  glyphs. Vesktop is Electron and hands the tray a bitmap, but it prefers
  `~/.config/vesktop/userAssets/{tray,trayUnread}` (its custom-tray-icon assets, extensionless PNGs) over
  its bundled ones: both become Adwaita's `audio-headset` glyph rendered to 64px PNG with `resvg`, the
  unread one with an accent dot. It re-reads them only at start or when the unread state changes.
- **ZAP's splash screen** keeps its white banner and blue progress bar: the banner is a bitmap in the jar
  (`/resource/zap-splash-screen.png`) and the bar is ZAP's own `SplashScreen$CustomProgressBarUI` with
  colours in code. Neither goes through the look and feel; only patching ZAP would change them.
- **Vesktop** (`cachyos/vesktop-bin`, else `chaotic-aur/vesktop`) uses quattro-dots' files verbatim:
  `vesktop/palette.css.tpl` (linked into `theme/default/themed/` as `quattro-vesktop.palette.css.tpl`, the
  name the hook expects), `vesktop/discord.css`, and `hooks/theme-set.d/vesktop`, linked into
  `~/.config/omarchy/hooks/theme-set.d/`. The hook writes the stylesheet into Vencord's themes folder (a
  write, not a link, so Vencord's directory watch fires) and adds it to `enabledThemes` only while Vesktop is
  closed, since Vencord rewrites that list from memory on exit; if it was running, enable "quattro-dots"
  under Settings > Themes once.
- **Not themed:** Firefox's toolbar beyond what GTK gives it; running GTK apps (and ZAP) keep their colours
  until restarted (no settings daemon to signal them).
- **Testing on the VM**: sync with `rsync -a --delete`, not tar. A stale `01-pinkrot.conf` left behind by a
  tar copy loaded after `01-colors.conf` and kept the old window colours.

## Desktop basics (bare metal)

- **VM-only pieces are gated on `systemd-detect-virt --vm`:** `spice-vdagent` and `qemu-guest-agent` are only
  installed (and the SPICE agent only started) inside a VM. `bin/x11-display` pins 1920x1080 with
  `x11-monitor` in a VM; on bare metal it runs `autorandr --change --default horizontal` (arrange with
  `arandr`, then `autorandr --save <name>`), then the wallpaper.
- **Default apps** (`setup_default_apps`, via `xdg-mime` into `~/.config/mimeapps.list`): qutebrowser
  (web), nautilus (folders), zathura (PDF), imv (images), mpv (media); each is themed by a template
  (`zathurarc.tpl`, `imv.config.tpl`, `mpv.conf.tpl` included from `mpv/mpv.conf`).
- **Keyring:** ly's own PAM file already unlocks gnome-keyring at login; `check_keyring_pam` only warns
  if those lines disappear. `seahorse` is the GUI.
- **Keys:** media keys via `playerctl`; backlight via `bin/x11-brightness` (brightnessctl, OSD);
  `$mod+Print` copies the text in a region (tesseract, upscaled 2x first).
- **Laptop:** `xorg/30-touchpad.conf` (tap to click, disable while typing) copied to
  `/etc/X11/xorg.conf.d/`; power profile switched from the `$mod+Escape` menu (power-profiles-daemon).
  Lid behaviour is logind's default (suspend; ignore when docked). No compositor, by choice.
- **Virtualisation is opt-in: `opt/virt.sh`**, not part of `install.sh`, so it runs on bare metal or nested
  inside a VM. It installs libvirt, qemu-desktop, virt-manager, virt-viewer, dnsmasq, edk2-ovmf and swtpm, and
  (`-n` for a dry run) sets up two connections, which virt-manager lists both of:
  - `qemu:///system`: the root daemons, socket-activated (`virtqemud`, `virtnetworkd`, `virtstoraged`). It
    defines and autostarts the NAT network `labbr0` (10.40.40.0/24, gateway 10.40.40.1, DHCP .100-.254) and the
    `default` storage pool. Access is by the `libvirt` group, which is root-equivalent: it can start any VM with
    any host device attached. Only the user running the script is added.
  - `qemu:///session`: nothing to set up. libvirt starts the user's own daemon on demand, with no root and no
    group. Its guests get user-mode networking only: no raw packets, no ICMP, and the host reaches a guest only
    through port forwards. That rules out CTF work that needs raw packets or routing through `tun0`.
  The packaged `unix_sock_group` is commented out, which leaves the sockets root-only, so the script sets it for
  the three daemons. The default network is deliberately left undefined; `labbr0` is the lab network. The
  firewall is libvirt's nftables backend (pinned in `/etc/libvirt/network.conf`) for the NAT, plus ufw rules from
  `opt/lab-firewall.sh`, **only while ufw is active**: a packet must be accepted by every base chain on its hook
  and ufw's drop wins over libvirt's own tables, which is why ufw rules are needed at all. The script is sourced
  by `virt.sh` and `arch-cloud-vm.sh` and runs on its own (`-n` to dry-run). Input: DHCP (67/udp, any
  destination, as it is a broadcast) and DNS (53 to 10.40.40.1) in on `labbr0`; nothing else from a guest
  reaches the host. Forward, only when `/etc/default/ufw` has `DEFAULT_FORWARD_POLICY="DROP"`: `labbr0` -> `tun0`
  (HTB/THM VPN) allowed first, then RFC1918, link-local and 100.64/10 (CGNAT, Tailscale) denied, then
  `labbr0` -> anywhere else allowed, so the lab reaches the internet and the VPN but not the LAN; nothing outside
  can start a connection to a guest (host to guest works: it is OUTPUT). The old unrestricted
  `route allow in/out on labbr0` rules are deleted. ufw stores its rules in `/etc/ufw/*.rules` and they name the
  interface, so they survive reboot and `ufw reload`; if ufw was off when the script ran, run it again. The
  earlier version of this section was checked on the VM with a network namespace on `labbr0`; **these rules were
  written without a ufw to run them against** (ufw needs root), so run `opt/lab-firewall.sh -n` first and test
  from a guest. ICMP is no test of FORWARD: ufw's default rules accept echo-request there. `qemu-full` depends on
  `qemu-desktop` and does not conflict with it, so the script installs whichever is already there.
- **Firewall:** `setup_firewall` keeps ufw at deny-incoming/allow-outgoing, enabled, allowing SSH first
  when sshd is enabled (rate-limited if it adds the rule). Open a port for CTF listeners by hand.
- **Obsidian:** `hooks/theme-set.d/obsidian` (from omarchy) writes the rendered `obsidian.css` into every
  vault as the "Omarchy" theme, and selects it only while Obsidian is closed. A new vault gets it on the
  next `x11-theme refresh`.
- **Firefox** is themed fully from the palette, not through GTK (its system theme did not follow GTK
  reliably): `firefox.userChrome.css.tpl` (frame, tabs, address bar, panels, accents) and
  `firefox.userContent.css.tpl` (only `about:` pages), linked into each profile's `chrome/` and
  `@import`ed by its userChrome/userContent.css; the policy sets
  `toolkit.legacyUserProfileCustomizations.stylesheets`. Applies at Firefox's next start.

