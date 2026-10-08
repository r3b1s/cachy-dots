#!/usr/bin/env bash
# cachy-dots installer for CachyOS (Arch-based).
#
#   1. checks the CachyOS repos, adds chaotic-aur (for qutebrowser-git only)
#   2. installs any missing packages (pacman; sudo is used when not root)
#   3. enables the guest-agent services, makes bash the login shell
#   4. symlinks the dots into ~/.config and ~/.local/bin
#   5. validates the i3 config
#
# Safe to re-run: installed packages are skipped, existing non-symlink targets
# are backed up, existing symlinks are replaced.
#
# Usage: ./install.sh [--packages-only | --links-only] [-n|--dry-run]
set -euo pipefail

REPO=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)

do_packages=1
do_links=1
dry=0
for arg in "$@"; do
    case "$arg" in
        --packages-only) do_links=0 ;;
        --links-only)    do_packages=0 ;;
        -n|--dry-run)    dry=1 ;;
        -h|--help)       sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

say()  { printf '\033[1;34m::\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
run()  { if [ "$dry" = 1 ]; then echo "+ $*"; else "$@"; fi; }

SUDO=
[ "$(id -u)" -ne 0 ] && SUDO=sudo

# The user the dots are for: the invoking user even under sudo.
TARGET_USER="${SUDO_USER:-${USER:-$(id -un)}}"

# ── packages ──────────────────────────────────────────────────────────────

# Packages are named plainly, never as cachyos-extra-v3/foo: CachyOS lists its
# optimised repos (cachyos-v3/-v4/-znver4, cachyos-core-*, cachyos-extra-*,
# cachyos) above core/extra in pacman.conf, so pacman already takes the Cachy
# build whenever one exists, and which of v3/v4/znver4 that is depends on the
# CPU the installer picked. Hard-coding a level would break on other hardware.
# check_cachy_repos() verifies that ordering; see AGENTS.md, "Repos".

# Core stack (see AGENTS.md).
PKGS=(
    i3-wm i3status-rust autotiling   # window manager, bar, auto-split
    rofi dunst kitty neovim btop     # launcher, notifications, terminal, editor, monitor
    alacritty                        # default terminal ($terminal in i3/config)
    chromium                         # browser that follows the system colour scheme
    firefox                          # second browser; themed and preconfigured by policy
    mise nix                         # package / language managers

    # i3-wm depends on neither of these. See AGENTS.md, "Starting i3".
    xorg-server                     # the X server itself
    xorg-xinit                      # startx / xinit
    xorg-xrandr                     # monitor size, set by bin/x11-monitor
    xorg-xauth                      # X authentication (ly and startx)
    ly                              # display manager; runs i3 (see AGENTS.md)
)

# What the config calls at runtime.
PKGS+=(
    jq                               # x11-ws-app
    eza zoxide fzf bat               # shell integrations (shell/); bat previews fzf's ff
    bash-completion
    maim xclip xcolor                # screenshots, clipboard, colour picker
    feh                              # wallpaper, set by bin/x11-wallpaper
    numlockx
    libnotify                        # dunstify links against it (dunst's optdep); the OSDs use it
    curl                             # fetches the seeded wallpaper
    rofimoji                         # emoji picker, bound in i3/conf.d/30-apps.conf

    # System-wide dark mode. There is no desktop here, so dconf is the system
    # theme: GTK4/libadwaita read it directly, and the portal reads it for
    # everything sandboxed (see setup_dark_theme).
    gsettings-desktop-schemas        # without this the color-scheme key does not exist
    dconf                            # the store gsettings writes to
    xdg-desktop-portal               # org.freedesktop.portal.Settings
    xdg-desktop-portal-gtk           # its backend; the one that implements Settings
    adwaita-icon-theme               # the base icon theme pinkrot inherits from
    pipewire-pulse                   # pactl, used by x11-volume
    ttf-jetbrains-mono-nerd          # font used by the terminals / i3 / bar
    starship                         # shell prompt (config in starship/)
    tmux                             # terminal multiplexer (config in tmux/)
    rclone                           # cloud storage sync
    obsidian                         # notes
    base-devel                       # makepkg and the toolchain, for yay and AUR builds
)

# Desktop tools for daily use (not just disposable VMs).
PKGS+=(
    copyq                            # clipboard history; bin/x11-clipboard puts it in rofi
    satty                            # screenshot annotation (bin/x11-screenshot annotate-*)
    xss-lock                         # locks on suspend and idle (i3lock-color is pinned below)
    xorg-xset                        # xset: sets the idle timer xss-lock watches (05-autostart.conf)
    gammastep                        # nightlight, toggled by bin/x11-nightlight
    blueman bluez bluez-utils        # bluetooth manager GUI + tray applet, the stack under it
    yazi                             # TUI file manager ($mod+Shift+e)
    nautilus gvfs                    # GUI file manager ($mod+e); gvfs: trash, mounts, network
    adw-gtk-theme                    # adw-gtk3: GTK3 drawn like libadwaita, recoloured by x11-theme's gtk.css
    zaproxy                          # web proxy ($mod+z workspace)
    # yazi's previewers and helpers (its optdepends): archives, PDFs, video
    # thumbnails, SVG, images, search. jq/fzf/zoxide are already above.
    7zip poppler ffmpegthumbnailer resvg imagemagick fd ripgrep
)

# Session helpers.
PKGS+=(
    polkit-gnome                     # polkit authentication agent
    network-manager-applet           # nm-applet
    gnome-keyring libsecret seahorse # secrets (Wi-Fi, browsers, Vesktop); unlocked at login by ly's PAM
)

# Default applications (setup_default_apps), each themed by x11-theme.
PKGS+=(
    imv                              # images
    zathura zathura-pdf-mupdf        # PDFs
    mpv                              # video and audio
)

# Bare-metal desktop: media and brightness keys, monitors, touchpad, power.
PKGS+=(
    playerctl                        # play/pause/next/previous for any MPRIS player
    brightnessctl                    # backlight keys (bin/x11-brightness)
    autorandr arandr                 # monitor profiles (bin/x11-display); arandr to arrange them
    xf86-input-libinput              # the X input driver xorg/30-touchpad.conf configures
    power-profiles-daemon            # power profile, switched from the $mod+Escape menu
    tesseract tesseract-data-eng     # OCR: $mod+Print copies the text in a region
)

# Network and security.
PKGS+=(
    wireguard-tools                  # wg, wg-quick (openvpn comes with CachyOS)
    ufw                              # firewall, set up by setup_firewall
)

# VM guest integration, only inside a VM: on bare metal these have nothing to
# talk to, so they are not installed at all.
IS_VM=0
if command -v systemd-detect-virt >/dev/null && systemd-detect-virt -q --vm; then
    IS_VM=1
    PKGS+=(
        spice-vdagent                # shared clipboard + display resize (SPICE)
        qemu-guest-agent             # host <-> guest control channel
    )
fi

# Set when something required could not be installed; reported at the end.
FAILED=0

PACMAN_CONF=/etc/pacman.conf

# CachyOS's own repos must come before core/extra, or pacman takes the generic
# Arch builds. The CachyOS installer writes them that way; this only checks, and
# warns rather than rewriting pacman.conf. (cachyos-rate-mirrors and
# cachyos-repo tooling own that file's repo section.)
check_cachy_repos() {
    command -v pacman >/dev/null || return 0

    if ! grep -qx 'ID=cachyos' /etc/os-release 2>/dev/null; then
        warn "this does not look like CachyOS (/etc/os-release); continuing anyway"
    fi

    local repos first_cachy first_arch
    repos=$(pacman-conf --repo-list 2>/dev/null || true)
    # A miss (no cachyos repos, as on vanilla Arch) is a result, not an error.
    first_cachy=$(printf '%s\n' "$repos" | grep -n '^cachyos' | head -1 | cut -d: -f1 || true)
    first_arch=$(printf '%s\n' "$repos" | grep -nxE 'core|extra' | head -1 | cut -d: -f1 || true)

    if [ -z "$first_cachy" ]; then
        warn "no [cachyos*] repos in $PACMAN_CONF: packages will come from plain Arch"
        return 0
    fi
    if [ -n "$first_arch" ] && [ "$first_cachy" -gt "$first_arch" ]; then
        warn "the [cachyos*] repos are listed after core/extra in $PACMAN_CONF;"
        warn "pacman will prefer the generic Arch builds. Move them above [core]."
        return 0
    fi
    say "CachyOS repos: $(printf '%s\n' "$repos" | grep '^cachyos' | paste -sd' ')"
}

# chaotic-aur exists here for qutebrowser-git alone (and blesh-git, if opted in
# with opt/blesh.sh); nothing else is installed from it. It is appended at the
# END of pacman.conf, below the Cachy and Arch repos, so it can never shadow
# their builds of anything: packages are only taken from it by qualified name.
#
# Setup follows https://aur.chaotic.cx/docs: trust the signing key, install the
# keyring and mirrorlist packages from its CDN, then add the repo. A repo that
# has just been added has no sync database, and the only supported way to get
# one is a full -Syu (a bare -Sy followed by -S is a partial upgrade).
CHAOTIC_KEY=3056513887B78AEB
CHAOTIC_CDN=https://cdn-mirror.chaotic.cx/chaotic-aur

setup_chaotic_aur() {
    command -v pacman >/dev/null || return 0

    if ! pacman-conf --repo-list 2>/dev/null | grep -qx chaotic-aur; then
        say "Adding the chaotic-aur repo (for qutebrowser-git)"
        # One -U for both packages: every pacman transaction costs a pre/post
        # snapper snapshot pair on CachyOS (cachyos-snapper-support).
        local pkgs=()
        pacman -Qq chaotic-keyring >/dev/null 2>&1 || pkgs+=("$CHAOTIC_CDN/chaotic-keyring.pkg.tar.zst")
        pacman -Qq chaotic-mirrorlist >/dev/null 2>&1 || pkgs+=("$CHAOTIC_CDN/chaotic-mirrorlist.pkg.tar.zst")
        if [ "${#pkgs[@]}" -gt 0 ]; then
            { run $SUDO pacman-key --recv-key "$CHAOTIC_KEY" --keyserver keyserver.ubuntu.com \
                && run $SUDO pacman-key --lsign-key "$CHAOTIC_KEY" \
                && run $SUDO pacman -U --needed --noconfirm "${pkgs[@]}"; } \
                || { warn "could not install chaotic-keyring/chaotic-mirrorlist"; FAILED=1; return 0; }
        fi
        if [ "$dry" = 1 ]; then
            echo "+ append [chaotic-aur] to $PACMAN_CONF"
        else
            $SUDO cp -a "$PACMAN_CONF" "$PACMAN_CONF.bak.$(date +%s)"
            printf '\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist\n' \
                | $SUDO tee -a "$PACMAN_CONF" >/dev/null
            echo "chaotic-aur: appended to $PACMAN_CONF (last, below the Cachy and Arch repos)"
        fi
    fi

    if [ ! -f "$(pacman-conf DBPath 2>/dev/null || echo /var/lib/pacman/)sync/chaotic-aur.db" ]; then
        say "Syncing the new repo (full -Syu; a bare -Sy would be a partial upgrade)"
        run $SUDO pacman -Syu --noconfirm || { warn "pacman -Syu failed"; FAILED=1; }
    fi
}

# Pinned packages. Each entry lists the repos it may come from, best first:
# the first one that has it is installed, by its qualified name, so pacman can
# never pick the same package from another repo. Order follows AGENTS.md:
# CachyOS's repos, then official Arch, then chaotic-aur. A pin with a single repo
# has no fallback:
#   chaotic-aur/qutebrowser-git  no CachyOS or official build; extra's plain
#                                `qutebrowser` is not wanted (they conflict, so
#                                an installed `qutebrowser` is removed first)
#   chaotic-aur/yaru-icon-theme  the icon themes omarchy themes name in icons.theme
#                                (Yaru-red, Yaru-blue, ...); in no official repo
# With a fallback list:
#   cachyos/yay                  CachyOS's build, else chaotic-aur's (never plain AUR)
#   cachyos/i3lock-color         the lock screen; i3lock with colour options, which
#                                plain extra/i3lock lacks (they conflict, so an
#                                installed `i3lock` is removed first)
#   cachyos/vesktop-bin          Discord client (Vencord), else chaotic-aur/vesktop
# If no listed repo has a package, it is skipped with a warning, the rest still
# installs, and the run exits non-zero.
PINNED=(
    chaotic-aur/qutebrowser-git
    chaotic-aur/yaru-icon-theme
    "cachyos/yay chaotic-aur/yay"
    "cachyos/i3lock-color chaotic-aur/i3lock-color"
    "cachyos/vesktop-bin chaotic-aur/vesktop"
)
# Plain package each pinned one conflicts with: the plain one is removed first
# when the pin is chosen (--noconfirm would answer the conflict prompt with No).
PINNED_REPLACES=(qutebrowser:qutebrowser-git i3lock:i3lock-color vesktop:vesktop-bin)

# Everything goes into ONE pacman transaction: on CachyOS each transaction also
# takes a pre/post snapper snapshot pair, so separate calls per package would
# litter the snapshot list.
# Arch's rule: never -S against a stale sync database (a partial upgrade). The
# database is a snapshot of the mirror from the last sync. Once the mirror
# replaces a package (CachyOS rebuilding qt6-* from 6.11.2 to 6.12.0, say), the
# old file is gone and pacman fails with "failed retrieving file ... 6.11.2".
# So sync first, as a full -Syu: an -Sy alone is the partial upgrade.
refresh_databases() {
    say "Refreshing package databases (pacman -Syu)"
    run $SUDO pacman -Syu --noconfirm || { warn "pacman -Syu failed"; FAILED=1; }
}

install_packages() {
    command -v pacman >/dev/null || { warn "pacman not found; skipping package install"; return; }

    say "Checking packages"
    local missing=() p c entry chosen installed need_refresh=0
    for p in "${PKGS[@]}"; do
        pacman -Qq "$p" >/dev/null 2>&1 || { missing+=("$p"); need_refresh=1; }
    done
    for entry in "${PINNED[@]}"; do
        installed=0
        for c in $entry; do pacman -Qq "${c#*/}" >/dev/null 2>&1 && installed=1; done
        [ "$installed" = 1 ] || need_refresh=1
    done
    # Only when something is missing, so a re-run on a finished install does not
    # upgrade the whole system. The -Si checks below need a current database too.
    [ "$need_refresh" = 1 ] && refresh_databases
    for entry in "${PINNED[@]}"; do
        installed=0
        for c in $entry; do pacman -Qq "${c#*/}" >/dev/null 2>&1 && installed=1; done
        [ "$installed" = 1 ] && continue
        chosen=
        for c in $entry; do
            if pacman -Si "$c" >/dev/null 2>&1; then chosen=$c; break; fi
        done
        if [ -z "$chosen" ]; then
            warn "none of these has the package: $entry (is the repo enabled and synced?)"
            warn "not installing it from any other repo; fix that and re-run"
            FAILED=1
            continue
        fi
        missing+=("$chosen")
    done

    if [ "${#missing[@]}" -eq 0 ]; then
        echo "all packages already installed"
        return
    fi

    # Conflicting plain packages: --noconfirm answers pacman's "remove X?" with
    # its default, No, so they have to go first.
    local pair plain pkg
    for pair in "${PINNED_REPLACES[@]}"; do
        plain=${pair%%:*}; pkg=${pair#*:}
        case " ${missing[*]} " in *"/$pkg "*|*"/$pkg") ;; *) continue ;; esac
        if [ "$(pacman -Qq "$plain" 2>/dev/null)" = "$plain" ]; then
            warn "replacing $plain with $pkg"
            run $SUDO pacman -Rns --noconfirm "$plain"
        fi
    done

    say "Installing: ${missing[*]}"
    # A failure is reported, not fatal: the rest of the install (Qt sync, theme,
    # links) still runs and the summary at the end says what is missing.
    if ! run $SUDO pacman -S --needed --noconfirm "${missing[@]}"; then
        warn "pacman could not install everything; syncing and retrying once"
        refresh_databases
        if ! run $SUDO pacman -S --needed --noconfirm "${missing[@]}"; then
            warn "still not installed: ${missing[*]}"
            warn "a mirror may be behind; re-run install.sh later"
            FAILED=1
        fi
    fi
}

