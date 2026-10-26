#!/usr/bin/env bash
# The Paseo desktop app, from the AppImage on Paseo's GitHub releases
# (https://github.com/getpaseo/paseo/releases), installed the way
# bin/install-appimage installs one, with a desktop entry that has its icon.
#
# What it does:
#   1. asks GitHub for the latest release (pre-releases are skipped), or takes --tag;
#   2. downloads Paseo-x86_64.AppImage and checks it against the sha256 GitHub
#      publishes for the asset. A version already in ~/Applications that matches is
#      not downloaded again;
#   3. hands it to install-appimage as Paseo-<version>-x86_64.AppImage: into
#      ~/Applications, executable, with the entry ~/.local/share/applications/paseo.desktop
#      (upstream's file name has no version, from which install-appimage would make
#      "Paseo x86 64");
#   4. rewrites that entry from the one inside the AppImage: its icon, installed into
#      ~/.local/share/icons/hicolor; its window class (StartupWMClass, so the window
#      matches its launcher); its arguments; and its paseo:// URL handler, which also
#      becomes the default for x-scheme-handler/paseo;
#   5. removes the Paseo AppImages it replaces from ~/Applications, and every entry
#      that runs one of them (such as paseo-x86-64.desktop from a manual install).
#
# The AppImage runtime needs libfuse.so.2 (the fuse2 package) to start. The daemon and
# its web UI are setup.sh's; this is only the desktop app.
#
# Usage: opt/services/paseo/appimage.sh [--tag vX.Y.Z] [--remove] [-n|--dry-run] [-h|--help]
set -euo pipefail

HERE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
INSTALL_APPIMAGE="$HERE/../../../bin/install-appimage"

dry=0
remove=0
tag=
while [ $# -gt 0 ]; do
    case "$1" in
        --tag)        tag=${2:?--tag needs a value}; shift ;;
        --remove)     remove=1 ;;
        -n|--dry-run) dry=1 ;;
        -h|--help)
            awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
            exit 0
            ;;
        *)
            echo "unknown option: $1" >&2
            exit 2
            ;;
    esac
    shift
done

