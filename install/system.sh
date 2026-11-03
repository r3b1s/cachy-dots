#!/usr/bin/env bash
# System setup: login shell, services, nix, firewall, touchpad, keyring.
# Sourced by install.sh, install_vm.sh and sync.sh through install/lib.sh; defines
# functions and package lists only, and runs nothing.

# The shell integrations (shell/) are bash-only, and CachyOS makes fish the
# login shell, so alacritty would start fish and never load them. Switch the
# login shell to bash; fish stays installed (it is CachyOS's package, not ours).
# Run as root (sudo), chsh does not ask for the user's password.
setup_login_shell() {
    local current bash_path=/bin/bash
    current=$(getent passwd "$TARGET_USER" | cut -d: -f7)
    case "$current" in
        /bin/bash|/usr/bin/bash) return 0 ;;
    esac
    [ "$TARGET_USER" = root ] && { warn "running as root without sudo; not changing root's shell"; return 0; }

    say "Changing the login shell of $TARGET_USER: $current -> $bash_path"
    run $SUDO chsh -s "$bash_path" "$TARGET_USER" \
        || { warn "could not change the login shell to bash"; return 0; }
    echo "login shell: $bash_path (applies at next login)"
}

# nix is for project-specific environments only (`nix-shell`, `nix develop`):
# no channels and no flake registry changes. What is set up:
#   - the daemon runs as a system service: nix-daemon.socket for activation and
#     nix-daemon.service enabled, so it is up at boot rather than only on demand
#   - /etc/nix/nix.conf enables the nix-command and flakes experimental features
#     and makes the user a trusted user (may pass build settings, e.g. substituters)
# Both go into one managed block of extra-* settings, which append to whatever the
# packaged file or a hand edit already says, rather than replace it. Re-running
# rewrites the block; the rest of the file is never touched.
NIX_CONF=/etc/nix/nix.conf

setup_nix_conf() {
    local user=$1 open="# >>> cachy-dots >>>" close="# <<< cachy-dots <<<"
    local block tmp
    block=$(printf '%s\nextra-experimental-features = nix-command flakes\nextra-trusted-users = %s\n%s\n' \
        "$open" "$user" "$close")

    if [ "$dry" = 1 ]; then
        echo "+ write to $NIX_CONF:"; printf '%s\n' "$block" | sed 's/^/+   /'
        return 0
    fi
    tmp=$(mktemp)
    # The file without any earlier managed block, then the block.
    { [ ! -f "$NIX_CONF" ] || awk -v o="$open" -v c="$close" '$0 == o { skip = 1; next } $0 == c { skip = 0; next } !skip' "$NIX_CONF"
      printf '%s\n' "$block"; } > "$tmp"
    if [ -f "$NIX_CONF" ] && cmp -s "$tmp" "$NIX_CONF"; then
        rm -f "$tmp"; return 1
    fi
    $SUDO install -Dm644 "$tmp" "$NIX_CONF"
    rm -f "$tmp"
    echo "nix.conf: nix-command and flakes enabled, $user trusted"
}

# TERMINAL: the default terminal, for scripts (x11-theme's picker, and whatever a
# terminal menu sets later). pam_env reads /etc/environment at every login, ly's
# included, so this reaches the i3 session and everything it starts. A managed
# block keeps the rest of the file as it is; it is rewritten on re-runs and only
# written when it differs. TERMINAL_ENV_FILE points it elsewhere (for tests).
setup_terminal_env() {
    local value=${1:-alacritty} file=${TERMINAL_ENV_FILE:-/etc/environment}
    local open="# >>> cachy-dots >>>" close="# <<< cachy-dots <<<"
    local block stripped tmp
    block=$(printf '%s\nTERMINAL=%s\n%s\n' "$open" "$value" "$close")

    if [ "$dry" = 1 ]; then
        echo "+ write to $file:"; printf '%s\n' "$block" | sed 's/^/+   /'
        return 0
    fi
    stripped=$([ ! -f "$file" ] || awk -v o="$open" -v c="$close" '$0 == o { skip = 1; next } $0 == c { skip = 0; next } !skip' "$file")
    if printf '%s\n' "$stripped" | grep -q '^TERMINAL='; then
        warn "$file sets TERMINAL outside the cachy-dots block; check which one should win"
    fi
    tmp=$(mktemp)
    { [ -z "$stripped" ] || printf '%s\n' "$stripped"; printf '%s\n' "$block"; } > "$tmp"
    if [ -f "$file" ] && cmp -s "$tmp" "$file"; then
        rm -f "$tmp"; return 0
    fi
    $SUDO install -Dm644 "$tmp" "$file"
    rm -f "$tmp"
    echo "$file: TERMINAL=$value (takes effect at the next login)"
}

