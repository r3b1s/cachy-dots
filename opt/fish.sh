#!/usr/bin/env bash
# Opt in to fish as the login shell. Not part of the default install: install.sh
# makes bash the login shell unless this script, or opt/zsh.sh, chose another.
#
#   1. installs fish
#   2. links fish/config.fish -> ~/.config/fish/config.fish: bash's aliases and
#      functions (shell/aliases) ported to fish, and the same tools (starship,
#      mise, zoxide, fzf).
#   3. records fish in ~/.config/cachy-dots/login-shell, which install.sh and
#      sync.sh follow, and makes /usr/bin/fish the login shell (the path
#      /etc/shells lists; pam_shells refuses any other)
#
# The login shell applies at the next login. Run it as your own user: sudo is
# used for pacman and chsh.
#
#   --remove  makes bash the login shell again, when fish is the recorded one,
#             and removes the config link. fish stays installed.
#
# Usage: opt/fish.sh [--remove] [-n|--dry-run] [-h|--help]
set -euo pipefail

remove=0
dry=0
for arg in "$@"; do
    case "$arg" in
        --remove)     remove=1 ;;
        -n|--dry-run) dry=1 ;;
        -h|--help)    awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; exit 0 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

PROFILE=${PROFILE:-$(cat "${XDG_CONFIG_HOME:-$HOME/.config}/cachy-dots/profile" 2>/dev/null || echo workstation)}
# shellcheck source=install/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)/install/lib.sh"
apply_profile

[ -n "$SUDO" ] || { warn "run opt/fish.sh as your own user (it uses sudo), not root"; exit 1; }
opt_login_shell fish "$remove"
[ "$FAILED" = 0 ] || exit 1
