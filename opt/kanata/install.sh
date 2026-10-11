#!/usr/bin/env bash
# Opt in to kanata, the keyboard remapper, as a system service that runs as its own
# user. Not part of the default install. kanata comes from chaotic-aur/kanata, with
# pacman. The enthium.kbd in this folder (copied from r3b1s/kanata-enthium) is the
# only config it installs.
#
#   1. installs chaotic-aur/kanata with pacman (the name is qualified, so no other
#      repo's build is taken). Run ./install.sh first: it adds the chaotic-aur repo.
#      Later updates come with a system upgrade (pacman -Syu), not from this script.
#   2. checks enthium.kbd with the installed kanata (kanata --check) before the
#      config or unit change. A rejected config leaves the live config and service
#      as they were.
#   3. installs these as root. A file that already matches is left alone:
#        /etc/kanata/enthium.kbd                    the config (root 0644)
#        /etc/systemd/system/kanata.service         the unit (root 0644), which
#                                                   overrides the packaged one
#        /etc/sysusers.d/kanata.conf                the kanata user and groups
#        /etc/udev/rules.d/99-kanata-uinput.rules   /dev/uinput for the uinput group
#        /etc/modules-load.d/kanata.conf            the uinput module, at boot
#   4. enables kanata.service. It does not start it, because starting grabs the
#      keyboards. A re-run restarts it only when it is already running and the
#      package, config or unit changed.
#
# Re-run after editing enthium.kbd. Run it as your own user: sudo is used for the
# root steps.
#
# Usage: opt/kanata/install.sh [-n|--dry-run]
set -euo pipefail

HERE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)

dry=0
for arg in "$@"; do
    case "$arg" in
        -n|--dry-run) dry=1 ;;
        -h|--help)    awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; exit 0 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

say()  { printf '\033[1;34m::\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
run()  { if [ "$dry" = 1 ]; then echo "+ $*"; else "$@"; fi; }

SUDO=
[ "$(id -u)" -ne 0 ] && SUDO=sudo

# ── kanata package ────────────────────────────────────────────────────────────

before=$(pacman -Q kanata 2>/dev/null || true)

# The old cargo install left an unowned binary at /usr/bin/kanata, and pacman will
# not overwrite a file it does not own. Stop here, before anything changes.
if [ -e /usr/bin/kanata ] && ! pacman -Qo /usr/bin/kanata >/dev/null 2>&1; then
    die "/usr/bin/kanata is not owned by a package (left by the old cargo install). Remove it with: sudo rm /usr/bin/kanata; then re-run this script"
fi

if [ -z "$before" ]; then
    if [ "$dry" != 1 ] && ! pacman -Si chaotic-aur/kanata >/dev/null 2>&1; then
        die "chaotic-aur/kanata is unavailable (run ./install.sh first: it adds chaotic-aur)"
    fi
    # A full -Syu, as install.sh does: -Sy alone would be a partial upgrade.
    say "Installing chaotic-aur/kanata (pacman -Syu, a full sync)"
    run $SUDO pacman -Syu --needed --noconfirm chaotic-aur/kanata || die "could not install chaotic-aur/kanata"
else
    say "kanata $before is installed. A system upgrade (pacman -Syu) updates it."
fi
after=$(pacman -Q kanata 2>/dev/null || true)
pkg_changed=0
if [ "$before" != "$after" ]; then pkg_changed=1; fi

# ── config check ──────────────────────────────────────────────────────────────

# The check runs on a private copy, and that same copy is what gets installed.
stage=$(mktemp -d)
trap 'rm -rf -- "$stage"' EXIT
cp -- "$HERE/enthium.kbd" "$stage/enthium.kbd"

say "Checking enthium.kbd with the installed kanata (kanata --check)"
if ! run /usr/bin/kanata --check --cfg "$stage/enthium.kbd"; then
    # TODO(human): decide what a rejected config does. The die below aborts. By then
    # the package is installed, but the live config, unit and service are untouched.
    die "kanata --check rejected enthium.kbd; the live config and service were not touched"
fi

# ── install as root ───────────────────────────────────────────────────────────

# replace SRC DEST MODE: makes DEST the same bytes as SRC, owned by root:root with
# MODE, and sets $replaced to 1 when it writes DEST (0 when it already matched).
# It writes DEST.new and renames that over DEST, so a reader sees the old file or
# the new one, never a partial write.
replace() {
    replaced=0
    if [ -f "$2" ] && cmp -s "$1" "$2"; then return 0; fi
    local dir
    dir=$(dirname -- "$2")
    [ -d "$dir" ] || run $SUDO install -d -m 0755 "$dir" || die "could not create $dir"
    run $SUDO install -o root -g root -m "$3" "$1" "$2.new" || die "could not write $2.new"
    run $SUDO mv -f -- "$2.new" "$2" || die "could not replace $2"
    echo "  installed $2"
    replaced=1
}

say "Installing as root (sudo)"
replace "$stage/enthium.kbd" /etc/kanata/enthium.kbd 0644;              config_changed=$replaced
replace "$HERE/kanata.service" /etc/systemd/system/kanata.service 0644; unit_changed=$replaced
replace "$HERE/sysusers.conf" /etc/sysusers.d/kanata.conf 0644
replace "$HERE/udev.rules" /etc/udev/rules.d/99-kanata-uinput.rules 0644; udev_changed=$replaced
replace "$HERE/modules-load.conf" /etc/modules-load.d/kanata.conf 0644

# ── activate ──────────────────────────────────────────────────────────────────

say "Activating"
# Idempotent, so it runs every time. It creates the user and groups before the udev
# rule that names the uinput group takes effect.
run $SUDO systemd-sysusers /etc/sysusers.d/kanata.conf
run $SUDO modprobe uinput
if [ "$udev_changed" = 1 ]; then
    run $SUDO udevadm control --reload-rules
    run $SUDO udevadm trigger
fi
if [ "$unit_changed" = 1 ]; then
    run $SUDO systemctl daemon-reload
    run systemd-analyze verify /etc/systemd/system/kanata.service \
        || warn "systemd-analyze reported problems with kanata.service (above)"
fi
run $SUDO systemctl enable kanata.service
if [ "$pkg_changed" = 1 ] || [ "$config_changed" = 1 ] || [ "$unit_changed" = 1 ]; then
    if systemctl is-active --quiet kanata.service; then
        say "Restarting kanata: its package, config or unit changed"
        run $SUDO systemctl restart kanata.service
    fi
fi

# ── leftovers from the old install-kanata.sh ──────────────────────────────────

# Reported, not removed: those files are outside what this script owns. The unit
# under /etc overrides this one, but the old enable link still points at it.
if [ -e /lib/systemd/system/kanata.service ]; then
    warn "left over from the old install-kanata.sh: /lib/systemd/system/kanata.service"
    warn "remove it with: sudo systemctl disable kanata.service; sudo rm -f /lib/systemd/system/kanata.service; sudo systemctl daemon-reload; then re-run this script"
fi

echo
echo "kanata is enabled at boot and is not started yet. First, see which keyboards it"
echo "would grab (it grabs every keyboard it finds, unless enthium.kbd sets linux-dev):"
echo "    sudo kanata --list"
echo "Then start it with: sudo systemctl start kanata.service"
echo "Emergency exit, which quits kanata: left Ctrl + Space + Escape."
