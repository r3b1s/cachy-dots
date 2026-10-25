#!/usr/bin/env bash
# Opt-in installer for Sunshine (https://github.com/LizardByte/Sunshine):
# a self-hosted GameStream host for Moonlight.
#
# Tailored strictly to the two supported distributions:
#   - CachyOS: installs strictly from `cachyos/sunshine` (no fallbacks).
#   - Arch Linux: adds LizardByte's official pacman repo and installs strictly
#     from `lizardbyte/sunshine` (no fallbacks).
#
# Systemd User Service:
#   Installs ~/.config/systemd/user/sunshine.service (WantedBy=default.target)
#   so Sunshine automatically starts upon graphical session login (i3 or Hyprland).
#   The session's autostart (05-autostart.conf or cachy.lua) updates the
#   activation environment and runs `systemctl --user try-restart sunshine.service`,
#   ensuring Sunshine connects to the active session and matches the capture
#   method (x11 or wlr) configured by cachy-session.
#
# Usage: opt/services/sunshine/install.sh [--remove] [-n|--dry-run] [-h|--help]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACMAN_CONF="/etc/pacman.conf"
BEGIN='# >>> cachy-dots lizardbyte >>>'
END='# <<< cachy-dots lizardbyte <<<'

say()  { printf '\033[1;34m::\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
run()  { if [ "$dry" = 1 ]; then echo "+ $*"; else "$@"; fi; }

SUDO=
[ "$(id -u)" -ne 0 ] && SUDO=sudo

remove=0
dry=0

for arg in "$@"; do
    case "$arg" in
        --remove)     remove=1 ;;
        -n|--dry-run) dry=1 ;;
        -h|--help)    sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

command -v pacman >/dev/null || { echo "pacman not found: this is for Arch/CachyOS systems" >&2; exit 1; }

# Distro check: CachyOS vs Arch Linux
is_cachyos=0
if grep -qx 'ID=cachyos' /etc/os-release 2>/dev/null || pacman-conf --repo-list 2>/dev/null | grep -qx 'cachyos'; then
    is_cachyos=1
fi

user_service_dst="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/sunshine.service"

# -----------------------------------------------------------------------------
# Removal
# -----------------------------------------------------------------------------
if [ "$remove" = 1 ]; then
    say "Disabling and removing Sunshine systemd user service..."
    if command -v systemctl >/dev/null 2>&1; then
        run systemctl --user disable --now sunshine.service 2>/dev/null || true
    fi
    if [ -f "$user_service_dst" ]; then
        run rm -f "$user_service_dst"
        [ command -v systemctl >/dev/null 2>&1 ] && run systemctl --user daemon-reload 2>/dev/null || true
    fi

    if pacman -Qq sunshine >/dev/null 2>&1; then
        say "Removing sunshine package..."
        run $SUDO pacman -Rns --noconfirm sunshine
    fi

    # Remove LizardByte repo on Arch if present
    if grep -qxF "$BEGIN" "$PACMAN_CONF" 2>/dev/null; then
        say "Removing [lizardbyte] repository from $PACMAN_CONF..."
        if [ "$dry" = 1 ]; then
            echo "+ delete $BEGIN block from $PACMAN_CONF"
        else
            $SUDO cp -a "$PACMAN_CONF" "$PACMAN_CONF.bak.$(date +%s)"
            $SUDO sed -i "\|^$BEGIN\$|,\|^$END\$|d" "$PACMAN_CONF"
            $SUDO sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$PACMAN_CONF"
        fi
        dbpath=$(pacman-conf DBPath 2>/dev/null || echo /var/lib/pacman/)
        run $SUDO rm -f "${dbpath%/}/sync/lizardbyte.db"
    fi

    say "Sunshine uninstalled successfully."
    exit 0
fi

