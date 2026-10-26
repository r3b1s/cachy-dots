#!/usr/bin/env bash
# One-time root setup for the Rakazo VM (opt/services/rakazo/install.sh), the
# pattern hitkit uses: the VM itself runs in the user's qemu:///session, so a
# QEMU escape lands in the user's account rather than root's, and only this
# script needs root (it uses sudo itself). Run it before install.sh.
#
#   - installs libvirt, QEMU, dnsmasq, OVMF, nftables and xorriso when missing;
#   - defines the libvirt network `rakazo` (network:///system): the bridge rakazo0
#     on 10.41.41.0/30 with NAT, the host at .1 and one static DHCP lease, .2, for
#     the VM's MAC: no room for anything else. It autostarts, and
#     virtnetworkd.service is enabled so that it comes up at boot rather than
#     when something first talks to libvirt;
#   - allows rakazo0 in /etc/qemu/bridge.conf (a managed block), so that the
#     setuid qemu-bridge-helper plugs the session VM into it;
#   - installs rakazo-guard.service, an nftables table of its own that holds
#     whether or not ufw is on. From rakazo0 the host accepts DHCP and DNS (the
#     dnsmasq libvirt runs) and nothing else, so the VM cannot reach any service
#     on the host, on any of its addresses. Forwarded traffic from rakazo0 may
#     go to public addresses only: not the LAN, not NetBird, not other VMs. And
#     nothing may open a connection into rakazo0: the host reaches the VM, and
#     Rakazo is served by the host's own proxy (install.sh);
#   - with ufw active, opens the matching holes in ufw too, since a packet must
#     pass every base chain: DHCP and DNS in from rakazo0, forwarding out of it
#     to public addresses when ufw drops forwarded traffic, and the web port in
#     on wt0 (NetBird) only;
#   - enables lingering for the user, so their user manager, and with it the VM,
#     starts at boot.
#
# Idempotent: each step checks first. --remove takes it all out again except
# the packages and lingering; run install.sh --remove first.
# --port must match install.sh's (default 15173).
#
# Usage: opt/services/rakazo/host-setup.sh [--port N] [--remove] [-n|--dry-run] [-h|--help]
set -euo pipefail

HERE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=opt/services/rakazo/common.sh
. "$HERE/common.sh"

dry=0
remove=0
while [ $# -gt 0 ]; do
    case "$1" in
        --port)       PORT=${2:?--port needs a value}; shift ;;
        --remove)     remove=1 ;;
        -n|--dry-run) dry=1 ;;
        -h|--help)    usage "$0" ;;
        *)            die "unknown option: $1" ;;
    esac
    shift
done
[[ $PORT =~ ^[0-9]+$ ]] || die "--port must be a number"

SUDO=
[ "$(id -u)" -ne 0 ] && SUDO=sudo
TARGET_USER="${SUDO_USER:-${USER:-$(id -un)}}"

GUARD_TABLE=cachy_rakazo
GUARD_RULES=/usr/local/lib/cachy-dots/rakazo-guard.nft
GUARD_UNIT=/etc/systemd/system/rakazo-guard.service
BRIDGE_CONF=/etc/qemu/bridge.conf
BLOCK_BEGIN='# >>> cachy-dots rakazo >>>'
BLOCK_END='# <<< cachy-dots rakazo <<<'
PRIVATE=(10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 169.254.0.0/16 100.64.0.0/10)

