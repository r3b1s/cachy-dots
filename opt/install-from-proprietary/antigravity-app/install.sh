#!/usr/bin/env bash
# Opt-in installer for Google Antigravity (https://antigravity.google/download), the
# desktop app ("Antigravity App"; the standalone "Antigravity IDE" is a separate download).
#
# Closed source: Google only ships a .tar.gz for Linux, with no package-manager repo and
# no published checksum. The archive's URL carries a build id, so the script reads the
# current one off the download page (it is in the static HTML) unless --url is given.
# TLS to Google's hosts is the only authenticity check there is.
#
# What it does:
#   1. installs the missing Electron runtime libraries via pacman
#   2. finds the download URL for this CPU (x86_64 -> linux-x64, aarch64 -> linux-arm)
#   3. downloads the archive and unpacks it as the invoking user, so nothing from
#      the archive runs or is written as root
#   4. copies the tree to /usr/local/lib/antigravity (root-owned), links the launcher
#      as /usr/local/bin/antigravity-app and writes a desktop entry; the archive ships
#      no icon file, so the 512x512 icon.png is read out of resources/app.asar and
#      installed as the hicolor icon "antigravity"
#   5. records the URL in the install dir; a re-run with the same URL does nothing
#      (--force reinstalls)
#
# No setuid chrome-sandbox is set: Arch and CachyOS allow unprivileged user namespaces,
# which Chromium's sandbox uses instead.
#
# --remove deletes the install, the link and the desktop entry, and leaves the user's
# own data (~/.config/Antigravity and the like) alone.
#
# Antigravity's own updater (app-update.yml) cannot replace the root-owned install;
# update by re-running this script.
#
# Usage: opt/install-from-proprietary/antigravity/install.sh [--url <tar.gz url>] [--force] [--remove] [-n|--dry-run]
set -euo pipefail

say()  { printf '\033[1;34m::\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
run()  { if [ "$dry" = 1 ]; then echo "+ $*"; else "$@"; fi; }

SUDO=
[ "$(id -u)" -ne 0 ] && SUDO=sudo

url=""
force=0
remove=0
dry=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --url)          url="${2:?--url needs a value}"; shift ;;
        --force)        force=1 ;;
        --remove)       remove=1 ;;
        -n|--dry-run)   dry=1 ;;
        -h|--help)      sed -n '2,/^set -/{/^set -/!p}' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

PAGE=https://antigravity.google/download
INSTALL_DIR=/usr/local/lib/antigravity
BIN_LINK=/usr/local/bin/antigravity-app
DESKTOP_FILE=/usr/local/share/applications/antigravity.desktop
ICON_FILE=/usr/local/share/icons/hicolor/512x512/apps/antigravity.png

refresh_desktop_db() {
    if command -v update-desktop-database >/dev/null 2>&1; then
        run $SUDO update-desktop-database -q /usr/local/share/applications || true
    fi
    if command -v gtk-update-icon-cache >/dev/null 2>&1; then
        run $SUDO gtk-update-icon-cache -q -t -f /usr/local/share/icons/hicolor || true
    fi
}

