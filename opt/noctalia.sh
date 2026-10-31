#!/usr/bin/env bash
# Opt in to Noctalia as the Hyprland session's shell: Hyprland, Noctalia, and what
# stands in for dux's own apps. Not part of the default install; i3 stays, and
# bin/graphical-session switches between the sessions. dux, if opt/hyprland.sh put it
# here, stays too: nothing of it is removed, and either shell can be picked.
#
# It installs by plain name (a Cachy build wins where one exists), after a full
# pacman -Syu. ly stays the login screen: both shells are its one "Hyprland" entry,
# and noctalia-greeter is not installed.
#
# It does not switch sessions: `graphical-session hyprland noctalia` does (and links
# noctalia/ into ~/.config/noctalia), then log out and pick Hyprland at the login
# screen.
#
# --remove uninstalls the noctalia package; everything else stays, its configuration
# and the packages it shares with dux and i3 among it. Run `graphical-session i3` or
# `graphical-session hyprland dux` first.
#
# Usage: opt/noctalia.sh [--remove] [-n|--dry-run]
set -euo pipefail

PKGS=(
    hyprland xdg-desktop-portal-hyprland
    hyprland-guiutils                # Hyprland's own dialogs (ANR, update notes)
    xorg-xwayland                    # X11 apps (ZAP, anything without Wayland support)
    noctalia                         # the shell
    nautilus                         # the file manager: $mod+e, folders, FileManager1
    xdg-desktop-portal-gtk           # open and save dialogs, the colour scheme
    btop                             # the system monitor: $mod+p
    hyprpicker                       # the colour picker
    wl-clipboard                     # wl-copy/wl-paste: voxtype, dictate, nvim, tmux
    wtype                            # dictate's paste keystroke
    ttf-firacode-nerd                # the terminals' font under Hyprland
    papirus-icon-theme               # the icon theme under Hyprland
)

remove=0
dry=0
for arg in "$@"; do
    case "$arg" in
        --remove)     remove=1 ;;
        -n|--dry-run) dry=1 ;;
        -h|--help)    sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

say()  { printf '\033[1;34m::\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
run()  { if [ "$dry" = 1 ]; then echo "+ $*"; else "$@"; fi; }

SUDO=
[ "$(id -u)" -ne 0 ] && SUDO=sudo
[ -n "$SUDO" ] || { warn "run opt/noctalia.sh as your own user (it uses sudo), not root"; exit 1; }

if [ "$remove" = 1 ]; then
    state="${XDG_STATE_HOME:-$HOME/.local/state}/graphical-session/hypr-shell"
    session="${XDG_CONFIG_HOME:-$HOME/.config}/cachy-dots/session"
    if [ "$(cat "$session" 2>/dev/null)" = hyprland ] && [ "$(cat "$state" 2>/dev/null)" = noctalia ]; then
        warn "Noctalia is the active session's shell: run graphical-session i3 first"
        exit 1
    fi
    if pacman -Qq noctalia >/dev/null 2>&1; then
        run $SUDO pacman -Rns --noconfirm noctalia
    fi
    exit 0
fi

missing=()
for p in "${PKGS[@]}"; do
    pacman -Qq "$p" >/dev/null 2>&1 || missing+=("$p")
done
if [ "${#missing[@]}" -gt 0 ]; then
    say "Installing ${missing[*]}"
    # A full upgrade first: -Sy followed by -S would be a partial upgrade.
    run $SUDO pacman -Syu --needed --noconfirm "${missing[@]}"
fi

echo
echo "Next: graphical-session hyprland noctalia, then log out and pick Hyprland at the login screen."