# The network daemon directly: qemu:///system would go through virtqemud.
vsys() { $SUDO virsh -c network:///system "$@"; }

# Write stdin to a root-owned FILE when it differs. Sets CHANGED=1 when it did.
put_root() {
    local file=$1 mode=$2 tmp
    tmp=$(mktemp)
    cat > "$tmp"
    if $SUDO cmp -s "$tmp" "$file" 2>/dev/null; then
        rm -f "$tmp"
        return 0
    fi
    CHANGED=1
    run $SUDO install -D -o root -g root -m "$mode" "$tmp" "$file"
    rm -f "$tmp"
}

# bridge.conf without our block.
bridge_conf_rest() {
    [ -f "$BRIDGE_CONF" ] || return 0
    awk -v b="$BLOCK_BEGIN" -v e="$BLOCK_END" '$0 == b { skip = 1; next } $0 == e { skip = 0; next } !skip' "$BRIDGE_CONF"
}

ufw_active()        { command -v ufw >/dev/null && $SUDO ufw status 2>/dev/null | grep -q '^Status: active'; }
ufw_drops_forward() { grep -qs '^DEFAULT_FORWARD_POLICY="DROP"' /etc/default/ufw; }

# Each rule as one line of ufw arguments (without the comment).
ufw_rules() {
    echo "allow in on $BRIDGE to any port 67 proto udp"
    echo "allow in on $BRIDGE to $HOST_IP port 53"
    if ufw_drops_forward; then
        local net
        for net in "${PRIVATE[@]}"; do echo "route deny in on $BRIDGE to $net"; done
        echo "route allow in on $BRIDGE from $SUBNET"
    fi
    echo "allow in on $NETBIRD_IF to any port $PORT proto tcp"
}

guard_rules() {
    cat <<NFT
# Written by cachy-dots opt/services/rakazo/host-setup.sh; loaded by
# rakazo-guard.service. Keeps the Rakazo VM on $BRIDGE ($SUBNET) off this host
# and off every private network. Its own table, so it holds with ufw on or off.
table inet $GUARD_TABLE
delete table inet $GUARD_TABLE

table inet $GUARD_TABLE {
    set private4 {
        type ipv4_addr
        flags interval
        elements = { 0.0.0.0/8, 10.0.0.0/8, 100.64.0.0/10, 127.0.0.0/8, 169.254.0.0/16,
                     172.16.0.0/12, 192.168.0.0/16, 224.0.0.0/3 }
    }

    # VM -> this host: DHCP and DNS from libvirt's dnsmasq, replies to what the
    # host started (the proxy, ssh), and nothing else, on any of its addresses.
    chain input {
        type filter hook input priority filter - 10; policy accept;
        iifname != "$BRIDGE" return
        meta nfproto ipv6 drop
        ct state established,related accept
        udp dport 67 accept
        ip daddr $HOST_IP meta l4proto { tcp, udp } th dport 53 accept
        drop
    }

    # VM -> elsewhere: public IPv4 only. Elsewhere -> VM: replies only.
    chain forward {
        type filter hook forward priority filter - 10; policy accept;
        oifname "$BRIDGE" ct state established,related accept
        oifname "$BRIDGE" drop
        iifname "$BRIDGE" meta nfproto ipv6 drop
        iifname "$BRIDGE" ip daddr @private4 drop
    }
}
NFT
}

guard_unit() {
    cat <<UNIT
[Unit]
Description=Keep the Rakazo VM ($BRIDGE) off this host and the LAN
DefaultDependencies=no
Wants=network-pre.target
Before=network-pre.target shutdown.target
Conflicts=shutdown.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/nft -f $GUARD_RULES
ExecStop=/usr/bin/nft delete table inet $GUARD_TABLE

[Install]
WantedBy=multi-user.target
UNIT
}

network_xml() {
    cat <<XML
<network>
  <name>$NET_NAME</name>
  <bridge name='$BRIDGE' stp='on' delay='0'/>
  <forward mode='nat'/>
  <ip address='$HOST_IP' netmask='$NETMASK'>
    <dhcp>
      <host mac='$GUEST_MAC' name='$VM_NAME' ip='$GUEST_IP'/>
    </dhcp>
  </ip>
</network>
XML
}

# ── Removal ──────────────────────────────────────────────────────────────────

if [ "$remove" = 1 ]; then
    if ip -o link show master "$BRIDGE" 2>/dev/null | grep -q .; then
        die "a VM is still attached to $BRIDGE; run opt/services/rakazo/install.sh --remove first"
    fi

    if vsys net-info "$NET_NAME" >/dev/null 2>&1; then
        say "Removing the libvirt network $NET_NAME"
        if [ "$(vsys net-info "$NET_NAME" | awk '/^Active:/ { print $2 }')" = yes ]; then
            run vsys net-destroy "$NET_NAME"
        fi
        run vsys net-undefine "$NET_NAME"
    fi

    if [ -f "$BRIDGE_CONF" ] && grep -qxF "$BLOCK_BEGIN" "$BRIDGE_CONF"; then
        say "Removing $BRIDGE from $BRIDGE_CONF"
        bridge_conf_rest | put_root "$BRIDGE_CONF" 0644
    fi

    if [ -f "$GUARD_UNIT" ]; then
        say "Removing rakazo-guard.service"
        run $SUDO systemctl disable --now rakazo-guard.service
        run $SUDO rm -f "$GUARD_UNIT" "$GUARD_RULES"
        run $SUDO systemctl daemon-reload
    fi

    if ufw_active; then
        say "Removing the ufw rules"
        while read -r rule; do
            # shellcheck disable=SC2086 # one rule's words
            case $rule in
                route\ *) run $SUDO ufw route delete ${rule#route } >/dev/null || true ;;
                *)        run $SUDO ufw delete $rule >/dev/null || true ;;
            esac
        done < <(ufw_rules)
    fi

    say "Removed. Packages and lingering ($TARGET_USER) are left as they are."
    exit 0
