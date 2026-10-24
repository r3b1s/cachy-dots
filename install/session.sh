#!/usr/bin/env bash
# The desktop session the dots are set up for: i3 (X11) or Hyprland with dux.
# One is active at a time. bin/cachy-session switches; install.sh and sync.sh
# re-apply the active one right after install_links. Sourced through
# install/lib.sh; defines functions only.
#
# A session owns some links (removed when the other one becomes active), points
# a few colour slots (one link each, retargeted on a switch), and masks user
# units that would otherwise start by D-Bus activation and get in its way.
# Everything else install_links makes is shared by both.

session_state_file() { echo "${XDG_CONFIG_HOME:-$HOME/.config}/cachy-dots/session"; }

# The active session: SESSION, else the recorded one, else i3 (a system set up
# before sessions existed is an i3 one).
active_session() {
    local s=${SESSION:-}
    [ -n "$s" ] || s=$(cat "$(session_state_file)" 2>/dev/null || true)
    case "$s" in
        i3|hyprland) echo "$s" ;;
        *) echo i3 ;;
    esac
}

# Scripts in bin/ that only the i3 session uses: i3 IPC, X11-only tools, or what
# dux does itself under Hyprland. install_links leaves these to the session.
I3_ONLY_BIN=(x11-clipboard x11-display x11-focus x11-gaps-cycle x11-idle x11-keybinds-menu
             x11-lock x11-monitor x11-nightlight x11-power-menu x11-theme x11-wallpaper)

# Started by D-Bus activation unless masked: dunst would take the notification
# name if a notification came before dux is up, and blueman's applet would add a
# tray icon dux has no use for. Masked under Hyprland, unmasked under i3.
HYPRLAND_MASKED_UNITS=(dunst.service blueman-applet.service)

# The first line of a file this module wrote in place of a link, so it can tell
# its own stub from a file the user put there.
SESSION_STUB_MARK="# cachy-session stub"

