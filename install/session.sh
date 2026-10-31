#!/usr/bin/env bash
# The desktop session the dots are set up for: i3 (X11), or Hyprland with dux or
# Noctalia as its shell. One is active at a time. bin/graphical-session switches;
# install.sh and sync.sh re-apply the active one right after install_links. Sourced
# through install/lib.sh; defines functions only.
#
# What follows is keyed by owner: i3, dux or noctalia, the last two being the
# Hyprland session with that shell. An owner points a few colour slots (one link
# each, retargeted on a switch) and masks user units that would otherwise start by
# D-Bus activation and get in its way. i3's links go when Hyprland becomes active.
# Hyprland's stay once made, whichever session or shell is recorded: only Hyprland
# reads them, each shell only its own, and ly offers every entry whatever is recorded.
# Without them, picking Hyprland while i3 is recorded fails at cachy.lua's first
# require and leaves Hyprland in emergency mode, with no binds. They also keep a
# running session working through a reload after the other shell is recorded.
# Everything else install_links makes is shared by all of them.

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

# The shell of the Hyprland session, as hypr/cachy.lua reads it. Two records of one
# choice: the file, read by this module and by cachy.lua, and environment.d's, which
# puts HYPR_SHELL in the user manager's environment.
hypr_shell_state_file() { echo "${XDG_STATE_HOME:-$HOME/.local/state}/graphical-session/hypr-shell"; }
hypr_shell_env_file() { echo "${XDG_CONFIG_HOME:-$HOME/.config}/environment.d/10-graphical-session.conf"; }

# The recorded shell. A Hyprland session recorded with no shell is older than the
# choice, so it is dux's; otherwise Noctalia, cachy.lua's default too.
active_hypr_shell() {
    local s
    s=$(cat "$(hypr_shell_state_file)" 2>/dev/null || true)
    case "$s" in
        dux|noctalia) echo "$s" ;;
        *) if [ "$(active_session)" = hyprland ]; then echo dux; else echo noctalia; fi ;;
    esac
}

# Scripts in bin/ that only the i3 session uses: i3 IPC, X11-only tools, or what
# the shell does itself under Hyprland. install_links leaves these to the session.
I3_ONLY_BIN=(x11-clipboard x11-display x11-focus x11-gaps-cycle x11-idle x11-keybinds-menu
             x11-lock x11-monitor x11-nightlight x11-power-menu x11-theme x11-wallpaper)

# Started by D-Bus activation unless masked: dunst would take the notification
# name if a notification came before the shell is up, and blueman's applet would add
# a tray icon neither shell has a use for. Masked under Hyprland, unmasked under i3.
HYPRLAND_MASKED_UNITS=(dunst.service blueman-applet.service)

# The first line of a file this module wrote in place of a link, so it can tell
# its own stub from a file the user put there. Older than the rename of
# bin/cachy-session: hosts have stubs with this line.
SESSION_STUB_MARK="# cachy-session stub"