say()  { printf '\033[1;34m::\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
run()  { if [ "$dry" = 1 ]; then echo "+ $*"; else "$@"; fi; }

REPO=getpaseo/paseo
ASSET=Paseo-x86_64.AppImage
SLUG=paseo
APPS_DIR="$HOME/Applications"
DESKTOP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
ICON_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor"
DESKTOP_FILE="$DESKTOP_DIR/$SLUG.desktop"

# The desktop entries other than ours that run FILE.
entries_running() {
    [ -d "$DESKTOP_DIR" ] || return 0
    grep -lF -- "$1" "$DESKTOP_DIR"/*.desktop 2>/dev/null | grep -vxF "$DESKTOP_FILE" || true
}

# Remove each Paseo AppImage in ~/Applications but KEEP (none: all), with its entries.
remove_appimages() {
    local keep=$1 f entry
    for f in "$APPS_DIR"/Paseo-*.AppImage "$APPS_DIR"/Paseo.AppImage; do
        [ -e "$f" ] && [ "$f" != "$keep" ] || continue
        say "Removing $f"
        while read -r entry; do
            [ -n "$entry" ] || continue
            say "Removing its desktop entry $entry"
            run rm -f "$entry"
        done < <(entries_running "$f")
        run rm -f "$f"
    done
}

refresh_desktop_database() {
    if command -v update-desktop-database >/dev/null 2>&1; then
        run update-desktop-database "$DESKTOP_DIR" || true
    fi
}

# ── Removal ───────────────────────────────────────────────────────────────────

if [ "$remove" = 1 ]; then
    remove_appimages none
    if [ -f "$DESKTOP_FILE" ]; then
        say "Removing $DESKTOP_FILE"
        run rm -f "$DESKTOP_FILE"
    fi
    while read -r icon; do
        [ -n "$icon" ] || continue
        say "Removing $icon"
        run rm -f "$icon"
    done < <(find "$ICON_DIR" -path "*/apps/$SLUG.*" 2>/dev/null)
    refresh_desktop_database
    say "Paseo desktop app removed."
    exit 0
fi

# ── Prerequisites ─────────────────────────────────────────────────────────────

for tool in curl jq sha256sum; do
    command -v "$tool" >/dev/null 2>&1 || die "$tool is required"
done
[ -x "$INSTALL_APPIMAGE" ] || die "install-appimage not found at $INSTALL_APPIMAGE"
[ "$(uname -m)" = x86_64 ] || die "Paseo publishes its AppImage for x86_64 only"
if command -v pacman >/dev/null 2>&1 && ! pacman -Qq fuse2 >/dev/null 2>&1; then
    warn "fuse2 is not installed: the AppImage installs, but needs it to start (sudo pacman -S fuse2)"
fi

# ── 1. The release ────────────────────────────────────────────────────────────

if [ -n "$tag" ]; then
    api="https://api.github.com/repos/$REPO/releases/tags/$tag"
else
    api="https://api.github.com/repos/$REPO/releases/latest"
fi
say "Asking GitHub for ${tag:-the latest release}"
release=$(curl -fsSL -H 'Accept: application/vnd.github+json' "$api") \
    || die "could not read $api"
tag=$(jq -r '.tag_name' <<<"$release")
version=${tag#v}
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.]+)?$ ]] || die "unexpected release tag: $tag"
url=$(jq -r --arg a "$ASSET" '.assets[] | select(.name == $a) | .browser_download_url' <<<"$release")
sha=$(jq -r --arg a "$ASSET" '.assets[] | select(.name == $a) | .digest // empty' <<<"$release")
[ -n "$url" ] || die "release $tag has no $ASSET"
sha=${sha#sha256:}
[[ $sha =~ ^[0-9a-f]{64}$ ]] || die "GitHub publishes no sha256 for $ASSET in $tag"

dest="$APPS_DIR/Paseo-$version-x86_64.AppImage"
say "Paseo $version"

# ── 2–3. Download, verify, install ────────────────────────────────────────────

work=$(mktemp -d "${TMPDIR:-/tmp}/paseo-appimage.XXXXXX")
trap 'rm -rf "$work"' EXIT

if [ -f "$dest" ] && [ "$(sha256sum "$dest" | awk '{ print $1 }')" = "$sha" ]; then
    say "$dest is already installed"
else
    if [ -e "$dest" ]; then
        warn "$dest does not match the release's sha256; replacing it"
        run rm -f "$dest"
    fi
    if [ "$dry" = 1 ]; then
        echo "+ download $url, check sha256 $sha"
        echo "+ $INSTALL_APPIMAGE $work/${dest##*/}"
    else
        say "Downloading $ASSET"
        if [ -t 1 ]; then progress=--progress-bar; else progress=-sS; fi
        curl -fL $progress -o "$work/${dest##*/}" "$url"
        [ "$(sha256sum "$work/${dest##*/}" | awk '{ print $1 }')" = "$sha" ] \
            || die "the download does not match the sha256 GitHub publishes ($sha)"
        "$INSTALL_APPIMAGE" "$work/${dest##*/}"
    fi
fi

if [ "$dry" = 1 ] && [ ! -f "$dest" ]; then
    echo "+ rewrite $DESKTOP_FILE from the AppImage's own entry, install its icons"
    remove_appimages "$dest"
    exit 0
fi

# ── 4. Icon and desktop entry ─────────────────────────────────────────────────

# --appimage-extract only unpacks (into ./squashfs-root); it needs no FUSE.
(cd "$work" && "$dest" --appimage-extract '*.desktop' >/dev/null \
    && "$dest" --appimage-extract 'usr/share/icons/*' >/dev/null) \
    || die "could not unpack the AppImage's desktop entry and icons"
bundled=$(find "$work/squashfs-root" -maxdepth 1 -name '*.desktop' | head -n 1)
[ -n "$bundled" ] || die "the AppImage has no desktop entry"

# KEY's value in the [Desktop Entry] group of the bundled entry.
key() {
    awk -F= -v k="$1" '/^\[/ { group = $0 } group == "[Desktop Entry]" && $1 == k { sub(/^[^=]*=/, ""); print; exit }' "$bundled"
}
icon_name=$(key Icon)
exec_args=$(key Exec)
case $exec_args in
    AppRun\ *) exec_args=${exec_args#AppRun } ;;
    *)         exec_args=%U ;;
esac

say "Icons into $ICON_DIR"
icons=0
while read -r icon; do
    [ -n "$icon" ] || continue
    rel=${icon#"$work/squashfs-root/usr/share/icons/hicolor/"}
    target="$ICON_DIR/${rel%/*}/$SLUG.${icon##*.}"
    icons=$((icons + 1))
    cmp -s "$icon" "$target" || run install -D -m 644 "$icon" "$target"
done < <(find "$work/squashfs-root/usr/share/icons/hicolor" \
    \( -name "$icon_name.png" -o -name "$icon_name.svg" \) 2>/dev/null)
if [ "$icons" = 0 ]; then
    warn "the AppImage has no hicolor icon named $icon_name; the entry keeps a generic one"
    entry_icon=application-x-executable
else
    entry_icon=$SLUG
fi

# Quoted for Exec= (\ " ` $ and %), as install-appimage does.
exec_path=$(printf '%s' "$dest" | sed -e 's/[\\"`$]/\\&/g' -e 's/%/%%/g')
{
    echo '[Desktop Entry]'
    echo 'Type=Application'
    echo "Name=$(key Name | grep . || echo Paseo)"
    [ -z "$(key Comment)" ] || echo "Comment=$(key Comment)"
    echo "Exec=\"$exec_path\" $exec_args"
    echo "TryExec=$dest"
    echo "Icon=$entry_icon"
    echo 'Terminal=false'
    [ -z "$(key Categories)" ] || echo "Categories=$(key Categories)"
    [ -z "$(key MimeType)" ] || echo "MimeType=$(key MimeType)"
    [ -z "$(key StartupWMClass)" ] || echo "StartupWMClass=$(key StartupWMClass)"
    echo "X-AppImage-Version=$version"
} > "$work/$SLUG.desktop"
if cmp -s "$work/$SLUG.desktop" "$DESKTOP_FILE"; then
    say "$DESKTOP_FILE is up to date"
else
    say "Writing $DESKTOP_FILE"
    run install -D -m 644 "$work/$SLUG.desktop" "$DESKTOP_FILE"
fi
if command -v desktop-file-validate >/dev/null 2>&1 && [ "$dry" = 0 ]; then
    desktop-file-validate "$DESKTOP_FILE" || warn "desktop-file-validate has complaints about $DESKTOP_FILE"
fi

refresh_desktop_database
if [[ $(key MimeType) == *x-scheme-handler/paseo* ]] && command -v xdg-mime >/dev/null 2>&1 \
    && [ "$(xdg-mime query default x-scheme-handler/paseo 2>/dev/null)" != "$SLUG.desktop" ]; then
    say "paseo:// links open in the desktop app"
    run xdg-mime default "$SLUG.desktop" x-scheme-handler/paseo
fi

# ── 5. What it replaces ───────────────────────────────────────────────────────

remove_appimages "$dest"

printf '\n\033[1;32m✓ Paseo %s: %s\033[0m\n' "$version" "$dest"
printf '  Desktop entry: %s (icon %s)\n' "$DESKTOP_FILE" "$entry_icon"
