#!/usr/bin/env bash
# System setup: login shell, ly, services, nix, firewall, touchpad, keyring.
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

# ly's settings overlay (colours come from the theme; see x11-theme apply_ly).
#
# ly reads exactly one config file, /etc/ly/config.ini - the path is compiled in,
# and there is no ~/.config/ly/config.ini fallback - so the theme has to be merged
# into that file. Merging rather than replacing keeps every setting we do not care
# about at its packaged value, and keeps working across upgrades that add keys.
#
# The original is kept once as config.ini.cachy-orig; re-running restores from it
# first, so the merge is idempotent instead of accumulating.
install_ly_theme() {
    # LY_CONFIG exists so this can be pointed elsewhere for testing; normal use
    # is the system path.
    local target="${LY_CONFIG:-/etc/ly/config.ini}"
    local src="$REPO/ly/overlay.ini"
    local pristine="$target.cachy-orig"

    [ -r "$src" ] || return 0
    if [ ! -f "$target" ]; then
        warn "$target not found; skipping the ly theme (is the 'ly' package installed?)"
        return
    fi

    say "Applying the ly overlay"
    local merged
    merged=$(mktemp)

    if [ -f "$pristine" ]; then
        cat "$pristine" > "$merged"
    else
        cat "$target" > "$merged"
        run $SUDO cp -a "$target" "$pristine"
        echo "saved pristine copy as $pristine"
    fi

    # Replace each key we theme in place; append any key the packaged file lacks.
    # Operating on the pristine copy means re-running never stacks duplicates.
    awk -v overlay="$src" '
        function keyof(s) { k = s; sub(/=.*/, "", k); gsub(/[[:space:]]/, "", k); return k }
        function valof(s) {
            v = substr(s, index(s, "=") + 1)
            sub(/^[[:space:]]+/, "", v); sub(/[[:space:]]+$/, "", v)
            return v
        }
        BEGIN {
            while ((getline line < overlay) > 0) {
                if (line ~ /^[a-z_]+[[:space:]]*=/) {
                    k = keyof(line)
                    if (!(k in val)) order[++n] = k
                    val[k] = valof(line)
                }
            }
            close(overlay)
        }
        {
            if ($0 ~ /^[a-z_]+[[:space:]]*=/) {
                k = keyof($0)
                if (k in val) { print k " = " val[k]; done_[k] = 1; next }
            }
            print
        }
        END {
            for (i = 1; i <= n; i++)
                if (!(order[i] in done_)) print order[i] " = " val[order[i]]
        }
    ' "$merged" > "$merged.new" && mv "$merged.new" "$merged"

    if cmp -s "$merged" "$target"; then
        echo "ly theme: already up to date"
    else
        run $SUDO install -m 644 "$merged" "$target"
        echo "ly theme: written to $target"
    fi
    rm -f "$merged"

    # The merge starts from the pristine file, so put the theme's colours back.
    if [ "$dry" = 0 ] && [ -f "$HOME/.local/state/omarchy/current/theme.name" ]; then
        "$REPO/bin/x11-theme" apply-ly || true
    fi
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
    if pacman -Qq bluez >/dev/null 2>&1; then
        run $SUDO systemctl enable bluetooth.service \
            || warn "could not enable bluetooth.service"
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

# Firewall: deny incoming, allow outgoing (CachyOS ships ufw like this already;
# this makes it so everywhere). SSH is allowed FIRST when sshd is enabled: on a
# headless host it is the way in, and a deny-all firewall without it would cut
# the installing session off. Rate-limited (ufw limit) when this adds the rule;
# an existing rule for port 22 is left as it is. Listeners for CTF work (reverse
# shells, HTTP servers) need their own rule: `sudo ufw allow 4444/tcp`.
setup_firewall() {
    command -v ufw >/dev/null || return 0
    say "Firewall (ufw): deny incoming, allow outgoing"
    if [ "$dry" = 1 ]; then echo "+ ufw: allow ssh if sshd is enabled, default deny incoming, enable"; return; fi
    if systemctl is-enabled --quiet sshd 2>/dev/null \
        && ! $SUDO ufw status | grep -qE '^22(/tcp)?[[:space:]]'; then
        $SUDO ufw limit 22/tcp comment 'ssh (cachy-dots)' >/dev/null && echo "ufw: ssh allowed (rate-limited)"
    fi
    $SUDO ufw default deny incoming >/dev/null
    $SUDO ufw default allow outgoing >/dev/null
    if ! $SUDO ufw status | grep -q '^Status: active'; then
        # Fails when the running kernel has lost its netfilter modules, which a
        # kernel upgrade in this run causes until a reboot (checked at the end).
        if $SUDO ufw --force enable >/dev/null; then
            echo "ufw: enabled"
        else
            warn "ufw could not start; reboot into the new kernel, then run: sudo ufw enable"
            FAILED=1
        fi
    fi
    $SUDO systemctl enable --quiet ufw.service || warn "could not enable ufw.service"
    $SUDO ufw status | sed -n '1p' || true
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
