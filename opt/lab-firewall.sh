#!/usr/bin/env bash
# firewalld zones for the labbr0 lab network (10.40.40.0/24, libvirt NAT). Sourced by
# opt/virt.sh and opt/arch-cloud-vm-lib.sh; also runnable on its own:
#
#   opt/lab-firewall.sh [-n|--dry-run]
#
# libvirt builds the NAT itself (masquerade, plus its own accept rules, in its own
# nftables tables), but that does not get a guest past firewalld: a packet has to be
# accepted by EVERY base chain on its hook. Left alone, libvirt puts its bridges in the
# `libvirt` zone it ships, which has target ACCEPT: guests may then forward anywhere,
# LAN included, whatever a policy says, and reach the host's ssh. So labbr0 goes in a
# zone of its own, named by the network's <bridge zone=...> (opt/virt.sh):
#
#   input   (guest -> this host)  DHCP (67/udp, a broadcast, so any destination) and
#           DNS (53, to the gateway only): the dnsmasq libvirt runs on the bridge.
#           Everything else a guest sends to the host is rejected, so the lab cannot
#           reach the host's services (ssh, CopyQ, a dev server...).
#   forward (guest -> outside)    the lab may reach the internet and the VPN (tun0,
#           for HTB/THM targets), but NOT the LAN or anything else private: 10/8,
#           172.16/12, 192.168/16, 169.254/16 and 100.64/10 (CGNAT, and Tailscale) are
#           dropped by cachy-lab-net, which runs after cachy-lab-vpn. Replies to what a
#           guest started pass through firewalld's conntrack rule; nothing outside can
#           start a connection to a guest.
#
# Telling the VPN from the LAN takes a zone: a policy can match zones, not interfaces.
# So tun0 is in cachy-vpn, which drops incoming as the default zone does. Its own
# consequence: a listener for a VPN target needs a rule in THAT zone, not the default:
#
#   sudo firewall-cmd --zone=cachy-vpn --add-port=4444/tcp
#
# With firewalld installed but stopped the files are still written, and it loads them
# when it starts; run this again then, as a network started meanwhile has no zone.
# Idempotent: the files are written only when they differ.

LAB_NET=${LAB_NET:-labbr0}
LAB_SUBNET=10.40.40.0/24
LAB_GW=10.40.40.1
LAB_VPN_IF=tun0
LAB_PRIVATE=(10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 169.254.0.0/16 100.64.0.0/10)
LAB_ZONE=cachy-lab
LAB_VPN_ZONE=cachy-vpn

declare -F say  >/dev/null || say()  { printf '\033[1;34m::\033[0m %s\n' "$*"; }
declare -F warn >/dev/null || warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
declare -F run  >/dev/null || run()  { if [ "${dry:-0}" = 1 ]; then echo "+ $*"; else "$@"; fi; }
[ -n "${SUDO+x}" ] || { SUDO=; [ "$(id -u)" -ne 0 ] && SUDO=sudo; }

# shellcheck source=opt/firewalld-lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/firewalld-lib.sh"

lab_firewall() {
    if ! fw_installed; then
        say "firewalld is not installed: no host firewall rules needed for $LAB_NET"
        return 0
    fi
    say "firewalld: $LAB_NET gets DHCP and DNS, the internet and $LAB_VPN_IF, not the LAN"

    fw_put zones "$LAB_ZONE" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<zone>
  <short>$LAB_ZONE</short>
  <description>The lab network: DHCP and DNS from the host, and nothing else of it.</description>
  <interface name="$LAB_NET"/>
  <service name="dhcp"/>
  <rule family="ipv4">
    <destination address="$LAB_GW"/>
    <service name="dns"/>
    <accept/>
  </rule>
</zone>
EOF

    fw_put zones "$LAB_VPN_ZONE" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<zone target="DROP">
  <short>$LAB_VPN_ZONE</short>
  <description>The VPN the lab reaches. Drops incoming, as the default zone does.</description>
  <interface name="$LAB_VPN_IF"/>
</zone>
EOF

    fw_put policies cachy-lab-vpn <<EOF
<?xml version="1.0" encoding="utf-8"?>
<policy target="ACCEPT" priority="-20">
  <short>cachy-lab-vpn</short>
  <description>The lab to the VPN. Runs before cachy-lab-net, whose private ranges VPN targets use.</description>
  <ingress-zone name="$LAB_ZONE"/>
  <egress-zone name="$LAB_VPN_ZONE"/>
</policy>
EOF

    local net drops=
    for net in "${LAB_PRIVATE[@]}"; do
        drops+="  <rule family=\"ipv4\">
    <destination address=\"$net\"/>
    <drop/>
  </rule>
"
    done
    # A heredoc, not a pipe: in a pipeline fw_put runs in a subshell, and the reload
    # would never hear that it changed anything.
    fw_put policies cachy-lab-net <<EOF
<?xml version="1.0" encoding="utf-8"?>
<policy target="CONTINUE" priority="-10">
  <short>cachy-lab-net</short>
  <description>The lab to the internet, not the LAN.</description>
  <ingress-zone name="$LAB_ZONE"/>
  <egress-zone name="ANY"/>
$drops  <rule family="ipv4">
    <source address="$LAB_SUBNET"/>
    <accept/>
  </rule>
</policy>
EOF

    fw_commit
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    set -euo pipefail
    dry=0
    case "${1:-}" in
        -n|--dry-run) dry=1 ;;
        -h|--help)    awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; exit 0 ;;
        "") ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    lab_firewall
fi
