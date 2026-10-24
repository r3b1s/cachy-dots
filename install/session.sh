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
            # Read only when XDG_CURRENT_DESKTOP is Hyprland: folders open in Dux Files.
            printf '%s\t%s\n' "$REPO/hypr/hyprland-mimeapps.list" "$cfg/hyprland-mimeapps.list"
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
        # A stub of ours, or a file with nothing but comments (dux's setup writes
        # binds-user.lua as just its header): nothing to back up.
        if is_session_stub "$dst" || { [ -f "$dst" ] && [ ! -L "$dst" ] && ! grep -qvE '^[[:space:]]*(--.*)?$' "$dst"; }; then
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

# The slots: one link (gtk.css: a link or a file) per app that both sessions
# theme, pointed at the active session's colours, and the terminals' font file:
# i3's own font under i3, dux's mono font under Hyprland.
point_slots() {
    local cfg="${XDG_CONFIG_HOME:-$HOME/.config}" d f
    local th="$HOME/.local/state/omarchy/current/theme"
    case "$1" in
        i3)
            link "$th/neovim.lua" "$cfg/nvim/lua/plugins/theme.lua"
            link "$th/alacritty.toml" "$cfg/alacritty/colors.toml"
            link "$th/kitty.conf" "$cfg/kitty/colors.conf"
            link "$REPO/alacritty/font-i3.toml" "$cfg/alacritty/font.toml"
            link "$REPO/kitty/font-i3.conf" "$cfg/kitty/font.conf"
            link "$th/satty.config.toml" "$cfg/satty/config.toml"
            for d in gtk-3.0 gtk-4.0; do
                is_dux_gtk_css "$cfg/$d/gtk.css" && run rm "$cfg/$d/gtk.css"
                link "$th/gtk.css" "$cfg/$d/gtk.css"
            done
            point_file_manager /usr/share/dbus-1/services/org.freedesktop.FileManager1.service
            ;;
        hyprland)
            # dux writes these when it starts (its theme templates for every
            # installed terminal), so before the first Hyprland login the links
            # point at nothing yet.
            # dux's own colourscheme (base46 and `colorscheme dms`); see hypr/nvim-theme.lua.
            link "$REPO/hypr/nvim-theme.lua" "$cfg/nvim/lua/plugins/theme.lua"
            link "$cfg/alacritty/dank-theme.toml" "$cfg/alacritty/colors.toml"
            link "$cfg/kitty/dank-theme.conf" "$cfg/kitty/colors.conf"
            link "$REPO/alacritty/font-hyprland.toml" "$cfg/alacritty/font.toml"
            link "$REPO/kitty/font-hyprland.conf" "$cfg/kitty/font.conf"
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
            point_file_manager /usr/local/share/dbus-1/services/dev.duxlabs.files.FileManager1.service
            ;;
    esac
}

# The GTK (and Qt, through GTK) icon theme: x11-theme's generated one under i3;
# under Hyprland the one picked in dux's settings, else Papirus-Dark, which dux's
# documentation recommends. dux's own default, "System Default", reads it back
# from settings.ini.
session_icon_theme() {
    local s=${1:-$(active_session)} pick
    if [ "$s" = i3 ]; then echo x11-theme; return; fi
    pick=$(jq -r '.iconThemeDark // empty' "${XDG_CONFIG_HOME:-$HOME/.config}/dms/settings.json" 2>/dev/null || true)
    if [ -n "$pick" ] && [ "$pick" != "System Default" ]; then echo "$pick"
    elif [ -d /usr/share/icons/Papirus-Dark ]; then echo Papirus-Dark
    else echo x11-theme; fi
}

# settings.ini and the dconf key both name the icon theme. dux resets its own pick
# to "System Default" when the dconf key changes under it, so the key is set back
# to the session's theme as well.
point_icons() {
    local icons cfg="${XDG_CONFIG_HOME:-$HOME/.config}" d
    icons=$(session_icon_theme "$1")
    for d in gtk-3.0 gtk-4.0; do
        [ -f "$cfg/$d/settings.ini" ] && ini_set "$cfg/$d/settings.ini" gtk-icon-theme-name "$icons"
    done
    if command -v gsettings >/dev/null && [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ] \
        && [ "$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null)" != "'$icons'" ]; then
        run gsettings set org.gnome.desktop.interface icon-theme "$icons" || true
    fi
    return 0
}

