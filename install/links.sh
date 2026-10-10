#!/usr/bin/env bash
# Linking the dots into ~/.config and ~/.local/bin.
# Sourced by install.sh, install_vm.sh and sync.sh through install/lib.sh; defines
# functions and package lists only, and runs nothing.

# Neovim is a LazyVim tree in this repo (init.lua, lua/config, lua/plugins,
# colors). install_links() calls link_nvim_tree() to link each file
# individually, so runtime state (lazyvim.json, lazy-lock.json, :Mason, spell,
# shada) stays out of the repo.
link_nvim_tree() {
    local cfg="${XDG_CONFIG_HOME:-$HOME/.config}"
    local rel
    ( cd "$REPO/nvim" && find . -type f | sed 's|^\./||' ) | while IFS= read -r rel; do
        link "$REPO/nvim/$rel" "$cfg/nvim/$rel"
    done
}

link() {
    local src="$1" dst="$2"
    # Already right: say nothing, so a re-run (sync.sh) shows only what changed.
    [ "$(readlink "$dst" 2>/dev/null)" = "$src" ] && return 0
    run mkdir -p "$(dirname "$dst")"
    if [ -e "$dst" ] && [ ! -L "$dst" ]; then
        local backup
        backup="$dst.bak.$(date +%s)"
        run mv "$dst" "$backup"
        echo "backed up $dst -> $backup"
    fi
    run ln -sfn "$src" "$dst"
    echo "linked $dst -> $src"
}

# Idempotent managed block in ~/.bashrc that loads shell/ (~/.config/shell).
# Everything else in .bashrc is left alone. Remove the block to undo.
install_bashrc_block() {
    local bashrc="$HOME/.bashrc"
    local open="# >>> cachy-dots >>>"
    if [ -f "$bashrc" ] && grep -qF "$open" "$bashrc"; then
        echo "bashrc: cachy-dots block already present"
    elif [ "$dry" = 1 ]; then
        echo "+ append cachy-dots block to $bashrc"
    else
        touch "$bashrc"
        {
            echo
            echo "$open"
            # shellcheck disable=SC2016  # written literally: expands in .bashrc, not here
            echo '[[ -r "${XDG_CONFIG_HOME:-$HOME/.config}/shell/init.sh" ]] && source "${XDG_CONFIG_HOME:-$HOME/.config}/shell/init.sh"'
            echo "# <<< cachy-dots <<<"
        } >> "$bashrc"
        echo "bashrc: appended cachy-dots block"
    fi
    # The passwd entry, not $SHELL: setup_login_shell may have just changed it.
    local login
    login=$(getent passwd "$TARGET_USER" | cut -d: -f7)
    case "$(basename "${login:-unknown}")" in
        bash) ;;
        *) [ "$dry" = 1 ] || warn "login shell is ${login:-unknown}, not bash; shell/ is only loaded by bash" ;;
    esac
}

