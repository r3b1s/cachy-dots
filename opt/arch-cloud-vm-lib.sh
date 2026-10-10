# Sourced by arch-cloud-vm.sh and arch-cloud-vm-dots.sh; not run on its own.
# The shared part of both: option parsing for the common flags, checks, the
# verified Arch cloud image, the overlay disk, the SSH key and password, the
# cloud-init seed, the libvirt domain and the final report.
#
# A caller sets its own defaults, parses its own options and hands the rest to
# acv_option, then runs the steps in order:
#
#   acv_option "$@"   sets ACV_USED to the arguments it took, or returns 1
#   acv_help FILE     prints FILE's leading comment block (up to `set -`)
#   acv_check         validates, finds libvirt, opens the lab firewall
#   acv_image         replaces an existing VM, fetches and verifies the image,
#                     makes the overlay
#   acv_credentials   the SSH key (imported or generated) and the password
#   acv_seed          the cloud-init seed; ACV_USERDATA_EXTRA is appended to the
#                     user-data (more top-level cloud-config keys)
#   acv_domain        defines and starts the VM; ACV_DEVICES_EXTRA is inserted
#                     into <devices>
#   acv_report        prints the summary; calls acv_report_extra when defined

BASE_URL=https://fastly.mirror.pkgbuild.com/images/latest
IMG=Arch-Linux-x86_64-cloudimg.qcow2
# arch-boxes signing key, from https://github.com/archlinux/arch-boxes (README).
ARCH_BOXES_FPR=1B9A16984A4E8CB448712D2AE0B78BF4326C6F8F
ARCH_BOXES_KEY=$(cat <<'KEY'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mDMEYpOJrBYJKwYBBAHaRw8BAQdAcSZilBvR58s6aD2qgsDE7WpvHQR2R5exQhNQ
yuILsTq0JWFyY2gtYm94ZXMgPGFyY2gtYm94ZXNAYXJjaGxpbnV4Lm9yZz6IkAQT
FggAOBYhBBuaFphKToy0SHEtKuC3i/QybG+PBQJik4msAhsBBQsJCAcCBhUKCQgL
AgQWAgMBAh4BAheAAAoJEOC3i/QybG+P81YA/A7HUftMGpzlJrPYBFPqW0nFIh7m
sIZ5yXxh7cTgqtJ7AQDFKSrulrsDa6hsqmEC11PWhv1VN6i9wfRvb1FwQPF6D7gz
BGKTiecWCSsGAQQB2kcPAQEHQBzLxT2+CwumKUtfi9UEXMMx/oGgpjsgp2ehYPBM
N8ejiPUEGBYIACYWIQQbmhaYSk6MtEhxLSrgt4v0MmxvjwUCYpOJ5wIbAgUJCWYB
gACBCRDgt4v0Mmxvj3YgBBkWCAAdFiEEZW5MWsHMO4blOdl+NDY1poWakXQFAmKT
iecACgkQNDY1poWakXTwaQEAwymt4PgXltHUH8GVUB6Xu7Gb5o6LwV9fNQJc1CMl
7CABAJw0We0w1q78cJ8uWiomE1MHdRxsuqbuqtsCn2Dn6/0Cj+4A/Apcqm7uzFam
pA5u9yvz1VJBWZY1PRBICBFSkuRtacUCAQC7YNurPPoWDyjiJPrf0Vzaz8UtKp0q
BSF/a3EoocLnCA==
=APeC
-----END PGP PUBLIC KEY BLOCK-----
KEY
)
POOL=/var/lib/libvirt/images
LAB_NET=labbr0

NAME=arch-lab
USER_NAME=arch
MEMORY=4096
VCPUS=2
DISK=20G
REPLACE=0
SUDO_RULE='ALL=(ALL) ALL'
SSH_KEY_ARG=
ACV_USERDATA_EXTRA=
ACV_DEVICES_EXTRA=

