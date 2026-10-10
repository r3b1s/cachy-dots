#!/usr/bin/env bash
# Shared state and helpers. Sourced first, by install/lib.sh.

# sync.sh and the entry scripts set these before sourcing; these are the defaults.
do_packages=${do_packages:-1}
do_links=${do_links:-1}
dry=${dry:-0}

say()  { printf '\033[1;34m::\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
run()  { if [ "$dry" = 1 ]; then echo "+ $*"; else "$@"; fi; }

SUDO=
[ "$(id -u)" -ne 0 ] && SUDO=sudo

# The user the dots are for: the invoking user even under sudo.
TARGET_USER="${SUDO_USER:-${USER:-$(id -un)}}"

# Set when something required could not be installed; reported at the end.
FAILED=0

# Runs a command as the invoking user: yay and gpg must not run as root.
as_user() {
    if [ "$(id -u)" -eq 0 ]; then
        run sudo -u "$TARGET_USER" "$@"
    else
        run "$@"
    fi
}

# Command-line arguments of the entry scripts (install.sh, install_vm.sh).
# $1 is the script, whose leading comment block is its --help.
parse_args() {
    local script=$1 arg; shift
    for arg in "$@"; do
        case "$arg" in
            --packages-only) do_links=0 ;;
            --links-only)    do_packages=0 ;;
            -n|--dry-run)    dry=1 ;;
            -h|--help)       awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$script"; exit 0 ;;
            *) echo "unknown option: $arg" >&2; exit 2 ;;
        esac
    done
}

# ── profiles ──────────────────────────────────────────────────────────────
# An entry script names its profile (PROFILE=workstation|vm), and install/profile-
# <name>.sh says what that profile leaves out. The package lists in packages.sh
# stay complete; apply_profile() takes the skipped ones out of them.

in_list() {
    local needle=$1 x; shift
    for x in "$@"; do [ "$x" = "$needle" ] && return 0; done
    return 1
}

# want <feature>: false when the profile skips that feature (PROFILE_SKIP_FEATURES).
want() { ! in_list "$1" ${PROFILE_SKIP_FEATURES[@]+"${PROFILE_SKIP_FEATURES[@]}"}; }

apply_profile() {
    local p entry c names keep skip

    keep=()
    for p in "${PKGS[@]}"; do
        in_list "$p" ${PROFILE_SKIP_PKGS[@]+"${PROFILE_SKIP_PKGS[@]}"} || keep+=("$p")
    done
    PKGS=("${keep[@]}")

    # A pinned entry is "repo/name repo/name ...": skipped when any name is listed.
    keep=()
    for entry in "${PINNED[@]}"; do
        names=()
        for c in $entry; do names+=("${c#*/}"); done
        skip=0
        for c in "${names[@]}"; do
            in_list "$c" ${PROFILE_SKIP_PINNED[@]+"${PROFILE_SKIP_PINNED[@]}"} && skip=1
        done
        [ "$skip" = 1 ] || keep+=("$entry")
    done
    PINNED=("${keep[@]}")

    keep=()
    for p in "${AUR_PKGS[@]}"; do
        in_list "$p" ${PROFILE_SKIP_AUR[@]+"${PROFILE_SKIP_AUR[@]}"} || keep+=("$p")
    done
    AUR_PKGS=(${keep[@]+"${keep[@]}"})
}
