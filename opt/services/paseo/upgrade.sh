#!/usr/bin/env bash
# Upgrades Paseo: its CLI and daemon (npm:@getpaseo/cli, through mise) and, where
# appimage.sh installed it, its desktop app.
#
# What it does:
#   1. asks mise whether a newer @getpaseo/cli is out (mise outdated --global), and
#      appimage.sh --check whether a newer AppImage is (only once one is installed);
#   2. with nothing to upgrade, stops there and leaves paseo.service alone;
#   3. otherwise stops paseo.service if it is running, runs mise upgrade --global
#      npm:@getpaseo/cli and appimage.sh for whichever is out of date, and starts the
#      service again. It starts it again after a failed upgrade too, on the version
#      still installed, and then exits non-zero.
#
# Stopping the service ends the agents it runs. Started from a terminal inside Paseo
# (in paseo.service's cgroup), it would also kill this script, so the script re-runs
# itself as the transient unit paseo-upgrade before it stops anything; follow it
# with journalctl --user -u paseo-upgrade -f.
#
# Nothing is pinned: the CLI follows its "latest" request in the global mise config
# (no --bump or --pin, so mise leaves the request as it is), and the desktop app the
# latest GitHub release. A request other than "latest" gets a warning, since mise
# then upgrades only within it.
#
# A desktop app that is running keeps the old version until it is restarted.
#
# Usage: opt/services/paseo/upgrade.sh [-n|--dry-run] [-h|--help]
set -euo pipefail

HERE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)

dry=0
for arg in "$@"; do
    case "$arg" in
        -n|--dry-run) dry=1 ;;
        -h|--help)
            awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
            exit 0
            ;;
        *)
            echo "unknown option: $arg" >&2
            exit 2
            ;;
    esac
done

say()  { printf '\033[1;34m::\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
run()  { if [ "$dry" = 1 ]; then echo "+ $*"; else "$@"; fi; }

CLI=npm:@getpaseo/cli
UNIT=paseo.service
FAILED=0

command -v mise >/dev/null 2>&1 || die "mise is required"
command -v jq >/dev/null 2>&1 || die "jq is required"

# ── 1. What is out of date ────────────────────────────────────────────────────

cli=0
if ! mise ls --global --json "$CLI" 2>/dev/null | jq -e 'length > 0' >/dev/null; then
    warn "$CLI is not in the global mise config (setup.sh adds it); skipping the CLI"
else
    request=$(mise ls --global --json "$CLI" | jq -r '[.[] | .requested_version // empty][0] // empty')
    if [ "$request" != latest ]; then
        warn "$CLI is requested as \"${request:-?}\", not \"latest\"; mise upgrades it only within that"
    fi
    say "Asking mise about $CLI"
    outdated=$(mise outdated --global --json "$CLI") || die "mise outdated failed"
    if jq -e 'length > 0' >/dev/null <<<"$outdated"; then
        cli=1
        say "$(jq -r 'to_entries[] | "\(.key): \(.value.current // "?") -> \(.value.latest // "?")"' <<<"$outdated")"
    else
        say "$CLI is current"
    fi
fi

app=0
rc=0
"$HERE/appimage.sh" --check || rc=$?
case $rc in
    0)  ;;
    10) app=1 ;;
    11) say "The desktop app is not installed (appimage.sh installs it); skipping it" ;;
    *)  warn "could not check the desktop app (appimage.sh --check exited $rc)"; FAILED=1 ;;
esac

if [ "$cli" = 0 ] && [ "$app" = 0 ]; then
    say "Nothing to upgrade; $UNIT left alone"
    exit "$FAILED"
fi

# ── 2. Out of the service's way ───────────────────────────────────────────────

# KillMode=control-group: stopping the unit kills everything in its cgroup,
# a shell Paseo spawned and this script included.
if [ "$dry" = 0 ] && grep -q "/$UNIT\$" /proc/self/cgroup 2>/dev/null; then
    command -v systemd-run >/dev/null 2>&1 || die "running inside $UNIT, and systemd-run is missing"
    say "Running inside $UNIT; re-running as the transient unit paseo-upgrade"
    systemd-run --user --unit=paseo-upgrade --collect --quiet \
        --setenv=PATH="$PATH" --working-directory="$HOME" -- "$HERE/upgrade.sh"
    say "Follow it with: journalctl --user -u paseo-upgrade -f"
    exit 0
fi

was_active=0
if systemctl --user is-active --quiet "$UNIT" 2>/dev/null; then
    was_active=1
fi

restart() {
    [ "$was_active" = 1 ] || return 0
    say "Starting $UNIT"
    if ! run systemctl --user start "$UNIT"; then
        warn "$UNIT did not start: journalctl --user -u $UNIT"
        FAILED=1
    fi
}
trap 'restart' EXIT

if [ "$was_active" = 1 ]; then
    say "Stopping $UNIT"
    run systemctl --user stop "$UNIT"
else
    say "$UNIT is not running; it stays stopped"
fi

# ── 3. Upgrade ────────────────────────────────────────────────────────────────

if [ "$cli" = 1 ]; then
    say "Upgrading $CLI"
    if run mise upgrade --global "$CLI"; then
        if [ "$dry" = 0 ]; then
            say "paseo $(mise exec -- paseo --version 2>/dev/null || echo '?')"
        fi
    else
        warn "mise upgrade failed; the previous version stays"
        FAILED=1
    fi
fi

if [ "$app" = 1 ]; then
    say "Upgrading the desktop app"
    args=()
    [ "$dry" = 0 ] || args+=(--dry-run)
    if ! "$HERE/appimage.sh" "${args[@]}"; then
        warn "appimage.sh failed; the previous version stays"
        FAILED=1
    elif pgrep -f -- "$HOME/Applications/Paseo-" >/dev/null 2>&1; then
        warn "the desktop app is running: restart it for the new version"
    fi
fi

trap - EXIT
restart
exit "$FAILED"
