#!/usr/bin/env bash
# Opt in: a libvirt VM from the official Arch Linux cloud image (arch-boxes),
# provisioned by cloud-init on the labbr0 lab network. Run opt/virt.sh first.
#
#   - downloads Arch-Linux-x86_64-cloudimg.qcow2 from pkgbuild's mirror and checks
#     it against the arch-boxes signing key (pinned below) and the published SHA256;
#   - generates an ed25519 key for the VM if it does not exist yet (passwordless
#     SSH, key only; password SSH is off), or imports the public key named by
#     --ssh-key instead, so that the same key can be reused across provisions;
#   - gives the user a random password for sudo and the console. It is printed
#     once and saved to ~/.config/arch-cloud-vm/<name>.password (mode 600);
#   - boots the VM with UEFI on labbr0 (DHCP from 10.40.40.100-254). The VM disk
#     is a qcow2 overlay on the verified base image, which is never written to.
#
# The image has no users of its own; cloud-init creates the user below.
# The steps shared with arch-cloud-vm-dots.sh are in arch-cloud-vm-lib.sh.
# Usage: opt/arch-cloud-vm.sh [--name NAME] [--user USER] [--memory MiB] [--vcpus N]
#                             [--disk SIZE] [--replace] [--nopasswd]
#                             [--ssh-key PUBKEY]
#
# --ssh-key takes the path of a public key file (or the key itself) to put in
# the user's authorized_keys. Nothing is generated then, and the key's private
# half is never read. Without it, ~/.ssh/arch-cloud-<name>-ed25519 is generated.
#
# --nopasswd gives the user passwordless sudo (cloud-init `NOPASSWD:ALL`), for a
# throwaway test VM driven over ssh, where nobody can type the sudo password.
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/arch-cloud-vm-lib.sh"

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) acv_help "$0" ;;
        *) acv_option "$@" || die "unknown option: $1"; shift $((ACV_USED - 1)) ;;
    esac
    shift
done

acv_check
acv_image
acv_credentials
acv_seed
acv_domain
acv_report