die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
say()  { printf '\033[1;34m::\033[0m %s\n' "$*"; }

acv_help() { sed -n '2,/^set -/p' "$1" | sed '$d; s/^# \{0,1\}//'; exit 0; }

# The options both scripts take. Sets ACV_USED (1, or 2 with a value).
acv_option() {
    ACV_USED=2
    case "$1" in
        --name)     NAME=${2:?--name needs a value} ;;
        --user)     USER_NAME=${2:?--user needs a value} ;;
        --memory)   MEMORY=${2:?--memory needs a value} ;;
        --vcpus)    VCPUS=${2:?--vcpus needs a value} ;;
        --disk)     DISK=${2:?--disk needs a value} ;;
        --ssh-key)  SSH_KEY_ARG=${2:?--ssh-key needs a value} ;;
        --replace)  REPLACE=1; ACV_USED=1 ;;
        --nopasswd) SUDO_RULE='ALL=(ALL) NOPASSWD:ALL'; ACV_USED=1 ;;
        *) return 1 ;;
    esac
}

acv_check() {
    [[ $NAME =~ ^[a-z0-9][a-z0-9-]{0,40}$ ]] || die "--name must be lowercase letters, digits and dashes"
    [[ $USER_NAME =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || die "--user is not a valid login name"
    [[ $MEMORY =~ ^[0-9]+$ && $VCPUS =~ ^[0-9]+$ ]] || die "--memory and --vcpus must be numbers"

    local tool
    for tool in virsh qemu-img xorriso gpg openssl ssh-keygen curl sha256sum; do
        command -v "$tool" >/dev/null || die "$tool is not installed (sudo pacman -S --needed xorriso gnupg openssl openssh curl)"
    done

    # An imported public key, checked before anything is created.
    PUB=
    if [ -n "$SSH_KEY_ARG" ]; then
        if [ -f "$SSH_KEY_ARG" ]; then PUB=$(head -n 1 "$SSH_KEY_ARG"); else PUB=$SSH_KEY_ARG; fi
        case $PUB in
            *"PRIVATE KEY"*) die "--ssh-key needs a public key, and this is a private one" ;;
        esac
        local probe; probe=$(mktemp); printf '%s\n' "$PUB" > "$probe"
        ssh-keygen -l -f "$probe" >/dev/null 2>&1 || { rm -f "$probe"; die "--ssh-key is not a valid public key: $SSH_KEY_ARG"; }
        rm -f "$probe"
    fi

    SUDO=
    [ "$(id -u)" -ne 0 ] && SUDO=sudo

    vsys version >/dev/null 2>&1 \
        || die "cannot reach qemu:///system; run opt/virt.sh, then log out and back in (libvirt group)"
    [ "$(vsys net-info "$LAB_NET" 2>/dev/null | awk '/^Active:/ { print $2 }')" = yes ] \
        || die "network $LAB_NET is not active; run opt/virt.sh"

    # The VM gets its address from the dnsmasq on labbr0, which ufw's
    # default-deny-incoming blocks unless DHCP and DNS are allowed in on the bridge
    # (opt/virt.sh does this too; it is repeated here for a ufw enabled since).
    . "$(dirname "${BASH_SOURCE[0]}")/lab-firewall.sh"
    lab_ufw_dhcp_dns

    CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/arch-cloud-vm"
    STATE="${XDG_CONFIG_HOME:-$HOME/.config}/arch-cloud-vm"
    KEY="$HOME/.ssh/arch-cloud-$NAME-ed25519"
    OVERLAY="$POOL/$NAME.qcow2"
    SEED="$POOL/$NAME-seed.iso"
    mkdir -p "$CACHE"
}

vsys() { $SUDO virsh -c qemu:///system "$@"; }

acv_image() {
    # ── an existing VM of this name ────────────────────────────────────────
    if vsys dominfo "$NAME" >/dev/null 2>&1; then
        [ "$REPLACE" = 1 ] || die "domain $NAME exists; remove it or pass --replace"
        say "Replacing $NAME"
        [ "$(vsys domstate "$NAME")" = "shut off" ] || vsys destroy "$NAME" >/dev/null
        vsys undefine "$NAME" --nvram >/dev/null
        $SUDO rm -f "$OVERLAY" "$SEED"
    elif $SUDO test -e "$OVERLAY"; then
        die "$OVERLAY exists without a domain; remove it or pick another --name"
    fi

    # ── the image, verified ────────────────────────────────────────────────
    say "Fetching the image checksum"
    curl -fsSL -o "$CACHE/$IMG.SHA256" "$BASE_URL/$IMG.SHA256"
    local latest progress gh keyfile status
    latest=$(awk -v f="$IMG" '$2 == f { print $1 }' "$CACHE/$IMG.SHA256")
    [[ $latest =~ ^[0-9a-f]{64}$ ]] || die "could not read the SHA256 for $IMG"

    local image="$CACHE/$IMG-${latest:0:16}"
    if [ ! -f "$image" ] || [ "$(sha256sum "$image" | awk '{ print $1 }')" != "$latest" ]; then
        say "Downloading $IMG"
        tmp=$(mktemp "$CACHE/download.XXXXXX")
        trap 'rm -f "$tmp"' EXIT
        if [ -t 1 ]; then progress=--progress-bar; else progress=-sS; fi
        curl -fL $progress -o "$tmp" "$BASE_URL/$IMG"
        [ "$(sha256sum "$tmp" | awk '{ print $1 }')" = "$latest" ] || die "SHA256 mismatch for the download"

        say "Checking the arch-boxes signature"
        curl -fsSL -o "$CACHE/$IMG.sig" "$BASE_URL/$IMG.sig"
        gh=$(mktemp -d "$CACHE/gnupg.XXXXXX")
        keyfile=$(mktemp "$CACHE/key.XXXXXX")
        printf '%s\n' "$ARCH_BOXES_KEY" > "$keyfile"
        gpg --homedir "$gh" --batch --quiet --import "$keyfile" 2>/dev/null
        status=$(gpg --homedir "$gh" --batch --status-fd 1 --verify "$CACHE/$IMG.sig" "$tmp" 2>/dev/null || true)
        rm -rf "$gh" "$keyfile"
        [ "$(awk '/^\[GNUPG:\] VALIDSIG/ { print $NF }' <<<"$status")" = "$ARCH_BOXES_FPR" ] \
            || die "signature does not verify against the arch-boxes key $ARCH_BOXES_FPR"
        mv "$tmp" "$image"
        trap - EXIT
    fi

    local base="$POOL/arch-cloud-base-${latest:0:12}.qcow2"
    if ! $SUDO test -e "$base"; then
        say "Installing the base image in $POOL"
        $SUDO install -m 0644 "$image" "$base"
    fi

    # ── the overlay disk ───────────────────────────────────────────────────
    say "Creating the $DISK overlay disk"
    $SUDO qemu-img create -q -f qcow2 -F qcow2 -b "$base" "$OVERLAY" "$DISK"
}

# ── SSH key and password ───────────────────────────────────────────────────
acv_credentials() {
    install -d -m 700 "$HOME/.ssh"
    if [ -n "$PUB" ]; then
        say "Importing the public key from --ssh-key"
    else
        if [ ! -f "$KEY" ]; then
            say "Generating $KEY"
            ssh-keygen -q -t ed25519 -N "" -C "arch-cloud-vm:$NAME" -f "$KEY"
        fi
        PUB=$(cat "$KEY.pub")
    fi

    PASS=$(openssl rand -base64 30 | tr -dc 'A-Za-z0-9' | cut -c1-20)
    HASH=$(printf '%s' "$PASS" | openssl passwd -6 -stdin)
    install -d -m 700 "$STATE"
    (umask 077; printf '%s\n' "$PASS" > "$STATE/$NAME.password")
}

# ── cloud-init seed (NoCloud) ──────────────────────────────────────────────
acv_seed() {
    work=$(mktemp -d "$CACHE/seed.XXXXXX")
    trap 'rm -rf "$work"' EXIT
    cat > "$work/user-data" <<YAML
#cloud-config
hostname: $NAME
users:
  - name: $USER_NAME
    groups: [wheel]
    sudo: $SUDO_RULE
    shell: /bin/bash
    lock_passwd: false
    passwd: '$HASH'
    ssh_authorized_keys:
      - '${PUB//\'/\'\'}'
ssh_pwauth: false
disable_root: true
$ACV_USERDATA_EXTRA
YAML
    cat > "$work/meta-data" <<META
instance-id: $NAME-$(date +%s)
local-hostname: $NAME
META
    # No network-config: cloud-init's default DHCPs every ethernet device. An explicit
    # one keyed by a name made it write Name=<key> instead of matching the NIC.
    xorriso -as mkisofs -quiet -output "$work/seed.iso" -volid cidata -joliet -rock \
        "$work/user-data" "$work/meta-data" >/dev/null 2>&1
    $SUDO install -m 0644 "$work/seed.iso" "$SEED"
}

# ── the domain ─────────────────────────────────────────────────────────────
acv_domain() {
    cat > "$work/domain.xml" <<XML
<domain type='kvm'>
  <name>$NAME</name>
  <memory unit='MiB'>$MEMORY</memory>
  <vcpu>$VCPUS</vcpu>
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
      <source file='$OVERLAY'/>
      <target dev='vda' bus='virtio'/>
    </disk>
    <disk type='file' device='cdrom'>
      <driver name='qemu' type='raw'/>
      <source file='$SEED'/>
      <target dev='sda' bus='sata'/>
      <readonly/>
    </disk>
    <interface type='network'>
      <source network='$LAB_NET'/>
      <model type='virtio'/>
    </interface>
    <serial type='pty'><target port='0'/></serial>
    <console type='pty'><target type='serial' port='0'/></console>
    <rng model='virtio'><backend model='random'>/dev/urandom</backend></rng>
$ACV_DEVICES_EXTRA
  </devices>
</domain>
XML
    vsys define "$work/domain.xml" >/dev/null
    vsys start "$NAME" >/dev/null
}

acv_report() {
    say "Waiting for an address on $LAB_NET"
    ip=
    local _
    for _ in $(seq 60); do
        ip=$(vsys domifaddr "$NAME" --source lease 2>/dev/null | awk '$3 == "ipv4" { print $4 }' | cut -d/ -f1 | head -1)
        [ -n "$ip" ] && break
        sleep 3
    done

    echo
    echo "VM:        $NAME on $LAB_NET${ip:+, $ip}"
    if [ -z "$SSH_KEY_ARG" ]; then
        echo "SSH:       ssh -i $KEY $USER_NAME@${ip:-<address>}"
    elif [ -f "$SSH_KEY_ARG" ] && [ -f "${SSH_KEY_ARG%.pub}" ] && [ "${SSH_KEY_ARG%.pub}" != "$SSH_KEY_ARG" ]; then
        echo "SSH:       ssh -i ${SSH_KEY_ARG%.pub} $USER_NAME@${ip:-<address>}"
    else
        echo "SSH:       ssh $USER_NAME@${ip:-<address>}   (with the private half of the imported key)"
    fi
    echo "Password:  $PASS   (for sudo and the console; saved to $STATE/$NAME.password)"
    echo "Console:   virsh -c qemu:///system console $NAME"
    ! declare -F acv_report_extra >/dev/null || acv_report_extra
    [ -n "$ip" ] || echo "cloud-init may still be running; the address appears once DHCP answers."
}