enable_nix() {
    pacman -Qq nix >/dev/null 2>&1 || return 0
    command -v systemctl >/dev/null || return 0

    local user="${SUDO_USER:-${USER:-}}" changed=0
    if [ -n "$user" ] && [ "$user" != root ]; then
        setup_nix_conf "$user" && changed=1 || true
    else
        warn "no non-root user to make a trusted nix user; leaving trusted-users alone"
    fi

    say "Enabling nix-daemon"
    # A running daemon reads nix.conf only at start.
    if [ "$changed" = 1 ] && systemctl is-active --quiet nix-daemon.service; then
        run $SUDO systemctl restart nix-daemon.service \
            || warn "could not restart nix-daemon.service"
    fi
    run $SUDO systemctl enable --now nix-daemon.socket nix-daemon.service \
        || warn "could not enable nix-daemon"

    # Multi-user nix: membership of nix-users (when the package ships it) is
    # what lets a normal user talk to the daemon. Applies at next login.
    if [ -n "$user" ] && [ "$user" != root ] && getent group nix-users >/dev/null; then
        if ! id -nG "$user" | tr ' ' '\n' | grep -qx nix-users; then
            run $SUDO usermod -aG nix-users "$user"
            echo "added $user to nix-users (log out and back in for it to apply)"
        fi
    fi
}

enable_services() {
    command -v systemctl >/dev/null || return 0
    say "Enabling guest services"

    # ly is the display manager: `ly@.service` is a template, so the instance is
    # named for the tty it takes over. It Conflicts= getty@tty1, which systemd
    # resolves automatically.
    if pacman -Qq ly >/dev/null 2>&1; then
        run $SUDO systemctl enable ly@tty1.service \
            || warn "could not enable ly@tty1.service"
        if systemctl is-enabled --quiet "${DISPLAY_MANAGER:-lightdm}.service" 2>/dev/null; then
            warn "another display manager (${DISPLAY_MANAGER}) is enabled; disable it or ly will not start"
        fi
    fi
    # bluetoothd. Its unit is conditioned on /sys/class/bluetooth, so on a host
    # without an adapter (any VM) it is enabled but simply never starts.
    # The rfkill units (setup_bluetooth_off) keep its radio blocked until turned on by hand.
    if pacman -Qq bluez >/dev/null 2>&1; then
        run $SUDO systemctl enable bluetooth.service "${BLUETOOTH_UNITS[@]}" \
            || warn "could not enable bluetooth.service and the rfkill units"
    fi

    if pacman -Qq power-profiles-daemon >/dev/null 2>&1; then
        run $SUDO systemctl enable --now power-profiles-daemon.service \
            || warn "could not enable power-profiles-daemon.service"
    fi

    # Nothing to enable for the guest agents: spice-vdagentd.socket and
    # qemu-guest-agent are both static units, pulled in by udev rules when their
    # virtio port (com.redhat.spice.0 / org.qemu.guest_agent.0) appears. Start
    # the socket now so the first session does not need a reboot.
    [ "$IS_VM" = 1 ] || return 0
    if [ -e /dev/virtio-ports/com.redhat.spice.0 ]; then
        run $SUDO systemctl start spice-vdagentd.socket \
            || warn "could not start spice-vdagentd.socket"
    else
        warn "no SPICE virtio port; spice-vdagent (clipboard, resize) will be idle"
    fi
}

# Bluetooth is off until turned on by hand: at boot, at login and after every wake,
# even when it was on before sleep. Two layers:
#   - BlueZ's AutoEnable=false: bluetoothd powers on no controller it finds, at boot,
#     after a resume or when a dongle is plugged in. With the default (true), an
#     adapter turned off in blueman came back after a wake, because Intel controllers
#     reload their firmware on resume and bluetoothd sees a new one. BlueZ has no
#     drop-in directory, so main.conf gets a managed block holding a second [Policy]
#     section, which GLib's keyfile parser merges into the first (the later key wins).
#     bluetoothd reads it at its next start, which is left to the next boot so a
#     connected headset is not dropped.
#   - an rfkill soft block at boot, before every sleep and after every wake
#     (systemd/cachy-bluetooth-off*.service, enabled by enable_services), so the
#     radio itself stays off whatever asks to power it.
# Turning it on needs no root: blueman unblocks through its polkit helper, and
# bluetoothd unblocks rfkill itself when asked to power on (the shells' toggles).
BLUETOOTH_CONF=/etc/bluetooth/main.conf
BLUETOOTH_UNITS=(cachy-bluetooth-off.service cachy-bluetooth-off-wake.service)

