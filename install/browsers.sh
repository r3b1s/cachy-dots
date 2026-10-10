#!/usr/bin/env bash
# Browser policies and the default applications.
# Sourced by install.sh, install_vm.sh and sync.sh through install/lib.sh; defines
# functions and package lists only, and runs nothing.

# Firefox: Vimium, Brave search and the default theme, via enterprise policy.
#
# /etc/firefox/policies/policies.json is the documented system-wide location on
# Linux (the install-directory alternative under /usr/lib/firefox would be
# clobbered by package upgrades). The policy installs both add-ons from AMO at
# startup, so this needs network on first run, and activates the theme through
# the pref its manifest declares.
#
# Vimium's options cannot be installed this way: its settings live in the
# extension's own browser storage, the only import path is the Restore control
# on chrome-extension://<id>/options.html, and no policy can write extension
# storage. Load firefox/vimium-options.json from the repo there once by hand.
# qutebrowser gets the same settings by config in qutebrowser/vimium.py, which
# needs no such step.
setup_firefox() {
    local target="/etc/firefox/policies/policies.json"
    local src="$REPO/firefox/policies.json"

    if [ -r "$src" ] && command -v pacman >/dev/null && pacman -Qq firefox >/dev/null 2>&1; then
        say "Installing the Firefox policy"
        if [ "$dry" = 1 ]; then
            echo "+ install $src -> $target"
        elif [ -f "$target" ] && cmp -s "$src" "$target"; then
            echo "firefox policy: already up to date"
        else
            [ -f "$target" ] && run $SUDO cp -a "$target" "$target.bak.$(date +%s)"
            run $SUDO install -D -m 644 "$src" "$target"
            echo "firefox policy: $target (default theme, Vimium from AMO, Brave default search)"
        fi
    fi

}

# Chromium: Brave default search via enterprise policy, in
# /etc/chromium/policies/managed/ (managed, because that is the only level that
# sets a default engine; recommended/ merely suggests). The toolbar colour is a
# second policy file, color.json, written by x11-theme on every theme switch
# through the helper installed by setup_theme_helper().
setup_chromium() {
    local src="$REPO/chromium/policies/managed/brave-search.json"
    local target="/etc/chromium/policies/managed/brave-search.json"

    if [ -r "$src" ] && command -v pacman >/dev/null && pacman -Qq chromium >/dev/null 2>&1; then
        say "Installing the Chromium policy"
        if [ "$dry" = 1 ]; then
            echo "+ install $src -> $target"
        elif [ -f "$target" ] && cmp -s "$src" "$target"; then
            echo "chromium policy: already up to date"
        else
            [ -f "$target" ] && run $SUDO cp -a "$target" "$target.bak.$(date +%s)"
            run $SUDO install -D -m 644 "$src" "$target"
            echo "chromium policy: $target (Brave default search)"
        fi
    fi
}

# Default applications, in ~/.config/mimeapps.list (xdg-mime writes it; the file
# is the apps' own state, so it is not linked from the repo). Without this,
# folders opened in a kitty helper and links and PDFs in Chromium.
DEFAULT_APPS=(
    "org.qutebrowser.qutebrowser.desktop:x-scheme-handler/http x-scheme-handler/https text/html application/xhtml+xml"
    "org.gnome.Nautilus.desktop:inode/directory"
    "org.pwmt.zathura-pdf-mupdf.desktop:application/pdf"
    "imv.desktop:image/png image/jpeg image/gif image/webp image/bmp image/tiff image/avif"
    "mpv.desktop:video/mp4 video/x-matroska video/webm video/quicktime video/x-msvideo audio/mpeg audio/flac audio/ogg audio/x-wav audio/mp4"
)

setup_default_apps() {
    command -v xdg-mime >/dev/null || return 0
    say "Default applications"
    # The $mod+Escape > "Default Browser" menu (bin/x11-default-browser) records
    # its pick here; keep it rather than putting qutebrowser back on every run.
    local pair app browser=org.qutebrowser.qutebrowser.desktop chosen
    chosen=$(cat "${XDG_CONFIG_HOME:-$HOME/.config}/cachy-dots/default-browser" 2>/dev/null || true)
    if [ -n "$chosen" ] && [ -f "/usr/share/applications/$chosen" ]; then
        browser=$chosen
        echo "default browser: $browser (chosen from the menu)"
    fi
    for pair in "${DEFAULT_APPS[@]}"; do
        app=${pair%%:*}
        [ "$app" = org.qutebrowser.qutebrowser.desktop ] && app=$browser
        if [ ! -f "/usr/share/applications/$app" ]; then
            warn "no $app installed; leaving its file types alone"
            continue
        fi
        # shellcheck disable=SC2086  # the type list is meant to split
        run xdg-mime default "$app" ${pair#*:}
        echo "default: $app"
    done
    if command -v xdg-settings >/dev/null; then
        run xdg-settings set default-web-browser "$browser" 2>/dev/null || true
    fi
}
