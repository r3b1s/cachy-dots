#!/usr/bin/env bash
# Setup script for Paseo (https://paseo.sh) in cachy-dots.
#
# What it does:
#   1. installs @getpaseo/cli globally via mise using the npm backend
#   2. installs the systemd user service into ~/.config/systemd/user/paseo.service
#   3. reloads the systemd user daemon (systemctl --user daemon-reload)
#
# Note: This script intentionally does NOT enable or start the service.
# Detailed instructions for configuring Paseo and enabling the service
# are printed upon completion.
#
# Usage: opt/paseo/setup.sh [--remove] [-n|--dry-run] [-h|--help]
set -euo pipefail

HERE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)

dry=0
remove=0

for arg in "$@"; do
    case "$arg" in
        --remove)     remove=1 ;;
        -n|--dry-run) dry=1 ;;
        -h|--help)
            awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
            exit 0
            ;;
        *)
            echo "unknown option: $arg" >&2
            exit 2
            ;;
    esac
done

say()  { printf '\033[1;34m::\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
run()  { if [ "$dry" = 1 ]; then echo "+ $*"; else "$@"; fi; }

service_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
service_file="$service_dir/paseo.service"

# ── Removal ───────────────────────────────────────────────────────────────────

if [ "$remove" = 1 ]; then
    say "Removing Paseo systemd user service..."
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl --user is-active --quiet paseo 2>/dev/null; then
            say "Stopping running paseo.service..."
            run systemctl --user stop paseo
        fi
        if systemctl --user is-enabled --quiet paseo 2>/dev/null; then
            say "Disabling paseo.service..."
            run systemctl --user disable paseo
        fi
    fi

    if [ -f "$service_file" ]; then
        say "Removing $service_file..."
        run rm -f "$service_file"
    fi

    if command -v systemctl >/dev/null 2>&1; then
        say "Reloading systemd user daemon..."
        run systemctl --user daemon-reload
    fi

    if command -v mise >/dev/null 2>&1; then
        say "Removing @getpaseo/cli from global mise configuration..."
        run mise unuse -g npm:@getpaseo/cli 2>/dev/null || true
    fi

    say "Paseo service and global CLI registration removed."
    exit 0
fi

# ── Prerequisites ─────────────────────────────────────────────────────────────

command -v mise >/dev/null 2>&1 || die "mise is required to install Paseo via the npm backend. Install mise first."

# ── 1. Install CLI via mise (npm backend) ────────────────────────────────────

say "Installing @getpaseo/cli globally via mise (npm backend)..."
run mise use -g npm:@getpaseo/cli
run mise reshim 2>/dev/null || true

if [ "$dry" != 1 ]; then
    if ! mise exec -- paseo --version >/dev/null 2>&1; then
        warn "Could not verify paseo execution via mise exec. Ensure Node.js is configured in mise or available in PATH."
    else
        version=$(mise exec -- paseo --version)
        say "Paseo CLI v${version} installed successfully via mise."
    fi
fi

# ── 2. Install systemd user service ──────────────────────────────────────────

say "Installing systemd user service to $service_file..."
run mkdir -p "$service_dir"
run cp "$HERE/paseo.service" "$service_file"

# ── 3. Daemon reload ──────────────────────────────────────────────────────────

say "Reloading systemd user daemon..."
run systemctl --user daemon-reload

# ── Guidance ──────────────────────────────────────────────────────────────────

printf '\n'
printf '\033[1;32m✓ Paseo CLI installation and systemd user service setup complete!\033[0m\n\n'

printf '\033[1mConfiguration:\033[0m\n'
printf '  1. Run the interactive onboarding wizard to configure relay pairing, passwords, and voice:\n'
printf '     \033[1;36mpaseo onboard\033[0m\n'
printf '  2. Inspect or update daemon configuration:\n'
printf '     \033[1;36mpaseo daemon config\033[0m\n'
printf '  3. Config file location:\n'
printf '     \033[1m~/.paseo/config.json\033[0m\n'
printf '  4. Daemon log location:\n'
printf '     \033[1m~/.paseo/daemon.log\033[0m\n'
printf '  5. Self-hosted Web UI (enabled in service):\n'
printf '     \033[1;36mhttp://localhost:6767\033[0m\n\n'

printf '\033[1mService Management (systemd):\033[0m\n'
printf '  • Enable on boot/login and start now:\n'
printf '     \033[1;36msystemctl --user enable --now paseo\033[0m\n'
printf '  • Start the daemon without enabling autostart:\n'
printf '     \033[1;36msystemctl --user start paseo\033[0m\n'
printf '  • Check daemon service status:\n'
printf '     \033[1;36msystemctl --user status paseo\033[0m\n'
printf '  • View live daemon logs:\n'
printf '     \033[1;36mjournalctl --user -u paseo -f\033[0m\n'
printf '  • Stop the daemon:\n'
printf '     \033[1;36msystemctl --user stop paseo\033[0m\n'
printf '  • Disable autostart and stop immediately:\n'
printf '     \033[1;36msystemctl --user disable --now paseo\033[0m\n\n'

printf '\033[1mHeadless / Server Persist (Optional):\033[0m\n'
printf '  If you want the user service to keep running after logging out (or at boot without logging in):\n'
printf '     \033[1;36mloginctl enable-linger %s\033[0m\n\n' "$(id -un 2>/dev/null || echo '$USER')"
