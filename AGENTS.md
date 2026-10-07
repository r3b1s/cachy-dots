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
| Lock, nightlight | `cachyos/i3lock-color` + `xss-lock`, `gammastep` |
| Bluetooth | `blueman`, `bluez`, `bluez-utils` (`bluetooth.service` enabled) |
| Files, build | `nautilus` + `gvfs`, `yazi` (+ previewers: `7zip`, `poppler`, `ffmpegthumbnailer`, `resvg`, `imagemagick`, `fd`, `ripgrep`), `base-devel` |
| Theming | `adw-gtk-theme` (adw-gtk3), `chaotic-aur/yaru-icon-theme`; see "Theming" |
| Pinned to one repo | `chaotic-aur/qutebrowser-git`, `cachyos/yay`, `cachyos/i3lock-color`, `chaotic-aur/yaru-icon-theme` |

Notes on particular entries:

- **`qutebrowser-git` is chaotic-aur only**, with no fallback. `install.sh` checks
  `pacman -Si chaotic-aur/qutebrowser-git`, and if that fails it warns, finishes the rest, and exits
  non-zero rather than substituting extra's `qutebrowser`. If a conflicting `qutebrowser` is installed it is
  removed first.
- **`yay` comes from Cachy's own `[cachyos]` repo**, installed by its qualified name `cachyos/yay` so pacman
  cannot take chaotic-aur's build. Same rules: no fallback, warn, finish, exit non-zero. An already-installed
  `yay` is left alone. (`[cachyos]` also has `paru`.)
- **Package source priority:** a Cachy repo, then the official Arch repos, then chaotic-aur, and never the
  plain AUR when chaotic-aur has the package. `i3lock-color` is in Cachy's own `[cachyos]` repo, so it is
  pinned there (on vanilla Arch it would be `chaotic-aur/i3lock-color`). It conflicts with `extra/i3lock`,
  which is removed first, like `qutebrowser` for `qutebrowser-git`.
- **No `fish` or `xonsh`.** CachyOS itself ships fish as the default login shell; it stays installed, but
  nothing here configures it (see "Shell").
- **`nix` is installed, nothing more.** `install.sh` enables `nix-daemon.socket` and adds the user to
  `nix-users` when that group exists. No channels, no flakes config: project-specific environments only.
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
`ly/pinkrot.ini` into that system file, keeping the packaged original at `/etc/ly/config.ini.cachy-orig` and
always re-merging from it, so repeat runs are idempotent. A `pacman -Syu` that upgrades ly restores the
packaged file (or leaves a `.pacnew`); re-run the installer to put the theme back.
Autologin is deliberately not enabled: log in interactively.

`xorg-xinit` and `xorg-xauth` are still installed, so `startx /usr/bin/i3` works from a tty as a fallback
when ly will not come up. Do not run a bare `startx` without naming i3: Arch's
`/etc/X11/xinit/xinitrc` falls back to `twm` and `xclock`.

`i3-wm` does not depend on `xorg-server`, which is why the X packages are in the list explicitly.

