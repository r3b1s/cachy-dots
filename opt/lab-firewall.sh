#!/usr/bin/env bash
# ufw rules for the labbr0 lab network (10.40.40.0/24, libvirt NAT). Sourced by
# opt/virt.sh and opt/arch-cloud-vm.sh; also runnable on its own:
#
#   opt/lab-firewall.sh [-n|--dry-run]
#
# libvirt builds the NAT itself (masquerade, plus its own accept rules, in its
# own nftables tables), but that does not get a guest past ufw: a packet has to
# be accepted by EVERY base chain on its hook, and ufw's drop wins. So with ufw
# active the host needs two sets of rules, and only then:
#
#   input   (guest -> this host)  DHCP (67/udp, a broadcast, so any destination)
#           and DNS (53, to the gateway only): the dnsmasq libvirt runs on the
#           bridge. Everything else a guest sends to the host stays denied by
#           ufw's default-deny-incoming, so the lab cannot reach the host's
#           services (ssh, CopyQ, a dev server...).
#   forward (guest -> outside)    only when /etc/default/ufw drops forwarded
#           traffic, which it does out of the box. The lab may reach the internet
#           and the VPN (tun0, for HTB/THM targets), but NOT the LAN or anything
#           else private: 10/8, 172.16/12, 192.168/16, 169.254/16 and 100.64/10
#           (CGNAT, and Tailscale) are denied after the VPN is allowed, in that
#           order. Replies to what a guest started pass through ufw's conntrack
#           rule; nothing outside can start a connection to a guest.
#
# ufw keeps its rules in /etc/ufw/*.rules and loads them at boot and on
# `ufw reload`, so they survive both; they name the interface, not its address,
# so they apply whenever labbr0 comes up. Run again after enabling ufw if it was
# off at the time: nothing is added while it is inactive. Idempotent: ufw skips
# a rule that exists.

LAB_NET=${LAB_NET:-labbr0}
LAB_SUBNET=10.40.40.0/24
LAB_GW=10.40.40.1
LAB_VPN_IF=tun0
LAB_PRIVATE=(10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 169.254.0.0/16 100.64.0.0/10)

declare -F say  >/dev/null || say()  { printf '\033[1;34m::\033[0m %s\n' "$*"; }
declare -F warn >/dev/null || warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
declare -F run  >/dev/null || run()  { if [ "${dry:-0}" = 1 ]; then echo "+ $*"; else "$@"; fi; }
[ -n "${SUDO+x}" ] || { SUDO=; [ "$(id -u)" -ne 0 ] && SUDO=sudo; }

# Read-only, so they run in a dry run too.
lab_ufw_active() {
    command -v ufw >/dev/null && $SUDO ufw status 2>/dev/null | grep -q '^Status: active'
}
lab_ufw_drops_forward() {
    grep -qs '^DEFAULT_FORWARD_POLICY="DROP"' /etc/default/ufw
}

# Guests -> host: DHCP and DNS.
lab_ufw_dhcp_dns() {
    if ! lab_ufw_active; then
        say "ufw is not active: no host firewall rules needed for $LAB_NET DHCP/DNS"
        return 0
    fi
    say "ufw: DHCP and DNS from $LAB_NET"
    run $SUDO ufw allow in on "$LAB_NET" to any port 67 proto udp comment 'lab dhcp (cachy-dots)'
    run $SUDO ufw allow in on "$LAB_NET" to "$LAB_GW" port 53 comment 'lab dns (cachy-dots)'
}

# Guests -> outside: internet and VPN, not the LAN.
lab_ufw_forward() {
    if ! lab_ufw_active || ! lab_ufw_drops_forward; then
        say "ufw is not dropping forwarded traffic: no route rules needed for $LAB_NET"
        return 0
    fi
    say "ufw: route $LAB_NET to the internet and $LAB_VPN_IF, not the LAN"
    # The unrestricted rules earlier versions of virt.sh added; they would let
    # the lab into the LAN ahead of the denies below.
    local old
    for old in in out; do
        run $SUDO ufw --force route delete allow "$old" on "$LAB_NET" >/dev/null 2>&1 || true
    done
    local net
    run $SUDO ufw route allow in on "$LAB_NET" out on "$LAB_VPN_IF" comment 'lab to vpn (cachy-dots)'
    for net in "${LAB_PRIVATE[@]}"; do
        run $SUDO ufw route deny in on "$LAB_NET" to "$net" comment 'lab not to lan (cachy-dots)'
    done
    run $SUDO ufw route allow in on "$LAB_NET" from "$LAB_SUBNET" comment 'lab to internet (cachy-dots)'
}

lab_firewall() {
    lab_ufw_dhcp_dns
    lab_ufw_forward
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    set -euo pipefail
    dry=0
    case "${1:-}" in
        -n|--dry-run) dry=1 ;;
        -h|--help)    sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        "") ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    lab_firewall
fi