# Whole directories are linked where the app never writes into its config dir.
# Where it does (qutebrowser, btop, nvim, starship's shared ~/.config) individual
# files are linked, so runtime state stays out of the repo.
install_links() {
    say "Linking dots"
    local cfg="${XDG_CONFIG_HOME:-$HOME/.config}"

    local d
    for d in i3 kitty alacritty rofi shell; do
        link "$REPO/$d" "$cfg/$d"
    done

    # Earlier layouts linked these whole directories. dunst now needs a real
    # directory (its theme is a drop-in beside dunstrc), and i3status-rust's
    # config is rendered into the state directory instead.
    for d in dunst i3status-rust; do
        if [ -L "$cfg/$d" ] && [ "$(readlink -f "$cfg/$d")" = "$REPO/$d" ]; then
            run rm "$cfg/$d"
            echo "removed the old $cfg/$d directory link"
        fi
    done

    # Files the rendered theme provides: ~/.local/state/omarchy/current/theme/
    # is replaced on every switch, so these links stay valid.
    local th="$HOME/.local/state/omarchy/current/theme"
    link "$th/dunst.conf" "$cfg/dunst/dunstrc.d/90-theme.conf"
    link "$th/btop.theme" "$cfg/btop/themes/current.theme"
    link "$th/gtk.css" "$cfg/gtk-3.0/gtk.css"
    link "$th/gtk.css" "$cfg/gtk-4.0/gtk.css"
    link "$th/satty.config.toml" "$cfg/satty/config.toml"
    link "$th/yazi.toml" "$cfg/yazi/flavors/omarchy.yazi/flavor.toml"
    link "$REPO/yazi/theme.toml" "$cfg/yazi/theme.toml"
    link "$th/zathurarc" "$cfg/zathura/zathurarc"
    link "$th/imv.config" "$cfg/imv/config"
    link "$REPO/mpv/mpv.conf" "$cfg/mpv/mpv.conf"

    # omarchy-style theme-set hooks, run by x11-theme after every switch as
    # `bash <hook> <theme>`. vesktop (from quattro-dots) composes the rendered
    # quattro-vesktop.palette.css with vesktop/discord.css into Vesktop's themes
    # folder; it reads discord.css from the repo, which is why only the hook is
    # linked.
    local hook
    for hook in "$REPO"/hooks/theme-set.d/*; do
        link "$hook" "$cfg/omarchy/hooks/theme-set.d/$(basename "$hook")"
    done

    for pair in \
        "qutebrowser/config.py:qutebrowser/config.py" \
        "qutebrowser/omarchy_theme.py:qutebrowser/omarchy_theme.py" \
        "dunst/dunstrc:dunst/dunstrc" \
        "qutebrowser/vimium.py:qutebrowser/vimium.py" \
        "qutebrowser/startpage.html:qutebrowser/startpage.html" \
        "btop/btop.conf:btop/btop.conf" \
        "tmux/tmux.conf:tmux/tmux.conf" \
        "env/telemetry.conf:environment.d/telemetry.conf" \
        "starship/starship.toml:starship.toml" \
        "voxtype/config.toml:voxtype/config.toml"
    do
        link "$REPO/${pair%%:*}" "$cfg/${pair#*:}"
    done

    # Neovim is a LazyVim tree (init.lua + lua/config + colors). Individual
    # files are linked so runtime state (lazyvim.json, lazy-lock.json, :Mason,
    # spell, shada) stays out of the repo. lua/plugins/theme.lua is the rendered
    # theme (aether.nvim with its palette), as on omarchy; replacing it is what
    # lazy.nvim's change detection sees, and omarchy-theme-hotreload.lua applies.
    link_nvim_tree
    link "$th/neovim.lua" "$cfg/nvim/lua/plugins/theme.lua"
    # Links into the repo whose file has since been removed (pinkrot-theme.lua).
    [ "$dry" = 1 ] || find "$cfg/nvim" -xtype l -lname "$REPO/*" -print -delete 2>/dev/null | sed 's/^/removed dangling link /' || true

    install_bashrc_block

    # ~/.xprofile is sourced by the session start-up (ly runs /etc/ly/setup.sh,
    # which reads it before exec'ing the session), so this is how XDG_CURRENT_DESKTOP
    # reaches everything i3 spawns. It lives in $HOME, not in ~/.config, hence the
    # separate link rather than one of the pair mappings above.
    link "$REPO/shell/xprofile" "$HOME/.xprofile"

    # ble.sh is opt-in here (opt/blesh.sh links ~/.blerc), so nothing for it.

    local script
    for script in "$REPO"/bin/*; do
        link "$script" "$HOME/.local/bin/$(basename "$script")"
    done
    # Scripts that only make sense in a guest (vm/): the vm profile only.
    if want vm-scripts; then
        for script in "$REPO"/vm/*; do
            link "$script" "$HOME/.local/bin/$(basename "$script")"
        done
    fi

    case ":$PATH:" in
        *":$HOME/.local/bin:"*) ;;
        *) echo "note: $HOME/.local/bin is added to PATH by shell/init.sh and ~/.xprofile from the next login" ;;
    esac

}
