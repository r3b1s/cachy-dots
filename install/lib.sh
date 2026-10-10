#!/usr/bin/env bash
# Loads the installer's modules. The entry scripts (install.sh, install_vm.sh) and
# sync.sh source this after setting PROFILE; it defines functions and package lists
# and runs nothing.
#
#   common.sh    helpers, argument parsing, profile handling
#   packages.sh  package lists
#   repos.sh     CachyOS repo check, chaotic-aur
#   pacman.sh    the pacman transaction, AUR builds, the Qt 6 stack
#   system.sh    login shell, ly, nix, services, firewall, touchpad, keyring
#   browsers.sh  Firefox and Chromium policies, default applications
#   theme.sh     root helpers, GTK, dark mode, the first theme
#   links.sh     symlinks into ~/.config and ~/.local/bin
#   voxtype.sh   the speech model
#   flow.sh      install_main: the steps, in order, for the profile
#   profile-<name>.sh   what a profile leaves out

REPO=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

PROFILE=${PROFILE:-workstation}
[ -r "$REPO/install/profile-$PROFILE.sh" ] || { echo "unknown profile: $PROFILE" >&2; exit 2; }

# shellcheck source=install/common.sh
. "$REPO/install/common.sh"
# shellcheck disable=SC1090
. "$REPO/install/profile-$PROFILE.sh"
for _m in packages repos pacman system browsers theme links voxtype flow; do
    # shellcheck disable=SC1090
    . "$REPO/install/$_m.sh"
done
unset _m
