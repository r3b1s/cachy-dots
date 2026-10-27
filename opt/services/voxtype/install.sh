#!/usr/bin/env bash
# Opt in to voxtype, push-to-talk dictation ($mod+d in both sessions, through
# bin/dictate). Not part of the default install: voxtype-bin is in no pacman
# repo, so it is built from the AUR.
#
#   1. installs voxtype-bin: from a pacman repo if an enabled one has it,
#      otherwise built from the AUR with yay, as you (makepkg refuses root). Run
#      ./install.sh first: it installs yay. Later updates come with `yay -Syu`.
#   2. links config.toml (in this folder) to ~/.config/voxtype/config.toml;
#      a link to an older place is repointed.
#   3. downloads the speech model the config names (base.en) with `voxtype setup
#      --download`, when there is none. Needs network.
#   4. starts the daemon at login with `~/.local/bin/dictate daemon`, a line in
#      each session's per-host hook: ~/.config/i3/conf.d/06-services.conf and
#      ~/.config/hypr/cachy-services.lua. A voxtype line already in either is
#      replaced by it, and a file that already matches is left alone.
#
# The daemon starts at the next login. Run it as your own user: sudo is used
# for pacman.
#
#   --remove  stops the daemon, removes the hook lines, the config link and
#             voxtype-bin. The models in ~/.local/share/voxtype are kept.
#
# Usage: opt/services/voxtype/install.sh [--remove] [-n|--dry-run] [-h|--help]
set -euo pipefail

HERE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)

remove=0
dry=0
for arg in "$@"; do
    case "$arg" in
        --remove)     remove=1 ;;
        -n|--dry-run) dry=1 ;;
        -h|--help)    awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; exit 0 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

