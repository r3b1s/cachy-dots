#!/usr/bin/env bash
# Opt in to the Hyprland session: Hyprland with dux-shell as its shell, and dux's
# own apps where dux has one. Not part of the default install; i3 stays, and
# bin/cachy-session switches between the two.
#
#   1. installs Hyprland and what dux-shell needs, by plain name (a Cachy build
#      wins where one exists), after a full pacman -Syu
#   2. installs dux from its GitHub releases, every file pinned in DUX below and
#      checked against its sha256: dux-shell (`dms`), Dux Files (`dfiles`), Dux
#      Calendar (`dcal`) and Dux Search (`dsearch`), laid out as their own
#      `make install` does (/usr/local, the polkit action under /usr/share).
#      Root-owned, so `dms update` cannot replace them; bump the pins instead.
#   3. has dux write its Hyprland config, once (while ~/.config/hypr/hyprland.lua
#      does not exist): `dms setup headless`, without systemd and without a
#      terminal config
#   4. installs dux's emojiLauncher plugin (best effort; needs network)
#
# It does not switch sessions: `cachy-session hyprland` does, then log out and
# pick Hyprland at the login screen.
#
# --remove deletes the files in DUX; the packages, ~/.config/dms and
# ~/.config/hypr stay. Run `cachy-session i3` first.
#
# Usage: opt/hyprland.sh [--remove] [-n|--dry-run]
set -euo pipefail

# Every file taken from dux's GitHub repos: "<repo> <tag> <source> <sha256> <destination>".
# A source under assets/ is that file in the repo at the tag; anything else is a
# release asset. A .gz is unpacked, and what lands in /usr/local/bin is
# executable. In the text files, /usr/bin/<tool> becomes /usr/local/bin/<tool>,
# as their `make install` does.
DUX=(
    "dux-shell    v2.0.0 dms-cli-amd64.gz                                         364292c726d3033081a8329bc2be1b2ac3f5ef9f906473aee53aa0361f764b81 /usr/local/bin/dms"
    "dux-shell    v2.0.0 completion.bash                                          61e116dd2fe4cd87ab203f6a3d193404dd5f3c0c0f6dc262439a64411bcb30c4 /usr/local/share/bash-completion/completions/dms"
    "dux-files    v2.0.0 dfiles-linux-amd64.gz                                    6d6b421cf62ae4ecd96eedc89e6f357d938d6d0632d096618ce049c394805b19 /usr/local/bin/dfiles"
    "dux-files    v2.0.0 dev.duxlabs.files.svg                                    a01be1c1c3780f8ea3ff3df530374c23088fd78265e070fdf93e5d41ee53fd69 /usr/local/share/icons/hicolor/scalable/apps/dev.duxlabs.files.svg"
    "dux-files    v2.0.0 assets/dev.duxlabs.files.desktop                         0f230c913a248cbac737341ef5ee0a9e6ccfdda08b459ca14b5af99dd49f773d /usr/local/share/applications/dev.duxlabs.files.desktop"
    "dux-files    v2.0.0 assets/dev.duxlabs.files.policy                          52fa30b44fefa5a632996075e370923c83b911cd198ffcff959a79789d1e5e17 /usr/share/polkit-1/actions/dev.duxlabs.files.policy"
    "dux-files    v2.0.0 assets/dbus/dev.duxlabs.files.FileManager1.service       b34bfc6ff30a69ed6bb465afd3acfcdb141c5801d29595b6b24558649d331268 /usr/local/share/dbus-1/services/dev.duxlabs.files.FileManager1.service"
    "dux-files    v2.0.0 assets/dbus/org.freedesktop.impl.portal.desktop.dfiles.service edafb25bfd85273bc28e9761dd06b43c61a2d5a6d6dab725766a2b0c6c717bca /usr/local/share/dbus-1/services/org.freedesktop.impl.portal.desktop.dfiles.service"
    "dux-files    v2.0.0 assets/portal/dfiles.portal                              1cf796976f0381a7967dd8785ef326414d6b62eb0fde1ff3691e06a744577669 /usr/local/share/xdg-desktop-portal/portals/dfiles.portal"
    "dux-calendar v2.0.0 dcal-linux-amd64.gz                                      8b0ab121a4b1eb82dc7ffc5a577e84f34a561618d0800a3cd02862c4ee9d7b66 /usr/local/bin/dcal"
    "dux-calendar v2.0.0 dev.duxlabs.calendar.svg                                 df7a0f965cc85e2e0d5b5dfa88b9b68b159a4bf846ef2906d7e05c3ca3c9ae39 /usr/local/share/icons/hicolor/scalable/apps/dev.duxlabs.calendar.svg"
    "dux-calendar v2.0.0 assets/dev.duxlabs.calendar.desktop                      49ab0353bd4a915c43adae4d11ff49730e13a2af530aaf6b918a3d8e430c9acf /usr/local/share/applications/dev.duxlabs.calendar.desktop"
    "dux-search   v2.0.0 dsearch-linux-amd64.gz                                   c46f6ce6f58e39e3d1c125aa4466034c9fd4402756b3f5438317d19ec3f820a0 /usr/local/bin/dsearch"
)
# The sha256 each destination was installed from, so a re-run skips what is current.
RECORD=/usr/local/share/cachy-dots/dux.sha256