# Keep the Qt 6 stack on one minor version.
#
# Qt modules link against qt6-base's *private* API, which is versioned per
# release (Qt_6_PRIVATE_API, QtPrivate_6_11_2), so qt6-svg 6.11.2 cannot load
# next to qt6-base 6.12.0 even though pacman sees nothing wrong: the
# dependencies are unversioned. That mix happens whenever Arch moves to a new Qt
# minor and CachyOS rebuilds it piecemeal. Both were hit on 2026-10-07:
#   * extra's python-pyqt6 (no Cachy build) was built for Qt 6.12 while
#     cachyos-extra-v3 still had qt6-base 6.11.2 -> qutebrowser died with
#     "version `Qt_6.12' not found";
#   * hours later cachyos-extra-v3 had qt6-base 6.12.0 but qt6-svg 6.11.2, so
#     CopyQ died with "undefined symbol ... QtPrivate_6_11_2" on a pure-Cachy
#     install.
#
# Rule: once qt6-base is at minor N, every installed qt6-* module still below N
# is taken from extra if extra has it at N. The newest qt6-base wins whichever
# repo it is in. Modules that extra itself ships at an older minor
# (qt6-webengine trails qt6-base by design) are left alone. It heals itself:
# CachyOS versions a rebuild as Arch's pkgrel plus ".1" (6.12.0-1 ->
# 6.12.0-1.1), so the next -Syu after CachyOS catches up moves each one back.
qt_minor() { printf '%s\n' "${1#*:}" | cut -d. -f1,2; }