fi

# ── Packages ─────────────────────────────────────────────────────────────────

missing=()
for p in libvirt dnsmasq edk2-ovmf nftables xorriso; do
    pacman -Qq "$p" >/dev/null 2>&1 || missing+=("$p")
done
pacman -Qq qemu-base >/dev/null 2>&1 || pacman -Qq qemu-desktop >/dev/null 2>&1 \
    || pacman -Qq qemu-full >/dev/null 2>&1 || missing+=(qemu-base)
if [ "${#missing[@]}" -gt 0 ]; then
    # Sync before -S: a stale database asks for package files the mirror has replaced.
    say "Installing: ${missing[*]}"
    run $SUDO pacman -Syu --noconfirm
    run $SUDO pacman -S --needed --noconfirm "${missing[@]}"
fi

# ── libvirt network ──────────────────────────────────────────────────────────

say "libvirt network $NET_NAME ($SUBNET on $BRIDGE)"
run $SUDO systemctl enable --now virtnetworkd.socket
# Without the service enabled, autostart networks come up only once something
# activates the socket, which a session VM's bridge helper never does.
run $SUDO systemctl enable virtnetworkd.service

if vsys net-info "$NET_NAME" >/dev/null 2>&1; then
    xml=$(vsys net-dumpxml "$NET_NAME")
    for want in "name='$BRIDGE'" "address='$HOST_IP'" "netmask='$NETMASK'" "mac='$GUEST_MAC'" "ip='$GUEST_IP'"; do
        grep -qF "$want" <<<"$xml" \
            || die "network $NET_NAME exists with another definition ($want missing); remove it with --remove, then re-run"
    done
else
    xmlfile=$(mktemp)
    trap 'rm -f "$xmlfile"' EXIT
    network_xml > "$xmlfile"
    run vsys net-define "$xmlfile"
fi
if [ "$(vsys net-info "$NET_NAME" 2>/dev/null | awk '/^Autostart:/ { print $2 }')" != yes ]; then
    run vsys net-autostart "$NET_NAME"
fi
if [ "$(vsys net-info "$NET_NAME" 2>/dev/null | awk '/^Active:/ { print $2 }')" != yes ]; then
    run vsys net-start "$NET_NAME"
fi

# ── Bridge helper ────────────────────────────────────────────────────────────

helper=/usr/lib/qemu/qemu-bridge-helper
if [ -e "$helper" ] || [ "$dry" = 0 ]; then
    [ -u "$helper" ] || die "$helper is not setuid root, so session VMs cannot use a bridge"
fi
say "Allowing $BRIDGE in $BRIDGE_CONF"
{ bridge_conf_rest; printf '%s\nallow %s\n%s\n' "$BLOCK_BEGIN" "$BRIDGE" "$BLOCK_END"; } \
    | put_root "$BRIDGE_CONF" 0644

# ── Guard ────────────────────────────────────────────────────────────────────

say "rakazo-guard.service (nftables table $GUARD_TABLE)"
CHANGED=0
rules=$(mktemp)
guard_rules > "$rules"
$SUDO nft -c -f "$rules" || { rm -f "$rules"; die "nft rejected the guard rules"; }
put_root "$GUARD_RULES" 0644 < "$rules"
rm -f "$rules"
guard_unit | put_root "$GUARD_UNIT" 0644
run $SUDO systemctl daemon-reload
run $SUDO systemctl enable rakazo-guard.service
if [ "$CHANGED" = 1 ]; then
    run $SUDO systemctl restart rakazo-guard.service
else
    run $SUDO systemctl start rakazo-guard.service
fi

# ── ufw ──────────────────────────────────────────────────────────────────────

if ufw_active; then
    say "ufw: DHCP/DNS in and forwarding out for $BRIDGE, port $PORT in on $NETBIRD_IF"
    while read -r rule; do
        # shellcheck disable=SC2086 # one rule's words
        run $SUDO ufw $rule comment 'rakazo (cachy-dots)' >/dev/null
    done < <(ufw_rules)
else
    say "ufw is not active: no ufw rules needed"
fi

# ── Lingering ────────────────────────────────────────────────────────────────

if [ ! -e "/var/lib/systemd/linger/$TARGET_USER" ]; then
    say "Lingering for $TARGET_USER (their user services start at boot)"
    run $SUDO loginctl enable-linger "$TARGET_USER"
fi

say "Host ready. Next, as $TARGET_USER: opt/services/rakazo/install.sh"