# The links a session owns, one "src<TAB>dst" per line.
session_links() {
    local cfg="${XDG_CONFIG_HOME:-$HOME/.config}" f
    local th="$HOME/.local/state/omarchy/current/theme"
    case "$1" in
        i3)
            printf '%s\t%s\n' "$REPO/i3/config" "$cfg/i3/config"
            for f in "$REPO"/i3/conf.d/*.conf; do
                printf '%s\t%s\n' "$f" "$cfg/i3/conf.d/$(basename "$f")"
            done
            # Read by ly's setup.sh for X sessions only, but its PATH and
            # XDG_CURRENT_DESKTOP are i3's, so it goes with i3.
            printf '%s\t%s\n' "$REPO/shell/xprofile" "$HOME/.xprofile"
            printf '%s\t%s\n' "$REPO/dunst/dunstrc" "$cfg/dunst/dunstrc"
            printf '%s\t%s\n' "$th/dunst.conf" "$cfg/dunst/dunstrc.d/90-theme.conf"
            for f in "${I3_ONLY_BIN[@]}"; do
                printf '%s\t%s\n' "$REPO/bin/$f" "$HOME/.local/bin/$f"
            done
            ;;
        hyprland)
            # dux owns hyprland.lua and the rest of hypr/dms/; these two are ours.
            printf '%s\t%s\n' "$REPO/hypr/cachy.lua" "$cfg/hypr/cachy.lua"
            printf '%s\t%s\n' "$REPO/hypr/dms/binds-user.lua" "$cfg/hypr/dms/binds-user.lua"
            ;;
    esac
}

is_session_stub() { [ -f "$1" ] && [ ! -L "$1" ] && head -n1 "$1" | grep -qxF "$SESSION_STUB_MARK"; }

# Removes a session's links, each only while it still points where the session
# put it: a real file, or a link the user repointed, is left alone.
unlink_session() {
    local src dst
    while IFS=$'\t' read -r src dst; do
        if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
            run rm "$dst"
            echo "unlinked $dst"
        fi
    done < <(session_links "$1")
}

link_session() {
    local src dst
    if [ "$1" = i3 ]; then
        # The i3 config is linked file by file: conf.d/04-monitors.conf is a
        # per-host copy, so ~/.config/i3 is a real directory. An old
        # whole-directory link is removed first.
        retire_dir_link "${XDG_CONFIG_HOME:-$HOME/.config}/i3" "$REPO/i3"
    fi
    while IFS=$'\t' read -r src dst; do
        if is_session_stub "$dst"; then
            run rm "$dst"
        fi
        link "$src" "$dst"
    done < <(session_links "$1")
    [ "$1" = i3 ] && import_monitors_conf
    return 0
}

# Under Hyprland, ~/.config/i3/config is a stub, so picking i3 at the login
# screen says what is going on instead of starting i3's own default config and
# its config wizard (which would write a real ~/.config/i3/config).
write_i3_stub() {
    local f="${XDG_CONFIG_HOME:-$HOME/.config}/i3/config"
    if [ -e "$f" ] || [ -L "$f" ]; then
        is_session_stub "$f" && return 0
        warn "$f is not a cachy-dots link or stub; left as it is"
        return 0
    fi
    if [ "$dry" = 1 ]; then echo "+ write the i3 stub $f"; return 0; fi
    mkdir -p "$(dirname "$f")"
    cat > "$f" <<EOF
$SESSION_STUB_MARK
# The Hyprland session is active (bin/cachy-session). To use i3 again, run
# \`cachy-session i3\`, then log out and back in.
exec --no-startup-id i3-nagbar -t warning -m 'The Hyprland session is active. Run: cachy-session i3, then log out and pick i3.' -B 'Log out' 'i3-msg exit'
bindsym Mod4+Shift+e exec i3-msg exit
EOF
    echo "wrote the i3 stub $f"
}

# gtk.css is dux's when it is a real file that only imports dux's colours: what
# point_slots writes under Hyprland, and what dux's own gtk.sh writes.
is_dux_gtk_css() {
    [ -f "$1" ] && [ ! -L "$1" ] && [ "$(grep -cv '^[[:space:]]*$' "$1")" -le 1 ] \
        && grep -qE '^@import url.*dank-colors\.css.*\);$' "$1"
}

# The colour slots: one link (gtk.css: a link or a file) per app that both
# sessions theme, pointed at the active session's colours.
point_slots() {
    local cfg="${XDG_CONFIG_HOME:-$HOME/.config}" d f
    local th="$HOME/.local/state/omarchy/current/theme"
    case "$1" in
        i3)
            link "$th/alacritty.toml" "$cfg/alacritty/colors.toml"
            link "$th/kitty.conf" "$cfg/kitty/colors.conf"
            link "$th/satty.config.toml" "$cfg/satty/config.toml"
            for d in gtk-3.0 gtk-4.0; do
                is_dux_gtk_css "$cfg/$d/gtk.css" && run rm "$cfg/$d/gtk.css"
                link "$th/gtk.css" "$cfg/$d/gtk.css"
            done
            ;;
        hyprland)
            # dux writes these on its first theme generation; until then the
            # terminals keep x11-theme's colours, and the next sync.sh or
            # cachy-session run repoints them.
            for f in alacritty/colors.toml:alacritty/dank-theme.toml kitty/colors.conf:kitty/dank-theme.conf; do
                if [ -f "$cfg/${f#*:}" ]; then
                    link "$cfg/${f#*:}" "$cfg/${f%%:*}"
                else
                    echo "note: no $cfg/${f#*:} yet (dux writes it); $cfg/${f%%:*} keeps x11-theme's colours"
                fi
            done
            link "$REPO/satty/config-wayland.toml" "$cfg/satty/config.toml"
            # A real file importing dux's colours, which dux's gtk.sh recognises as
            # its own (it leaves a symlink alone).
            for d in gtk-3.0 gtk-4.0; do
                is_dux_gtk_css "$cfg/$d/gtk.css" && continue
                if [ -L "$cfg/$d/gtk.css" ] && [ "$(readlink "$cfg/$d/gtk.css")" = "$th/gtk.css" ]; then
                    run rm "$cfg/$d/gtk.css"
                elif [ -e "$cfg/$d/gtk.css" ] || [ -L "$cfg/$d/gtk.css" ]; then
                    warn "$cfg/$d/gtk.css is not x11-theme's link; left as it is (import dank-colors.css there for dux's colours)"
                    continue
                fi
                if [ "$dry" = 1 ]; then echo "+ write $cfg/$d/gtk.css (imports dank-colors.css)"; continue; fi
                mkdir -p "$cfg/$d"
                echo '@import url("dank-colors.css");' > "$cfg/$d/gtk.css"
                echo "wrote $cfg/$d/gtk.css (imports dux's dank-colors.css)"
            done
            ;;
    esac
}

# A mask is a link to /dev/null in the user's unit directory: no root, no running
# user manager needed, and it survives package updates.
mask_units() {
    local dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user" u changed=0
    for u in "${HYPRLAND_MASKED_UNITS[@]}"; do
        if [ "$1" = mask ]; then
            [ "$(readlink "$dir/$u" 2>/dev/null)" = /dev/null ] && continue
            if [ -e "$dir/$u" ] || [ -L "$dir/$u" ]; then
                warn "$dir/$u exists; not masking it"
                continue
            fi
            run mkdir -p "$dir"
            run ln -s /dev/null "$dir/$u"
            echo "masked $u"
        else
            [ "$(readlink "$dir/$u" 2>/dev/null)" = /dev/null ] || continue
            run rm "$dir/$u"
            echo "unmasked $u"
        fi
        changed=1
    done
    if [ "$changed" = 1 ] && [ "$dry" = 0 ]; then
        systemctl --user daemon-reload 2>/dev/null || true
    fi
}

# The one line cachy-dots adds to dux's hyprland.lua: it loads hypr/cachy.lua
# (submaps, the session environment, voxtype's daemon) after dux's own modules.
# Re-added if a `dms setup` that replaced hyprland.lua dropped it.
CACHY_REQUIRE='require("cachy") -- cachy-dots: hypr/cachy.lua (added by cachy-session)'

ensure_cachy_require() {
    local f="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprland.lua"
    [ -f "$f" ] || { warn "$f is missing: run \`dms setup\` (see opt/hyprland.sh)"; return 0; }
    grep -qF 'require("cachy")' "$f" && return 0
    if [ "$dry" = 1 ]; then echo "+ append to $f: $CACHY_REQUIRE"; return 0; fi
    printf '\n%s\n' "$CACHY_REQUIRE" >> "$f"
    echo "added require(\"cachy\") to $f"
}

record_session() {
    [ "$dry" = 1 ] && { echo "+ record the session ($1)"; return; }
    mkdir -p "$(dirname "$(session_state_file)")"
    echo "$1" > "$(session_state_file)"
}

# Makes the session in $1 (default: the active one) the one set up: the other
# session's links go, this one's are made, the colour slots point at its colours.
apply_session() {
    local s=${1:-$(active_session)} other=i3
    [ "$s" = i3 ] && other=hyprland
    say "Session: $s"
    unlink_session "$other"
    [ "$s" = hyprland ] && write_i3_stub
    link_session "$s"
    point_slots "$s"
    if [ "$s" = hyprland ]; then
        mask_units mask
        ensure_cachy_require
    else
        mask_units unmask
    fi
    record_session "$s"
}

# Hyprland's own check of the config dux wrote and ours on top of it.
validate_hyprland() {
    local cfg="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprland.lua"
    if [ "$dry" = 0 ] && command -v Hyprland >/dev/null && [ -f "$cfg" ]; then
        say "Validating the Hyprland config"
        Hyprland --verify-config -c "$cfg" >/dev/null 2>&1 && echo "Hyprland config OK" \
            || warn "Hyprland reports errors in $cfg (run: Hyprland --verify-config -c $cfg)"
    fi
}

validate_session() {
    if [ "$(active_session)" = i3 ]; then validate_i3; else validate_hyprland; fi
}