sync_qt_stack() {
    pacman -Qq qt6-base >/dev/null 2>&1 || return 0

    local base_ver base_min p inst ext behind=()
    base_ver=$(pacman -Q qt6-base | cut -d' ' -f2)
    # extra may already be a minor ahead of an installed (Cachy) qt6-base.
    ext=$(pacman -Sl extra 2>/dev/null | awk '$2 == "qt6-base" { print $3 }')
    if [ -n "$ext" ] && [ "$(vercmp "$(qt_minor "$base_ver")" "$(qt_minor "$ext")")" -lt 0 ]; then
        behind+=(extra/qt6-base)
        base_ver=$ext
    fi
    base_min=$(qt_minor "$base_ver")

    for p in $(pacman -Qq | grep '^qt6-' | grep -vx qt6-base); do
        inst=$(pacman -Q "$p" | cut -d' ' -f2)
        [ "$(vercmp "$(qt_minor "$inst")" "$base_min")" -lt 0 ] || continue
        ext=$(pacman -Sl extra 2>/dev/null | awk -v p="$p" '$2 == p { print $3 }')
        [ -n "$ext" ] && [ "$(qt_minor "$ext")" = "$base_min" ] && behind+=("extra/$p")
    done

    if [ "${#behind[@]}" -gt 0 ]; then
        say "Qt modules behind qt6-base $base_min (CachyOS mid-rebuild); taking from extra: ${behind[*]}"
        refresh_databases
        run $SUDO pacman -S --noconfirm "${behind[@]}" || { warn "could not sync the Qt stack"; FAILED=1; }
    fi

    [ "$dry" = 1 ] && return 0
    if pacman -Qq qutebrowser-git >/dev/null 2>&1 \
        && ! python3 -c 'import PyQt6.QtWebEngineWidgets' >/dev/null 2>&1; then
        warn "PyQt6 still does not load; qutebrowser will not start:"
        python3 -c 'import PyQt6.QtWebEngineWidgets' 2>&1 | tail -1 >&2
        FAILED=1
    fi
}

# The shell integrations (shell/) are bash-only, and CachyOS makes fish the
# login shell, so alacritty would start fish and never load them. Switch the
# login shell to bash; fish stays installed (it is CachyOS's package, not ours).
# Run as root (sudo), chsh does not ask for the user's password.
setup_login_shell() {
    local current bash_path=/bin/bash
    current=$(getent passwd "$TARGET_USER" | cut -d: -f7)
    case "$current" in
        /bin/bash|/usr/bin/bash) return 0 ;;
    esac
    [ "$TARGET_USER" = root ] && { warn "running as root without sudo; not changing root's shell"; return 0; }

    say "Changing the login shell of $TARGET_USER: $current -> $bash_path"
    run $SUDO chsh -s "$bash_path" "$TARGET_USER" \
        || { warn "could not change the login shell to bash"; return 0; }
    echo "login shell: $bash_path (applies at next login)"
}

