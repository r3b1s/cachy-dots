#!/usr/bin/env bash
# Opt in to Omarchy's RetroArch setup (its bin/omarchy-install-gaming-retroarch):
# RetroArch with the full libretro core set, and the config that makes it usable.
# Not part of the default install.
#
#   1. needs Omarchy's package repo for 15 of its 51 packages (the libretro
#      database, the joypad profiles, and the FBNeo, UAE, CPC and VICE cores):
#      when [omarchy] is not in pacman.conf it asks (y/N) before running
#      opt/omarchy-repo.sh, which adds it. --yes answers yes
#   2. installs the packages in one pacman transaction: 36 by plain name, so a
#      Cachy repo wins where it has one, the 15 by omarchy/<name>
#   3. makes ~/Games/roms and ~/Games/bios, merges retroarch/omarchy.cfg into
#      ~/.config/retroarch/retroarch.cfg (Vulkan, the XMB menu, the CRT shader,
#      the library paths, ROM and BIOS directories) and writes
#      ~/.config/retroarch/config/global.slangp from retroarch/global.slangp
#
# The settings are applied once. RetroArch saves its config on exit, so a re-run
# that applied them again would undo what you changed in its menus: later runs only
# install what is missing. --reconfigure applies them again. It refuses to
# touch the config while RetroArch runs (it would be overwritten on exit).
#
# The Hyprland and i3 window rules (fullscreen, no idle while fullscreen) are in
# hypr/cachy.lua and i3/conf.d/30-apps.conf, and need no run.
#
# --remove uninstalls the packages. ~/.config/retroarch (saves, states, config),
# ~/Games and the omarchy repo stay.
#
# Usage: opt/omarchy-retroarch.sh [--yes] [--reconfigure] [--remove] [-n|--dry-run]
set -euo pipefail

REPO=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

# In Arch's repos (a Cachy build is taken where there is one).
ARCH_PKGS=(
    retroarch
    retroarch-assets-glui retroarch-assets-ozone retroarch-assets-xmb
    libretro-beetle-pce libretro-beetle-pce-fast libretro-beetle-psx libretro-beetle-psx-hw libretro-beetle-supergrafx
    libretro-blastem
    libretro-bsnes libretro-bsnes-hd
    libretro-core-info
    libretro-desmume libretro-dolphin libretro-flycast
    libretro-gambatte libretro-genesis-plus-gx
    libretro-kronos
    libretro-mame libretro-melonds libretro-mesen libretro-mesen-s libretro-mgba libretro-mupen64plus-next
    libretro-nestopia
    libretro-overlays
    libretro-parallel-n64 libretro-picodrive libretro-play libretro-ppsspp
    libretro-sameboy libretro-scummvm libretro-shaders-slang libretro-snes9x
    libretro-yabause
)
# Only in Omarchy's repo (prebuilt versions of AUR -git packages).
OMARCHY_PKGS=(
    libretro-cap32-git libretro-fbneo-git libretro-uae-git
    libretro-vice-x128-git libretro-vice-x64-git libretro-vice-x64dtv-git libretro-vice-x64sc-git
    libretro-vice-xcbm2-git libretro-vice-xcbm5x0-git libretro-vice-xpet-git
    libretro-vice-xplus4-git libretro-vice-xscpu64-git libretro-vice-xvic-git
    libretro-database-git
    retroarch-joypad-autoconfig-git
)

yes=0
reconfigure=0
remove=0
dry=0
for arg in "$@"; do
    case "$arg" in
        -y|--yes)      yes=1 ;;
        --reconfigure) reconfigure=1 ;;
        --remove)      remove=1 ;;
        -n|--dry-run)  dry=1 ;;
        -h|--help)     sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

