#!/usr/bin/env bash
# Runs inside the Rakazo VM as root, sent by install.sh over SSH
# (`sudo bash -s -- ARGS < guest.sh`); not run on its own. Converges the guest,
# each step only when it differs:
#
#   1. pacman -Syu with docker and docker-compose. Exits 100 when the running
#      kernel's modules are gone (a kernel upgrade): Docker cannot load its
#      modules until a reboot, so install.sh reboots the VM and runs this again;
#   2. upstream's docker-daemon.json (live restore, bounded logs, no new
#      privileges, no userland proxy), then Docker itself;
#   3. the bot-computer egress rules, the release's restrict-computer-egress.sh,
#      which persists itself as rakazo-computer-egress.service: bot computers
#      reach public addresses only, not this VM, the host or any LAN;
#   4. the stack, as the user rakazo (docker group) in ~/rakazo. install-images.sh
#      --prepare-only makes .env with its secrets once; this script sets the
#      keys it owns (below) and a Compose override that publishes the web port
#      on all of the VM's addresses (its only interface is the /30 to the host;
#      the API stays on loopback); then install-images.sh pulls and starts the
#      stack, and Compose recreates only what changed;
#   5. checks the API's health, the web app and the egress rules.
#
# The .env keys it owns: RAKAZO_IMAGE_TAG and RAKAZO_COMPUTER_IMAGE_TAG (the
# release); WEB_ORIGIN, BETTER_AUTH_URL, API_URL and RAKAZO_HOST (the origin);
# SANDBOX_COMPUTER_EGRESS=restricted; SANDBOX_COMPUTER_DNS (public resolvers:
# the VM's resolver is the host's dnsmasq, a private address the egress rules
# drop); and SIGNUPS_ENABLED when --signups is given. Nothing else in .env is
# touched, and none of it is printed.
#
# Usage: guest.sh --tag vX.Y.Z --origin http://ADDRESS:PORT [--signups true|false]

set -euo pipefail

say()  { printf '\033[1;34m  guest:\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m  guest error:\033[0m %s\n' "$*" >&2; exit 1; }

APP_USER=rakazo
APP_HOME=/home/$APP_USER
APP_DIR=$APP_HOME/rakazo
COMPUTER_DNS=9.9.9.9,149.112.112.112   # Quad9, and its secondary
EGRESS_INSTALLED=/usr/local/sbin/rakazo-computer-egress
EGRESS_UNIT=/etc/systemd/system/rakazo-computer-egress.service

# Fetch URL into a new temporary file and print its path.
fetch() {
    local tmp
    tmp=$(mktemp)
    curl -fsSL --proto '=https' --retry 3 -o "$tmp" "$1" || { rm -f "$tmp"; die "could not download $1"; }
    printf '%s\n' "$tmp"
}

# Move SRC to DEST (mode, owner) when it differs; returns 1 when nothing changed.
place() {
    local src=$1 dest=$2 mode=$3 owner=$4
    if cmp -s "$src" "$dest"; then
        rm -f "$src"
        return 1
    fi
    install -D -m "$mode" -o "$owner" -g "$owner" "$src" "$dest"
    rm -f "$src"
}

as_app() {
    runuser -u "$APP_USER" -- env -C "$APP_DIR" HOME="$APP_HOME" PATH=/usr/local/bin:/usr/bin \
        RAKAZO_DOWNLOAD_BASE="$BASE" "$@"
}

# Set KEY=VALUE lines in .env: replace each key's first line, drop its later
# duplicates, append the missing ones. Written (0600) only when it changes.
set_env() {
    local env=$APP_DIR/.env tmp kv changed=()
    for kv; do grep -qxF -- "$kv" "$env" || changed+=("${kv%%=*}"); done
    tmp=$(mktemp)
    printf '%s\n' "$@" | awk '
        NR == FNR { k = $0; sub(/=.*/, "", k); want[k] = $0; order[++n] = k; next }
        { k = $0; sub(/=.*/, "", k) }
        k in want { if (!(k in done)) print want[k]; done[k] = 1; next }
        { print }
        END { for (i = 1; i <= n; i++) if (!(order[i] in done)) print want[order[i]] }
    ' - "$env" > "$tmp"
    if place "$tmp" "$env" 0600 "$APP_USER"; then
        say ".env: set ${changed[*]:-(duplicates removed)}"
    fi
}

wait_http() {
    local url=$1 _
    for _ in $(seq 60); do
        curl -fsS -o /dev/null --max-time 5 "$url" 2>/dev/null && return 0
        sleep 5
    done
    die "no answer from $url"
}

