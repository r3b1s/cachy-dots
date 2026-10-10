#!/usr/bin/env bash
# cachy-dots installer, vm profile: a lean desktop for a throwaway guest. The same
# steps as install.sh, minus what a VM has no use for (Vesktop, rclone, bluetooth,
# backlight and power profiles, voxtype, the touchpad config...). The list is
# install/profile-vm.sh, and only that.
#
# Meant for a VM: the guest agents (spice-vdagent, qemu-guest-agent) go in
# whether or not systemd-detect-virt agrees. Everything else about the install is
# as install.sh describes, and sync.sh later follows the profile recorded here.
#
# Usage: ./install_vm.sh [--packages-only | --links-only] [-n|--dry-run]
set -euo pipefail

PROFILE=vm
. "$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/install/lib.sh"

parse_args "$0" "$@"
install_main