# The links of i3, hyprland (both shells) or dux, one "src<TAB>dst" per line.
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
            # hypr/cachy.lua is a per-host copy (import_cachy_lua), not linked.
            printf '%s\t%s\n' "$REPO/hypr/noctalia/binds-user.lua" "$cfg/hypr/noctalia/binds-user.lua"
            printf '%s\t%s\n' "$REPO/hypr/noctalia/compositor.lua" "$cfg/hypr/noctalia/compositor.lua"
            # dux owns hypr/dms/; binds-user is ours. Only once dux's setup has run:
            # it writes that file itself, and would write through a link into the repo.
            if [ -f "$cfg/hypr/dms/binds.lua" ]; then
                printf '%s\t%s\n' "$REPO/hypr/dms/binds-user.lua" "$cfg/hypr/dms/binds-user.lua"
            fi
            # Noctalia reads every *.toml directly in its directory, and never
            # writes there: its Settings window has ~/.local/state/noctalia/settings.toml.
            if command -v noctalia >/dev/null; then
                printf '%s\t%s\n' "$REPO/noctalia/config.toml" "$cfg/noctalia/config.toml"
                printf '%s\t%s\n' "$REPO/noctalia/templates.toml" "$cfg/noctalia/templates.toml"
                for f in "$REPO"/noctalia/templates/*; do
                    printf '%s\t%s\n' "$f" "$cfg/noctalia/templates/$(basename "$f")"
                done
                printf '%s\t%s\n' "$REPO/noctalia/hooks/on-theme-change" "$cfg/noctalia/hooks/on-theme-change"
            fi
            ;;
        dux)
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

# cachy.lua holds Hyprland environment, submaps, the shared binds, autostart, and
# which shell's modules are loaded. It is per host, so it is copied from
# hypr/cachy.lua once and left alone (not symlinked): neither install.sh nor sync.sh
# overwrites it, and a host can edit its startup without touching the repo.
#
# The one exception is a copy from before the shell choice: hyprland.lua no longer
# loads dux's modules (ensure_cachy_require), so one that does not pick a shell
# would leave the session with no shell at all. It moves aside for its edits to be
# carried over by hand.
import_cachy_lua() {
    local dst="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/cachy.lua"
    local src="$REPO/hypr/cachy.lua"
    if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
        run rm "$dst"
        if [ "$dry" = 1 ]; then
            echo "+ install -m 644 $src $dst"
            return 0
        fi
    elif [ -f "$dst" ] && [ ! -L "$dst" ] && ! grep -qF HYPR_SHELL "$dst"; then
        local backup
        backup="$dst.bak.$(date +%s)"
        run mv "$dst" "$backup"
        warn "$dst predates the shell choice: moved to $backup; carry this host's edits over to the new copy"
        if [ "$dry" = 1 ]; then
            echo "+ install -m 644 $src $dst"
            return 0
        fi
    fi
    if [ -e "$dst" ] || [ -L "$dst" ]; then
        return 0
    fi
    run mkdir -p "$(dirname "$dst")"
    run install -m 644 "$src" "$dst"
    echo "copied $src -> $dst (this host's hypr/cachy.lua; edit it there)"
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
    [ "$1" = hyprland ] && import_cachy_lua
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
# The Hyprland session is active (bin/graphical-session). To use i3 again, run
# \`graphical-session i3\`, then log out and back in.
exec --no-startup-id i3-nagbar -t warning -m 'The Hyprland session is active. Run: graphical-session i3, then log out and pick i3.' -B 'Log out' 'i3-msg exit'
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

# The slots that read x11-theme's render: i3's theme, or Noctalia's palette through
# `x11-theme from-noctalia`.
point_rendered_slots() {
    local cfg="${XDG_CONFIG_HOME:-$HOME/.config}" d
    local th="$HOME/.local/state/omarchy/current/theme"
    link "$th/neovim.lua" "$cfg/nvim/lua/plugins/theme.lua"
    link "$th/alacritty.toml" "$cfg/alacritty/colors.toml"
    link "$th/kitty.conf" "$cfg/kitty/colors.conf"
    for d in gtk-3.0 gtk-4.0; do
        is_dux_gtk_css "$cfg/$d/gtk.css" && run rm "$cfg/$d/gtk.css"
        link "$th/gtk.css" "$cfg/$d/gtk.css"
    done
}

# The slots: one link (gtk.css: a link or a file) per app that the sessions theme,
# pointed at the active owner's colours, and the terminals' font file: i3's own font
# under i3, dux's mono font under Hyprland.
point_slots() {
    local cfg="${XDG_CONFIG_HOME:-$HOME/.config}" d
    local th="$HOME/.local/state/omarchy/current/theme"
    case "$1" in
        i3)
            point_rendered_slots
            link "$REPO/alacritty/font-i3.toml" "$cfg/alacritty/font.toml"
            link "$REPO/kitty/font-i3.conf" "$cfg/kitty/font.conf"
            link "$th/satty.config.toml" "$cfg/satty/config.toml"
            point_file_manager /usr/share/dbus-1/services/org.freedesktop.FileManager1.service
            ;;
        noctalia)
            point_rendered_slots
            link "$REPO/alacritty/font-hyprland.toml" "$cfg/alacritty/font.toml"
            link "$REPO/kitty/font-hyprland.conf" "$cfg/kitty/font.conf"
            link "$REPO/satty/config-wayland.toml" "$cfg/satty/config.toml"
            point_file_manager /usr/share/dbus-1/services/org.freedesktop.FileManager1.service
            ;;
        dux)
            # dux writes these when it starts (its theme templates for every
            # installed terminal), so before the first dux login the links point
            # at nothing yet.
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

# The owner of the active session, or of the session in $1.
session_owner() {
    local s=${1:-$(active_session)}
    if [ "$s" = i3 ]; then echo i3; else active_hypr_shell; fi
}

# The GTK (and Qt, through GTK) icon theme: x11-theme's generated one under i3;
# under Hyprland the one picked in dux's settings (dux only), else Papirus-Dark,
# which dux's documentation recommends. dux's own default, "System Default", reads
# it back from settings.ini.
session_icon_theme() {
    local o=${1:-$(session_owner)} pick=
    if [ "$o" = i3 ]; then echo x11-theme; return; fi
    if [ "$o" = dux ]; then
        pick=$(jq -r '.iconThemeDark // empty' "${XDG_CONFIG_HOME:-$HOME/.config}/dms/settings.json" 2>/dev/null || true)
    fi
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
# under i3 and Noctalia, dux's dank-discord.css (its matugen template) under dux.
# Vencord rewrites enabledThemes from memory when it exits, so this waits for it to
# be closed.
point_vesktop_theme() {
    local settings="${XDG_CONFIG_HOME:-$HOME/.config}/vesktop/settings/settings.json" on off tmp
    command -v vesktop >/dev/null || [ -f "$settings" ] || return 0
    if [ "$1" = dux ]; then on=dank-discord.css off=cachy-dots.theme.css
    else on=cachy-dots.theme.css off=dank-discord.css; fi
    if jq -e --arg on "$on" --arg off "$off" \
        '(.enabledThemes // []) | (index($on) != null) and (index($off) == null)' "$settings" >/dev/null 2>&1; then
        return 0
    fi
    if pgrep -x -u "$(id -u)" 'vesktop|Vesktop' >/dev/null 2>&1; then
        warn "Vesktop is running: close it and re-run graphical-session to switch its theme to $on"
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
# written here rather than linked. The mark is older than the rename of
# bin/cachy-session: hosts have drop-ins with this line.
MATUGEN_DROPIN_MARK="# cachy-dots: written by install/session.sh (cachy-session); i3 removes it"
# Sunshine's capture method is the one setting of sunshine.conf that follows the
# session: x11 grabs an X server, which Hyprland has not got (Sunshine then
# fails at start with "Unable to initialize capture method"), and wlr, the
# wlr-screencopy protocol, is what Hyprland offers. The rest of the file (the
# display, the GPU, the encoder, what its web UI saved) belongs to the host and
# is left alone. Only when Sunshine is installed or already has a config. A
# running Sunshine keeps its method until restarted; opt-in service autostarts
# start it at session login (06-services.conf under i3, cachy-services.lua under Hyprland).
point_sunshine() {
    local conf="${XDG_CONFIG_HOME:-$HOME/.config}/sunshine/sunshine.conf" want=wlr tmp
    [ "$1" = i3 ] && want=x11
    command -v sunshine >/dev/null || [ -f "$conf" ] || return 0
    if [ -f "$conf" ] && [ "$(grep -E '^[[:space:]]*capture[[:space:]]*=' "$conf" | tail -n1 | sed 's/^[^=]*=[[:space:]]*//; s/[[:space:]]*$//')" = "$want" ]; then
        return 0
    fi
    [ "$dry" = 1 ] && { echo "+ set capture = $want in $conf"; return; }
    mkdir -p "$(dirname "$conf")"
    tmp=$(mktemp)
    { [ -f "$conf" ] && grep -vE '^[[:space:]]*capture[[:space:]]*=' "$conf"; printf 'capture = %s\n' "$want"; } > "$tmp" || true
    # cat keeps a link to the file (or its owner) as it is
    cat "$tmp" > "$conf"
    rm -f "$tmp"
    echo "sunshine: capture = $want"
}