# -----------------------------------------------------------------------------
# Installation
# -----------------------------------------------------------------------------
if [ "$is_cachyos" = 1 ]; then
    say "Detected CachyOS: installing exclusively from 'cachyos/sunshine'..."
    if ! pacman-conf --repo-list 2>/dev/null | grep -qx 'cachyos'; then
        warn "cachyos repository not found in $PACMAN_CONF; refusing to fall back"
        exit 1
    fi
    run $SUDO pacman -S --needed --noconfirm cachyos/sunshine
else
    say "Detected vanilla Arch Linux: configuring LizardByte's official pacman repository..."
    repo_listed=0
    pacman-conf --repo-list 2>/dev/null | grep -qx 'lizardbyte' && repo_listed=1

    if [ "$repo_listed" = 0 ]; then
        say "Adding [lizardbyte] repository to $PACMAN_CONF"
        if [ "$dry" = 1 ]; then
            echo "+ append [lizardbyte] to $PACMAN_CONF"
        else
            $SUDO cp -a "$PACMAN_CONF" "$PACMAN_CONF.bak.$(date +%s)"
            printf '\n%s\n[lizardbyte]\nSigLevel = Optional\nServer = https://github.com/LizardByte/pacman-repo/releases/latest/download\n%s\n' \
                "$BEGIN" "$END" | $SUDO tee -a "$PACMAN_CONF" >/dev/null
        fi
    fi

    # Sync lizardbyte repository database
    dbpath=$(pacman-conf DBPath 2>/dev/null || echo /var/lib/pacman/)
    if [ ! -f "${dbpath%/}/sync/lizardbyte.db" ]; then
        say "Fetching lizardbyte repository sync database..."
        if [ "$dry" = 1 ]; then
            echo "+ sudo pacman --config <[lizardbyte] alone> -Sy"
        else
            conf=$(mktemp)
            trap 'rm -f "$conf"' EXIT
            printf '[options]\nDBPath = %s\nArchitecture = auto\nSigLevel = Optional\n\n[lizardbyte]\nServer = https://github.com/LizardByte/pacman-repo/releases/latest/download\n' \
                "$dbpath" > "$conf"
            $SUDO pacman --config "$conf" -Sy
        fi
    fi

    say "Installing exclusively from 'lizardbyte/sunshine'..."
    run $SUDO pacman -S --needed --noconfirm lizardbyte/sunshine
fi

# Ensure uinput kernel module is loaded for virtual gamepad/input emulation
if command -v modprobe >/dev/null 2>&1; then
    run $SUDO modprobe uinput 2>/dev/null || true
fi

# -----------------------------------------------------------------------------
# Systemd User Service Setup
# -----------------------------------------------------------------------------
say "Setting up systemd user service..."
run mkdir -p "$(dirname "$user_service_dst")"
run cp "$SCRIPT_DIR/sunshine.service" "$user_service_dst"

if command -v systemctl >/dev/null 2>&1; then
    run systemctl --user daemon-reload
    run systemctl --user enable sunshine.service
fi

# -----------------------------------------------------------------------------
# Initial Config: capture method follows active session
# -----------------------------------------------------------------------------
conf="${XDG_CONFIG_HOME:-$HOME/.config}/sunshine/sunshine.conf"
if [ ! -f "$conf" ]; then
    session="i3"
    session_file="${XDG_CONFIG_HOME:-$HOME/.config}/cachy-dots/session"
    [ -f "$session_file" ] && session=$(cat "$session_file" 2>/dev/null || echo "i3")
    want="x11"
    [ "$session" = "hyprland" ] && want="wlr"
    say "Initializing $conf with capture = $want"
    if [ "$dry" = 1 ]; then
        echo "+ write capture = $want to $conf"
    else
        mkdir -p "$(dirname "$conf")"
        echo "capture = $want" > "$conf"
    fi
fi

say "Sunshine setup complete!"
echo "  - Sunshine will start automatically upon graphical login."
echo "  - Session capture method (x11 for i3, wlr for Hyprland) is managed by cachy-session."
echo "  - Web UI: https://localhost:47990"