# ly's settings overlay (colours come from the theme; see x11-theme apply_ly).
#
# ly reads exactly one config file, /etc/ly/config.ini - the path is compiled in,
# and there is no ~/.config/ly/config.ini fallback - so the theme has to be merged
# into that file. Merging rather than replacing keeps every setting we do not care
# about at its packaged value, and keeps working across upgrades that add keys.
#
# The original is kept once as config.ini.cachy-orig; re-running restores from it
# first, so the merge is idempotent instead of accumulating.
install_ly_theme() {
    # LY_CONFIG exists so this can be pointed elsewhere for testing; normal use
    # is the system path.
    local target="${LY_CONFIG:-/etc/ly/config.ini}"
    local src="$REPO/ly/overlay.ini"
    local pristine="$target.cachy-orig"

    [ -r "$src" ] || return 0
    if [ ! -f "$target" ]; then
        warn "$target not found; skipping the ly theme (is the 'ly' package installed?)"
        return
    fi

    say "Applying the ly overlay"
    local merged
    merged=$(mktemp)

    if [ -f "$pristine" ]; then
        cat "$pristine" > "$merged"
    else
        cat "$target" > "$merged"
        run $SUDO cp -a "$target" "$pristine"
        echo "saved pristine copy as $pristine"
    fi

    # Replace each key we theme in place; append any key the packaged file lacks.
    # Operating on the pristine copy means re-running never stacks duplicates.
    awk -v overlay="$src" '
        function keyof(s) { k = s; sub(/=.*/, "", k); gsub(/[[:space:]]/, "", k); return k }
        function valof(s) {
            v = substr(s, index(s, "=") + 1)
            sub(/^[[:space:]]+/, "", v); sub(/[[:space:]]+$/, "", v)
            return v
        }
        BEGIN {
            while ((getline line < overlay) > 0) {
                if (line ~ /^[a-z_]+[[:space:]]*=/) {
                    k = keyof(line)
                    if (!(k in val)) order[++n] = k
                    val[k] = valof(line)
                }
            }
            close(overlay)
        }
        {
            if ($0 ~ /^[a-z_]+[[:space:]]*=/) {
                k = keyof($0)
                if (k in val) { print k " = " val[k]; done_[k] = 1; next }
            }
            print
        }
        END {
            for (i = 1; i <= n; i++)
                if (!(order[i] in done_)) print order[i] " = " val[order[i]]
        }
    ' "$merged" > "$merged.new" && mv "$merged.new" "$merged"

    if cmp -s "$merged" "$target"; then
        echo "ly theme: already up to date"
    else
        run $SUDO install -m 644 "$merged" "$target"
        echo "ly theme: written to $target"
    fi
    rm -f "$merged"

    # The merge starts from the pristine file, so put the theme's colours back.
    if [ "$dry" = 0 ] && [ -f "$HOME/.local/state/omarchy/current/theme.name" ]; then
        "$REPO/bin/x11-theme" apply-ly || true
    fi
}

# Neovim is a LazyVim tree in this repo (init.lua, lua/config, lua/plugins,
# colors). install_links() calls link_nvim_tree() to link each file
# individually, so runtime state (lazyvim.json, lazy-lock.json, :Mason, spell,
# shada) stays out of the repo.
link_nvim_tree() {
    local cfg="${XDG_CONFIG_HOME:-$HOME/.config}"
    local rel
    ( cd "$REPO/nvim" && find . -type f | sed 's|^\./||' ) | while IFS= read -r rel; do
        link "$REPO/nvim/$rel" "$cfg/nvim/$rel"
    done
}

# Firefox: Vimium, Brave search and the default theme, via enterprise policy.
#
# /etc/firefox/policies/policies.json is the documented system-wide location on
# Linux (the install-directory alternative under /usr/lib/firefox would be
# clobbered by package upgrades). The policy installs both add-ons from AMO at
# startup, so this needs network on first run, and activates the theme through
# the pref its manifest declares.
#
# Vimium's options cannot be installed this way: its settings live in the
# extension's own browser storage, the only import path is the Restore control
# on chrome-extension://<id>/options.html, and no policy can write extension
# storage. Load firefox/vimium-options.json from the repo there once by hand.
# qutebrowser gets the same settings by config in qutebrowser/vimium.py, which
# needs no such step.
setup_firefox() {
    local target="/etc/firefox/policies/policies.json"
    local src="$REPO/firefox/policies.json"

    if [ -r "$src" ] && command -v pacman >/dev/null && pacman -Qq firefox >/dev/null 2>&1; then
        say "Installing the Firefox policy"
        if [ "$dry" = 1 ]; then
            echo "+ install $src -> $target"
        elif [ -f "$target" ] && cmp -s "$src" "$target"; then
            echo "firefox policy: already up to date"
        else
            [ -f "$target" ] && run $SUDO cp -a "$target" "$target.bak.$(date +%s)"
            run $SUDO install -D -m 644 "$src" "$target"
            echo "firefox policy: $target (default theme, Vimium from AMO, Brave default search)"
        fi
    fi

}

# Chromium: Brave default search via enterprise policy, in
# /etc/chromium/policies/managed/ (managed, because that is the only level that
# sets a default engine; recommended/ merely suggests). The toolbar colour is a
# second policy file, color.json, written by x11-theme on every theme switch
# through the helper installed by setup_theme_helper().
setup_chromium() {
    local src="$REPO/chromium/policies/managed/brave-search.json"
    local target="/etc/chromium/policies/managed/brave-search.json"

    if [ -r "$src" ] && command -v pacman >/dev/null && pacman -Qq chromium >/dev/null 2>&1; then
        say "Installing the Chromium policy"
        if [ "$dry" = 1 ]; then
            echo "+ install $src -> $target"
        elif [ -f "$target" ] && cmp -s "$src" "$target"; then
            echo "chromium policy: already up to date"
        else
            [ -f "$target" ] && run $SUDO cp -a "$target" "$target.bak.$(date +%s)"
            run $SUDO install -D -m 644 "$src" "$target"
            echo "chromium policy: $target (Brave default search)"
        fi
    fi
}

# x11-theme writes two root-owned files: Chromium's BrowserThemeColor policy and
# ly's colours in /etc/ly/config.ini. As omarchy does for Chromium, each write
# goes through one root-owned helper, with a sudoers rule naming those helpers
# alone, so a theme switch never prompts for a password:
#   /usr/local/lib/cachy-dots/{chromium-theme-color,ly-theme-colors}
#     COPIED from theme/root/ (root must not run a file the user can edit);
#     each accepts only strictly validated colour arguments
#   /etc/sudoers.d/cachy-dots-theme    NOPASSWD for exactly those two paths
THEME_HELPER_DIR=/usr/local/lib/cachy-dots
THEME_HELPERS=(chromium-theme-color ly-theme-colors)
THEME_SUDOERS=/etc/sudoers.d/cachy-dots-theme

