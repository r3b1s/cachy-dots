#!/usr/bin/env bash
# cachy-dots installer for CachyOS (Arch-based): the workstation profile, the full
# install. install_vm.sh is the lean one for a guest.
#
#   1. checks the CachyOS repos, adds chaotic-aur (for qutebrowser-git only)
#   2. installs any missing packages (pacman; sudo is used when not root),
#      and the few that only the AUR has (voxtype-bin, through yay)
#   3. enables the guest-agent services, makes bash the login shell
#   4. symlinks the dots into ~/.config and ~/.local/bin
#   5. validates the i3 config
#
# Safe to re-run: installed packages are skipped, existing non-symlink targets
# are backed up, existing symlinks are replaced.
#
# Usage: ./install.sh [--packages-only | --links-only] [-n|--dry-run]
#
# The steps live in install/ (see install/lib.sh); this script only names the profile.
set -euo pipefail

PROFILE=workstation
. "$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/install/lib.sh"

parse_args "$0" "$@"
install_main
