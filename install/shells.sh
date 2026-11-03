#!/usr/bin/env bash
# Login shells: bash by default, fish or zsh once opt/fish.sh or opt/zsh.sh chose
# one, and what CachyOS's own shell setups leave behind.
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

# CachyOS's own shell setups: cachyos-fish-config (pure prompt, done, autopair, a
# fastfetch greeting) and cachyos-zsh-config (oh-my-zsh, powerlevel10k, zsh's
# plugins). shell/ and fish/ replace them, so they go: -s also removes what was
# installed only for them, and -n leaves no .pacsave. Where an earlier run removed
# one without -s, the targets are those of its dependencies that are orphans now,
# as the sync database lists them (-tt: also when only an optdepends names one,
# as -s would have removed it with the package).
# Some of those dependencies are wanted: in PKGS (bat, eza, fzf), or the shell an
# account logs in with, or the recorded one. Installed as dependencies, -s would
# remove them, or a later `pacman -Rns $(pacman -Qdtq)` would, so they are marked
# explicitly installed first. Packages installed explicitly (pkgfile, fastfetch
# and vim on a stock install) are never removed by -s.
CACHYOS_SHELL_CONFIGS=(cachyos-fish-config cachyos-zsh-config)

remove_cachyos_shell_configs() {
    command -v pacman >/dev/null || return 0
    local pkg p n info sh_path orphans deps=() all=() targets=() keep=() wanted=("${PKGS[@]}")

    # pacman -Qo names the package even for a path through the merged-sbin link.
    for sh_path in $(getent passwd | cut -d: -f7 | sort -u) "$(login_shell_path "$(wanted_login_shell)")"; do
        n=$(pacman -Qoq "$sh_path" 2>/dev/null) && wanted+=("$n")
    done

    for pkg in "${CACHYOS_SHELL_CONFIGS[@]}"; do
        if [ "$(pacman -Qq "$pkg" 2>/dev/null)" = "$pkg" ]; then
            info=$(pacman -Qi "$pkg")
            targets+=("$pkg")
            orphans=0
        elif info=$(pacman -Si "$pkg" 2>/dev/null); then
            orphans=1
        else
            continue
        fi
        read -ra deps <<<"$(sed -n '/^Depends On/{s/^Depends On *: //p;q}' <<<"$info")"
        for p in "${deps[@]}"; do
            [ "$p" = None ] && continue
            # By the installed package's own name, which may be a provider's.
            n=$(pacman -Qq "${p%%[<>=]*}" 2>/dev/null) || continue
            all+=("$n")
            if [ "$orphans" = 1 ] && pacman -Qdttq "$n" >/dev/null 2>&1 \
                && ! in_list "$n" "${wanted[@]}" && ! in_list "$n" ${targets[@]+"${targets[@]}"}; then
                targets+=("$n")
            fi
        done
    done

    # The dependencies, and what -Rs would remove (-p only prints, and needs no root).
    for p in ${all[@]+"${all[@]}"} $([ "${#targets[@]}" -gt 0 ] && pacman -Rsp --print-format '%n' "${targets[@]}" 2>/dev/null); do
        in_list "$p" "${wanted[@]}" && pacman -Qdq "$p" >/dev/null 2>&1 \
            && ! in_list "$p" ${keep[@]+"${keep[@]}"} && keep+=("$p")
    done
    if [ "${#keep[@]}" -gt 0 ]; then
        say "Marking ${keep[*]} explicitly installed (CachyOS's shell setups pulled them in)"
        run $SUDO pacman -D --asexplicit "${keep[@]}" \
            || { warn "could not mark ${keep[*]} explicitly installed; removing nothing"; return 0; }
    fi
    [ "${#targets[@]}" -gt 0 ] || return 0
    say "Removing ${targets[*]} and the packages only they needed"
    run $SUDO pacman -Rns --noconfirm "${targets[@]}" || warn "could not remove ${targets[*]}"
}

# What CachyOS's shell setups leave in ~ once their package is gone. /etc/skel
# gives each user a config.fish and a .zshrc that only source the package's file:
# such a stub holds nothing of the user's, so it is deleted, and so are the
# backups link() made of config.fish. A file with anything more stays. The
# universal variables done.fish and fish-pure-prompt saved (__done_*, pure_*) are
# erased once neither the package nor a conf.d file of the user's loads them.
retire_cachyos_shell_leftovers() {
    local cfg="${XDG_CONFIG_HOME:-$HOME/.config}" vars pattern=
    if [ "$(pacman -Qq cachyos-fish-config 2>/dev/null)" != cachyos-fish-config ]; then
        retire_shell_stub /usr/share/cachyos-fish-config/cachyos-config.fish "$cfg/fish/config.fish" "$cfg"/fish/config.fish.bak.*
        [ -e "$cfg/fish/conf.d/done.fish" ] || pattern=__done_
    fi
    if [ "$(pacman -Qq cachyos-zsh-config 2>/dev/null)" != cachyos-zsh-config ]; then
        retire_shell_stub /usr/share/cachyos-zsh-config/cachyos-config.zsh "$HOME/.zshrc"
    fi
    if [ "$(pacman -Qq fish-pure-prompt 2>/dev/null)" != fish-pure-prompt ] && [ ! -e "$cfg/fish/conf.d/pure.fish" ]; then
        pattern="${pattern:+$pattern|}pure_"
    fi

    # fish's own format, one "SETUVAR [--export ]<name>:<value>" line each; edited
    # with sed, since fish itself may be gone.
    vars="$cfg/fish/fish_variables"
    [ -n "$pattern" ] && [ -f "$vars" ] || return 0
    grep -qE "^SETUVAR (--export )?($pattern)" "$vars" || return 0
    run sed -i -E "/^SETUVAR (--export )?($pattern)/d" "$vars"
    echo "removed the ${pattern//|/* and }* universal variables from $vars"
}

retire_shell_stub() {
    local src=$1 f
    shift
    for f in "$@"; do
        [ -f "$f" ] && [ ! -L "$f" ] || continue
        [ "$(grep -vE '^[[:space:]]*(#|$)' "$f")" = "source $src" ] || continue
        run rm -f "$f"
        echo "removed $f (it only sourced $src, which is gone)"
    done
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
    remove_cachyos_shell_configs
    if [ "$(pacman -Qq "$shell" 2>/dev/null)" != "$shell" ]; then
        say "Installing $shell"
        # A full upgrade first: -Sy followed by -S would be a partial upgrade.
        run $SUDO pacman -Syu --needed --noconfirm "$shell" \
            || { warn "could not install $shell; the login shell stays as it is"; FAILED=1; return 0; }
    fi
    retire_cachyos_shell_leftovers
    link_shell_config "$shell"
    setup_login_shell
}
