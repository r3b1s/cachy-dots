#!/usr/bin/env bash
# Opt in to hibernation on a btrfs root (CachyOS's default layout). zram stays for
# everyday swapping. Not part of the default install.
#
#   1. creates a @swap subvolume at the top of the btrfs filesystem, a sibling of
#      @, so snapper never snapshots it (btrfs refuses to snapshot a subvolume that
#      holds an active swap file), and mounts it on /swap
#   2. makes /swap/swapfile the size of RAM (btrfs filesystem mkswapfile: no
#      copy-on-write, no compression) and turns it on below zram's priority: zram
#      still takes everyday swapping, and the file holds the hibernation image.
#      Inside LUKS, the image is encrypted with the rest of the disk
#   3. writes both mounts into a managed /etc/fstab block
#   4. tells the kernel where the image is (resume=UUID=<fs> resume_offset=<n>):
#      a managed /etc/default/limine block, then limine-update. With another boot
#      loader it prints the parameters to add by hand
#   5. makes closing the lid suspend, then hibernate after 10 minutes, on battery
#      and on AC (systemd/20-cachy-dots-hibernate-{logind,sleep}.conf)
#
# Needs a btrfs root, an initramfs with mkinitcpio's systemd hook (it resumes once
# sd-encrypt has unlocked the disk), and a kernel that allows hibernation (not
# under lockdown, which Secure Boot turns on). Refuses a host whose hibernate.target
# is masked (the vm profile). Reboot afterwards: the kernel command line and logind
# are read at boot.
#
# Opt back out with --remove: the swap file, @swap, both blocks and the drop-ins
# go. zram is left alone either way.
#
# Usage: opt/hibernate.sh [--size <N>G] [--remove] [-n|--dry-run]
#   --size  the swap file's size in GiB (default: RAM, rounded up)
set -euo pipefail

REPO=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

remove=0
dry=0
size=
while [ $# -gt 0 ]; do
    case "$1" in
        --remove)     remove=1 ;;
        -n|--dry-run) dry=1 ;;
        --size)       [ $# -ge 2 ] || { echo "--size needs a value" >&2; exit 2; }; size=$2; shift ;;
        --size=*)     size=${1#--size=} ;;
        -h|--help)    awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