# Vesktop's theme: cachy-dots' own (hooks/theme-set.d/vesktop, x11-theme's colours)
# under i3, dux's dank-discord.css (its matugen template) under Hyprland. Vencord
# rewrites enabledThemes from memory when it exits, so this waits for it to be closed.
point_vesktop_theme() {
    local settings="${XDG_CONFIG_HOME:-$HOME/.config}/vesktop/settings/settings.json" on off tmp
    command -v vesktop >/dev/null || [ -f "$settings" ] || return 0
    if [ "$1" = hyprland ]; then on=dank-discord.css off=cachy-dots.theme.css
    else on=cachy-dots.theme.css off=dank-discord.css; fi
    if jq -e --arg on "$on" --arg off "$off" \
        '(.enabledThemes // []) | (index($on) != null) and (index($off) == null)' "$settings" >/dev/null 2>&1; then
        return 0
    fi
    if pgrep -x -u "$(id -u)" 'vesktop|Vesktop' >/dev/null 2>&1; then
        warn "Vesktop is running: close it and re-run cachy-session to switch its theme to $on"
        return 0
    fi
    if [ "$dry" = 1 ]; then echo "+ Vesktop: enable $on, disable $off"; return 0; fi
    mkdir -p "$(dirname "$settings")"
    tmp=$(mktemp)
    if { cat "$settings" 2>/dev/null || echo '{}'; } \
        | jq --arg on "$on" --arg off "$off" '.enabledThemes = (((.enabledThemes // []) - [$off]) + [$on] | unique)' > "$tmp"; then
        mv "$tmp" "$settings"
        echo "Vesktop: theme $on"
    else
        rm -f "$tmp"
        warn "could not edit $settings; pick $on under Vesktop's Settings > Themes"
    fi
}

# dux renders hypr/matugen/omarchy-colors.toml with its own templates, through this
# drop-in in the directory it reads extra matugen configs from; the template's
# post_hook runs `x11-theme from-dux`. matugen wants absolute paths, so the file is
# written here rather than linked.
MATUGEN_DROPIN_MARK="# cachy-dots: written by install/session.sh (cachy-session); i3 removes it"
matugen_dropin() { echo "${XDG_CONFIG_HOME:-$HOME/.config}/matugen/dms/configs/cachy-dots.toml"; }

point_matugen() {
    local f content
    f=$(matugen_dropin)
    if [ "$1" = i3 ]; then
        if [ -f "$f" ] && head -n1 "$f" | grep -qxF "$MATUGEN_DROPIN_MARK"; then
            run rm "$f"
            echo "removed $f"
        fi
        return 0
    fi
    content="$MATUGEN_DROPIN_MARK
[templates.cachy-dots]
input_path = '$REPO/hypr/matugen/omarchy-colors.toml'
output_path = '${XDG_STATE_HOME:-$HOME/.local/state}/cachy-dots/dux-colors.toml'
post_hook = 'sh -c \"$REPO/bin/x11-theme from-dux >/dev/null 2>&1 &\"'"
    [ -f "$f" ] && [ "$(cat "$f")" = "$content" ] && return 0
    if [ -e "$f" ] && ! head -n1 "$f" | grep -qxF "$MATUGEN_DROPIN_MARK"; then
        warn "$f is not cachy-dots'; left as it is"
        return 0
    fi
    if [ "$dry" = 1 ]; then echo "+ write $f"; return 0; fi
    mkdir -p "$(dirname "$f")"
    printf '%s\n' "$content" > "$f"
    echo "wrote $f"
}

# The apps that read x11-theme's render (the state directory) follow the session's
# palette: under Hyprland dux's, rendered by `x11-theme from-dux` from what dux last
# wrote; under i3 the theme it was set to, rendered again if dux's took its place.
render_session_theme() {
    local state="$HOME/.local/state/omarchy/current"
    local colors="${XDG_STATE_HOME:-$HOME/.local/state}/cachy-dots/dux-colors.toml"
    if [ "$1" = hyprland ]; then
        [ -s "$colors" ] || { echo "theme: dux renders its palette when it next starts"; return 0; }
        if [ "$dry" = 1 ]; then echo "+ x11-theme from-dux"; return 0; fi
        SESSION=hyprland "$REPO/bin/x11-theme" from-dux || warn "x11-theme from-dux failed"
    elif [ -f "$state/theme.dux" ]; then
        if [ "$dry" = 1 ]; then echo "+ x11-theme refresh (back from dux's palette)"; return 0; fi
        SESSION=i3 "$REPO/bin/x11-theme" refresh || warn "x11-theme refresh failed"
    fi
    return 0
}

# Which file manager D-Bus starts for org.freedesktop.FileManager1 ("show in
# folder"): nautilus under i3, Dux Files under Hyprland. Both ship an activation
# file for the name, and Dux Files' in /usr/local/share would win in both
# sessions; one in the user's own data directory comes first, so it is a link
# there to the active session's. Nothing is linked when that file is missing.
point_file_manager() {
    local src=$1 dst="${XDG_DATA_HOME:-$HOME/.local/share}/dbus-1/services/org.freedesktop.FileManager1.service"
    [ -f "$src" ] || return 0
    [ "$(readlink "$dst" 2>/dev/null)" = "$src" ] && return 0
    link "$src" "$dst"
    [ "$dry" = 1 ] || busctl --user call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus ReloadConfig >/dev/null 2>&1 || true
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
    [ -f "$f" ] || { warn "$f is missing: opt/hyprland.sh has dux write it"; return 0; }
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
    point_icons "$s"
    point_vesktop_theme "$s"
    point_matugen "$s"
    if [ "$s" = hyprland ]; then
        mask_units mask
        ensure_cachy_require
    else
        mask_units unmask
    fi
    record_session "$s"
    render_session_theme "$s"
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