setup_theme_helper() {
    local h src rule tmp paths=()
    say "Installing the theme helpers (Chromium, ly)"
    for h in "${THEME_HELPERS[@]}"; do
        src="$REPO/theme/root/$h"
        [ -r "$src" ] || continue
        paths+=("$THEME_HELPER_DIR/$h")
        if [ "$dry" = 1 ]; then
            echo "+ install $src -> $THEME_HELPER_DIR/$h (root:root 755)"
        elif ! cmp -s "$src" "$THEME_HELPER_DIR/$h" 2>/dev/null; then
            $SUDO install -D -o root -g root -m 755 "$src" "$THEME_HELPER_DIR/$h"
            echo "theme helper: $THEME_HELPER_DIR/$h"
        fi
    done
    [ "${#paths[@]}" -gt 0 ] || return 0
    rule="$TARGET_USER ALL=(root) NOPASSWD: $(IFS=,; echo "${paths[*]}" | sed 's/,/, /g')"
    if [ "$dry" = 1 ]; then echo "+ write $THEME_SUDOERS: $rule"; return; fi
    if ! $SUDO grep -qxF "$rule" "$THEME_SUDOERS" 2>/dev/null; then
        tmp=$(mktemp)
        printf '# cachy-dots: lets x11-theme set Chromium'"'"'s colour policy and ly'"'"'s colours.\n%s\n' "$rule" > "$tmp"
        # visudo checks the syntax before anything reaches sudoers.d; a broken
        # file there would lock sudo out entirely.
        if $SUDO visudo -cqf "$tmp"; then
            $SUDO install -o root -g root -m 440 "$tmp" "$THEME_SUDOERS"
            echo "theme helpers: sudoers rule in $THEME_SUDOERS"
        else
            warn "the sudoers rule did not validate; Chromium and ly will not follow the theme"
        fi
        rm -f "$tmp"
    fi
}

# Set a key in an INI file, creating the file and its [Settings] section as
# needed. Used for the GTK settings files, which are plain INI and may already
# exist with the user's own keys.
ini_set() {
    local file="$1" key="$2" value="$3"
    [ "$dry" = 1 ] && { echo "+ set $key=$value in $file"; return; }
    mkdir -p "$(dirname "$file")"
    if [ ! -f "$file" ]; then
        printf '[Settings]\n%s=%s\n' "$key" "$value" > "$file"
        return
    fi
    if grep -qE "^[[:space:]]*${key}[[:space:]]*=" "$file"; then
        sed -i -E "s|^[[:space:]]*${key}[[:space:]]*=.*|${key}=${value}|" "$file"
    elif grep -qE "^\[Settings\]" "$file"; then
        # insert directly after the [Settings] header, not at the end of the
        # file, so a later section cannot claim the key
        awk -v k="$key" -v v="$value" '
            { print }
            /^\[Settings\]/ && !done { print k "=" v; done = 1 }
        ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
    else
        printf '\n[Settings]\n%s=%s\n' "$key" "$value" >> "$file"
    fi
}

# GTK theme and icon theme.
#
# GTK does not read org.gnome.desktop.interface for either of these. It reads the
# XSETTINGS protocol, which a desktop session publishes via a settings daemon.
# There is none here, so the gsettings values that setup_dark_theme() writes are
# ignored by GTK. Confirmed on the VM with Gtk.IconTheme: nm-device-wired
# resolved to /usr/share/icons/hicolor/... however gsettings was set. GTK does
# read ~/.config/gtk-{3,4}.0/settings.ini directly, which fixes it.
#
#   * GTK3 theme: adw-gtk3-dark (adw-gtk-theme), which draws GTK3 like libadwaita
#     and takes the same named colours, so the one gtk.css x11-theme renders
#     recolours GTK3 (Firefox, virt-manager) and GTK4 (nautilus) alike. x11-theme
#     switches it to adw-gtk3 for a light theme. Never "Adwaita-dark": no GTK3
#     theme has that name, and naming one that does not exist makes GTK fall back
#     to *light* Adwaita without a word (menu background #F6F5F4, not #353535).
#   * icon theme: x11-theme, generated by x11-theme from the NetworkManager
#     symbolic icons tinted to the theme (the i3bar tray's nm-applet glyph).
#   * gtk.css: linked from the rendered theme (see install_links).
setup_gtk() {
    local cfg="${XDG_CONFIG_HOME:-$HOME/.config}"
    local dir
    for dir in gtk-3.0 gtk-4.0; do
        [ "$dir" = gtk-3.0 ] && ini_set "$cfg/$dir/settings.ini" gtk-theme-name adw-gtk3-dark
        [ "$dir" = gtk-4.0 ] && ini_set "$cfg/$dir/settings.ini" gtk-theme-name Adwaita
        ini_set "$cfg/$dir/settings.ini" gtk-icon-theme-name x11-theme
        ini_set "$cfg/$dir/settings.ini" gtk-application-prefer-dark-theme 1
    done
    # The previous generated icon theme, before x11-theme took it over.
    [ -d "$HOME/.local/share/icons/pinkrot" ] && run rm -rf "$HOME/.local/share/icons/pinkrot"
    [ "$dry" = 1 ] || echo "gtk: adw-gtk3-dark / Adwaita (dark), icons x11-theme ($cfg/gtk-{3,4}.0/settings.ini)"
}

# Make the session read as dark.
#
# Two halves, and neither is what GTK itself uses - GTK reads XSETTINGS, which
# nothing publishes here. See setup_gtk() for that; this is for everything else:
#   * dconf. color-scheme is what GTK4/libadwaita and Qt consult, and what a
#     desktop would normally republish over XSETTINGS.
#   * the portal. Sandboxed apps and Qt6 (qutebrowser) ask
#     org.freedesktop.portal.Settings instead of reading dconf, and that only
#     works if the backend is running, which needs XDG_CURRENT_DESKTOP to name a
#     desktop the backend is registered for: gtk.portal declares UseIn=gnome.
#     Check it with:
#       busctl --user call org.freedesktop.portal.Desktop \
#         /org/freedesktop/portal/desktop org.freedesktop.portal.Settings \
#         ReadOne ss org.gnome.desktop.interface color-scheme
#
# Best run from inside the desktop session, since both halves need the session
# bus. Run from a bare tty and it explains what to do instead.
setup_dark_theme() {
    command -v gsettings >/dev/null || { warn "gsettings not installed; skipping dark mode"; return; }

    if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
        warn "no session bus: cannot set the system colour scheme from here."
        warn "Run these inside the i3 session to finish:"
        warn "  gsettings set org.gnome.desktop.interface color-scheme prefer-dark"
        warn "  gsettings set org.gnome.desktop.interface gtk-theme adw-gtk3-dark"
        warn "  systemctl --user enable --now xdg-desktop-portal.service xdg-desktop-portal-gtk.service"
        return
    fi

    say "Setting the system colour scheme to dark"
    run gsettings set org.gnome.desktop.interface color-scheme prefer-dark
    run gsettings set org.gnome.desktop.interface gtk-theme adw-gtk3-dark
    # GTK itself ignores this (see setup_gtk), but other consumers read it.
    run gsettings set org.gnome.desktop.interface icon-theme x11-theme

    if command -v systemctl >/dev/null; then
        # The gtk portal backend is gated on XDG_CURRENT_DESKTOP; i3/config sets
        # it for everything i3 spawns, this covers the user services.
        XDG_CURRENT_DESKTOP=GNOME run dbus-update-activation-environment --systemd XDG_CURRENT_DESKTOP
        # Both units are static and D-Bus activated, so there is nothing to
        # enable; the first portal request starts them. Starting them here only
        # works with a display: the GTK backend exits at once without one (as
        # over ssh), and systemd then refuses retries until its start limit resets.
        if [ -n "${DISPLAY:-}" ]; then
            run systemctl --user restart xdg-desktop-portal-gtk.service xdg-desktop-portal.service \
                || warn "could not start the xdg-desktop-portal user services"
        else
            echo "portal: no DISPLAY; it starts on demand in the i3 session"
        fi
    fi
}

