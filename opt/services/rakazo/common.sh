# Sourced by host-setup.sh and install.sh; not run on its own. What both sides
# of the Rakazo VM must agree on, and the message helpers.
#
# The VM has a bridge of its own, rakazo0, on a /30: the host is .1 and the
# VM .2, and DHCP hands out that one address to that one MAC, so the network
# has no room for anything else.
# shellcheck disable=SC2034 # read by the scripts that source this

VM_NAME=rakazo
NET_NAME=rakazo
BRIDGE=rakazo0
SUBNET=10.41.41.0/30
NETMASK=255.255.255.252
HOST_IP=10.41.41.1
GUEST_IP=10.41.41.2
GUEST_MAC=52:54:00:72:6b:7a
GUEST_PORT=5173      # the web app inside the VM; the API (3100) stays on its loopback
PORT=15173           # the host side, on 127.0.0.1 and the NetBird address (5173 is Vite's)
NETBIRD_IF=wt0

say()  { printf '\033[1;34m::\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
# A dry run prints on the original stdout (fd 3), so `run cmd >/dev/null` still shows it.
exec 3>&1
run()  { if [ "${dry:-0}" = 1 ]; then echo "+ $*" >&3; else "$@"; fi; }
usage() { awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$1"; exit 0; }