say()  { printf '\033[1;34m::\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
run()  { if [ "$dry" = 1 ]; then echo "+ $*"; else "$@"; fi; }

SUDO=
[ "$(id -u)" -ne 0 ] && SUDO=sudo
FAILED=0

SWAP_DIR=/swap
SWAP_FILE=$SWAP_DIR/swapfile
SUBVOL=@swap
FSTAB=/etc/fstab
LIMINE_CONF=/etc/default/limine
DROPINS=(
    "$REPO/systemd/20-cachy-dots-hibernate-logind.conf:/etc/systemd/logind.conf.d/20-cachy-dots-hibernate.conf"
    "$REPO/systemd/20-cachy-dots-hibernate-sleep.conf:/etc/systemd/sleep.conf.d/20-cachy-dots-hibernate.conf"
)
OPEN="# >>> cachy-dots >>>"
CLOSE="# <<< cachy-dots <<<"

# The block device under / (without the [/@] subvolume suffix), and its filesystem UUID.
dev=$(findmnt -nvo SOURCE /)
uuid=$(findmnt -no UUID /)

top=""
cleanup() {
    [ -n "$top" ] || return 0
    mountpoint -q "$top" && $SUDO umount "$top"
    rmdir "$top" 2>/dev/null || true
}
trap cleanup EXIT

# The top of the btrfs filesystem (subvolid 5), where @ and its siblings live,
# mounted on a temporary directory.
mount_top() {
    top=$(mktemp -d)
    $SUDO mount -o subvolid=5 "$dev" "$top"
}

# The file without its managed block, on stdout.
strip_block() {
    [ ! -f "$1" ] || awk -v o="$OPEN" -v c="$CLOSE" '$0 == o { skip = 1; next } $0 == c { skip = 0; next } !skip' "$1"
}

# write_block <file> <block>: replaces the file's managed block, or appends one; an
# empty block takes it out. Writes only when the result differs; returns 0 if it did
# (or would, in a dry run), 1 if the file is unchanged.
write_block() {
    local file=$1 block=$2 tmp
    tmp=$(mktemp)
    { strip_block "$file"; [ -z "$block" ] || printf '%s\n' "$block"; } > "$tmp"
    if cmp -s "$tmp" "$file"; then
        rm -f "$tmp"; return 1
    fi
    if [ "$dry" = 1 ]; then
        echo "+ change $file:"; diff -u "$file" "$tmp" | tail -n +3 | sed 's/^/+   /' || true
    elif [ "$file" = "$FSTAB" ] && ! findmnt --verify --tab-file "$tmp" >/dev/null 2>&1 \
            && findmnt --verify --tab-file "$file" >/dev/null 2>&1; then
        # A broken fstab can stop the next boot: never write one that fails where the old one passed.
        findmnt --verify --tab-file "$tmp" >&2 || true
        rm -f "$tmp"
        die "the new $FSTAB does not verify; it was not written"
    else
        $SUDO install -m 644 "$tmp" "$file"
        echo "$file: cachy-dots block $([ -n "$block" ] && echo written || echo removed)"
    fi
    rm -f "$tmp"
    return 0
}

swap_active() { awk 'NR > 1 { print $1 }' /proc/swaps | grep -qxF "$SWAP_FILE"; }

regenerate_limine() {
    say "Regenerating the Limine boot entries"
    run $SUDO limine-update || { warn "limine-update failed; run it by hand before rebooting"; FAILED=1; }
}

# ── opting out ──────────────────────────────────────────────────────────────
if [ "$remove" = 1 ]; then
    say "Removing hibernation"
    if swap_active; then
        run $SUDO swapoff "$SWAP_FILE"
    fi
    if write_block "$FSTAB" ""; then
        run $SUDO systemctl daemon-reload
    fi
    if [ -f "$LIMINE_CONF" ] && write_block "$LIMINE_CONF" ""; then
        regenerate_limine
    fi
    for pair in "${DROPINS[@]}"; do
        dst=${pair#*:}
        [ ! -e "$dst" ] || { run $SUDO rm "$dst"; echo "removed $dst"; }
    done
    if mountpoint -q "$SWAP_DIR"; then
        run $SUDO umount "$SWAP_DIR"
    fi
    if [ "$dry" = 1 ]; then
        echo "+ delete the $SUBVOL subvolume (and the swap file in it), if there is one"
    else
        mount_top
        if $SUDO btrfs subvolume show "$top/$SUBVOL" >/dev/null 2>&1; then
            $SUDO btrfs subvolume delete "$top/$SUBVOL"
        fi
    fi
    [ ! -d "$SWAP_DIR" ] || run $SUDO rmdir "$SWAP_DIR" 2>/dev/null || warn "$SWAP_DIR is not empty; left in place"
    [ "$FAILED" = 0 ] || exit 1
    echo "Hibernation is off; the lid suspends again from the next boot."
    exit 0
fi

# ── checks ──────────────────────────────────────────────────────────────────
[ "$(findmnt -no FSTYPE /)" = btrfs ] || die "/ is not btrfs; this script only makes a btrfs swap file"
command -v btrfs >/dev/null || die "btrfs-progs is not installed"
[ -r /etc/mkinitcpio.conf ] || die "no /etc/mkinitcpio.conf; only a mkinitcpio initramfs is handled"
# The HOOKS mkinitcpio ends up with: its config, then its drop-ins, as it reads them.
# shellcheck disable=SC2016
hooks=$(bash -c '. /etc/mkinitcpio.conf; for f in /etc/mkinitcpio.conf.d/*.conf; do [ -f "$f" ] && . "$f"; done; echo " ${HOOKS[*]} "')
case "$hooks" in
    *" systemd "*) ;;
    *) die "the initramfs has no systemd hook; a busybox one needs a resume hook, which this script does not add" ;;
esac
if ! grep -qw disk /sys/power/state || grep -qF '[disabled]' /sys/power/disk; then
    die "the kernel does not allow hibernation here (kernel lockdown, which Secure Boot turns on?)"
fi
[ "$(systemctl is-enabled hibernate.target 2>/dev/null)" != masked ] \
    || die "hibernate.target is masked (the vm profile's no-sleep setup); unmask it first"
if mountpoint -q "$SWAP_DIR"; then
    [ "$(findmnt -no FSROOT "$SWAP_DIR")" = "/$SUBVOL" ] || die "$SWAP_DIR is mounted from somewhere else than $SUBVOL"
elif [ -d "$SWAP_DIR" ] && [ -n "$(ls -A "$SWAP_DIR")" ]; then
    die "$SWAP_DIR is a directory with files in it; move them away first"
fi

if [ -z "$size" ]; then
    size=$(awk '/^MemTotal:/ { print int(($2 + 1048575) / 1048576) }' /proc/meminfo)