# -----------------------------------------------------------------------------
# Removal
# -----------------------------------------------------------------------------
if [ "$remove" = 1 ]; then
    say "Removing Antigravity from /usr/local..."
    # Only a link that points into the install dir is ours.
    if [ -L "$BIN_LINK" ] && [[ "$(readlink "$BIN_LINK")" == "$INSTALL_DIR"/* ]]; then
        run $SUDO rm -f "$BIN_LINK"
    fi
    run $SUDO rm -f "$DESKTOP_FILE" "$ICON_FILE"
    run $SUDO rm -rf "$INSTALL_DIR"
    refresh_desktop_db
    say "Antigravity removed. Its user data (~/.config/Antigravity) is untouched."
    exit 0
fi

# -----------------------------------------------------------------------------
# System dependencies (pacman)
# -----------------------------------------------------------------------------
# Electron's runtime, and python for reading the icon out of app.asar; curl and tar are in base.
PKGS=(gtk3 nss alsa-lib libsecret xdg-utils python)

missing_pkgs=()
for pkg in "${PKGS[@]}"; do
    pacman -Qq "$pkg" >/dev/null 2>&1 || missing_pkgs+=("$pkg")
done
if [ "${#missing_pkgs[@]}" -gt 0 ]; then
    say "Installing missing system dependencies: ${missing_pkgs[*]}"
    run $SUDO pacman -S --needed --noconfirm "${missing_pkgs[@]}"
fi

# -----------------------------------------------------------------------------
# Download URL
# -----------------------------------------------------------------------------
case "$(uname -m)" in
    x86_64)  platform=linux-x64 ;;
    aarch64) platform=linux-arm ;;
    *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

if [ -z "$url" ]; then
    say "Reading the current download URL from $PAGE..."
    url=$(curl -fsSL --proto '=https' --tlsv1.2 "$PAGE" \
        | grep -oE "https://storage\.googleapis\.com/antigravity-public/antigravity-hub/[^\"' ]+/$platform/Antigravity\.tar\.gz" \
        | sort -u | head -n1 || true)
    if [ -z "$url" ]; then
        echo "no $platform archive found on $PAGE; pass one with --url" >&2
        exit 1
    fi
fi
case "$url" in https://*) ;; *) echo "refusing a non-https URL: $url" >&2; exit 1 ;; esac
say "Archive: $url"

if [ "$force" = 0 ] && [ -f "$INSTALL_DIR/.source-url" ] \
    && [ "$(cat "$INSTALL_DIR/.source-url")" = "$url" ]; then
    say "Already installed from this URL (--force reinstalls)."
    exit 0
fi

# -----------------------------------------------------------------------------
# Download and unpack, as the invoking user
# -----------------------------------------------------------------------------
work=$(mktemp -d "${XDG_CACHE_HOME:-$HOME/.cache}/antigravity-install.XXXXXX")
trap 'rm -rf "$work"' EXIT

say "Downloading (about 180 MB)..."
run curl -fL --proto '=https' --tlsv1.2 --progress-bar -o "$work/antigravity.tar.gz" "$url"

say "Unpacking..."
run mkdir "$work/tree"
run tar -xzf "$work/antigravity.tar.gz" -C "$work/tree" --no-same-owner --no-same-permissions

if [ "$dry" = 1 ]; then
    src="$work/tree"
    launcher_rel="antigravity"
else
    src="$work/tree"
    # A single top-level directory is the tree itself; otherwise the archive is.
    mapfile -t top < <(find "$src" -mindepth 1 -maxdepth 1)
    if [ "${#top[@]}" -eq 1 ] && [ -d "${top[0]}" ]; then
        src="${top[0]}"
    fi

    launcher=$(find "$src" -maxdepth 2 -type f -perm -u+x -iname antigravity | sort | head -n1)
    if [ -z "$launcher" ]; then
        echo "no 'antigravity' executable in the archive; its layout has changed" >&2
        exit 1
    fi
    launcher_rel=${launcher#"$src"/}
fi

# The archive has no icon file; the app's 512x512 icon.png is inside resources/app.asar
# (header: four little-endian words, then JSON; file data follows, 4-byte aligned).
# Checked against the SHA-256 the header records.
extract_icon() {
    python3 -I - "$1" "$2" <<'PY'
import hashlib, json, struct, sys
asar, out = sys.argv[1:3]
with open(asar, "rb") as f:
    n = struct.unpack("<I", f.read(16)[12:16])[0]
    header = json.loads(f.read(n))
    entry = header["files"]["icon.png"]
    f.seek((16 + n + 3) & ~3)
    f.seek(int(entry["offset"]), 1)
    data = f.read(entry["size"])
if hashlib.sha256(data).hexdigest() != entry["integrity"]["hash"] or data[:8] != b"\x89PNG\r\n\x1a\n":
    sys.exit("icon.png in app.asar failed its integrity check")
with open(out, "wb") as f:
    f.write(data)
PY
}

icon=""
if [ "$dry" = 1 ]; then
    echo "+ extract icon.png from resources/app.asar"
    icon=antigravity
elif extract_icon "$src/resources/app.asar" "$work/icon.png"; then
    icon=antigravity
else
    warn "could not read the icon out of app.asar; the desktop entry gets none"
fi

# -----------------------------------------------------------------------------
# Install (root-owned copy under /usr/local)
# -----------------------------------------------------------------------------
say "Installing to $INSTALL_DIR..."
run $SUDO rm -rf "$INSTALL_DIR"
run $SUDO mkdir -p "$INSTALL_DIR"
run $SUDO cp -a --no-preserve=ownership "$src"/. "$INSTALL_DIR"/
run $SUDO chown -R root:root "$INSTALL_DIR"
if [ "$dry" = 1 ]; then
    echo "+ write $INSTALL_DIR/.source-url"
else
    printf '%s\n' "$url" | $SUDO tee "$INSTALL_DIR/.source-url" >/dev/null
fi
run $SUDO ln -sfn "$INSTALL_DIR/$launcher_rel" "$BIN_LINK"

if [ -n "$icon" ]; then
    say "Installing the icon..."
    if [ "$dry" = 1 ]; then
        echo "+ install -Dm0644 <icon.png> $ICON_FILE"
    else
        $SUDO install -Dm0644 "$work/icon.png" "$ICON_FILE"
    fi
fi

say "Writing the desktop entry..."
if [ "$dry" = 1 ]; then
    echo "+ write $DESKTOP_FILE"
else
    entry=$(mktemp "$work/desktop.XXXXXX")
    {
        echo "[Desktop Entry]"
        echo "Name=Antigravity"
        echo "GenericName=AI Development Environment"
        echo "Comment=Google Antigravity"
        echo "Exec=$BIN_LINK %U"
        [ -n "$icon" ] && echo "Icon=$icon"
        echo "Terminal=false"
        echo "Type=Application"
        echo "Categories=Development;IDE;"
    } >"$entry"
    if ! cmp -s "$entry" "$DESKTOP_FILE" 2>/dev/null; then
        $SUDO install -Dm0644 "$entry" "$DESKTOP_FILE"
    fi
fi
refresh_desktop_db

say "Antigravity installed. Launch it with antigravity-app or from your launcher."
