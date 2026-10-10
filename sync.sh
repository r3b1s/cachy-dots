#!/usr/bin/env bash
# Bring an installed system up to date with the repo, after a `git pull` or your
# own edits. The light counterpart of install.sh: nothing is installed, no service
# is touched, and nothing is downloaded unless --themes asks for it.
#
#   1. symlinks what is not linked yet (new configs, new bin/ scripts), repoints
#      links that moved, and removes links whose repo file is gone; a real file
#      in the way is backed up as <name>.bak.<time>
#   2. copies the configs that cannot be links, each only when it differs from the
#      repo: the ly overlay, the theme helpers and their sudoers rule, the
#      Firefox and Chromium policies, the touchpad config, the nix.conf block,
#      the GTK settings, the managed ~/.bashrc block
#   3. re-renders the current theme (templates, the files rendered from them)
#   4. re-applies the default apps, keeping the browser chosen in the menu
#   5. validates the i3 config, and lists packages the repo wants that are missing
#
# Safe to re-run. The root-owned copies use sudo; --no-root skips them.
#
# Usage: ./sync.sh [-n|--dry-run] [--no-root] [--themes]
#   -n, --dry-run  print what would change
#   --no-root      skip the copies into /etc and /usr/local (no sudo prompt)
#   --themes       also `git pull` the installed theme repos (needs network)
set -euo pipefail

do_packages=0   # install.sh's functions are used; its package phase is not
do_links=1
dry=0
root=1
themes=0
for arg in "$@"; do
    case "$arg" in
        -n|--dry-run) dry=1 ;;
        --no-root)    root=0 ;;
        --themes)     themes=1 ;;
        -h|--help)    sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

# Functions and package lists only; install.sh does not run its main flow when sourced.
# shellcheck source=install.sh
. "$(dirname "${BASH_SOURCE[0]}")/install.sh"

[ "$TARGET_USER" != root ] || { warn "run sync.sh as your own user, not root"; exit 1; }

# Links into the repo whose file is gone (a removed script or config).
prune_dangling() {
    local cfg="${XDG_CONFIG_HOME:-$HOME/.config}" l
    while IFS= read -r l; do
        echo "removing dangling link $l"
        run rm "$l"
    done < <(find "$HOME/.local/bin" "$cfg" -maxdepth 4 -xtype l -lname "$REPO/*" -print 2>/dev/null)
}

# What install.sh would install and is not there: reported, never installed.
report_missing_packages() {
    command -v pacman >/dev/null || return 0
    local p entry c have missing=()
    for p in "${PKGS[@]}" "${AUR_PKGS[@]}"; do
        pacman -Qq "$p" >/dev/null 2>&1 || missing+=("$p")
    done
    for entry in "${PINNED[@]}"; do
        have=0
        for c in $entry; do pacman -Qq "${c#*/}" >/dev/null 2>&1 && have=1; done
        [ "$have" = 1 ] || missing+=("${entry%% *}")
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        warn "packages the repo wants that are not installed: ${missing[*]}"
        warn "run ./install.sh to install them"
    fi
}

sync_theme() {
    if [ ! -f "$HOME/.local/state/omarchy/current/theme.name" ]; then
        setup_theme   # nothing applied yet: first-time apply
    elif [ "$dry" = 1 ]; then
        if [ "$themes" = 1 ]; then echo "+ x11-theme update"; else echo "+ x11-theme refresh"; fi
    elif [ "$themes" = 1 ]; then
        say "Updating the installed themes and re-rendering the current one"
        "$REPO/bin/x11-theme" update || warn "a theme could not be updated (see above)"
    else
        say "Re-rendering the current theme"
        "$REPO/bin/x11-theme" refresh || warn "x11-theme refresh failed"
    fi
}

install_links
prune_dangling
setup_gtk
if [ "$root" = 1 ]; then
    # Each only writes when its target differs from the repo.
    setup_theme_helper
    install_ly_theme
    setup_firefox
    setup_chromium
    setup_touchpad
    if pacman -Qq nix >/dev/null 2>&1 && [ "$TARGET_USER" != root ]; then
        # Restart the daemon only if the block changed; it reads nix.conf at start.
        if setup_nix_conf "$TARGET_USER" && [ "$dry" = 0 ] && systemctl is-active --quiet nix-daemon.service; then
            $SUDO systemctl restart nix-daemon.service || warn "could not restart nix-daemon.service"
        fi
    fi
else
    echo "--no-root: skipped the copies into /etc and /usr/local"
fi
sync_theme
setup_default_apps
validate_i3
report_missing_packages

echo
if [ "$FAILED" = 1 ]; then
    warn "synced with errors (see the warnings above)"
    exit 1
fi
echo "Synced. Reload i3 with \$mod+Shift+Ctrl+Mod1+c for config changes that i3 reads at start."