# nix is for project-specific environments only: the daemon is enabled so
# `nix-shell` / `nix develop` work for the user, and nothing else is configured
# (no channels, no flakes settings).
enable_nix() {
    pacman -Qq nix >/dev/null 2>&1 || return 0
    command -v systemctl >/dev/null || return 0

    say "Enabling nix-daemon"
    run $SUDO systemctl enable --now nix-daemon.socket \
        || warn "could not enable nix-daemon.socket"

    # Multi-user nix: membership of nix-users (when the package ships it) is
    # what lets a normal user talk to the daemon. Applies at next login.
    local user="${SUDO_USER:-${USER:-}}"
    if [ -n "$user" ] && [ "$user" != root ] && getent group nix-users >/dev/null; then
        if ! id -nG "$user" | tr ' ' '\n' | grep -qx nix-users; then
            run $SUDO usermod -aG nix-users "$user"
            echo "added $user to nix-users (log out and back in for it to apply)"
        fi
    fi
}

enable_services() {
    command -v systemctl >/dev/null || return 0
    say "Enabling guest services"

    # ly is the display manager: `ly@.service` is a template, so the instance is
    # named for the tty it takes over. It Conflicts= getty@tty1, which systemd
    # resolves automatically.
    if pacman -Qq ly >/dev/null 2>&1; then
        run $SUDO systemctl enable ly@tty1.service \
            || warn "could not enable ly@tty1.service"
        if systemctl is-enabled --quiet "${DISPLAY_MANAGER:-lightdm}.service" 2>/dev/null; then
            warn "another display manager (${DISPLAY_MANAGER}) is enabled; disable it or ly will not start"
        fi
    fi
    # bluetoothd. Its unit is conditioned on /sys/class/bluetooth, so on a host
    # without an adapter (any VM) it is enabled but simply never starts.
    if pacman -Qq bluez >/dev/null 2>&1; then
        run $SUDO systemctl enable bluetooth.service \
            || warn "could not enable bluetooth.service"
    fi

    if pacman -Qq power-profiles-daemon >/dev/null 2>&1; then
        run $SUDO systemctl enable --now power-profiles-daemon.service \
            || warn "could not enable power-profiles-daemon.service"
    fi

    # Nothing to enable for the guest agents: spice-vdagentd.socket and
    # qemu-guest-agent are both static units, pulled in by udev rules when their
    # virtio port (com.redhat.spice.0 / org.qemu.guest_agent.0) appears. Start
    # the socket now so the first session does not need a reboot.
    [ "$IS_VM" = 1 ] || return 0
    if [ -e /dev/virtio-ports/com.redhat.spice.0 ]; then
        run $SUDO systemctl start spice-vdagentd.socket \
            || warn "could not start spice-vdagentd.socket"
    else
        warn "no SPICE virtio port; spice-vdagent (clipboard, resize) will be idle"
    fi
}

# Firewall: deny incoming, allow outgoing (CachyOS ships ufw like this already;
# this makes it so everywhere). SSH is allowed FIRST when sshd is enabled: on a
# headless host it is the way in, and a deny-all firewall without it would cut
# the installing session off. Rate-limited (ufw limit) when this adds the rule;
# an existing rule for port 22 is left as it is. Listeners for CTF work (reverse
# shells, HTTP servers) need their own rule: `sudo ufw allow 4444/tcp`.
setup_firewall() {
    command -v ufw >/dev/null || return 0
    say "Firewall (ufw): deny incoming, allow outgoing"
    if [ "$dry" = 1 ]; then echo "+ ufw: allow ssh if sshd is enabled, default deny incoming, enable"; return; fi
    if systemctl is-enabled --quiet sshd 2>/dev/null \
        && ! $SUDO ufw status | grep -qE '^22(/tcp)?[[:space:]]'; then
        $SUDO ufw limit 22/tcp comment 'ssh (cachy-dots)' >/dev/null && echo "ufw: ssh allowed (rate-limited)"
    fi
    $SUDO ufw default deny incoming >/dev/null
    $SUDO ufw default allow outgoing >/dev/null
    if ! $SUDO ufw status | grep -q '^Status: active'; then
        # Fails when the running kernel has lost its netfilter modules, which a
        # kernel upgrade in this run causes until a reboot (checked at the end).
        if $SUDO ufw --force enable >/dev/null; then
            echo "ufw: enabled"
        else
            warn "ufw could not start; reboot into the new kernel, then run: sudo ufw enable"
            FAILED=1
        fi
    fi
    $SUDO systemctl enable --quiet ufw.service || warn "could not enable ufw.service"
    $SUDO ufw status | sed -n '1p'
}

# Touchpad: tap to click and friends (xorg/30-touchpad.conf). A root file, so a
# copy; it matches nothing where there is no touchpad.
setup_touchpad() {
    local src="$REPO/xorg/30-touchpad.conf" target=/etc/X11/xorg.conf.d/30-touchpad.conf
    [ -r "$src" ] || return 0
    if [ "$dry" = 1 ]; then echo "+ install $src -> $target"; return; fi
    if ! cmp -s "$src" "$target" 2>/dev/null; then
        $SUDO install -D -o root -g root -m 644 "$src" "$target"
        echo "touchpad: $target (applies at the next X start)"
    fi
}