say()  { printf '\033[1;34m::\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
run()  { if [ "$dry" = 1 ]; then echo "+ $*"; else "$@"; fi; }

[ "$(id -u)" -ne 0 ] || die "run this as your own user: the hooks and the config are in your home"
command -v pacman >/dev/null || die "pacman not found: this is for Arch/CachyOS systems"

cfg="${XDG_CONFIG_HOME:-$HOME/.config}"
config_src="$HERE/config.toml"
config_dst="$cfg/voxtype/config.toml"

# Signing keys voxtype-bin's sources are verified with (validpgpkeys in its
# PKGBUILD), imported best effort before the build.
AUR_KEYS=(E79F5BAF8CD51A806AA27DBB7DA2709247D75BC6 9CCF7915B750CAE8B095ED1AA3FC9F33FD209279)

# The session hooks, and their first lines when this script creates them (the
# same as opt/services/sunshine/install.sh writes).
i3_hook="$cfg/i3/conf.d/06-services.conf"
i3_header='# Opt-in service autostarts (managed by opt/services/*)'
i3_line='exec --no-startup-id ~/.local/bin/dictate daemon'
hypr_hook="$cfg/hypr/cachy-services.lua"
hypr_header='-- Opt-in service autostarts (managed by opt/services/*)
-- Sourced by ~/.config/hypr/cachy.lua during hyprland.start'
hypr_line='hl.exec_cmd("~/.local/bin/dictate daemon")'
# Lines that start the daemon: this script's, and the inline command that an
# earlier install/voxtype.sh wrote.
ours='dictate daemon|voxtype -q daemon'

# set_hook FILE HEADER [LINE]: makes FILE hold no line of ours but LINE (when
# given), as its last line. Writes only when that changes the file; a file left
# with nothing but comments is removed.
set_hook() {
    local file=$1 header=$2 line=${3:-} tmp
    [ -f "$file" ] || [ -n "$line" ] || return 0
    tmp=$(mktemp)
    {
        if [ -f "$file" ]; then grep -vE "$ours" "$file" || true; else printf '%s\n' "$header"; fi
        [ -z "$line" ] || printf '%s\n' "$line"
    } > "$tmp"
    if [ -f "$file" ] && cmp -s "$tmp" "$file"; then
        rm -f "$tmp"
        return 0
    fi
    if ! grep -qvE '^[[:space:]]*((#|--).*)?$' "$tmp"; then
        rm -f "$tmp"
        run rm -f "$file"
        echo "removed $file (nothing left in it)"
        return 0
    fi
    if [ "$dry" = 1 ]; then
        rm -f "$tmp"
        echo "+ write $file"
        return 0
    fi
    mkdir -p "$(dirname "$file")"
    cat "$tmp" > "$file"
    rm -f "$tmp"
    echo "updated $file"
}

# hypr/cachy.lua is copied to a host once and never overwritten, and copies made
# before voxtype was opt-in start the daemon themselves. That line races this
# one at login (both kill the other's daemon, or the first takes voxtype's lock
# before there is a sound output), and only the host's owner may edit the copy.
check_host_cachy_lua() {
    if grep -qF 'voxtype -q daemon' "$cfg/hypr/cachy.lua" 2>/dev/null; then
        warn "$cfg/hypr/cachy.lua starts voxtype itself (an older copy of hypr/cachy.lua): delete its voxtype hl.exec_cmd line"
    fi
}

if [ "$remove" = 1 ]; then
    say "Removing voxtype"
    pgrep -x -u "$(id -u)" voxtype >/dev/null && run pkill -x -u "$(id -u)" voxtype
    set_hook "$i3_hook" "$i3_header"
    set_hook "$hypr_hook" "$hypr_header"
    if [ "$(readlink "$config_dst" 2>/dev/null)" = "$config_src" ]; then
        run rm "$config_dst"
        echo "removed the link $config_dst"
    fi
    if pacman -Qq voxtype-bin >/dev/null 2>&1; then
        run sudo pacman -Rns --noconfirm voxtype-bin
    fi
    check_host_cachy_lua
    say "Done. The speech models in ${XDG_DATA_HOME:-$HOME/.local/share}/voxtype are kept."
    exit 0
fi

# ── the package ───────────────────────────────────────────────────────────────

if pacman -Qq voxtype-bin >/dev/null 2>&1; then
    say "$(pacman -Q voxtype-bin) is installed. yay -Syu updates it."
elif pacman -Si voxtype-bin >/dev/null 2>&1; then
    # A full -Syu, as install.sh does: -Sy alone would be a partial upgrade.
    say "Installing voxtype-bin from a pacman repo (pacman -Syu, a full sync)"
    run sudo pacman -Syu --needed --noconfirm voxtype-bin || die "could not install voxtype-bin"
else
    command -v yay >/dev/null || [ "$dry" = 1 ] || die "no yay, so voxtype-bin cannot be built from the AUR (run ./install.sh first: it installs yay)"
    say "Building voxtype-bin from the AUR with yay"
    if [ "$dry" = 1 ]; then
        echo "+ gpg --recv-keys ${AUR_KEYS[*]}"
    else
        for key in "${AUR_KEYS[@]}"; do
            gpg --quiet --keyserver hkps://keyserver.ubuntu.com --recv-keys "$key" >/dev/null 2>&1 || true
        done
    fi
    run yay -S --needed --noconfirm --answerclean None --answerdiff None voxtype-bin \
        || die "could not build voxtype-bin from the AUR"
fi

# ── the config ────────────────────────────────────────────────────────────────

if [ "$(readlink "$config_dst" 2>/dev/null)" != "$config_src" ]; then
    run mkdir -p "$(dirname "$config_dst")"
    if [ -e "$config_dst" ] && [ ! -L "$config_dst" ]; then
        backup="$config_dst.bak.$(date +%s)"
        run mv "$config_dst" "$backup"
        echo "backed up $config_dst -> $backup"
    fi
    run ln -sfn "$config_src" "$config_dst"
    echo "linked $config_dst -> $config_src"
fi

# ── the speech model ──────────────────────────────────────────────────────────

if ! ls "${XDG_DATA_HOME:-$HOME/.local/share}"/voxtype/models/*.bin >/dev/null 2>&1; then
    say "Downloading the speech model (base.en)"
    run voxtype setup --download || warn "the model download failed; run: voxtype setup --download"
fi

# ── the session hooks ─────────────────────────────────────────────────────────

set_hook "$i3_hook" "$i3_header" "$i3_line"
set_hook "$hypr_hook" "$hypr_header" "$hypr_line"
[ -x "$HOME/.local/bin/dictate" ] || warn "$HOME/.local/bin/dictate is missing: run ./sync.sh to link bin/"
check_host_cachy_lua

say "Done. The daemon starts at the next login."
