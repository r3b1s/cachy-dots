#!/usr/bin/env bash
# Brings the service stack to what stack.toml and services/*/ describe, under
# Incus. Runs as the user (in incus-admin), after host-setup.sh has run once with
# sudo. Every step is idempotent; re-run it after any change.
#
#   - initialises Incus from incus/preseed.yaml when it has no storage pool yet;
#   - renders the Incus objects (render.py) and creates or updates, per service,
#     its ACL, its bridge and its profile (limits, NIC, disk; the edge's proxy
#     devices, which publish ports.first + index on the NetBird address);
#   - creates each instance from stack.toml's image and starts it;
#   - keeps a private CA in ~/.local/share/cachy-stack/ca, name-constrained to
#     the NetBird address, and a leaf certificate for that address, which goes
#     to the edge; clients trust ca.crt (Node: NODE_EXTRA_CA_CERTS);
#   - copies this directory into each guest as /etc/cachy-stack and runs
#     `nixos-rebuild switch --flake` there for the guest's service;
#   - checks each published port.
#
#   --render         print the rendered Incus objects and change nothing
#   --only NAME      apply one service (its Incus objects and its guest)
#   --no-rebuild     leave the guests' NixOS configurations alone
#   --remove         delete the instances (their disks and data with them), the
#                    profiles, bridges and ACLs; keeps the CA
#   --purge          with --remove: delete the CA too
#
# Usage: apply.sh [--render] [--only NAME] [--no-rebuild] [--remove [--purge]] [-n|--dry-run] [-h|--help]
set -euo pipefail

HERE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
STATE=${XDG_DATA_HOME:-$HOME/.local/share}/cachy-stack
CA=$STATE/ca

say()  { printf '\033[1;34m::\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; FAILED=1; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
exec 3>&1
run()  { if [ "$dry" = 1 ]; then echo "+ $*" >&3; else "$@"; fi; }
usage() { awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; exit 0; }

dry=0 render=0 only='' rebuild=1 remove=0 purge=0 FAILED=0
while [ $# -gt 0 ]; do
    case $1 in
        --render) render=1 ;;
        --only) only=${2:?--only needs a service name}; shift ;;
        --no-rebuild) rebuild=0 ;;
        --remove) remove=1 ;;
        --purge) purge=1 ;;
        -n|--dry-run) dry=1 ;;
        -h|--help) usage ;;
        *) die "unknown option: $1" ;;
    esac
    shift
done