fi
size=${size%[Gg]}
case "$size" in
    ''|*[!0-9]*|0) die "--size takes a whole number of GiB, like 16G" ;;
esac
bytes=$((size * 1024 * 1024 * 1024))

# ── 1. @swap, mounted on /swap ──────────────────────────────────────────────
say "Swap subvolume $SUBVOL on $SWAP_DIR"
if ! mountpoint -q "$SWAP_DIR"; then
    if [ "$dry" = 1 ]; then
        echo "+ create the $SUBVOL subvolume at the top of $dev (if missing)"
        echo "+ mount it on $SWAP_DIR"
    else
        mount_top
        if ! $SUDO btrfs subvolume show "$top/$SUBVOL" >/dev/null 2>&1; then
            $SUDO btrfs subvolume create "$top/$SUBVOL"
        fi
        cleanup; top=""
        $SUDO mkdir -p "$SWAP_DIR"
        $SUDO mount -o "subvol=/$SUBVOL,noatime" "$dev" "$SWAP_DIR"
    fi
fi

# ── 2. the swap file ────────────────────────────────────────────────────────
say "Swap file $SWAP_FILE (${size} GiB)"
if [ -f "$SWAP_FILE" ] && [ "$(stat -c %s "$SWAP_FILE")" = "$bytes" ]; then
    echo "already there"
else
    avail=$(findmnt -bno AVAIL /)
    if [ -f "$SWAP_FILE" ]; then
        avail=$((avail + $(stat -c %s "$SWAP_FILE")))
    fi
    [ "$avail" -gt $((bytes + 10 * 1024 * 1024 * 1024)) ] \
        || die "not enough free space for a ${size} GiB swap file (and 10 GiB to spare)"
    if swap_active; then
        run $SUDO swapoff "$SWAP_FILE"
    fi
    [ ! -f "$SWAP_FILE" ] || run $SUDO rm "$SWAP_FILE"
    run $SUDO btrfs filesystem mkswapfile --size "${size}g" --uuid clear "$SWAP_FILE"
fi

# ── 3. fstab ────────────────────────────────────────────────────────────────
# pri=0, below zram's 100: the kernel fills zram first.
say "Mounts in $FSTAB"
block=$(printf '%s\nUUID=%s %s btrfs subvol=/%s,noatime 0 0\n%s none swap defaults,pri=0 0 0\n%s' \
    "$OPEN" "$uuid" "$SWAP_DIR" "$SUBVOL" "$SWAP_FILE" "$CLOSE")
if write_block "$FSTAB" "$block"; then
    run $SUDO systemctl daemon-reload
fi
if ! swap_active; then
    run $SUDO swapon --priority 0 "$SWAP_FILE"
fi

# ── 4. where the image is ───────────────────────────────────────────────────
say "Resume location"
if [ "$dry" = 1 ] && [ ! -f "$SWAP_FILE" ]; then
    offset="<offset of $SWAP_FILE>"
else
    offset=$($SUDO btrfs inspect-internal map-swapfile -r "$SWAP_FILE")
fi
params="resume=UUID=$uuid resume_offset=$offset"
if [ -f "$LIMINE_CONF" ] && command -v limine-update >/dev/null; then
    if strip_block "$LIMINE_CONF" | grep -q 'resume='; then
        warn "$LIMINE_CONF sets resume= outside the cachy-dots block; check which one should win"
    fi
    block=$(printf '%s\nKERNEL_CMDLINE[default]+=" %s"\n%s' "$OPEN" "$params" "$CLOSE")
    if write_block "$LIMINE_CONF" "$block"; then
        regenerate_limine
    else
        echo "kernel command line: already has $params"
    fi
else
    warn "not a Limine system: add these kernel parameters to the boot loader by hand: $params"
    echo "Until then, on UEFI, systemd's HibernateLocation EFI variable tells the initramfs where the image is."
fi

# ── 5. the lid ──────────────────────────────────────────────────────────────
say "Lid: suspend, then hibernate after 10 minutes"
for pair in "${DROPINS[@]}"; do
    src=${pair%%:*} dst=${pair#*:}
    cmp -s "$src" "$dst" 2>/dev/null && continue
    run $SUDO install -D -o root -g root -m 644 "$src" "$dst"
    [ "$dry" = 1 ] || echo "$dst (read at the next boot)"
done

echo
[ "$FAILED" = 0 ] || { warn "finished with errors (see the warnings above)"; exit 1; }
echo "Done. Reboot, then hibernate from the power menu or with: systemctl hibernate"
