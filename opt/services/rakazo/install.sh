#!/usr/bin/env bash
# Rakazo (https://github.com/elie222/rakazo) in an Arch Linux VM of its own, in
# the user's libvirt session (qemu:///session), kept up by lingering systemd user
# services. Run host-setup.sh once first (root, for the bridge); this script
# never uses sudo.
#
#   - resolves the newest Rakazo release that has both of its images on GHCR
#     (the app and the bot computer), or takes --tag. GitHub's releases are the
#     desktop app's and can be ahead of the images;
#   - creates the VM `rakazo` once: the arch-boxes cloud image (checked against
#     its signing key) copied to a standalone disk in ~/.local/share/rakazo-vm,
#     on the bridge rakazo0 at 10.41.41.2. cloud-init makes the user `rakazo`
#     (SSH key only, passwordless sudo) and installs an SSH host key generated
#     here, so even the first connection is pinned. A disk left by --remove is
#     reused, data and all;
#   - installs user units: rakazo-vm.service starts the VM at boot and shuts it
#     down cleanly; rakazo-web.socket listens on 127.0.0.1 and on the NetBird
#     address (wt0), nowhere else, and hands connections to
#     systemd-socket-proxyd, which forwards them to the VM's web port;
#   - provisions the guest over SSH with guest.sh: an upgraded Arch with Docker
#     (rebooting the VM after a kernel upgrade), restricted egress for bot
#     computers, and upstream's install-images.sh at that release, with the
#     origin http://<NetBird address>:<port>;
#   - checks the web app on both addresses.
#
# Rakazo takes one origin, so sign in at the NetBird address, from this host
# too: 127.0.0.1 answers, but a sign-in there fails Rakazo's origin check.
# Re-run after the NetBird address changes. A re-run converges: the newest
# release, upgraded packages in the guest, the same secrets (.env stays in the
# VM; back up its ENCRYPTION_KEY).
#
#   --close-signups    set SIGNUPS_ENABLED=false (do it once your account exists)
#   --open-signups     set SIGNUPS_ENABLED=true; without either, it is left alone
#   --tag vX.Y.Z       this release instead of the newest
#   --listen-ip IP     instead of wt0's address (127.0.0.1: loopback only)
#   --port N           the host port (default 15173; host-setup.sh opens it on wt0)
#   --memory MiB       16384   } for a new VM; memory and vCPUs are also applied
#   --vcpus N          4       } to an existing one, from its next start
#   --disk SIZE        60G     }
#   --remove           stop and remove the units and the VM, keep its disk
#   --purge            with --remove: delete the disk and the keys too (Rakazo's
#                      data, and the ENCRYPTION_KEY it is encrypted with)
#
# Usage: opt/services/rakazo/install.sh [options] [-n|--dry-run] [-h|--help]
set -euo pipefail

HERE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# The verified Arch cloud image (acv_fetch_image).
# shellcheck source=opt/arch-cloud-vm-lib.sh
. "$HERE/../../arch-cloud-vm-lib.sh"
# shellcheck source=opt/services/rakazo/common.sh
. "$HERE/common.sh"

dry=0
remove=0
purge=0
signups=
tag=
listen_ip=
memory=16384
vcpus=4
disk=60G
while [ $# -gt 0 ]; do
    case "$1" in
        --close-signups) signups=false ;;
        --open-signups)  signups=true ;;
        --tag)           tag=${2:?--tag needs a value}; shift ;;
        --listen-ip)     listen_ip=${2:?--listen-ip needs a value}; shift ;;
        --port)          PORT=${2:?--port needs a value}; shift ;;
        --memory)        memory=${2:?--memory needs a value}; shift ;;
        --vcpus)         vcpus=${2:?--vcpus needs a value}; shift ;;
        --disk)          disk=${2:?--disk needs a value}; shift ;;
        --remove)        remove=1 ;;
        --purge)         purge=1 ;;
        -n|--dry-run)    dry=1 ;;
        -h|--help)       usage "$0" ;;
        *)               die "unknown option: $1" ;;
    esac
    shift
done
[[ $PORT =~ ^[0-9]+$ && $memory =~ ^[0-9]+$ && $vcpus =~ ^[0-9]+$ ]] \
    || die "--port, --memory and --vcpus must be numbers"
[ "$purge" = 0 ] || [ "$remove" = 1 ] || die "--purge goes with --remove"
[ "$(id -u)" -ne 0 ] || die "run this as the user who owns the VM, not root"