command -v incus >/dev/null || die "incus is not installed"
toml() { python3 -I -c 'import sys, tomllib; d = tomllib.load(open(sys.argv[1], "rb"))
for k in sys.argv[2].split("."): d = d[k]
print(d)' "$HERE/stack.toml" "$1"; }
iface=$(toml interface)
image=$(toml image)
edge_ip=$(ip -4 -o addr show dev "$iface" 2>/dev/null | awk '{ sub(/\/.*/, "", $4); print $4; exit }')
[ -n "$edge_ip" ] || die "$iface has no IPv4 address (is NetBird up?)"

selected() { [ -z "$only" ] || [ "$1" = "$only" ]; }

out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
python3 -I "$HERE/render.py" "$HERE" "$edge_ip" "$out"

if [ "$render" = 1 ]; then
    for f in "$out"/acls/*.json "$out"/networks/*.json "$out"/profiles/*.json; do
        printf '# %s\n' "${f#"$out"/}"; cat "$f"
    done
    printf '# instances.tsv\n'; cat "$out/instances.tsv"
    exit 0
fi

# ── Removal ──────────────────────────────────────────────────────────────────
if [ "$remove" = 1 ]; then
    # Instances first (they use the profiles and bridges), then what they used.
    while IFS=$'\t' read -r -u 4 name _ _ service; do
        selected "$service" || continue
        if incus info "$name" >/dev/null 2>&1; then say "Deleting $name"; run incus delete --force "$name"; fi
        if incus profile show "$name" >/dev/null 2>&1; then run incus profile delete "$name"; fi
        if incus network show "$name" >/dev/null 2>&1; then run incus network delete "$name"; fi
        if incus network acl show "$name" >/dev/null 2>&1; then run incus network acl delete "$name"; fi
    done 4< "$out/instances.tsv"
    if [ "$purge" = 1 ] && [ -z "$only" ]; then say "Deleting $CA"; run rm -rf "$CA"; fi
    exit 0
fi

# ── Incus itself ─────────────────────────────────────────────────────────────
if ! incus storage show default >/dev/null 2>&1; then
    say "Initialising Incus (incus/preseed.yaml)"
    run incus admin init --preseed < "$HERE/incus/preseed.yaml"
fi

# put KIND NAME FILE: create the object if it is missing, then make it match FILE.
put() {
    local kind=$1 name=$2 file=$3
    # shellcheck disable=SC2086 # kind is one or two words
    if ! incus $kind show "$name" >/dev/null 2>&1; then
        say "Creating $kind $name"
        if [ "$kind" = network ]; then run incus network create "$name" --type=bridge < "$file"
        else run incus $kind create "$name" < "$file"; fi
    else
        run incus $kind edit "$name" < "$file"
    fi
}

# The loops below read their lists from fd 4: incus reads YAML from stdin
# whenever it is not a terminal, and would take the list as an object.

while IFS=$'\t' read -r -u 4 name _ _ service; do
    selected "$service" || continue
    put "network acl" "$name" "$out/acls/$name.json"
    put network "$name" "$out/networks/$name.json"
    put profile "$name" "$out/profiles/$name.json"
done 4< "$out/instances.tsv"

# ── TLS: the CA stays here, the leaf goes to the edge ────────────────────────
leaf_ok() {
    [ -f "$CA/leaf.crt" ] && openssl x509 -in "$CA/leaf.crt" -noout -checkend $((30 * 86400)) >/dev/null &&
        openssl x509 -in "$CA/leaf.crt" -noout -ext subjectAltName | grep -qx "    IP Address:$edge_ip" &&
        openssl verify -CAfile "$CA/ca.crt" "$CA/leaf.crt" >/dev/null 2>&1
}
ca_ok() {
    [ -f "$CA/ca.crt" ] && openssl x509 -in "$CA/ca.crt" -noout -ext nameConstraints | grep -q "IP:$edge_ip/255.255.255.255"
}
if [ "$dry" = 0 ]; then
    install -d -m 700 "$STATE" "$CA"
    if ! ca_ok; then
        [ ! -f "$CA/ca.crt" ] || warn "the NetBird address is now $edge_ip: a new CA, which clients must trust again"
        say "Creating the private CA for $edge_ip"
        (umask 077
         openssl genpkey -algorithm ec -pkeyopt ec_paramgen_curve:P-256 -out "$CA/ca.key" 2>/dev/null
         openssl req -x509 -new -key "$CA/ca.key" -days 3650 -subj "/CN=cachy-stack CA ($edge_ip)" \
             -addext "basicConstraints=critical,CA:true,pathlen:0" \
             -addext "keyUsage=critical,keyCertSign,cRLSign" \
             -addext "nameConstraints=critical,permitted;IP:$edge_ip/255.255.255.255" \
             -out "$CA/ca.crt")
        rm -f "$CA/leaf.crt"
    fi
    if ! leaf_ok; then
        say "Issuing the edge's certificate for $edge_ip"
        (umask 077
         openssl genpkey -algorithm ec -pkeyopt ec_paramgen_curve:P-256 -out "$CA/leaf.key" 2>/dev/null
         openssl req -new -key "$CA/leaf.key" -subj "/CN=$edge_ip" -out "$CA/leaf.csr"
         printf '%s\n' "basicConstraints=critical,CA:false" "keyUsage=critical,digitalSignature" \
             "extendedKeyUsage=serverAuth" "subjectAltName=IP:$edge_ip" > "$CA/leaf.ext"
         openssl x509 -req -in "$CA/leaf.csr" -CA "$CA/ca.crt" -CAkey "$CA/ca.key" -CAcreateserial \
             -days 397 -extfile "$CA/leaf.ext" -out "$CA/leaf.crt" 2>/dev/null)
    fi
fi

# ── Instances ────────────────────────────────────────────────────────────────
# A command in a guest, with NixOS's PATH: a VM's agent does not set it.
gexec() {
    local name=$1; shift
    incus exec "$name" --env PATH=/run/wrappers/bin:/run/current-system/sw/bin -- "$@"
}

wait_agent() {
    local _
    for _ in $(seq 90); do gexec "$1" true >/dev/null 2>&1 && return 0; sleep 2; done
    return 1
}

# The agent answers before the guest has its address and DNS; a build started
# then cannot fetch anything.
wait_online() {
    local _
    for _ in $(seq 60); do gexec "$1" getent hosts cache.nixos.org >/dev/null 2>&1 && return 0; sleep 2; done
    return 1
}

# Files a guest needs that are not in its flake: secrets and runtime facts.
#   every guest      /var/lib/cachy-stack/ca.crt      the CA, to verify other services through the edge
#   a published one  /var/lib/cachy-stack/origin.env  ORIGIN and BETTER_AUTH_URL: its https://<NetBird address>:<port>
#   the edge         /var/lib/cachy-edge/{tls/leaf.crt,tls/leaf.key,env}
runtime_files() {
    local name=$1 service=$2 port
    run gexec "$name" install -d -m 755 /var/lib/cachy-stack
    run incus file push --uid 0 --gid 0 --mode 0644 "$CA/ca.crt" "$name/var/lib/cachy-stack/ca.crt"
    port=$(awk -F'\t' -v s="$service" '$3 == s { print $1 }' "$out/sites.tsv")
    if [ -n "$port" ]; then
        printf '%s\n' "ORIGIN=https://$edge_ip:$port" "BETTER_AUTH_URL=https://$edge_ip:$port" > "$out/$service.env"
        run incus file push --uid 0 --gid 0 --mode 0644 "$out/$service.env" "$name/var/lib/cachy-stack/origin.env"
    fi
    if [ "$service" = edge ]; then
        run gexec "$name" install -d -m 700 /var/lib/cachy-edge/tls
        run incus file push --uid 0 --gid 0 --mode 0600 "$CA/leaf.crt" "$name/var/lib/cachy-edge/tls/leaf.crt"
        run incus file push --uid 0 --gid 0 --mode 0600 "$CA/leaf.key" "$name/var/lib/cachy-edge/tls/leaf.key"
        printf 'EDGE_IP=%s\n' "$edge_ip" > "$out/edge.env"
        run incus file push --uid 0 --gid 0 --mode 0600 "$out/edge.env" "$name/var/lib/cachy-edge/env"
    fi
}

while IFS=$'\t' read -r -u 4 name type profile service; do
    selected "$service" || continue
    if ! incus info "$name" >/dev/null 2>&1; then
        say "Creating $name ($type)"
        vm=(); [ "$type" = virtual-machine ] && vm=(--vm)
        run incus init "$image" "$name" "${vm[@]}" --profile default --profile "$profile"
    fi
    if [ "$(incus list "$name" -c s -f csv 2>/dev/null)" != RUNNING ]; then
        run incus start "$name"
    fi
    [ "$dry" = 1 ] && continue
    wait_agent "$name" || { warn "$name: no agent after 3 minutes"; continue; }
    wait_online "$name" || { warn "$name: cannot resolve cache.nixos.org after 2 minutes"; continue; }
    runtime_files "$name" "$service"
    [ "$rebuild" = 1 ] || continue

    say "$name: nixos-rebuild switch --flake .#$service"
    tar -C "$HERE" -cf - --exclude=./apply.sh . |
        gexec "$name" sh -c 'rm -rf /etc/cachy-stack.new && mkdir -p /etc/cachy-stack.new &&
            tar -xf - -C /etc/cachy-stack.new && rm -rf /etc/cachy-stack && mv /etc/cachy-stack.new /etc/cachy-stack'
    # Whether it switched is checked below, so the build's own status is not needed.
    sandbox=(); [ "$type" = container ] && sandbox=(--option sandbox false)  # see modules/common.nix
    gexec "$name" nixos-rebuild switch "${sandbox[@]}" --flake "path:/etc/cachy-stack#$service" 2>&1 |
        grep -vE '^(copying path|building|these [0-9]+ (paths|derivations)|  /nix/store)' || true
    if ! gexec "$name" readlink /run/current-system | grep -q nixos-system-"$service"; then
        warn "$name: the rebuild did not switch to the $service configuration"
        continue
    fi
    # A switch can stop units it does not start again (restartIfChanged =
    # false, such as a display manager): bring up whatever the guest should run.
    gexec "$name" systemctl start default.target
    # The flake's first evaluation writes flake.lock; keep it with the flake.
    if [ ! -f "$HERE/flake.lock" ]; then
        incus file pull "$name/etc/cachy-stack/flake.lock" "$HERE/flake.lock" && say "flake.lock written"
    fi
    [ "$service" != edge ] || gexec "$name" systemctl restart caddy.service
done 4< "$out/instances.tsv"

# ── Checks ───────────────────────────────────────────────────────────────────
if [ "$dry" = 0 ]; then
    while IFS=$'\t' read -r -u 4 port upstream service; do
        selected "$service" || selected edge || continue
        code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 --cacert "$CA/ca.crt" "https://$edge_ip:$port/") || true
        case $code in
            2??|3??) say "$service: https://$edge_ip:$port answers ($code)" ;;
            *) warn "$service: https://$edge_ip:$port gave ${code:-nothing} (upstream $upstream)" ;;
        esac
    done 4< "$out/sites.tsv"
    say "Clients trust $CA/ca.crt (Node: NODE_EXTRA_CA_CERTS=$CA/ca.crt)"
fi

exit "$FAILED"
