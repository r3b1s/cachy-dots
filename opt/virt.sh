#!/usr/bin/env bash
# Opt in to libvirt for virt-manager. Not part of install.sh: run it on purpose,
# on bare metal or nested inside a VM (which needs /dev/kvm passed through).
#
#   qemu:///system   the root daemons, socket-activated (virtqemud, virtnetworkd,
#                    virtstoraged). Provides the NAT network `labbr0`
#                    (10.40.40.0/24, gateway 10.40.40.1, DHCP .100-.254) and the
#                    `default` storage pool. Access is by the libvirt group, which
#                    is root-equivalent: the user running this is the only one added.
#   qemu:///session  nothing to set up. libvirt starts the user's own daemon on
#                    demand. Guests get user-mode networking only: no raw packets,
#                    no ICMP, and the host reaches a guest only through port forwards.
#
# The packaged configs leave the socket group commented out, which makes the
# sockets root-only, so it is set here. ufw's default forward policy drops
# forwarded traffic, so labbr0 gets `ufw route` rules, or its guests cannot leave
# the host. The default network is not defined: labbr0 is the lab network.
#
# Usage: opt/virt.sh [-n|--dry-run]
set -euo pipefail

LAB_NET=labbr0
LAB_XML='<network>
  <name>labbr0</name>
  <bridge name="labbr0" stp="on" delay="0"/>
  <forward mode="nat"/>
  <ip address="10.40.40.1" netmask="255.255.255.0">
    <dhcp>
      <range start="10.40.40.100" end="10.40.40.254"/>
    </dhcp>
  </ip>
</network>'

dry=0
for arg in "$@"; do
    case "$arg" in
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
TARGET_USER="${SUDO_USER:-${USER:-$(id -un)}}"

# virsh against the system daemons. Read-only queries run too, even in a dry run.
vsys() { $SUDO virsh -c qemu:///system "$@"; }

PKGS=(libvirt qemu-desktop virt-manager virt-viewer dnsmasq edk2-ovmf swtpm)
missing=()
for p in "${PKGS[@]}"; do
    pacman -Qq "$p" >/dev/null 2>&1 || missing+=("$p")
done
if [ "${#missing[@]}" -gt 0 ]; then
    # Sync before -S: a stale database asks for package files the mirror has replaced.
    say "Installing: ${missing[*]}"
    run $SUDO pacman -Syu --noconfirm
    run $SUDO pacman -S --needed --noconfirm "${missing[@]}"
fi

say "Socket group and sockets"
restart=()
for conf in virtqemud virtnetworkd virtstoraged; do
    if $SUDO grep -q '^#unix_sock_group = "libvirt"' "/etc/libvirt/$conf.conf"; then
        run $SUDO sed -i 's/^#unix_sock_group = "libvirt"/unix_sock_group = "libvirt"/' "/etc/libvirt/$conf.conf"
        restart+=("$conf.service")
    fi
done
if [ "${#restart[@]}" -gt 0 ]; then
    run $SUDO systemctl try-restart "${restart[@]}"
fi
run $SUDO systemctl enable --now virtqemud.socket virtnetworkd.socket virtstoraged.socket

say "Network $LAB_NET (10.40.40.0/24)"
if ! vsys net-info "$LAB_NET" >/dev/null 2>&1; then
    xml=$(mktemp)
    trap 'rm -f "$xml"' EXIT
    printf '%s\n' "$LAB_XML" > "$xml"
    run vsys net-define "$xml"
fi
run vsys net-autostart "$LAB_NET"
if [ "$(vsys net-info "$LAB_NET" 2>/dev/null | awk '/^Active:/ { print $2 }')" != yes ]; then
    run vsys net-start "$LAB_NET"
fi

say "Storage pool default"
if ! vsys pool-info default >/dev/null 2>&1; then
    run vsys pool-define-as default dir --target /var/lib/libvirt/images
    run vsys pool-build default
fi
run vsys pool-autostart default
if [ "$(vsys pool-info default 2>/dev/null | awk '/^State:/ { print $2 }')" != running ]; then
    run vsys pool-start default
fi

if command -v ufw >/dev/null; then
    say "ufw: forward $LAB_NET traffic"
    run $SUDO ufw route allow in on "$LAB_NET"
    run $SUDO ufw route allow out on "$LAB_NET"
fi

if getent group libvirt >/dev/null; then
    if ! id -nG "$TARGET_USER" | tr ' ' '\n' | grep -qx libvirt; then
        say "Adding $TARGET_USER to the libvirt group (log out and back in)"
        run $SUDO usermod -aG libvirt "$TARGET_USER"
    fi
else
    warn "no libvirt group; the system connection stays root-only"
fi

echo
echo "Done. virt-manager: QEMU/KVM (system) uses $LAB_NET; QEMU/KVM User session needs nothing."
