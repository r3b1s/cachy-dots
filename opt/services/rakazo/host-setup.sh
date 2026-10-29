#!/usr/bin/env bash
# The service stack's one root step, run once per host with sudo; apply.sh does
# everything else as the user.
#
#   - installs incus and edk2-ovmf (VM firmware), with a full -Syu when either
#     is missing;
#   - gives root the subordinate ID range Incus maps container users into
#     (/etc/subuid, /etc/subgid);
#   - enables incus.socket, and incus.service so instances with boot.autostart
#     start with the host;
#   - adds the invoking user to incus-admin (root-equivalent, like libvirt);
#   - when ufw is installed: a managed block in /etc/ufw/before.rules that lets
#     the stack's bridges (<prefix>-*, stack.toml) take DHCP and DNS from the
#     host and forward. ufw would otherwise drop both, and Incus's own ACLs
#     (apply.sh) are what decide where a guest may go.
#
#   --remove    take the ufw block out and disable Incus; instances, packages,
#               the ID ranges and the group are left (apply.sh --remove takes
#               the stack itself out)
#
# Usage: sudo opt/services/rakazo/host-setup.sh [--remove] [-n|--dry-run] [-h|--help]
set -euo pipefail

HERE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
UFW_RULES=/etc/ufw/before.rules
SUBID="root:1000000:1000000000"

say()  { printf '\033[1;34m::\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
exec 3>&1
run()  { if [ "$dry" = 1 ]; then echo "+ $*" >&3; else "$@"; fi; }
usage() { awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; exit 0; }

dry=0 remove=0
while [ $# -gt 0 ]; do
    case $1 in
        --remove) remove=1 ;;
        -n|--dry-run) dry=1 ;;
        -h|--help) usage ;;
        *) die "unknown option: $1" ;;
    esac
    shift
done

[ "$(id -u)" = 0 ] || [ "$dry" = 1 ] || die "run it with sudo"
user=${SUDO_USER:-}
if [ "$remove" = 0 ] && { [ -z "$user" ] || [ "$user" = root ]; }; then
    die "run it with sudo from your own account"
fi
prefix=$(python3 -I -c 'import sys, tomllib; print(tomllib.load(open(sys.argv[1], "rb"))["prefix"])' "$HERE/stack.toml")

BEGIN="# >>> cachy-dots rakazo stack >>>"
END="# <<< cachy-dots rakazo stack <<<"

# before.rules without the block.
ufw_rest() { awk -v b="$BEGIN" -v e="$END" '$0 == b { skip = 1; next } $0 == e { skip = 0; next } !skip' "$UFW_RULES"; }

# before.rules with the block just before the *filter table's COMMIT.
ufw_with_block() {
    ufw_rest | awk -v b="$BEGIN" -v e="$END" -v p="$prefix" '
        /^\*filter/ { in_filter = 1 }
        in_filter && /^COMMIT/ {
            print b
            print "# The stack'"'"'s Incus bridges: DHCP and DNS from the host, and forwarding."
            print "# Incus'"'"'s ACLs decide where a guest may go (opt/services/rakazo)."
            print "-A ufw-before-input -i " p "-+ -p udp --dport 67 -j ACCEPT"
            print "-A ufw-before-input -i " p "-+ -p udp --dport 53 -j ACCEPT"
            print "-A ufw-before-input -i " p "-+ -p tcp --dport 53 -j ACCEPT"
            print "-A ufw-before-forward -i " p "-+ -j ACCEPT"
            print "-A ufw-before-forward -o " p "-+ -j ACCEPT"
            print e
            in_filter = 0
        }
        { print }'
}

# put_ufw CONTENT-COMMAND: replace before.rules when it differs, then reload ufw.
put_ufw() {
    local tmp
    tmp=$(mktemp)
    "$@" > "$tmp"
    if cmp -s "$tmp" "$UFW_RULES"; then rm -f "$tmp"; return 0; fi
    say "Updating $UFW_RULES"
    if [ "$dry" = 1 ]; then diff -u "$UFW_RULES" "$tmp" || true; rm -f "$tmp"; return 0; fi
    install -m 0640 -o root -g root "$tmp" "$UFW_RULES"
    rm -f "$tmp"
    ! ufw status | grep -q '^Status: active' || ufw reload >/dev/null
}

if [ "$remove" = 1 ]; then
    [ ! -f "$UFW_RULES" ] || put_ufw ufw_rest
    if systemctl is-enabled --quiet incus.service 2>/dev/null || systemctl is-enabled --quiet incus.socket 2>/dev/null; then
        say "Disabling Incus"
        run systemctl disable --now incus.service incus.socket
    fi
    say "Done. Instances, packages, /etc/subuid and /etc/subgid, and incus-admin are left as they were."
    exit 0
fi

# ── Packages ─────────────────────────────────────────────────────────────────
missing=()
for p in incus edk2-ovmf; do pacman -Qq "$p" >/dev/null 2>&1 || missing+=("$p"); done
if [ ${#missing[@]} -gt 0 ]; then
    say "Installing ${missing[*]} (with a full upgrade: never -S against a stale database)"
    run pacman -Syu --needed --noconfirm incus edk2-ovmf
fi

# ── Subordinate IDs ──────────────────────────────────────────────────────────
for f in /etc/subuid /etc/subgid; do
    if ! grep -q '^root:' "$f" 2>/dev/null; then
        say "Adding $SUBID to $f"
        [ "$dry" = 1 ] && { echo "+ echo $SUBID >> $f"; continue; }
        echo "$SUBID" >> "$f"
        restart_incus=1
    fi
done

# ── Incus ────────────────────────────────────────────────────────────────────
if ! systemctl is-enabled --quiet incus.service 2>/dev/null; then
    say "Enabling incus.socket and incus.service"
    run systemctl enable --now incus.socket incus.service
elif [ "${restart_incus:-0}" = 1 ]; then
    run systemctl restart incus.service
fi
if ! id -nG "$user" | tr ' ' '\n' | grep -qx incus-admin; then
    say "Adding $user to incus-admin: log out of your desktop session and back in (a new terminal is not enough), or run \`newgrp incus-admin\` in one"
    run usermod -aG incus-admin "$user"
fi

# ── ufw ──────────────────────────────────────────────────────────────────────
if [ -f "$UFW_RULES" ]; then
    put_ufw ufw_with_block
fi

say "Done. Next, as $user: opt/services/rakazo/apply.sh"
