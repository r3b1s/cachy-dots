#!/usr/bin/env bash
# Apply dms/settings.json, the snapshot of dux's settings, to ~/.config/dms/settings.json.
#
#   (default)   merge it under the host's file: the host's values win. Once: the marker
#               ~/.config/cachy-dots/dux-settings-seeded makes a later run do nothing, so a
#               key reset in dux's Settings is not put back. opt/hyprland.sh runs this.
#   --reset     restore the baseline: the snapshot wins over every key it holds; keys it
#               lacks stay. The old file is kept as settings.json.bak-<timestamp>.
#
# A copy, never a link: dux rewrites settings.json from its Settings pages. Safe with dux
# running: it watches the file and reloads it when it changes (SettingsData.qml,
# watchChanges). Not seen on a live session.
#
# Usage: opt/dux-settings.sh [--reset] [-n|--dry-run]
set -euo pipefail

reset=0
dry=0
for arg in "$@"; do
    case "$arg" in
        --reset)      reset=1 ;;
        -n|--dry-run) dry=1 ;;
        -h|--help)    sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

mode=merge
[ "$reset" = 1 ] && mode=reset
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }

src="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/dms/settings.json"
cfg="${XDG_CONFIG_HOME:-$HOME/.config}/dms/settings.json"
marker="${XDG_CONFIG_HOME:-$HOME/.config}/cachy-dots/dux-settings-seeded"

command -v jq >/dev/null || { warn "jq is needed"; exit 1; }
jq -e . "$src" >/dev/null || { warn "$src is not valid JSON"; exit 1; }

if [ "$reset" = 0 ] && [ -e "$marker" ]; then
    echo "dux's settings snapshot already applied ($marker); --reset restores it"
    exit 0
fi
if [ "$dry" = 1 ]; then
    echo "+ $mode $src into $cfg"
    exit 0
fi
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
existing="$tmp/existing.json"
{ cat "$cfg" 2>/dev/null || echo '{}'; } > "$existing"
if [ "$reset" = 1 ]; then
    jq -s '.[0] * .[1]' "$existing" "$src" > "$tmp/new.json"
    [ -s "$cfg" ] && cp -p "$cfg" "$cfg.bak-$(date +%Y%m%d-%H%M%S)"
else
    jq -s '.[0] * .[1]' "$src" "$existing" > "$tmp/new.json"
fi
# Replaced by a rename in the same directory, as dux writes it (atomicWrites), so a
# running dux, which watches the file and reloads on an outside change, never reads half.
mkdir -p "$(dirname "$cfg")"
install -m644 "$tmp/new.json" "$cfg.new" && mv -f "$cfg.new" "$cfg"
install -Dm644 /dev/null "$marker"
echo "applied dux's settings snapshot ($mode, $cfg)"