setup_bluetooth_off() {
    pacman -Qq bluez >/dev/null 2>&1 || return 0
    local open="# >>> cachy-dots >>>" close="# <<< cachy-dots <<<"
    local block tmp unit changed=0
    block=$(printf '%s\n[Policy]\nAutoEnable=false\n%s\n' "$open" "$close")

    if [ "$dry" = 1 ]; then
        echo "+ write to $BLUETOOTH_CONF:"; printf '%s\n' "$block" | sed 's/^/+   /'
    else
        tmp=$(mktemp)
        # The file without any earlier managed block, then the block.
        { [ ! -f "$BLUETOOTH_CONF" ] || awk -v o="$open" -v c="$close" '$0 == o { skip = 1; next } $0 == c { skip = 0; next } !skip' "$BLUETOOTH_CONF"
          printf '%s\n' "$block"; } > "$tmp"
        if ! { [ -f "$BLUETOOTH_CONF" ] && cmp -s "$tmp" "$BLUETOOTH_CONF"; }; then
            $SUDO install -Dm644 "$tmp" "$BLUETOOTH_CONF"
            echo "bluetooth: AutoEnable=false in $BLUETOOTH_CONF (applies at the next boot)"
        fi
        rm -f "$tmp"
    fi

    for unit in "${BLUETOOTH_UNITS[@]}"; do
        cmp -s "$REPO/systemd/$unit" "/etc/systemd/system/$unit" 2>/dev/null && continue
        run $SUDO install -D -o root -g root -m 644 "$REPO/systemd/$unit" "/etc/systemd/system/$unit"
        changed=1
    done
    if [ "$changed" = 1 ]; then
        run $SUDO systemctl daemon-reload || warn "could not reload systemd's units"
    fi
}

# Firewall: deny incoming, allow outgoing, in firewalld's default zone. Target DROP,
# as ufw's default deny was, which also drops ping, so echo-request gets a rule (ICMP
# errors for our own connections pass as related, and neighbour discovery is not
# affected). dhcpv6-client and mdns stay open, as ufw's before.rules had them. No
# forwarding between the zone's interfaces.
#
# The zone is set offline, before the daemon loads it, and ssh is settled FIRST: on a
# headless host it is the way in, and a deny-all firewall without it would cut the
# installing session off. The stock zone allows ssh, so it is taken out when no sshd is
# in use. An existing rule for port 22 is left as it is. ssh is not rate-limited: a
# firewalld `limit` is one budget shared by every source, so one scanner would lock
# everyone out; sshd's PerSourcePenalties does this per address, and is on by default.
#
# The zone's other rules are yours and are never touched. Listeners for CTF work
# (reverse shells, HTTP servers) need their own rule, until the next reload with
# `sudo firewall-cmd --add-port=4444/tcp`, for good with --permanent then --reload.
#
# ufw (CachyOS ships it on) goes off only once firewalld is running, so a failed start
# leaves the old firewall up. Its rules are listed, not carried over.
fw_default_zone() { $SUDO firewall-offline-cmd --zone="$zone" "$@" >/dev/null 2>&1; }

setup_firewall() {
    command -v firewall-cmd >/dev/null || return 0
    say "Firewall (firewalld): deny incoming, allow outgoing"
    if [ "$dry" = 1 ]; then echo "+ firewalld: default zone drops incoming, ssh allowed if sshd is in use, start, ufw off"; return; fi

    local zone
    zone=$($SUDO firewall-offline-cmd --get-default-zone)
    if systemctl is-enabled --quiet sshd 2>/dev/null || systemctl is-active --quiet sshd 2>/dev/null; then
        if ! fw_default_zone --query-service=ssh && ! fw_default_zone --query-port=22/tcp; then
            fw_default_zone --add-service=ssh && echo "firewalld: ssh allowed"
        fi
    else
        # Not --remove-service: with --zone, this tool rejects that as a lokkit option.
        fw_default_zone --remove-service-from-zone=ssh
    fi
    fw_default_zone --set-target=DROP \
        && fw_default_zone --remove-forward \
        && fw_default_zone --add-service=dhcpv6-client \
        && fw_default_zone --add-service=mdns \
        && fw_default_zone --add-rich-rule='rule icmp-type name="echo-request" accept' \
        || { warn "could not configure firewalld's $zone zone"; FAILED=1; return 0; }

    $SUDO systemctl enable --quiet firewalld.service || warn "could not enable firewalld.service"
    if $SUDO firewall-cmd -q --state 2>/dev/null; then
        $SUDO firewall-cmd --reload >/dev/null || warn "could not reload firewalld"
    else
        $SUDO systemctl start firewalld.service || true
    fi
    # Never the unit's result: firewalld exits 0 when nftables cannot load, which a
    # kernel upgrade in this run causes until a reboot (checked at the end).
    if ! $SUDO firewall-cmd -q --state 2>/dev/null; then
        warn "firewalld could not start; reboot into the new kernel (it starts there), then re-run this with --packages-only"
        FAILED=1
        return 0
    fi

    if command -v ufw >/dev/null; then
        if $SUDO ufw status 2>/dev/null | grep -q '^Status: active'; then
            warn "turning ufw off; these rules of its own are not carried over to firewalld:"
            $SUDO ufw show added 2>/dev/null | sed -n 's/^ufw /    /p' >&2 || true
            $SUDO ufw --force disable >/dev/null || warn "could not turn ufw off"
        fi
        $SUDO systemctl disable --now --quiet ufw.service 2>/dev/null || true
    fi
    echo "firewalld: running, default zone $zone"
}

