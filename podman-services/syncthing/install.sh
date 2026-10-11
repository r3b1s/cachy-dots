#!/usr/bin/env bash
# Install the rootless Syncthing Quadlet (syncthing.container) for this user.
#
#   1. asks for this host's NetBird (wt0) address on the first run; later runs
#      reuse the one in the installed unit (--reconfigure asks again)
#   2. renders syncthing.container with it into ~/.config/containers/systemd/
#   3. reloads systemd --user, then starts syncthing.service, or restarts it
#      when it is running and the unit changed
#
# Run as your own user, never with sudo: the container is rootless.
#
# Usage: podman-services/syncthing/install.sh [--reconfigure] [-n|--dry-run]
set -euo pipefail

HERE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)

reconfigure=0
dry=0
for arg in "$@"; do
    case "$arg" in
        --reconfigure) reconfigure=1 ;;
        -n|--dry-run)  dry=1 ;;
        -h|--help)     sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

say()  { printf '\033[1;34m::\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
run()  { if [ "$dry" = 1 ]; then echo "+ $*"; else "$@"; fi; }

template="$HERE/syncthing.container"
dest="${XDG_CONFIG_HOME:-$HOME/.config}/containers/systemd/syncthing.container"

if [ "$(id -u)" -eq 0 ]; then
    echo "run this as your own user, not root: the container is rootless" >&2
    exit 1
fi
command -v podman >/dev/null || { echo "podman is not installed" >&2; exit 1; }

# The address on wt0 right now, or nothing when NetBird is down.
wt0_ip() {
    ip -4 -o addr show dev wt0 2>/dev/null | awk '{ split($4, a, "/"); print a[1]; exit }'
}

# The address the installed unit publishes 22000 on, or nothing.
installed_ip() {
    [ -f "$dest" ] || return 0
    sed -n 's|^PublishPort=\([0-9.]*\):22000:22000/tcp$|\1|p' "$dest"
}

# Prints the NetBird address to publish on (stdout); prompts go to stderr.
# Enter takes wt0's current address. Asks again until the answer is an IPv4
# address, which is also what makes it safe to put in the sed expression.
ask_netbird_ip() {
    local def answer o ok
    local octet='(0|[1-9][0-9]{0,2})'    # no leading zeros, which some tools read as octal
    def=$(wt0_ip)
    while :; do
        # read fails at end of input; a last line without a newline still counts.
        if ! read -rp "NetBird (wt0) address of this host${def:+ [$def]}: " answer && [ -z "$answer" ]; then
            printf '\nno address given\n' >&2
            return 1
        fi
        answer=${answer:-$def}
        ok=0
        if [[ $answer =~ ^$octet(\.$octet){3}$ ]]; then
            ok=1
            for o in ${answer//./ }; do (( o <= 255 )) || ok=0; done
        fi
        # 0.0.0.0 would publish on every interface, not just wt0.
        case $answer in 0.0.0.0|127.*)
            echo "$answer is not a NetBird address" >&2; continue ;;
        esac
        if [ "$ok" = 1 ]; then
            printf '%s\n' "$answer"
            return 0
        fi
        echo "not an IPv4 address: ${answer:-(empty)}" >&2
    done
}

ip=
[ "$reconfigure" = 1 ] || ip=$(installed_ip)
if [ -n "$ip" ]; then
    say "NetBird address: $ip (from the installed unit; --reconfigure to change)"
else
    ip=$(ask_netbird_ip)
fi
current=$(wt0_ip)
[ "$ip" = "$current" ] || warn "wt0 has ${current:-no address} now, not $ip; syncthing will retry until $ip is up"

rendered=$(mktemp)
trap 'rm -f "$rendered"' EXIT
sed "s/@NETBIRD_IP@/$ip/g" "$template" > "$rendered"

changed=1
cmp -s "$rendered" "$dest" 2>/dev/null && changed=0
if [ "$changed" = 1 ]; then
    say "writing $dest"
    [ "$dry" = 1 ] && { diff -u "$dest" "$rendered" 2>/dev/null || true; }
    run mkdir -p "$(dirname "$dest")" "$HOME/Sync"
    run install -m 0644 "$rendered" "$dest"
    run systemctl --user daemon-reload
fi

if systemctl --user -q is-active syncthing.service; then
    if [ "$changed" = 1 ]; then
        say "restarting syncthing.service"
        run systemctl --user restart syncthing.service
    fi
else
    say "starting syncthing.service (the first start pulls the image)"
    run systemctl --user start syncthing.service
fi

if [ "$(loginctl show-user "$USER" -p Linger --value 2>/dev/null)" != yes ]; then
    warn "syncthing stops when you log out; to keep it running: loginctl enable-linger"
fi
say "GUI: http://127.0.0.1:8384 (set a GUI password; add $HOME/Sync as the folder)"
