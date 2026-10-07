#!/usr/bin/env bash
# Opt in to ble.sh (Bash Line Editor). Not part of the default install.
#
#   1. installs blesh-git from chaotic-aur (by qualified name; no other repo
#      packages it, and there is no fallback)
#   2. links shell/blerc -> ~/.blerc
#
# shell/init.sh loads /usr/share/blesh/ble.sh whenever it is installed, so
# nothing else is needed; open a new terminal. Run ./install.sh first: it is
# what adds the chaotic-aur repo.
#
# Opt back out with --remove: uninstalls blesh-git and removes the ~/.blerc link.
#
# Usage: opt/blesh.sh [--remove] [-n|--dry-run]
set -euo pipefail

REPO=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

remove=0
dry=0
for arg in "$@"; do
    case "$arg" in
        --remove)     remove=1 ;;
        -n|--dry-run) dry=1 ;;
        -h|--help)    sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

say()  { printf '\033[1;34m::\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
run()  { if [ "$dry" = 1 ]; then echo "+ $*"; else "$@"; fi; }

SUDO=
[ "$(id -u)" -ne 0 ] && SUDO=sudo

blerc="$HOME/.blerc"

if [ "$remove" = 1 ]; then
    if pacman -Qq blesh-git >/dev/null 2>&1; then
        say "Removing blesh-git"
        run $SUDO pacman -Rns --noconfirm blesh-git
    fi
    if [ -L "$blerc" ] && [ "$(readlink "$blerc")" = "$REPO/shell/blerc" ]; then
        run rm "$blerc"
        echo "removed the $blerc link"
    fi
    echo "ble.sh is off from the next shell."
    exit 0
fi

if ! pacman -Qq blesh-git >/dev/null 2>&1; then
    say "Installing blesh-git (chaotic-aur)"
    if ! pacman -Si chaotic-aur/blesh-git >/dev/null 2>&1; then
        warn "chaotic-aur/blesh-git is unavailable (run ./install.sh first: it adds chaotic-aur)."
        exit 1
    fi
    run $SUDO pacman -S --needed --noconfirm chaotic-aur/blesh-git
fi

if [ -e "$blerc" ] && [ ! -L "$blerc" ]; then
    backup="$blerc.bak.$(date +%s)"
    run mv "$blerc" "$backup"
    echo "backed up $blerc -> $backup"
fi
run ln -sfn "$REPO/shell/blerc" "$blerc"
echo "linked $blerc -> $REPO/shell/blerc"

echo "ble.sh is on from the next shell."
