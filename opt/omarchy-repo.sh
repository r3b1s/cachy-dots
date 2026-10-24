#!/usr/bin/env bash
# Opt in to Omarchy's package repo (https://pkgs.omarchy.org), so its prebuilt
# packages can be installed with pacman. Not part of the default install.
#
# What it does (once; a re-run changes nothing):
#   1. trusts Omarchy's package signing key (fetched by its full fingerprint from
#      keys.openpgp.org, then locally signed: pacman-key --lsign-key)
#   2. appends [omarchy] to the END of /etc/pacman.conf, below the Cachy and Arch
#      repos and chaotic-aur, with SigLevel = Required DatabaseOptional (every
#      package must carry a signature from that key; the database itself is not
#      signed upstream). A backup of pacman.conf is kept next to it
#   3. fetches the new repo's sync database, and only that one: no system upgrade,
#      and the other repos' databases are left as they are (pacman -Sy would
#      refresh them all, which is a partial upgrade once something is installed)
#
# It installs no package. Take packages from it by qualified name, e.g.
# `sudo pacman -S omarchy/libretro-database-git`, never by plain name:
#   * Omarchy's repo carries 240-odd packages, some with the names of Arch's own
#     (quickshell, ghostty, ...) and of chaotic-aur's (yay, yaru-icon-theme, ...).
#     Last in pacman.conf it never shadows either, but only a qualified name is
#     sure to come from it.
#   * Trusting the key means anything in that repo can be installed as root.
#
# Channel: stable (default), rc or edge, as Omarchy's own pacman.conf uses.
#
# --remove drops the [omarchy] block and its sync database. Installed packages stay
# (those the repo also carries are listed first, pacman not recording where each came from); the key stays too, and
# `sudo pacman-key --delete 40DFB630FF42BCFFB047046CF0134EE680CAC571` removes it.
#
# Usage: opt/omarchy-repo.sh [--channel stable|rc|edge] [--remove] [-n|--dry-run]
set -euo pipefail

KEY=40DFB630FF42BCFFB047046CF0134EE680CAC571
KEYSERVER=keys.openpgp.org
PACMAN_CONF=/etc/pacman.conf
BEGIN='# >>> cachy-dots omarchy >>>'
END='# <<< cachy-dots omarchy <<<'

channel=stable
remove=0
dry=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --channel)    channel=${2:-}; shift ;;
        --remove)     remove=1 ;;
        -n|--dry-run) dry=1 ;;
        -h|--help)    sed -n '2,31p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done
case "$channel" in stable|rc|edge) ;; *) echo "unknown channel: $channel" >&2; exit 2 ;; esac

