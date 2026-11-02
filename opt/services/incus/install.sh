#!/usr/bin/env bash
# Opt in to Incus, the system-container and VM manager, on the host. Not part of the
# default install. This sets up the Incus daemon only: no networks, profiles or
# instances (that is what a stack built on top of it brings). The package comes from
# the repos pacman already uses, by its plain name.
#
#   1. installs incus and edk2-ovmf (UEFI firmware for VMs), with --ui also incus-ui
#      (the web UI). A missing package triggers a full -Syu, never a bare -S.
#   2. gives root the subordinate ID ranges Incus maps instance users into
#      (/etc/subuid, /etc/subgid), unless root already has an entry.
#   3. enables and starts incus.socket and incus.service (the service, so instances
#      with boot.autostart come back with the host).
#   4. adds you to incus-admin. That group is root-equivalent (a member can start a
#      privileged instance that mounts the host's /), like libvirt's or docker's. The
#      other group, incus, is not used: its members get only a restricted per-user
#      project through incus-user.socket, with no access to networks, storage or
#      profiles, which a host's own Incus is managed with.
#   5. when firewalld is installed: a zone, cachy-incus, for the default bridge
#      (incusbr0), with DHCP and DNS from the host, and forwarding. firewalld denies
#      both by default, so instances there would get no address and no network.
#      Bridges with other names are not covered.
#
# The daemon is not initialised: run `incus admin init` once (or `--minimal`) for a
# storage pool and incusbr0. A restart of incus.service stops every running instance,
# so one needed for a change above (new ID ranges, or --ui on a running daemon) is done
# only when none is running, and is otherwise left to you, with a warning.
#
#   --ui        also install incus-ui. Open it with `incus webui`: that proxies the
#               UI to a loopback port over the local socket with a one-time token,
#               so there is no TLS certificate to import and nothing listens on the
#               network. (Listening for other machines is not set up here: it takes
#               `incus config set core.https_address ...`, plus a trusted certificate.)
#   --remove    take the firewalld zone out, disable incus.service and incus.socket
#               (which stops running instances), and remove incus-ui if it is
#               installed. The incus package, instances, storage, the ID ranges and
#               the group are left as they were.
#
# Run it as your own user: sudo is used for the root steps (and to read firewalld's
# files, which only root can, so -n asks for sudo too when firewalld is installed).
#
# Usage: opt/services/incus/install.sh [--ui] [--remove] [-n|--dry-run] [-h|--help]
set -euo pipefail

BRIDGE=incusbr0
SUBID="root:1000000:1000000000"

say()  { printf '\033[1;34m::\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
run()  { if [ "$dry" = 1 ]; then echo "+ $*"; else "$@"; fi; }

dry=0 remove=0 ui=0
for arg in "$@"; do
    case "$arg" in
        --ui)         ui=1 ;;
        --remove)     remove=1 ;;
        -n|--dry-run) dry=1 ;;
        -h|--help)    awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; exit 0 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

command -v pacman >/dev/null || die "pacman not found: this is for Arch/CachyOS systems"

SUDO=
if [ "$(id -u)" -ne 0 ]; then SUDO=sudo; fi
user=${SUDO_USER:-$(id -un)}
[ "$user" != root ] || die "run it as your own user (or with sudo from it), so there is a user to give access to"

# ── firewalld ────────────────────────────────────────────────────────────────
ZONE=cachy-incus
# shellcheck source=opt/firewalld-lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../../firewalld-lib.sh"

# ── remove ───────────────────────────────────────────────────────────────────
if [ "$remove" = 1 ]; then
    if fw_installed; then
        fw_guest_zone_remove "$ZONE"
        fw_commit
    fi
    if systemctl is-enabled --quiet incus.service 2>/dev/null || systemctl is-enabled --quiet incus.socket 2>/dev/null; then
        warn "disabling Incus stops its running instances"
        say "Disabling incus.service and incus.socket"
        run $SUDO systemctl disable --now incus.service incus.socket
    fi
    if pacman -Qq incus-ui >/dev/null 2>&1; then
        say "Removing incus-ui"
        run $SUDO pacman -Rns --noconfirm incus-ui
    fi
    say "Done. The incus package, instances, storage, /etc/subuid, /etc/subgid and incus-admin are left as they were."
    exit 0