# Touchpad: tap to click and friends (xorg/30-touchpad.conf). A root file, so a
# copy; it matches nothing where there is no touchpad.
setup_touchpad() {
    local src="$REPO/xorg/30-touchpad.conf" target=/etc/X11/xorg.conf.d/30-touchpad.conf
    [ -r "$src" ] || return 0
    if [ "$dry" = 1 ]; then echo "+ install $src -> $target"; return; fi
    if ! cmp -s "$src" "$target" 2>/dev/null; then
        $SUDO install -D -o root -g root -m 644 "$src" "$target"
        echo "touchpad: $target (applies at the next X start)"
    fi
}

# A guest that never sleeps (PROFILE_NO_SLEEP, the vm profile): no suspend,
# hibernation, idle action or lid handling in logind, the sleep targets masked so
# nothing can reach them (not even a stray `systemctl suspend`), and X told never to
# blank or power the display off. The session stays up until someone ends it.
# logind reads its drop-in at its next start (a reboot); the rest applies at once or
# at the next X start. Not part of the workstation, where sleep is wanted.
setup_no_sleep() {
    local logind_src="$REPO/systemd/10-cachy-dots-awake.conf" logind_dst=/etc/systemd/logind.conf.d/10-cachy-dots-awake.conf
    local xorg_src="$REPO/xorg/20-no-blanking.conf" xorg_dst=/etc/X11/xorg.conf.d/20-no-blanking.conf
    local units=(sleep.target suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target)
    say "No sleep, hibernation or display blanking"
    if [ -r "$logind_src" ] && ! cmp -s "$logind_src" "$logind_dst" 2>/dev/null; then
        run $SUDO install -D -o root -g root -m 644 "$logind_src" "$logind_dst"
        [ "$dry" = 1 ] || echo "logind: $logind_dst (read at the next boot)"
    fi
    if [ -r "$xorg_src" ] && ! cmp -s "$xorg_src" "$xorg_dst" 2>/dev/null; then
        run $SUDO install -D -o root -g root -m 644 "$xorg_src" "$xorg_dst"
        [ "$dry" = 1 ] || echo "X: $xorg_dst (applies at the next X start)"
    fi
    if command -v systemctl >/dev/null; then
        run $SUDO systemctl mask --quiet "${units[@]}" || warn "could not mask the sleep targets"
    fi
    # Left in place when an earlier run installed them (removing packages is not this
    # step's job), but x11-idle would then still lock after 10 idle minutes.
    if pacman -Qq xss-lock >/dev/null 2>&1; then
        warn "xss-lock is installed and will auto-lock this session; remove it: sudo pacman -Rns xss-lock i3lock-color"
    fi
}

# The keyring (Wi-Fi passwords for nm-applet, Chromium and Vesktop secrets) is
# unlocked at login by pam_gnome_keyring in ly's own PAM file, which the ly
# package ships with those lines. Only checked: if a future package drops them,
# say so rather than edit a root PAM file behind the user's back.
check_keyring_pam() {
    [ -f /etc/pam.d/ly ] || return 0
    if grep -qE '^-?auth[[:space:]]+optional[[:space:]]+pam_gnome_keyring\.so' /etc/pam.d/ly \
        && grep -qE '^-?session[[:space:]]+optional[[:space:]]+pam_gnome_keyring\.so.*auto_start' /etc/pam.d/ly; then
        echo "keyring: unlocked at login by ly's PAM (pam_gnome_keyring)"
    else
        warn "/etc/pam.d/ly lacks pam_gnome_keyring; the keyring will not unlock at login."
        warn "add: 'auth optional pam_gnome_keyring.so' and 'session optional pam_gnome_keyring.so auto_start'"
    fi
}

validate_i3() {
    local cfg="${XDG_CONFIG_HOME:-$HOME/.config}"
    if [ "$dry" = 0 ] && command -v i3 >/dev/null; then
        say "Validating i3 config"
        i3 -C -c "$cfg/i3/config" && echo "i3 config OK"
    fi
}