say()  { printf '\033[1;34m::\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
run()  { if [ "$dry" = 1 ]; then echo "+ $*"; else "$@"; fi; }

SUDO=
[ "$(id -u)" -ne 0 ] && SUDO=sudo

command -v pacman >/dev/null || { echo "pacman not found: this is for Arch-based systems" >&2; exit 1; }

# Our own block, whatever its channel, or a hand-written [omarchy] section.
ours=0
grep -qxF "$BEGIN" "$PACMAN_CONF" && ours=1
listed=0
pacman-conf --repo-list 2>/dev/null | grep -qx omarchy && listed=1

if [ "$remove" = 1 ]; then
    if [ "$listed" = 1 ]; then
        held=$(pacman -Sl omarchy 2>/dev/null | awk '/\[installed\]/ {print $2}' | paste -sd' ')
        [ -z "$held" ] || warn "installed, and also carried by [omarchy] (some may have come from elsewhere; pacman does not record the repo), left in place: $held"
    fi
    if [ "$ours" = 1 ]; then
        say "Removing [omarchy] from $PACMAN_CONF"
        if [ "$dry" = 1 ]; then
            echo "+ delete the $BEGIN block from $PACMAN_CONF"
        else
            $SUDO cp -a "$PACMAN_CONF" "$PACMAN_CONF.bak.$(date +%s)"
            $SUDO sed -i "\|^$BEGIN\$|,\|^$END\$|d" "$PACMAN_CONF"
            # The blank line the block was appended after.
            $SUDO sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$PACMAN_CONF"
        fi
    elif [ "$listed" = 1 ]; then
        warn "[omarchy] in $PACMAN_CONF was not added by this script; left alone"
    fi
    run $SUDO rm -f "$(pacman-conf DBPath 2>/dev/null || echo /var/lib/pacman/)sync/omarchy.db"
    echo "Omarchy's repo is off."
    exit 0
fi

if [ "$(uname -m)" != x86_64 ]; then
    warn "$(uname -m): this script is only checked on x86_64"
fi

# Trust the key. recv-keys by full fingerprint; gpg refuses a key that does not match it.
if ! $SUDO pacman-key --list-keys "$KEY" >/dev/null 2>&1; then
    say "Trusting Omarchy's signing key $KEY"
    run $SUDO pacman-key --recv-keys "$KEY" --keyserver "$KEYSERVER" \
        && run $SUDO pacman-key --lsign-key "$KEY" \
        || { warn "could not import the key from $KEYSERVER"; exit 1; }
fi

if [ "$listed" = 1 ] && [ "$ours" = 0 ]; then
    warn "an [omarchy] repo is already in pacman.conf (not ours); leaving it as it is"
elif [ "$listed" = 0 ]; then
    say "Adding [omarchy] ($channel) to the end of $PACMAN_CONF"
    if [ "$dry" = 1 ]; then
        echo "+ append [omarchy], Server = https://pkgs.omarchy.org/$channel/\$arch to $PACMAN_CONF"
    else
        $SUDO cp -a "$PACMAN_CONF" "$PACMAN_CONF.bak.$(date +%s)"
        printf '\n%s\n[omarchy]\nSigLevel = Required DatabaseOptional\nServer = https://pkgs.omarchy.org/%s/$arch\n%s\n' \
            "$BEGIN" "$channel" "$END" | $SUDO tee -a "$PACMAN_CONF" >/dev/null
    fi
elif [ "$ours" = 1 ] && ! grep -qF "pkgs.omarchy.org/$channel/" "$PACMAN_CONF"; then
    warn "[omarchy] is on another channel; --remove, then run this again to switch"
fi

# A repo added just now has no database. Refresh that one alone: pacman -Sy with a
# config that lists only [omarchy] (same DBPath, so the file lands where the real
# config looks) leaves every other sync database untouched. No -u, no upgrade.
dbpath=$(pacman-conf DBPath 2>/dev/null || echo /var/lib/pacman/)
if [ ! -f "${dbpath%/}/sync/omarchy.db" ]; then
    say "Fetching the omarchy database (only that one; nothing is upgraded)"
    if [ "$dry" = 1 ]; then
        echo "+ sudo pacman --config <[omarchy] alone> -Sy"
    else
        conf=$(mktemp)
        trap 'rm -f "$conf"' EXIT
        printf '[options]\nDBPath = %s\nArchitecture = auto\nSigLevel = Required DatabaseOptional\n\n[omarchy]\nServer = https://pkgs.omarchy.org/%s/$arch\n' \
            "$dbpath" "$channel" > "$conf"
        $SUDO pacman --config "$conf" -Sy
    fi
fi

last=$(pacman-conf --repo-list 2>/dev/null | tail -n1 || true)
[ "$dry" = 1 ] || [ "$last" = omarchy ] || warn "[omarchy] is not the last repo (it is $last): check $PACMAN_CONF"
echo "Omarchy's repo is on (last in $PACMAN_CONF). Install from it by qualified name, e.g."
echo "  sudo pacman -S omarchy/libretro-database-git"
echo "(-S resolves dependencies against the other repos' databases as they are: run your own -Syu first if they are stale.)"