main() {
    # Everything below runs with the script fully read: nothing may eat stdin.
    exec </dev/null

    local tag='' origin='' signups=''
    while [ $# -gt 0 ]; do
        case "$1" in
            --tag)     tag=${2:-}; shift ;;
            --origin)  origin=${2:-}; shift ;;
            --signups) signups=${2:-}; shift ;;
            *) die "unknown option: $1" ;;
        esac
        shift
    done
    [[ $tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "--tag must look like v1.2.3"
    [[ $origin =~ ^https?://[A-Za-z0-9.-]+(:[0-9]+)?$ ]] || die "--origin must be scheme://host[:port]"
    [[ -z $signups || $signups == true || $signups == false ]] || die "--signups is true or false"
    local host=${origin#*://}
    host=${host%%:*}
    BASE=https://raw.githubusercontent.com/elie222/rakazo/$tag/infra/compose

    . /etc/os-release
    [ "${ID:-}" = arch ] || die "this is not Arch Linux"

    # 1 ── packages ───────────────────────────────────────────────────────────
    say "pacman -Syu docker docker-compose"
    pacman -Syu --needed --noconfirm --noprogressbar docker docker-compose >/dev/null
    if [ ! -d "/usr/lib/modules/$(uname -r)" ]; then
        say "the kernel was upgraded: reboot needed"
        exit 100
    fi

    # 2 ── Docker ─────────────────────────────────────────────────────────────
    local tmp
    tmp=$(fetch "$BASE/docker-daemon.json")
    if place "$tmp" /etc/docker/daemon.json 0644 root; then
        say "docker-daemon.json updated"
        ! systemctl is-active --quiet docker.service || systemctl restart docker.service
    fi
    systemctl enable --now docker.service >/dev/null 2>&1
    id -nG "$APP_USER" | tr ' ' '\n' | grep -qx docker || usermod -aG docker "$APP_USER"

    # 3 ── bot computer egress ────────────────────────────────────────────────
    tmp=$(fetch "$BASE/restrict-computer-egress.sh")
    if ! cmp -s "$tmp" "$EGRESS_INSTALLED" || [ ! -f "$EGRESS_UNIT" ] \
        || ! iptables -S DOCKER-USER 2>/dev/null | grep -q rakazo-c; then
        say "installing the bot computer egress rules"
        bash "$tmp"
    fi
    rm -f "$tmp"

    # 4 ── the stack ──────────────────────────────────────────────────────────
    install -d -o "$APP_USER" -g "$APP_USER" -m 0750 "$APP_DIR"
    tmp=$(fetch "$BASE/install-images.sh")
    place "$tmp" "$APP_DIR/install-images.sh" 0700 "$APP_USER" || true

    if [ ! -f "$APP_DIR/.env" ]; then
        say "creating .env (random secrets; back up ENCRYPTION_KEY from $APP_DIR/.env)"
    fi
    as_app bash install-images.sh --prepare-only >/dev/null

    tmp=$(mktemp)
    cat > "$tmp" <<'YAML'
# Written by cachy-dots (opt/services/rakazo/guest.sh). The host reaches the web
# app over the VM's bridge, so publish it on every address of the VM, whose only
# interface is the /30 to the host. The API stays on loopback.
services:
  web:
    ports: !override
      - "5173:5173"
YAML
    place "$tmp" "$APP_DIR/docker-compose.override.yml" 0644 "$APP_USER" || true

    local keys=(
        "RAKAZO_IMAGE_TAG=$tag"
        "RAKAZO_COMPUTER_IMAGE_TAG=$tag"
        "WEB_ORIGIN=$origin"
        "BETTER_AUTH_URL=$origin"
        "API_URL=$origin"
        "RAKAZO_HOST=$host"
        "SANDBOX_COMPUTER_EGRESS=restricted"
        "SANDBOX_COMPUTER_DNS=$COMPUTER_DNS"
    )
    [ -z "$signups" ] || keys+=("SIGNUPS_ENABLED=$signups")
    set_env "${keys[@]}"

    say "install-images.sh at $tag (pulls, then starts what changed)"
    as_app bash install-images.sh

    # 5 ── checks ─────────────────────────────────────────────────────────────
    wait_http http://127.0.0.1:3100/internal/health
    wait_http http://127.0.0.1:5173/
    iptables -S DOCKER-USER | grep -q rakazo-c || die "the bot computer egress rules are missing"
    say "Rakazo $tag is up (egress for bot computers: restricted)"
}

main "$@"
