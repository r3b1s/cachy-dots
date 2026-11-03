#!/usr/bin/env bash
# Login shells: bash by default, fish or zsh once opt/fish.sh or opt/zsh.sh chose
# one.
# Sourced by install.sh, install_vm.sh, sync.sh, opt/fish.sh and opt/zsh.sh through
# install/lib.sh; defines functions and package lists only, and runs nothing.

# The shell opt/fish.sh or opt/zsh.sh made the login shell. install.sh keeps it,
# and install.sh and sync.sh link its config; with none recorded it is bash.
# WANT_LOGIN_SHELL overrides the file, so the opt scripts' dry runs show the
# shell they would record.
login_shell_state_file() { echo "${XDG_CONFIG_HOME:-$HOME/.config}/cachy-dots/login-shell"; }

wanted_login_shell() {
    local s=${WANT_LOGIN_SHELL:-}
    [ -n "$s" ] || s=$(cat "$(login_shell_state_file)" 2>/dev/null || true)
    case "$s" in fish|zsh) echo "$s" ;; *) echo bash ;; esac
}

record_login_shell() {
    local f
    f=$(login_shell_state_file)
    if [ "$1" = bash ]; then
        [ -e "$f" ] || return 0
        run rm -f "$f"
        echo "login shell record removed: bash from now on"
    else
        [ "$(cat "$f" 2>/dev/null)" = "$1" ] && return 0
        [ "$dry" = 1 ] && { echo "+ record the login shell ($1)"; return 0; }
        mkdir -p "$(dirname "$f")"
        echo "$1" > "$f"
        echo "login shell recorded: $1 ($f)"
    fi
}

# The path chsh writes must be a line of /etc/shells as written: pam_shells, in
# system-login and so in ly's and the ttys' stacks, compares the strings and
# refuses every login otherwise. Never `command -v`: it finds /usr/sbin/fish, the
# same file (/usr/sbin is a link to bin) under a path that is not listed,
# because PATH names /usr/sbin first.
login_shell_path() {
    case "$1" in
        bash) echo /bin/bash ;;
        fish) echo /usr/bin/fish ;;
        zsh)  echo /usr/bin/zsh ;;
    esac
}

# CachyOS makes fish the login shell; here it is bash unless another was chosen
# (above). A login shell of the right name under a path /etc/shells does not list
# is replaced too. Run as root (sudo), chsh does not ask for the user's password.
setup_login_shell() {
    local want path current
    want=$(wanted_login_shell)
    path=$(login_shell_path "$want")
    current=$(getent passwd "$TARGET_USER" | cut -d: -f7)
    if [ "$(basename "$current")" = "$want" ] && grep -qxF -- "$current" /etc/shells; then
        return 0
    fi
    [ "$TARGET_USER" = root ] && { warn "running as root without sudo; not changing root's shell"; return 0; }
    if [ "$dry" != 1 ] && ! grep -qxF -- "$path" /etc/shells; then
        warn "$path is not in /etc/shells, so pam_shells would refuse every login; not changing the login shell"
        return 0
    fi

    say "Changing the login shell of $TARGET_USER: $current -> $path"
    run $SUDO chsh -s "$path" "$TARGET_USER" \
        || { warn "could not change the login shell to $want"; return 0; }
    echo "login shell: $path (applies at next login)"
}

# The config of the shell opt/fish.sh or opt/zsh.sh chose; bash's (shell/ and the
# ~/.bashrc block) is linked for every install. fish: fish/config.fish. zsh:
# shell/init.zsh and integrations.zsh beside bash's files, with aliases shared,
# loaded from a managed block in ~/.zshrc.
link_shell_config() {
    local cfg="${XDG_CONFIG_HOME:-$HOME/.config}" f
    case "$1" in
        fish)
            link "$REPO/fish/config.fish" "$cfg/fish/config.fish"
            ;;
        zsh)
            for f in aliases init.zsh integrations.zsh; do
                link "$REPO/shell/$f" "$cfg/shell/$f"
            done
            install_rc_block "$HOME/.zshrc" init.zsh
            ;;
    esac
}

# Undoes link_shell_config, leaving what bash needs (aliases).
unlink_shell_config() {
    local cfg="${XDG_CONFIG_HOME:-$HOME/.config}" f
    case "$1" in
        fish) unlink_repo_file "$REPO/fish/config.fish" "$cfg/fish/config.fish" ;;
        zsh)
            for f in init.zsh integrations.zsh; do
                unlink_repo_file "$REPO/shell/$f" "$cfg/shell/$f"
            done
            if grep -qxF "# >>> cachy-dots >>>" "$HOME/.zshrc" 2>/dev/null; then
                run sed -i '/^# >>> cachy-dots >>>$/,/^# <<< cachy-dots <<<$/d' "$HOME/.zshrc"
                echo "zshrc: removed the cachy-dots block"
            fi
            ;;
    esac
}

unlink_repo_file() {
    [ -L "$2" ] && [ "$(readlink "$2")" = "$1" ] || return 0
    run rm "$2"
    echo "removed the $2 link"
}

# opt/fish.sh and opt/zsh.sh: make $1 the login shell with its config, or with
# --remove ($2 = 1) undo that, making bash the login shell again when $1 is the
# recorded one. The package stays installed either way.
opt_login_shell() {
    local shell=$1 remove=$2
    if [ "$remove" = 1 ]; then
        if [ "$(wanted_login_shell)" = "$shell" ]; then
            WANT_LOGIN_SHELL=bash
            record_login_shell bash
            setup_login_shell
        fi
        unlink_shell_config "$shell"
        echo "$shell is no longer configured here; it stays installed."
        return 0
    fi

    WANT_LOGIN_SHELL=$shell
    record_login_shell "$shell"
    if [ "$(pacman -Qq "$shell" 2>/dev/null)" != "$shell" ]; then
        say "Installing $shell"
        # A full upgrade first: -Sy followed by -S would be a partial upgrade.
        run $SUDO pacman -Syu --needed --noconfirm "$shell" \
            || { warn "could not install $shell; the login shell stays as it is"; FAILED=1; return 0; }
    fi
    link_shell_config "$shell"
    setup_login_shell
}