STATE="${XDG_DATA_HOME:-$HOME/.local/share}/rakazo-vm"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/arch-cloud-vm"
UNITS="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
DISK_PATH=$STATE/$VM_NAME.qcow2
SEED_PATH=$STATE/seed.iso
CLIENT_KEY=$STATE/id_ed25519
HOST_KEY=$STATE/ssh_host_ed25519_key

vses() { virsh -c qemu:///session "$@"; }
domstate() { vses domstate "$VM_NAME" 2>/dev/null || true; }

GSSH=(ssh -i "$CLIENT_KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=5
      -o UserKnownHostsFile="$STATE/known_hosts" -o StrictHostKeyChecking=yes
      -o HostKeyAlias=rakazo-vm -o LogLevel=ERROR "rakazo@$GUEST_IP")

# Write stdin to FILE when it differs. Sets CHANGED=1 when it did.
put() {
    local file=$1 mode=$2 tmp
    tmp=$(mktemp)
    cat > "$tmp"
    if cmp -s "$tmp" "$file"; then
        rm -f "$tmp"
        return 0
    fi
    CHANGED=1
    run install -D -m "$mode" "$tmp" "$file"
    rm -f "$tmp"
}

shutdown_vm() {
    [ "$(domstate)" = running ] || return 0
    say "Shutting the VM down"
    run vses shutdown "$VM_NAME" >/dev/null
    [ "$dry" = 0 ] || return 0
    local _
    for _ in $(seq 120); do
        [ "$(domstate)" = "shut off" ] && return 0
        sleep 1
    done
    warn "the VM did not shut down in time; stopping it"
    vses destroy "$VM_NAME" >/dev/null
}

# ── Removal ──────────────────────────────────────────────────────────────────

if [ "$remove" = 1 ]; then
    say "Stopping and removing the user units"
    for unit in rakazo-web.socket rakazo-web.service rakazo-vm.service; do
        if [ -f "$UNITS/$unit" ]; then
            run systemctl --user disable --now "$unit" >/dev/null 2>&1 || true
            run rm -f "$UNITS/$unit"
        fi
    done
    run systemctl --user daemon-reload

    if vses dominfo "$VM_NAME" >/dev/null 2>&1; then
        shutdown_vm
        say "Removing the VM definition"
        run vses undefine "$VM_NAME" --nvram >/dev/null
    fi

    if [ "$purge" = 1 ]; then
        say "Deleting $STATE (the disk, the seed and the keys)"
        run rm -rf "$STATE"
    elif [ -d "$STATE" ]; then
        say "Kept $STATE: a re-run reuses the disk; --remove --purge deletes it"
    fi
    say "Removed. The bridge stays until host-setup.sh --remove."
    exit 0
fi

# ── Checks ───────────────────────────────────────────────────────────────────

for tool in virsh qemu-img xorriso curl gpg sha256sum ssh ssh-keygen systemctl; do
    command -v "$tool" >/dev/null || die "$tool is not installed; run host-setup.sh"
done
[ -x /usr/lib/systemd/systemd-socket-proxyd ] || die "systemd-socket-proxyd is missing"
ip link show "$BRIDGE" >/dev/null 2>&1 \
    || die "no bridge $BRIDGE; run opt/services/rakazo/host-setup.sh first"
grep -qx "allow $BRIDGE" /etc/qemu/bridge.conf 2>/dev/null \
    || die "$BRIDGE is not allowed in /etc/qemu/bridge.conf; run host-setup.sh"
systemctl is-active --quiet rakazo-guard.service \
    || die "rakazo-guard.service is not active, and the VM must not run without it; run host-setup.sh"
[ -e "/var/lib/systemd/linger/$(id -un)" ] \
    || warn "lingering is off: the VM starts only once you log in (host-setup.sh turns it on)"

if [ -z "$listen_ip" ]; then
    listen_ip=$(ip -4 -o addr show dev "$NETBIRD_IF" 2>/dev/null | awk '{ sub(/\/.*/, "", $4); print $4; exit }')
    [ -n "$listen_ip" ] || die "$NETBIRD_IF has no IPv4 address (is NetBird up?); or pass --listen-ip"
fi
[[ $listen_ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "--listen-ip must be an IPv4 address"
origin=http://$listen_ip:$PORT

# ── Release ──────────────────────────────────────────────────────────────────

# The vX.Y.Z tags of ghcr.io/elie222/rakazo/IMAGE, one per line.
ghcr_versions() {
    local repo=elie222/rakazo/$1 token page tags last='' n
    token=$(curl -fsS "https://ghcr.io/token?scope=repository:$repo:pull" \
        | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
    [ -n "$token" ] || return 1
    while :; do
        page=$(curl -fsS -H "Authorization: Bearer $token" \
            "https://ghcr.io/v2/$repo/tags/list?n=1000${last:+&last=$last}") || return 1
        tags=$(sed -n 's/.*"tags":\[\([^]]*\)\].*/\1/p' <<<"$page" | tr ',' '\n' | tr -d '"')
        [ -n "$tags" ] || break
        grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' <<<"$tags" || true
        n=$(wc -l <<<"$tags")
        last=$(tail -n 1 <<<"$tags")
        [ "$n" -ge 1000 ] || break
    done
}

if [ -z "$tag" ]; then
    say "Finding the newest Rakazo release on GHCR"
    app=$(ghcr_versions app) || die "could not list ghcr.io/elie222/rakazo/app"
    computer=$(ghcr_versions computer) || die "could not list ghcr.io/elie222/rakazo/computer"
    tag=$(comm -12 <(sort -u <<<"$app") <(sort -u <<<"$computer") | sort -V | tail -n 1)
    [ -n "$tag" ] || die "no release has both images yet"
fi
[[ $tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "--tag must look like v1.2.3"
curl -fsSI -o /dev/null "https://raw.githubusercontent.com/elie222/rakazo/$tag/infra/compose/install-images.sh" \
    || die "release $tag has no infra/compose/install-images.sh"
say "Release $tag, origin $origin"

# ── The VM ───────────────────────────────────────────────────────────────────

run install -d -m 700 "$STATE"
mkdir -p "$CACHE"

if [ ! -f "$CLIENT_KEY" ]; then
    say "Generating the SSH key $CLIENT_KEY"
    run ssh-keygen -q -t ed25519 -N "" -C "rakazo-vm-client" -f "$CLIENT_KEY"
fi
if [ ! -f "$HOST_KEY" ]; then
    say "Generating the VM's SSH host key"
    run ssh-keygen -q -t ed25519 -N "" -C "rakazo-vm" -f "$HOST_KEY"
fi
if [ "$dry" = 0 ]; then
    printf 'rakazo-vm %s\n' "$(cut -d' ' -f1-2 "$HOST_KEY.pub")" | put "$STATE/known_hosts" 0600
fi

if ! vses dominfo "$VM_NAME" >/dev/null 2>&1; then
    if [ ! -f "$DISK_PATH" ] && [ "$dry" = 1 ]; then
        echo "+ fetch and verify the Arch cloud image, then create $DISK_PATH ($disk)"
    elif [ ! -f "$DISK_PATH" ]; then
        acv_fetch_image
        say "Creating the $disk disk"
        run qemu-img convert -O qcow2 "$ACV_IMAGE" "$DISK_PATH"
        run qemu-img resize -q "$DISK_PATH" "$disk"
    else
        say "Reusing the disk $DISK_PATH"
    fi

    if [ ! -f "$SEED_PATH" ] && [ "$dry" = 0 ]; then
        say "Writing the cloud-init seed"
        work=$(mktemp -d)
        trap 'rm -rf "$work"' EXIT
        {
            echo '#cloud-config'
            echo "hostname: $VM_NAME"
            echo 'users:'
            echo '  - name: rakazo'
            echo '    groups: [wheel]'
            echo "    sudo: 'ALL=(ALL) NOPASSWD:ALL'"
            echo '    shell: /bin/bash'
            echo '    lock_passwd: true'
            echo '    ssh_authorized_keys:'
            echo "      - '$(cat "$CLIENT_KEY.pub")'"
            echo 'ssh_pwauth: false'
            echo 'disable_root: true'
            echo 'ssh_deletekeys: true'
            echo 'ssh_genkeytypes: []'
            echo 'ssh_keys:'
            echo '  ed25519_private: |'
            sed 's/^/    /' "$HOST_KEY"
            echo "  ed25519_public: '$(cat "$HOST_KEY.pub")'"
        } > "$work/user-data"
        printf 'instance-id: %s\nlocal-hostname: %s\n' "$VM_NAME" "$VM_NAME" > "$work/meta-data"
        (umask 077; xorriso -as mkisofs -quiet -output "$SEED_PATH" -volid cidata -joliet -rock \
            "$work/user-data" "$work/meta-data" >/dev/null 2>&1)
    fi

    say "Defining the VM $VM_NAME ($vcpus vCPUs, $memory MiB, $BRIDGE)"
    xml=$(mktemp)
    cat > "$xml" <<XML
<domain type='kvm'>
  <name>$VM_NAME</name>
  <description>Rakazo (cachy-dots opt/services/rakazo)</description>
  <memory unit='MiB'>$memory</memory>
  <vcpu>$vcpus</vcpu>
  <os firmware='efi'>
    <type arch='x86_64' machine='q35'>hvm</type>
    <firmware>
      <feature enabled='no' name='secure-boot'/>
    </firmware>
  </os>
  <features><acpi/><apic/></features>
  <cpu mode='host-passthrough' check='none'/>
  <clock offset='utc'/>
  <on_poweroff>destroy</on_poweroff>
  <on_reboot>restart</on_reboot>
  <on_crash>destroy</on_crash>
  <devices>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2' discard='unmap'/>
      <source file='$DISK_PATH'/>
      <target dev='vda' bus='virtio'/>
    </disk>
    <disk type='file' device='cdrom'>
      <driver name='qemu' type='raw'/>
      <source file='$SEED_PATH'/>
      <target dev='sda' bus='sata'/>
      <readonly/>
    </disk>
    <interface type='bridge'>
      <mac address='$GUEST_MAC'/>
      <source bridge='$BRIDGE'/>
      <model type='virtio'/>
    </interface>
    <serial type='pty'><target port='0'/></serial>
    <console type='pty'><target type='serial' port='0'/></console>
    <rng model='virtio'><backend model='random'>/dev/urandom</backend></rng>
  </devices>
</domain>
XML
    run vses define "$xml" >/dev/null
    rm -f "$xml"
else
    # Memory and vCPUs follow the flags; they apply from the VM's next start.
    info=$(vses dominfo "$VM_NAME")
    have_mem=$(awk '/^Max memory:/ { print $3 }' <<<"$info")
    have_cpu=$(awk '/^CPU\(s\):/ { print $2 }' <<<"$info")
    if [ "$have_mem" != $((memory * 1024)) ]; then
        say "Memory: ${have_mem} KiB -> $memory MiB (from the next start)"
        run vses setmaxmem "$VM_NAME" "${memory}M" --config
        run vses setmem "$VM_NAME" "${memory}M" --config
    fi
    if [ "$have_cpu" != "$vcpus" ]; then
        say "vCPUs: $have_cpu -> $vcpus (from the next start)"
        run vses setvcpus "$VM_NAME" "$vcpus" --config --maximum
        run vses setvcpus "$VM_NAME" "$vcpus" --config
    fi
fi

# ── User units ───────────────────────────────────────────────────────────────

say "User units: rakazo-vm.service, rakazo-web.socket"
CHANGED=0
put "$UNITS/rakazo-vm.service" 0644 <<UNIT
# Written by cachy-dots opt/services/rakazo/install.sh.
[Unit]
Description=Rakazo VM (libvirt qemu:///session, bridge $BRIDGE)
Documentation=https://github.com/elie222/rakazo

[Service]
Type=oneshot
RemainAfterExit=yes
# The bridge is virtnetworkd's, a system service a user unit cannot be ordered
# after, so wait for it.
ExecStart=/bin/sh -c 'i=0; until ip link show $BRIDGE >/dev/null 2>&1; do i=\$\$((i + 1)); [ \$\$i -lt 120 ] || exit 1; sleep 1; done; [ "\$\$(virsh -c qemu:///session domstate $VM_NAME)" = running ] || exec virsh -c qemu:///session start $VM_NAME'
# A clean shutdown, so that Postgres is not killed; forced after two minutes.
ExecStop=/bin/sh -c 'virsh -c qemu:///session shutdown $VM_NAME >/dev/null 2>&1 || exit 0; i=0; until [ "\$\$(virsh -c qemu:///session domstate $VM_NAME)" = "shut off" ]; do i=\$\$((i + 1)); [ \$\$i -lt 120 ] || exec virsh -c qemu:///session destroy $VM_NAME; sleep 1; done'
TimeoutStartSec=180
TimeoutStopSec=150

[Install]
WantedBy=default.target
UNIT
vm_changed=$CHANGED

CHANGED=0
{
    echo "# Written by cachy-dots opt/services/rakazo/install.sh."
    echo "[Unit]"
    echo "Description=Rakazo's web app on loopback and NetBird"
    echo
    echo "[Socket]"
    echo "ListenStream=127.0.0.1:$PORT"
    [ "$listen_ip" = 127.0.0.1 ] || echo "ListenStream=$listen_ip:$PORT"
    echo "# The NetBird address may not exist yet when this starts at boot."
    echo "FreeBind=yes"
    echo
    echo "[Install]"
    echo "WantedBy=sockets.target"
} | put "$UNITS/rakazo-web.socket" 0644
put "$UNITS/rakazo-web.service" 0644 <<UNIT
# Written by cachy-dots opt/services/rakazo/install.sh.
[Unit]
Description=Forward Rakazo's web port to its VM
Requires=rakazo-web.socket
After=rakazo-web.socket

[Service]
ExecStart=/usr/lib/systemd/systemd-socket-proxyd $GUEST_IP:$GUEST_PORT
UNIT
web_changed=$CHANGED

run systemctl --user daemon-reload
run systemctl --user enable rakazo-vm.service rakazo-web.socket >/dev/null 2>&1
if [ "$web_changed" = 1 ]; then
    run systemctl --user stop rakazo-web.service rakazo-web.socket
fi
run systemctl --user start rakazo-web.socket
[ "$vm_changed" = 0 ] || [ "$(domstate)" != running ] || say "rakazo-vm.service changed; it applies from the next boot"
run systemctl --user start rakazo-vm.service

if [ "$dry" = 1 ]; then
    echo "+ provision the guest with guest.sh --tag $tag --origin $origin ${signups:+--signups $signups}"
    exit 0
fi

# ── The guest ────────────────────────────────────────────────────────────────

wait_ssh() {
    local _
    for _ in $(seq 90); do
        "${GSSH[@]}" true 2>/dev/null && return 0
        sleep 5
    done
    die "no SSH from the VM at $GUEST_IP (console: virsh -c qemu:///session console $VM_NAME)"
}

say "Waiting for SSH on $GUEST_IP"
wait_ssh
# cloud-init's first boot also initialises pacman's keyring.
"${GSSH[@]}" 'cloud-init status --wait >/dev/null 2>&1 || true'

guest_args=(--tag "$tag" --origin "$origin")
[ -z "$signups" ] || guest_args+=(--signups "$signups")
for attempt in 1 2 3; do
    say "Provisioning the guest"
    rc=0
    "${GSSH[@]}" sudo bash -s -- "${guest_args[@]}" < "$HERE/guest.sh" || rc=$?
    case $rc in
        0)   break ;;
        100) [ "$attempt" -lt 3 ] || die "the guest still needs a reboot after two"
             say "Rebooting the VM into its new kernel"
             "${GSSH[@]}" sudo systemctl reboot || true
             sleep 15
             wait_ssh ;;
        *)   die "provisioning the guest failed (exit $rc)" ;;
    esac
done

# ── Checks ───────────────────────────────────────────────────────────────────

FAILED=0
for addr in 127.0.0.1 $([ "$listen_ip" = 127.0.0.1 ] || echo "$listen_ip"); do
    if curl -fsS -o /dev/null --max-time 10 "http://$addr:$PORT/"; then
        say "http://$addr:$PORT/ answers"
    else
        warn "http://$addr:$PORT/ does not answer"
        FAILED=1
    fi
done

echo
echo "Rakazo $tag:  $origin   (sign in here; Rakazo accepts this origin only)"
case $signups in
    false) echo "Signups:     closed (--open-signups reopens them)" ;;
    true)  echo "Signups:     open (--close-signups once your account exists)" ;;
    *)     echo "Signups:     as they were (open on a fresh install; --close-signups closes them)" ;;
esac
echo "VM:          $VM_NAME on $BRIDGE ($GUEST_IP), qemu:///session; disk in $STATE"
echo "SSH:         ssh -i $CLIENT_KEY -o UserKnownHostsFile=$STATE/known_hosts -o HostKeyAlias=rakazo-vm rakazo@$GUEST_IP"
echo "Secrets:     /home/rakazo/rakazo/.env in the VM; back up its ENCRYPTION_KEY"
exit "$FAILED"