# The keyring (Wi-Fi passwords for nm-applet, Chromium and Vesktop secrets) is
# unlocked at login by pam_gnome_keyring in ly's own PAM file, which the ly
# package ships with those lines. Only checked: if a future package drops them,
# say so rather than edit a root PAM file behind the user's back.
check_keyring_pam() {
    [ -f /etc/pam.d/ly ] || return 0
    if grep -qE '^-?auth[[:space:]]+optional[[:space:]]+pam_gnome_keyring\.so' /etc/pam.d/ly \
        && grep -qE '^-?session[[:space:]]+optional[[:space:]]+pam_gnome_keyring\.so.*auto_start' /etc/pam.d/ly; then
        echo "keyring: unlocked at login by ly's PAM (pam_gnome_keyring)"
    else
        warn "/etc/pam.d/ly lacks pam_gnome_keyring; the keyring will not unlock at login."
        warn "add: 'auth optional pam_gnome_keyring.so' and 'session optional pam_gnome_keyring.so auto_start'"
    fi
}

# Hardened sshd config. Unlike athena-dots, sshd is left exactly as found:
# CachyOS enables it, and on a headless host it is the only way in, so this
# neither enables nor disables the service. Installs a drop-in (pubkey only, no
# passwords/interactive, no root) and the deploy key into
# ~/.ssh/authorized_keys, validates with sshd -t, and reloads sshd if it is
# running. The key goes in FIRST, so password logins are never switched off
# before a key that can replace them is in place.
setup_sshd() {
    local src="$REPO/ssh/sshd_config.d/10-cachy-safe.conf"
    local target="/etc/ssh/sshd_config.d/10-cachy-safe.conf"
    local key='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGeIuM1WNYaQp75xua3Fh/DgPdFdEqGIVN748bbO5Sis athena0'

    say "Installing the sshd hardening drop-in (service state left as is)"

    local auth="$HOME/.ssh/authorized_keys"
    if [ "$dry" = 1 ]; then
        echo "+ ensure the athena0 key is in $auth"
    else
        mkdir -p "$(dirname "$auth")"
        touch "$auth"
        chmod 700 "$(dirname "$auth")"
        chmod 600 "$auth"
        if grep -qF "$key" "$auth" 2>/dev/null; then
            echo "authorized_keys: athena0 key already present"
        else
            printf '%s\n' "$key" >> "$auth"
            echo "authorized_keys: added the athena0 key"
        fi
    fi

    if [ -r "$src" ]; then
        local changed=0
        if [ "$dry" = 1 ]; then
            echo "+ install $src -> $target"
        elif [ -f "$target" ] && cmp -s "$src" "$target"; then
            echo "sshd config: already up to date"
        else
            [ -f "$target" ] && run $SUDO cp -a "$target" "$target.bak.$(date +%s)"
            run $SUDO install -D -m 644 "$src" "$target"
            echo "sshd config: $target (pubkey only, no root)"
            changed=1
        fi
        if [ "$changed" = 1 ] && command -v sshd >/dev/null; then
            if $SUDO sshd -t; then
                echo "sshd config OK"
                if systemctl is-active --quiet sshd 2>/dev/null; then
                    $SUDO systemctl reload sshd && echo "sshd: reloaded"
                fi
            else
                warn "sshd -t rejected the config; removing $target"
                $SUDO rm -f "$target"
                FAILED=1
            fi
        fi
    fi

}
# Apply a theme, so every file the configs point into the state directory
# exists (i3 includes its colours from there, i3bar runs its rendered config).
# First run: pinkrot, cloned from its repo for the backgrounds and previews; with
# no network, the built-in copy of its colors.toml (theme/themes/pinkrot).
# Later runs pull the installed theme repos (fast-forward only) and re-render
# the current theme, picking up both upstream theme changes and template edits.
PINKROT_REPO=https://github.com/r3b1s/omarchy-pinkrot-theme

setup_theme() {
    local theme="$REPO/bin/x11-theme"
    if [ "$dry" = 1 ]; then echo "+ x11-theme (apply or refresh)"; return; fi
    if [ -f "$HOME/.local/state/omarchy/current/theme.name" ]; then
        say "Updating the installed themes and re-rendering the current one"
        "$theme" update || warn "a theme could not be updated (see above); the current one was still re-rendered"
    else
        say "Applying the default theme (pinkrot)"
        "$theme" install "$PINKROT_REPO" \
            || { warn "could not clone $PINKROT_REPO; using the built-in pinkrot colours"; "$theme" set pinkrot; } \
            || { warn "could not apply any theme"; FAILED=1; }
    fi
}

# ── links ─────────────────────────────────────────────────────────────────

link() {
    local src="$1" dst="$2"
    run mkdir -p "$(dirname "$dst")"
    if [ -e "$dst" ] && [ ! -L "$dst" ]; then
        local backup
        backup="$dst.bak.$(date +%s)"
        run mv "$dst" "$backup"
        echo "backed up $dst -> $backup"
    fi
    run ln -sfn "$src" "$dst"
    echo "linked $dst -> $src"
}

# Idempotent managed block in ~/.bashrc that loads shell/ (~/.config/shell).
# Everything else in .bashrc is left alone. Remove the block to undo.
install_bashrc_block() {
    local bashrc="$HOME/.bashrc"
    local open="# >>> cachy-dots >>>"
    if [ -f "$bashrc" ] && grep -qF "$open" "$bashrc"; then
        echo "bashrc: cachy-dots block already present"
    elif [ "$dry" = 1 ]; then
        echo "+ append cachy-dots block to $bashrc"
    else
        touch "$bashrc"
        {
            echo
            echo "$open"
            # shellcheck disable=SC2016  # written literally: expands in .bashrc, not here
            echo '[[ -r "${XDG_CONFIG_HOME:-$HOME/.config}/shell/init.sh" ]] && source "${XDG_CONFIG_HOME:-$HOME/.config}/shell/init.sh"'
            echo "# <<< cachy-dots <<<"
        } >> "$bashrc"
        echo "bashrc: appended cachy-dots block"
    fi
    # The passwd entry, not $SHELL: setup_login_shell may have just changed it.
    local login
    login=$(getent passwd "$TARGET_USER" | cut -d: -f7)
    case "$(basename "${login:-unknown}")" in
        bash) ;;
        *) [ "$dry" = 1 ] || warn "login shell is ${login:-unknown}, not bash; shell/ is only loaded by bash" ;;
    esac
}