PKGS=(
    hyprland xdg-desktop-portal-hyprland
    hyprland-guiutils                # Hyprland's own dialogs (ANR, update notes)
    xorg-xwayland                    # X11 apps (ZAP, anything without Wayland support)
    quickshell                       # dux's QML runtime, for the shell and its apps
    dux-gop                          # dgop: dux's system monitor backend
    accountsservice                  # the user's name and avatar
    matugen                          # dux's theming: colours from the wallpaper or a scheme
    qt6ct qt6-multimedia cava        # Qt theming, sound effects, the audio visualiser
    wl-clipboard                     # wl-copy/wl-paste: voxtype, screenshot, dictate, nvim, tmux
    wtype                            # dictate's paste keystroke
    ttf-firacode-nerd                # dux's mono font (Fira Code), for the terminals
)

remove=0
dry=0
for arg in "$@"; do
    case "$arg" in
        --remove)     remove=1 ;;
        -n|--dry-run) dry=1 ;;
        -h|--help)    sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

say()  { printf '\033[1;34m::\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
run()  { if [ "$dry" = 1 ]; then echo "+ $*"; else "$@"; fi; }

SUDO=
[ "$(id -u)" -ne 0 ] && SUDO=sudo
[ -n "$SUDO" ] || { warn "run opt/hyprland.sh as your own user (it uses sudo), not root"; exit 1; }

if [ "$remove" = 1 ]; then
    for row in "${DUX[@]}"; do
        read -r _ _ _ _ dst <<<"$row"
        if [ -e "$dst" ]; then
            run $SUDO rm "$dst"
            echo "removed $dst"
        fi
    done
    [ -e "$RECORD" ] && run $SUDO rm "$RECORD"
    exit 0
fi

# ── packages ─────────────────────────────────────────────────────────────
missing=()
for p in "${PKGS[@]}"; do
    pacman -Qq "$p" >/dev/null 2>&1 || missing+=("$p")
done
if [ "${#missing[@]}" -gt 0 ]; then
    say "Installing ${missing[*]}"
    # A full upgrade first: -Sy followed by -S would be a partial upgrade.
    run $SUDO pacman -Syu --needed --noconfirm "${missing[@]}"
fi

# ── dux, from GitHub ─────────────────────────────────────────────────────
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
changed=0
for row in "${DUX[@]}"; do
    read -r repo tag src sum dst <<<"$row"
    if [ -e "$dst" ] && grep -qxF "$sum $dst" "$RECORD" 2>/dev/null; then
        continue
    fi
    case "$src" in
        assets/*) url="https://raw.githubusercontent.com/duxlabs-dev/$repo/$tag/$src" ;;
        *)        url="https://github.com/duxlabs-dev/$repo/releases/download/$tag/$src" ;;
    esac
    if [ "$dry" = 1 ]; then echo "+ install $dst from $repo $tag ($src)"; continue; fi
    f="$tmp/$(basename "$src")"
    curl -fsSL --retry 3 -o "$f" "$url" || { warn "could not download $url"; exit 1; }
    if ! printf '%s  %s\n' "$sum" "$f" | sha256sum -c --quiet >/dev/null 2>&1; then
        warn "$repo $tag $src does not match its pinned sha256; stopped"
        exit 1
    fi
    case "$f" in *.gz) gunzip "$f"; f=${f%.gz} ;; esac
    case "$dst" in
        /usr/local/bin/*) mode=755 ;;
        *.desktop|*.service|*.policy|*.portal)
            mode=644
            sed -i -E 's#/usr/bin/(dms|dfiles|dcal|dsearch)\b#/usr/local/bin/\1#g' "$f" ;;
        *) mode=644 ;;
    esac
    # Staged beside the target and renamed into place, so a running app never
    # sees a half-written file.
    $SUDO install -Dm"$mode" "$f" "$dst.new"
    $SUDO mv -f "$dst.new" "$dst"
    { awk -v d="$dst" '$2 != d' "$RECORD" 2>/dev/null || true; echo "$sum $dst"; } > "$tmp/record"
    $SUDO install -Dm644 "$tmp/record" "$RECORD"
    echo "installed $dst ($repo $tag)"
    changed=1
done
if [ "$changed" = 1 ]; then
    $SUDO update-desktop-database -q /usr/local/share/applications 2>/dev/null || true
    # The session bus reads D-Bus activation files at start; this picks up dfiles' now.
    busctl --user call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus ReloadConfig >/dev/null 2>&1 || true
fi
bin=/usr/local/bin/dms

# ── dux's Hyprland config ───────────────────────────────────────────────
# dux writes hyprland.lua and hypr/dms/ itself, with its installer-facing setup.
# Without systemd: dms.service runs /usr/bin/dms and the release ships no unit,
# so hyprland.lua runs `dms run` itself. Without --terminal: a terminal config
# would be written through the links into this repo's alacritty or kitty file.
# Its binds name $TERMINAL. (The interactive `dms setup` also adds the user to
# the input group, which can read every keyboard; headless does not.)
hypr_lua="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprland.lua"
if [ -f "$hypr_lua" ]; then
    echo "$hypr_lua exists; dux's setup not run again"
else
    say "Writing dux's Hyprland config (dms setup headless)"
    run env TERMINAL="${TERMINAL:-alacritty}" "$bin" setup headless --compositor hyprland --no-systemd
fi

# ── Dux Files as the file chooser ────────────────────────────────────────
# dfiles' own switch: it puts itself first for FileChooser in
# ~/.config/xdg-desktop-portal/hyprland-portals.conf, which only a Hyprland
# session reads. A user file there replaces the system one rather than adding
# to it, so the system's is copied first and its other preferences kept.
portals="${XDG_CONFIG_HOME:-$HOME/.config}/xdg-desktop-portal/hyprland-portals.conf"
if ! XDG_CURRENT_DESKTOP=Hyprland /usr/local/bin/dfiles portal status 2>/dev/null | grep -q 'prefers dfiles'; then
    if [ "$dry" = 1 ]; then
        echo "+ dfiles portal install (for Hyprland)"
    else
        if [ ! -e "$portals" ] && [ -f /usr/share/xdg-desktop-portal/hyprland-portals.conf ]; then
            mkdir -p "$(dirname "$portals")"
            { cat /usr/share/xdg-desktop-portal/hyprland-portals.conf; echo; } > "$portals"
        fi
        XDG_CURRENT_DESKTOP=Hyprland /usr/local/bin/dfiles portal install --no-restart >/dev/null \
            && echo "Dux Files serves open and save dialogs under Hyprland ($portals)" \
            || warn "could not make Dux Files the file chooser; run: dfiles portal install"
    fi
fi

# ── plugins ──────────────────────────────────────────────────────────────
# The emoji picker ($mod+Ctrl+e on i3 is rofimoji, which Hyprland does without).
if [ "$dry" = 1 ]; then
    echo "+ dms plugins install emojiLauncher"
else
    if ! "$bin" plugins list 2>/dev/null | grep -qi emojiLauncher; then
        if "$bin" plugins install emojiLauncher >/dev/null 2>&1; then
            echo "installed dux's emojiLauncher plugin"
        else
            warn "could not install dux's emojiLauncher plugin; run: dms plugins install emojiLauncher"
        fi
    fi
    # Installed plugins load only once enabled: through the running shell when
    # there is one, else in its settings file, unless that already says either way.
    plugin_cfg="${XDG_CONFIG_HOME:-$HOME/.config}/dms/plugin_settings.json"
    if "$bin" plugins list 2>/dev/null | grep -qi emojiLauncher \
        && ! "$bin" ipc call plugins enable emojiLauncher >/dev/null 2>&1 \
        && ! jq -e '.emojiLauncher | has("enabled")' "$plugin_cfg" >/dev/null 2>&1; then
        { cat "$plugin_cfg" 2>/dev/null || echo '{}'; } | jq '.emojiLauncher.enabled = true' > "$tmp/plugin_settings.json" \
            && install -Dm644 "$tmp/plugin_settings.json" "$plugin_cfg" \
            && echo "enabled dux's emojiLauncher plugin ($plugin_cfg)"
    fi
fi

echo
echo "Next: cachy-session hyprland, then log out and pick Hyprland at the login screen."