say()  { printf '\033[1;34m::\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
run()  { if [ "$dry" = 1 ]; then echo "+ $*"; else "$@"; fi; }

SUDO=
[ "$(id -u)" -ne 0 ] && SUDO=sudo

command -v pacman >/dev/null || { echo "pacman not found: this is for Arch-based systems" >&2; exit 1; }

if [ "$remove" = 1 ]; then
    installed=()
    for p in "${ARCH_PKGS[@]}" "${OMARCHY_PKGS[@]}"; do
        pacman -Qq "$p" >/dev/null 2>&1 && installed+=("$p")
    done
    if [ "${#installed[@]}" -gt 0 ]; then
        say "Removing ${#installed[@]} packages"
        run $SUDO pacman -Rns --noconfirm "${installed[@]}"
    fi
    echo "RetroArch is removed. ~/.config/retroarch, ~/Games and the omarchy repo are left as they are."
    exit 0
fi

# ── the repo ─────────────────────────────────────────────────────────────
if ! pacman-conf --repo-list 2>/dev/null | grep -qx omarchy; then
    echo "${#OMARCHY_PKGS[@]} of the packages (the libretro database, joypad profiles and the FBNeo, UAE, CPC and"
    echo "VICE cores) are only in Omarchy's package repo, https://pkgs.omarchy.org. Adding it trusts"
    echo "Omarchy's signing key and appends [omarchy] to /etc/pacman.conf (opt/omarchy-repo.sh)."
    if [ "$yes" = 1 ]; then
        echo "Add it now? [y/N] y (--yes)"
    elif [ -t 0 ]; then
        read -r -p "Add it now? [y/N] " answer
        case "$answer" in y|Y|yes|YES) ;; *) echo "Not adding it; nothing was installed."; exit 1 ;; esac
    else
        echo "Not a terminal: pass --yes to add it, or run opt/omarchy-repo.sh first." >&2
        exit 1
    fi
    if [ "$dry" = 1 ]; then "$REPO/opt/omarchy-repo.sh" -n; else "$REPO/opt/omarchy-repo.sh"; fi
fi

# ── packages ─────────────────────────────────────────────────────────────
pkgs=("${ARCH_PKGS[@]}")
for p in "${OMARCHY_PKGS[@]}"; do pkgs+=("omarchy/$p"); done
say "Installing RetroArch and its cores (missing ones only)"
if ! run $SUDO pacman -S --needed --noconfirm "${pkgs[@]}"; then
    warn "pacman failed. A 404 means a stale package database: run a full system upgrade (sudo pacman -Syu) and again."
    exit 1
fi

if ! compgen -G '/usr/share/vulkan/icd.d/*.json' >/dev/null; then
    warn "no Vulkan driver is installed (vulkan-radeon, vulkan-intel, nvidia-utils; vulkan-swrast for software rendering):"
    warn "RetroArch will not start with video_driver = vulkan until one is. Omarchy's installer assumes it."
fi

# ── config ───────────────────────────────────────────────────────────────
marker="${XDG_CONFIG_HOME:-$HOME/.config}/cachy-dots/omarchy-retroarch"
if [ -e "$marker" ] && [ "$reconfigure" = 0 ]; then
    say "Config already applied (--reconfigure applies it again)"
    exit 0
fi
if pgrep -x retroarch >/dev/null 2>&1; then
    warn "RetroArch is running: it rewrites its config on exit. Close it and run this again."
    exit 1
fi

say "Applying Omarchy's RetroArch config"
cfgdir="${XDG_CONFIG_HOME:-$HOME/.config}/retroarch"
cfg="$cfgdir/retroarch.cfg"
run mkdir -p "$HOME/Games/bios" "$HOME/Games/roms" "$cfgdir/config" "$(dirname "$marker")"
if [ "$dry" = 1 ]; then
    echo "+ merge $REPO/retroarch/omarchy.cfg into $cfg"
    echo "+ copy $REPO/retroarch/global.slangp to $cfgdir/config/global.slangp"
else
    touch "$cfg"
    tmp=$(mktemp)
    cp "$cfg" "$tmp"
    while IFS= read -r line; do
        [[ $line =~ ^([a-z_0-9]+)\ =\ \"(.*)\"$ ]] || continue
        key=${BASH_REMATCH[1]}
        value=${BASH_REMATCH[2]//@HOME@/$HOME}
        # Drop the key where it is and append the new value, as Omarchy's set_cfg does
        # (it rewrites the line in place); RetroArch rewrites the file on exit anyway.
        grep -v "^$key = " "$tmp" > "$tmp.new" || true
        printf '%s = "%s"\n' "$key" "$value" >> "$tmp.new"
        mv "$tmp.new" "$tmp"
    done < "$REPO/retroarch/omarchy.cfg"
    cat "$tmp" > "$cfg"
    rm -f "$tmp"
    cp "$REPO/retroarch/global.slangp" "$cfgdir/config/global.slangp"
    touch "$marker"
fi
echo "Put ROMs in ~/Games/roms and BIOS files in ~/Games/bios, then start RetroArch."