# Whole directories are linked where the app never writes into its config dir.
# Where it does (qutebrowser, btop, nvim, starship's shared ~/.config) individual
# files are linked, so runtime state stays out of the repo.
install_links() {
    say "Linking dots"
    local cfg="${XDG_CONFIG_HOME:-$HOME/.config}"

    local d
    for d in i3 kitty alacritty rofi shell; do
        link "$REPO/$d" "$cfg/$d"
    done

    # Earlier layouts linked these whole directories. dunst now needs a real
    # directory (its theme is a drop-in beside dunstrc), and i3status-rust's
    # config is rendered into the state directory instead.
    for d in dunst i3status-rust; do
        if [ -L "$cfg/$d" ] && [ "$(readlink -f "$cfg/$d")" = "$REPO/$d" ]; then
            run rm "$cfg/$d"
            echo "removed the old $cfg/$d directory link"
        fi
    done

    # Files the rendered theme provides: ~/.local/state/omarchy/current/theme/
    # is replaced on every switch, so these links stay valid.
    local th="$HOME/.local/state/omarchy/current/theme"
    link "$th/dunst.conf" "$cfg/dunst/dunstrc.d/90-theme.conf"
    link "$th/btop.theme" "$cfg/btop/themes/current.theme"
    link "$th/gtk.css" "$cfg/gtk-3.0/gtk.css"
    link "$th/gtk.css" "$cfg/gtk-4.0/gtk.css"
    link "$th/satty.config.toml" "$cfg/satty/config.toml"
    link "$th/yazi.toml" "$cfg/yazi/flavors/omarchy.yazi/flavor.toml"
    link "$REPO/yazi/theme.toml" "$cfg/yazi/theme.toml"
    link "$th/zathurarc" "$cfg/zathura/zathurarc"
    link "$th/imv.config" "$cfg/imv/config"
    link "$REPO/mpv/mpv.conf" "$cfg/mpv/mpv.conf"

    # omarchy-style theme-set hooks, run by x11-theme after every switch as
    # `bash <hook> <theme>`. vesktop (from quattro-dots) composes the rendered
    # quattro-vesktop.palette.css with vesktop/discord.css into Vesktop's themes
    # folder; it reads discord.css from the repo, which is why only the hook is
    # linked.
    local hook
    for hook in "$REPO"/hooks/theme-set.d/*; do
        link "$hook" "$cfg/omarchy/hooks/theme-set.d/$(basename "$hook")"
    done

    for pair in \
        "qutebrowser/config.py:qutebrowser/config.py" \
        "qutebrowser/omarchy_theme.py:qutebrowser/omarchy_theme.py" \
        "dunst/dunstrc:dunst/dunstrc" \
        "qutebrowser/vimium.py:qutebrowser/vimium.py" \
        "qutebrowser/startpage.html:qutebrowser/startpage.html" \
        "btop/btop.conf:btop/btop.conf" \
        "tmux/tmux.conf:tmux/tmux.conf" \
        "env/telemetry.conf:environment.d/telemetry.conf" \
        "starship/starship.toml:starship.toml"
    do
        link "$REPO/${pair%%:*}" "$cfg/${pair#*:}"
    done

    # Neovim is a LazyVim tree (init.lua + lua/config + colors). Individual
    # files are linked so runtime state (lazyvim.json, lazy-lock.json, :Mason,
    # spell, shada) stays out of the repo. lua/plugins/theme.lua is the rendered
    # theme (aether.nvim with its palette), as on omarchy; replacing it is what
    # lazy.nvim's change detection sees, and omarchy-theme-hotreload.lua applies.
    link_nvim_tree
    link "$th/neovim.lua" "$cfg/nvim/lua/plugins/theme.lua"
    # Links into the repo whose file has since been removed (pinkrot-theme.lua).
    [ "$dry" = 1 ] || find "$cfg/nvim" -xtype l -lname "$REPO/*" -print -delete 2>/dev/null | sed 's/^/removed dangling link /' || true

    install_bashrc_block

    # ~/.xprofile is sourced by the session start-up (ly runs /etc/ly/setup.sh,
    # which reads it before exec'ing the session), so this is how XDG_CURRENT_DESKTOP
    # reaches everything i3 spawns. It lives in $HOME, not in ~/.config, hence the
    # separate link rather than one of the pair mappings above.
    link "$REPO/shell/xprofile" "$HOME/.xprofile"

    # ble.sh is opt-in here (opt/blesh.sh links ~/.blerc), so nothing for it.

    local script
    for script in "$REPO"/bin/*; do
        link "$script" "$HOME/.local/bin/$(basename "$script")"
    done

    case ":$PATH:" in
        *":$HOME/.local/bin:"*) ;;
        *) echo "note: $HOME/.local/bin is added to PATH by shell/init.sh and ~/.xprofile from the next login" ;;
    esac

}

# Default applications, in ~/.config/mimeapps.list (xdg-mime writes it; the file
# is the apps' own state, so it is not linked from the repo). Without this,
# folders opened in a kitty helper and links and PDFs in Chromium.
DEFAULT_APPS=(
    "org.qutebrowser.qutebrowser.desktop:x-scheme-handler/http x-scheme-handler/https text/html application/xhtml+xml"
    "org.gnome.Nautilus.desktop:inode/directory"
    "org.pwmt.zathura-pdf-mupdf.desktop:application/pdf"
    "imv.desktop:image/png image/jpeg image/gif image/webp image/bmp image/tiff image/avif"
    "mpv.desktop:video/mp4 video/x-matroska video/webm video/quicktime video/x-msvideo audio/mpeg audio/flac audio/ogg audio/x-wav audio/mp4"
)

setup_default_apps() {
    command -v xdg-mime >/dev/null || return 0
    say "Default applications"
    local pair app
    for pair in "${DEFAULT_APPS[@]}"; do
        app=${pair%%:*}
        if [ ! -f "/usr/share/applications/$app" ]; then
            warn "no $app installed; leaving its file types alone"
            continue
        fi
        # shellcheck disable=SC2086  # the type list is meant to split
        run xdg-mime default "$app" ${pair#*:}
        echo "default: $app"
    done
    if command -v xdg-settings >/dev/null; then
        run xdg-settings set default-web-browser org.qutebrowser.qutebrowser.desktop 2>/dev/null || true
    fi
}

validate_i3() {
    local cfg="${XDG_CONFIG_HOME:-$HOME/.config}"
    if [ "$dry" = 0 ] && command -v i3 >/dev/null; then
        say "Validating i3 config"
        i3 -C -c "$cfg/i3/config" && echo "i3 config OK"
    fi
}

if [ "$do_packages" = 1 ]; then
    check_cachy_repos
    setup_chaotic_aur
    install_packages
    sync_qt_stack
    setup_login_shell
    setup_theme_helper
    install_ly_theme
    enable_services
    enable_nix
    setup_dark_theme
    setup_gtk
    setup_firefox
    setup_chromium
    setup_sshd
    setup_firewall
    setup_touchpad
    check_keyring_pam
fi
if [ "$do_links" = 1 ]; then
    install_links
    setup_theme
    setup_default_apps
    validate_i3
fi

echo
# A kernel upgraded by this run leaves the running one without modules; anything
# netfilter-based (ufw, libvirt's NAT) stays broken until a reboot.
if [ ! -d "/usr/lib/modules/$(uname -r)" ]; then
    warn "reboot needed: kernel $(uname -r) is running but its modules are gone (it was upgraded)"
fi
if [ "$FAILED" = 1 ]; then
    warn "finished with errors (see the warnings above)"
    exit 1
fi
echo "Done. Log into the i3 session, or reload with \$mod+Shift+Ctrl+Mod1+c (i3-msg reload)."
