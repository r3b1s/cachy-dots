#!/usr/bin/env bash
# Opt in: arch-cloud-vm.sh, plus a graphical console and the dots. A libvirt VM
# from the official Arch Linux cloud image, provisioned by cloud-init on the
# labbr0 lab network (run opt/virt.sh first), which then installs this repo:
#
#   - everything arch-cloud-vm.sh does: the verified image, a qcow2 overlay, a
#     random password for sudo and the console, key-only SSH, UEFI, labbr0;
#   - a SPICE display (virtio GPU, spice-vdagent channel, tablet) for
#     virt-manager and virt-viewer, and the qemu-guest-agent channel;
#   - on first boot, as the user: mkdir ~/Dotfiles, git clone
#     https://github.com/r3b1s/cachy-dots into it, and run ./install_vm.sh.
#
# The install runs inside cloud-init (cloud-final), after the VM has an address,
# and takes a while: a full upgrade, then the packages. It has no terminal, so
# sudo is passwordless only for its duration (a sudoers drop-in removed at the
# end; --nopasswd keeps it for good through cloud-init). Follow it, and find its exit status, with
#   ssh USER@ADDRESS tail -f /var/log/dots-provision.log
# and reboot afterwards: the upgrade may bring a kernel the running one lacks,
# and ly (the login screen) starts on the next boot.
#
# The steps shared with arch-cloud-vm.sh are in arch-cloud-vm-lib.sh.
#
# Usage: opt/arch-cloud-vm-dots.sh [--name NAME] [--user USER] [--memory MiB]
#                                  [--vcpus N] [--disk SIZE] [--replace]
#                                  [--nopasswd] [--ssh-key PUBKEY]
#                                  [--repo URL] [--no-install]
#
# --ssh-key takes the path of a public key file (or the key itself) to put in
# the user's authorized_keys. Nothing is generated then, and the key's private
# half is never read. Without it, ~/.ssh/arch-cloud-<name>-ed25519 is generated.
# --nopasswd keeps passwordless sudo (cloud-init `NOPASSWD:ALL`) for good.
# --repo clones another URL (a fork or a branch's remote) instead of r3b1s's.
# --no-install clones but does not run install_vm.sh.
# Defaults are larger than arch-cloud-vm.sh's (6144 MiB, 4 vCPUs, 30G): the
# install adds browsers, Obsidian and the AUR build.
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/arch-cloud-vm-lib.sh"

# This script's own defaults: the install adds browsers, Obsidian and an AUR build.
NAME=dots-vm
MEMORY=6144
VCPUS=4
DISK=30G
REPO=https://github.com/r3b1s/cachy-dots
INSTALL=1

while [ $# -gt 0 ]; do
    case "$1" in
        --repo)       REPO=${2:?--repo needs a value}; shift ;;
        --no-install) INSTALL=0 ;;
        -h|--help)    acv_help "$0" ;;
        *) acv_option "$@" || die "unknown option: $1"; shift $((ACV_USED - 1)) ;;
    esac
    shift
done

[[ $REPO =~ ^(https://|git@|ssh://)[A-Za-z0-9._~:/@+-]+$ ]] || die "--repo is not a plain git URL"

acv_check
acv_image
acv_credentials

# The first-boot job, run by cloud-init as root. The values come first (quoted
# by printf %q), the body is a quoted heredoc so nothing in it expands here.
PROVISION=$({
    printf 'USER_NAME=%q\nREPO=%q\nINSTALL=%q\n' "$USER_NAME" "$REPO" "$INSTALL"
    cat <<'PROVISION'
LOG=/var/log/dots-provision.log
DROPIN=/etc/sudoers.d/90-dots-provision
exec >>"$LOG" 2>&1
set -x
status=0
trap 'rm -f "$DROPIN"; echo "$status" > /var/lib/dots-provision.status; echo "dots-provision finished, status $status"' EXIT

# Nobody can type a sudo password here. Removed again on exit; with --nopasswd
# cloud-init's own sudoers file for the user stays.
printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$USER_NAME" > "$DROPIN"
chmod 0440 "$DROPIN"

# The keyring is initialised by a oneshot that may still be running.
systemctl start pacman-init.service || true
# The image has no git, and a bare -Sy then -S would be a partial upgrade.
for try in 1 2 3; do
    pacman -Syu --noconfirm --needed git && break
    sleep 10
done
command -v git >/dev/null || { status=1; exit; }

home=$(getent passwd "$USER_NAME" | cut -d: -f6)
for try in 1 2 3 4 5; do
    runuser -u "$USER_NAME" -- sh -c 'mkdir -p "$1/Dotfiles" && cd "$1/Dotfiles" && { [ -d cachy-dots ] || git clone "$2" cachy-dots; }' _ "$home" "$REPO" && break
    sleep 10
done
[ -d "$home/Dotfiles/cachy-dots/.git" ] || { status=1; exit; }

if [ "$INSTALL" = 1 ]; then
    runuser -l "$USER_NAME" -c 'cd ~/Dotfiles/cachy-dots && ./install_vm.sh' || status=$?
fi
exit "$status"
PROVISION
})
PROVISION_B64=$(printf '%s\n' "$PROVISION" | base64 -w0)

ACV_USERDATA_EXTRA="write_files:
  - path: /usr/local/sbin/dots-provision
    permissions: '0755'
    encoding: b64
    content: $PROVISION_B64
runcmd:
  - [/usr/local/sbin/dots-provision]"
ACV_DEVICES_EXTRA="    <graphics type='spice'>
      <listen type='none'/>
      <image compression='off'/>
      <gl enable='no'/>
    </graphics>
    <video>
      <model type='virtio' heads='1' primary='yes'/>
    </video>
    <input type='tablet' bus='usb'/>
    <channel type='spicevmc'>
      <target type='virtio' name='com.redhat.spice.0'/>
    </channel>
    <channel type='unix'>
      <target type='virtio' name='org.qemu.guest_agent.0'/>
    </channel>"

acv_seed
acv_domain

acv_report_extra() {
    echo "Display:   virt-manager --connect qemu:///system --show-domain-console $NAME"
    if [ "$INSTALL" = 1 ]; then
        echo "Install:   running inside the VM as $USER_NAME once cloud-init gets there (~/Dotfiles/cachy-dots, ./install_vm.sh)"
    else
        echo "Install:   skipped (--no-install); the repo is cloned to ~/Dotfiles/cachy-dots"
    fi
    echo "Progress:  ssh ${USER_NAME}@${ip:-<address>} tail -f /var/log/dots-provision.log   (status in /var/lib/dots-provision.status)"
}
acv_report
