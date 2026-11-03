#!/usr/bin/env bash
# Opt in to zsh as the login shell. Not part of the default install: install.sh
# makes bash the login shell unless this script, or opt/fish.sh, chose another.
#
#   1. installs zsh
#   2. links shell/init.zsh and shell/integrations.zsh into ~/.config/shell/,
#      beside bash's files, and adds a managed block to ~/.zshrc that loads
#      init.zsh: bash's aliases and functions (shell/aliases, shared with bash),
#      the same tools (starship, mise, zoxide, fzf), zsh's completion and a
#      history file.
#   3. records zsh in ~/.config/cachy-dots/login-shell, which install.sh and
#      sync.sh follow, and makes /usr/bin/zsh the login shell
#
# The login shell applies at the next login. Run it as your own user: sudo is
# used for pacman and chsh.
#
#   --remove  makes bash the login shell again, when zsh is the recorded one,
#             and removes the links and the ~/.zshrc block. zsh stays installed.
#
# Usage: opt/zsh.sh [--remove] [-n|--dry-run] [-h|--help]
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

[ -n "$SUDO" ] || { warn "run opt/zsh.sh as your own user (it uses sudo), not root"; exit 1; }
opt_login_shell zsh "$remove"
[ "$FAILED" = 0 ] || exit 1