fi

# ── packages ─────────────────────────────────────────────────────────────────
pkgs=(incus edk2-ovmf)
if [ "$ui" = 1 ]; then pkgs+=(incus-ui); fi
missing=()
for p in "${pkgs[@]}"; do
    pacman -Qq "$p" >/dev/null 2>&1 || missing+=("$p")
done
restart_reason=
if [ ${#missing[@]} -gt 0 ]; then
    say "Installing ${missing[*]} (pacman -Syu: never -S against a stale database)"
    run $SUDO pacman -Syu --needed --noconfirm "${missing[@]}" || die "could not install ${missing[*]}"
    # The daemon reads INCUS_UI's directory when it starts.
    case " ${missing[*]} " in *" incus-ui "*) restart_reason="incus-ui was installed" ;; esac
fi

# ── subordinate IDs ──────────────────────────────────────────────────────────
for f in /etc/subuid /etc/subgid; do
    if ! grep -q '^root:' "$f" 2>/dev/null; then
        say "Adding $SUBID to $f"
        if [ "$dry" = 1 ]; then echo "+ echo $SUBID >> $f"; else printf '%s\n' "$SUBID" | $SUDO tee -a "$f" >/dev/null; fi
        restart_reason="${restart_reason:+$restart_reason and }new subordinate ID ranges"
    fi
done

# ── services ─────────────────────────────────────────────────────────────────
was_active=0
if systemctl is-active --quiet incus.service 2>/dev/null; then was_active=1; fi

if ! systemctl is-enabled --quiet incus.service 2>/dev/null || ! systemctl is-enabled --quiet incus.socket 2>/dev/null; then
    say "Enabling and starting incus.socket and incus.service"
    run $SUDO systemctl enable --now incus.socket incus.service
fi

if [ -n "$restart_reason" ] && [ "$was_active" = 1 ]; then
    # `incusd shutdown` is the unit's ExecStop, and it stops the instances.
    running=$($SUDO incus list --all-projects --format csv --columns ns 2>/dev/null | grep -c ',RUNNING$' || true)
    if [ "$running" = 0 ]; then
        say "Restarting incus.service ($restart_reason)"
        run $SUDO systemctl restart incus.service
    else
        warn "$restart_reason, and incus.service needs a restart for that. $running instance(s) are running, and a restart stops them: run 'sudo systemctl restart incus.service' when they can stop"
    fi
fi

# ── group ────────────────────────────────────────────────────────────────────
if ! id -nG "$user" | tr ' ' '\n' | grep -qx incus-admin; then
    if [ "$dry" = 0 ] && ! getent group incus-admin >/dev/null; then
        die "no incus-admin group: the incus package's sysusers file should have made it"
    fi
    say "Adding $user to incus-admin (root-equivalent): log out of your desktop session and back in (a new terminal is not enough), or run \`newgrp incus-admin\` in one"
    run $SUDO usermod -aG incus-admin "$user"
fi

# ── firewalld ────────────────────────────────────────────────────────────────
if fw_installed; then
    fw_guest_zone "$ZONE" "$BRIDGE" "The default Incus bridge: DHCP and DNS from the host, and forwarding (opt/services/incus). Bridges with other names are not covered."
    fw_commit
fi

echo
echo "Incus is running. Next, as $user (after the group applies):"
echo "    incus admin init --minimal    # a dir storage pool and $BRIDGE; plain 'incus admin init' asks instead"
echo "    incus launch images:archlinux/cloud demo"
if [ "$ui" = 1 ]; then
    echo "    incus webui                   # the web UI, in your browser, over the local socket"
fi