matugen_dropin() { echo "${XDG_CONFIG_HOME:-$HOME/.config}/matugen/dms/configs/cachy-dots.toml"; }

point_matugen() {
    local f content
    f=$(matugen_dropin)
    if [ "$1" != dux ]; then
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
# palette: under Hyprland the shell's, rendered by `x11-theme from-dux` or
# `from-noctalia` from what it last wrote; under i3 the theme it was set to, rendered
# again if a shell's palette took its place.
render_session_theme() {
    local state="$HOME/.local/state/omarchy/current"
    local colors="${XDG_STATE_HOME:-$HOME/.local/state}/cachy-dots/$1-colors.toml"
    if [ "$1" != i3 ]; then
        [ -s "$colors" ] || { echo "theme: $1 renders its palette when it next starts"; return 0; }
        if [ "$dry" = 1 ]; then echo "+ x11-theme from-$1"; return 0; fi
        SESSION=hyprland "$REPO/bin/x11-theme" "from-$1" || warn "x11-theme from-$1 failed"
    elif [ -f "$state/theme.dux" ] || [ -f "$state/theme.noctalia" ]; then
        if [ "$dry" = 1 ]; then echo "+ x11-theme refresh (back from the shell's palette)"; return 0; fi
        SESSION=i3 "$REPO/bin/x11-theme" refresh || warn "x11-theme refresh failed"
    fi
    return 0
}

# Which file manager D-Bus starts for org.freedesktop.FileManager1 ("show in
# folder"): nautilus under i3 and Noctalia, Dux Files under dux. Both ship an
# activation file for the name, and Dux Files' in /usr/local/share would win in
# every session; one in the user's own data directory comes first, so it is a link
# there to the active session's. Nothing is linked when that file is missing.
point_file_manager() {
    local src=$1 dst="${XDG_DATA_HOME:-$HOME/.local/share}/dbus-1/services/org.freedesktop.FileManager1.service"
    [ -f "$src" ] || return 0
    [ "$(readlink "$dst" 2>/dev/null)" = "$src" ] && return 0
    link "$src" "$dst"
    [ "$dry" = 1 ] || busctl --user call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus ReloadConfig >/dev/null 2>&1 || true
}

# Open and save dialogs under Hyprland. dfiles is first for FileChooser in the file
# opt/hyprland.sh made, and it reads as a dux app, so under Noctalia that preference
# is taken out and GTK's portal serves them; under dux, dfiles' own switch puts it back.
point_file_chooser() {
    local f="${XDG_CONFIG_HOME:-$HOME/.config}/xdg-desktop-portal/hyprland-portals.conf"
    [ -f "$f" ] && command -v dfiles >/dev/null || return 0
    if [ "$1" = noctalia ]; then
        grep -q '^org\.freedesktop\.impl\.portal\.FileChooser=dfiles;' "$f" || return 0
        run sed -i 's/^\(org\.freedesktop\.impl\.portal\.FileChooser=\)dfiles;/\1/' "$f"
        echo "portal: GTK's file chooser under Noctalia ($f)"
    elif [ "$1" = dux ] && ! grep -q '^org\.freedesktop\.impl\.portal\.FileChooser=dfiles;' "$f"; then
        run env XDG_CURRENT_DESKTOP=Hyprland dfiles portal install --no-restart >/dev/null \
            || warn "could not make Dux Files the file chooser; run: dfiles portal install"
    fi
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

# hyprland.lua is the session's entry point. dux writes its own, which loads dux's
# modules and starts it, and Lua runs that whichever shell is wanted. So those lines
# are commented out and hypr/cachy.lua, which picks the shell, does them instead; the
# rest of the file (the environment, general settings, animations, window rules) is
# what both shells share. One line is added to load cachy.lua, after dux's modules
# as before. Re-done if a `dms setup` that replaced hyprland.lua brought them back.
# A host with no hyprland.lua (Noctalia, no dux) gets a copy of hypr/hyprland.lua,
# the same file without dux's lines.
CACHY_REQUIRE='require("cachy") -- cachy-dots: hypr/cachy.lua (added by graphical-session)'
DUX_LINES='^[[:space:]]*(require\("dms\.[^"]*"\)|hl\.exec_cmd\("dms run"\))[[:space:]]*$'

ensure_cachy_require() {
    local f="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprland.lua"
    if [ ! -f "$f" ]; then
        run mkdir -p "$(dirname "$f")"
        run install -m 644 "$REPO/hypr/hyprland.lua" "$f"
        echo "copied $REPO/hypr/hyprland.lua -> $f"
        return 0
    fi
    if grep -qE "$DUX_LINES" "$f"; then
        if [ "$dry" = 1 ]; then
            echo "+ comment out dux's modules and startup in $f (cachy.lua loads them)"
        else
            cp -p "$f" "$f.bak.$(date +%s)"
            sed -i -E "s/$DUX_LINES/-- cachy-dots: hypr\/cachy.lua does this: &/" "$f"
            echo "commented out dux's modules and startup in $f (hypr/cachy.lua loads them)"
        fi
    fi
    grep -qF 'require("cachy")' "$f" && return 0
    if [ "$dry" = 1 ]; then echo "+ append to $f: $CACHY_REQUIRE"; return 0; fi
    printf '\n%s\n' "$CACHY_REQUIRE" >> "$f"
    echo "added require(\"cachy\") to $f"
}

record_session() {
    [ "$dry" = 1 ] && { echo "+ record the session ($1${2:+ $2})"; return; }
    mkdir -p "$(dirname "$(session_state_file)")"
    echo "$1" > "$(session_state_file)"
    [ -n "${2:-}" ] || return 0
    mkdir -p "$(dirname "$(hypr_shell_state_file)")" "$(dirname "$(hypr_shell_env_file)")"
    echo "$2" > "$(hypr_shell_state_file)"
    echo "HYPR_SHELL=$2" > "$(hypr_shell_env_file)"
}

# Makes the session in $1 (default: the active one), with the Hyprland shell in $2
# (default: the recorded one), the one set up: the links it does not use go, its own
# are made, the colour slots point at its colours.
apply_session() {
    local s=${1:-$(active_session)} shell=${2:-$(active_hypr_shell)} owner=i3 keep=i3 o
    if [ "$s" = i3 ]; then
        say "Session: i3"
    else
        owner=$shell keep="hyprland $shell"
        say "Session: hyprland $shell"
    fi
    # shellcheck disable=SC2086  # keep is a list of words
    for o in i3 dux; do
        in_list "$o" $keep || unlink_session "$o"
    done
    [ "$s" = hyprland ] && write_i3_stub
    for o in $keep; do
        link_session "$o"
    done
    point_slots "$owner"
    point_icons "$owner"
    point_vesktop_theme "$owner"
    point_matugen "$owner"
    point_sunshine "$owner"
    point_file_chooser "$owner"
    if [ "$s" = hyprland ]; then
        mask_units mask
        ensure_cachy_require
        record_session hyprland "$shell"
    else
        mask_units unmask
        record_session i3
    fi
    render_session_theme "$owner"
}

# Hyprland's own check of hyprland.lua and ours on top of it.
validate_hyprland() {
    local cfg="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprland.lua"
    if [ "$dry" = 0 ] && command -v Hyprland >/dev/null && [ -f "$cfg" ]; then
        say "Validating the Hyprland config"
        # The recorded shell, not one inherited from a session running the other.
        HYPR_SHELL=$(active_hypr_shell) Hyprland --verify-config -c "$cfg" >/dev/null 2>&1 && echo "Hyprland config OK" \
            || warn "Hyprland reports errors in $cfg (run: Hyprland --verify-config -c $cfg)"
    fi
}

validate_session() {
    if [ "$(active_session)" = i3 ]; then validate_i3; else validate_hyprland; fi
}