The display is SPICE (virt-manager's graphical console), paired with `spice-vdagent` for clipboard and
resize; the test VM's GPU is virtio (`Virtio 1.0 GPU`, `/dev/dri/card1`), driven by xorg-server's built-in
`modesetting` driver. `spice-vdagentd.socket` and `qemu-guest-agent` are static units that udev starts when
their virtio ports appear, so `enable_services()` only starts the socket (no reboot needed) and enables nothing.

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

- `Extensions.Install` fetches two add-ons from AMO at Firefox's first start, so that run needs network:
  Vimium (`vimium-ff`, id `{d7742d87-e61d-4b78-b8a1-b469842139fa}`) and the Flame theme
  (`nova_flame`, id `nova-flame@mozilla.org`, requires Firefox 153+). Both ids were read out of the XPIs
  rather than guessed.
- `SearchEngines` adds Brave (`https://search.brave.com/search?q={searchTerms}`, alias `b`) and sets
  `Default` to it, so search.brave.com is the default engine on a fresh profile.
- `Preferences` sets `extensions.activeThemeID` to the theme's id, which is what actually *activates* it;
  installing a theme does not select it. It is set with status `default`, not `locked`, so the theme is
  active on a fresh profile but can still be changed in the UI. If a later build ever resets it, `locked`
  forces it.

## Chromium

`setup_chromium()` in `install.sh` installs `chromium/policies/managed/brave-search.json` to
`/etc/chromium/policies/managed/`. Managed (not recommended/) is the only level that sets a default
engine: it locks Brave (`https://search.brave.com/search?q={searchTerms}`) as `DefaultSearchProvider`.
The built-in "Rose" theme has no policy equivalent, so `seed_chromium_rose()` seeds
`browser.theme.color_scheme = 2` into `~/.config/chromium/Default/Preferences` only when no theme choice
exists yet, never overwriting a user-picked theme. Takes effect on next launch.

## sshd

Different from athena-dots, where sshd must stay disabled: CachyOS enables sshd, and on a headless VM it is
the way in, so `setup_sshd()` leaves the service's state alone. It first ensures the `athena0` ed25519 key is
in `~/.ssh/authorized_keys` (700/600), then installs `ssh/sshd_config.d/10-cachy-safe.conf` to
`/etc/ssh/sshd_config.d/` (pubkey yes, passwords/interactive no, root no). When that file changed it is
validated with `sshd -t` (and removed again if rejected) and a running sshd is reloaded, so **password SSH
logins stop working after the first install**: have a key in `authorized_keys` before running it. The drop-in
wins because Arch's `sshd_config` Includes `sshd_config.d/*.conf` at its top and sshd keeps the first value.

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

## Neovim

`nvim/` is a LazyVim tree ported from the Omarchy host (`init.lua`, `lua/config/lazy.lua`,
`lua/config/options.lua`, `lua/config/keymaps.lua`, `lua/config/autocmds.lua`), minus Omarchy theming:
`theme.lua`, `all-themes.lua` and `omarchy-theme-hotreload.lua` were dropped, and `pinkrot-theme.lua`
selects the `pinkrot` colourscheme instead. Portable keeps: `snacks-animated-scrolling-off.lua`,
`disable-news-alert.lua`. `link_nvim_tree()` links each file individually so runtime state
(`lazyvim.json`, `lazy-lock.json`, `:Mason`, spell, shada) stays out of the repo.

Deltas from the Omarchy source: `lua/config/options.lua` adds `vim.opt.wrap = true`;
`lua/config/clipboard.lua` replaces `remote_clipboard.lua`'s Wayland path (`wl-copy`/`wl-paste`) with X11
(`xclip`, already a dependency) while keeping the OSC 52 emit under tmux/SSH; `Visual` is high-contrast
(`#f17e97` on `#050007`) instead of the low-contrast `#24101a` wash.

One trap in the colours file itself: it set `vim.g.colors_name` before `highlight clear`, and that command
resets `g:colors_name`, so it read back as nil even though the colours applied. The assignment now comes
after, and `:colorscheme` reports `pinkrot` again.

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
- `install.sh` checks the Cachy repos, adds chaotic-aur, installs missing packages (pacman), switches the
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
  pinkrot colours are `nvim/`, `ly/pinkrot.ini` (see "Starting i3") and `satty/config.toml`'s palette.
- Default terminal is alacritty (`set $terminal` in `i3/config`). Kitty stays installed and follows the
  theme, but nothing in the config launches it and its remote-control socket is off.
- `install.sh` links whole dirs for i3, kitty, alacritty, rofi, shell; individual files for dunst (`dunstrc`;
  the theme drop-in goes beside it in `dunstrc.d/`), qutebrowser (`config.py`, `omarchy_theme.py`,
  `vimium.py`, `startpage.html`), btop, nvim (full LazyVim tree via
  `link_nvim_tree()`), tmux (`tmux/tmux.conf` -> `~/.config/tmux/tmux.conf`), satty
  (`satty/config.toml`), the telemetry opt-outs (`env/telemetry.conf` -> `~/.config/environment.d/`), chromium policy
  (`chromium/policies/managed/*.json` -> `/etc/chromium/policies/managed/`) and `starship/starship.toml` ->
  `~/.config/starship.toml` (those apps write runtime state next to their config). `shell/xprofile` is
  linked separately to `~/.xprofile`, which is outside `~/.config`; `bin/*` goes to `~/.local/bin`; the sshd
  drop-in goes to `/etc/ssh/sshd_config.d/`. The ly theme is merged
  into `/etc/ly/config.ini` instead
  of linked, and the GTK icon theme is generated into `~/.local/share/icons/`.
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
  `xss-lock --transfer-sleep-lock` locks before suspend, holding suspend until the locker is up (which is why
  `x11-lock` execs `i3lock --nofork`), and when the X screensaver fires: `xset s 600 600`, 10 idle minutes.
- **Nightlight.** `bin/x11-nightlight` (`$mod+Ctrl+n`) toggles `gammastep -m randr -O 4000` (one-shot: it sets
  the gamma ramps and exits, X keeps them, so no daemon runs). `NIGHTLIGHT_TEMP` changes the warmth. The
  virtio GPU on the test VM supports gamma ramps (`xrandr --verbose` shows `Gamma: 1.0:1.3:1.6` when on).
- **Bluetooth.** `blueman-manager` is in rofi's drun list; `blueman-applet` starts only when
  `/sys/class/bluetooth` has an adapter. `bluetooth.service` is enabled; its unit is conditioned on the same
  directory, so on a VM it is enabled but never starts.
- **File managers:** nautilus on `$mod+e`, yazi in a terminal on `$mod+Shift+e`. yazi's image previews in
  alacritty would need `ueberzugpp`; not installed.
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
  `set`, `refresh` (re-render after editing a template), `list`, `current`, `remove`, and `menu` (rofi,
  each row iconed with the theme's `preview.png`; `$mod+Ctrl+t`). `$mod+Ctrl+w` cycles the theme's
  backgrounds.
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
  `x11-theme refresh`. A theme must always be applied: i3 includes `i3.conf` and i3bar runs the rendered
  status config from the state directory (i3 only warns about a missing include; i3status-rs shows an error).
- **What follows the theme, and how:**

  | App | Mechanism | Live? |
  | --- | --- | --- |
  | i3 windows, i3bar | `i3.conf.tpl` -> `$th_*` vars, included by `i3/config`; `01-colors.conf`, `15-bar.conf` | `i3-msg reload` |
  | i3status-rust | `i3status-rust/config.toml.tpl` is itself a template (linked into `theme/default/themed/`); each block is a hue mixed into the background, stronger from idle to critical | SIGUSR2 (in-place restart) |
  | rofi | `rofi.rasi.tpl`, `@import`ed by `rofi/config.rasi` | next open |
  | dunst | `dunst.conf.tpl` -> `~/.config/dunst/dunstrc.d/90-theme.conf` drop-in | `dunstctl reload` |
  | alacritty, kitty, btop | omarchy's own templates; alacritty `import`, kitty `include`, btop `themes/current.theme` link | touch config / SIGUSR1 / SIGUSR2 |
  | qutebrowser | `qutebrowser/omarchy_theme.py` (from quattro-dots) reads `colors.toml` | `:config-source` |
  | GTK3, GTK4, Firefox, virt-manager, Qt | `gtk.css.tpl` -> `~/.config/gtk-{3,4}.0/gtk.css` (see below) | app restart |
  | icons | generated `x11-theme` icon theme inherits the theme's `icons.theme` (Yaru-red ...) | app restart |
  | Chromium | `BrowserThemeColor` policy from the theme's `chromium.theme` | Chromium re-reads policy |
  | wallpaper | the theme's `backgrounds/` (+ `~/.config/omarchy/backgrounds/<theme>/`) | immediate |
  | lock screen | `bin/x11-lock` reads `colors.toml` | next lock |
  | light/dark | `mode` -> dconf `color-scheme`, adw-gtk3 vs adw-gtk3-dark, `prefer-dark` | app restart |

- **GTK, Firefox and Qt from one file.** GTK3 uses **adw-gtk3** (`adw-gtk-theme`), which draws GTK3 like
  libadwaita and takes the same named colours, so one `gtk.css` with `@define-color window_bg_color` & co.
  recolours GTK4/libadwaita (nautilus) and GTK3 (virt-manager, verified with gtk3-widget-factory) alike.
  Firefox's **default ("system") theme follows GTK3**, so the policy now activates `default-theme@mozilla.org`
  instead of Flame (still installed, selectable). Qt reads its palette from GTK3 through qt6-base's gtk3
  platform theme (`QT_QPA_PLATFORMTHEME=gtk3` in `shell/xprofile`); for that the CSS also defines GTK3's
  legacy `theme_*` names, without which Qt's selection stayed GTK's blue.
- **Chromium needs root, narrowly.** The policy lives in root-owned `/etc/chromium/policies/managed/`.
  `setup_theme_helper()` copies `theme/root/chromium-theme-color` to `/usr/local/lib/cachy-dots/` (root:root
  755, never a link into the repo) and adds `/etc/sudoers.d/cachy-dots-theme`, validated with `visudo -c`,
  allowing exactly that path without a password. The helper accepts one `#rrggbb` and writes only
  `color.json` (`BrowserThemeColor` + `BrowserColorScheme: device`); this is what omarchy does too.
- **Not themed yet:** Neovim (omarchy's template needs the `aether.nvim` plugin), ly (a root file; still
  `ly/pinkrot.ini`), satty's palette, CopyQ's own item list, tmux, yazi, starship. Running GTK apps keep their
  colours until restarted (no settings daemon to signal them).
- **Testing on the VM**: sync with `rsync -a --delete`, not tar. A stale `01-pinkrot.conf` left behind by a
  tar copy loaded after `01-colors.conf` and kept the old window colours.
