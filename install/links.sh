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

# ~/.ssh for the user: the directory, an empty authorized_keys (sshd reads it, and
# the opt-in hardened drop-in in ssh/ needs a key there before it turns passwords
# off), and ~/.ssh/config with github.com and gitlab.com identities. The block is
# appended only when neither host already has a Host entry in ~/.ssh/config; if
# either does, nothing is appended, so the user's own entries are never duplicated
# or overridden. Existing content is never rewritten. Remove the block to have it
# added again.
setup_ssh() {
    local dir="$HOME/.ssh" cfg="$HOME/.ssh/config" keys="$HOME/.ssh/authorized_keys"
    local open="# >>> cachy-dots >>>" close="# <<< cachy-dots <<<"

    if [ ! -d "$dir" ]; then
        run mkdir -m 700 "$dir"
        echo "created $dir"
    fi
    if [ ! -e "$keys" ]; then
        run install -m 600 /dev/null "$keys"
        echo "created $keys (empty)"
    fi

    # A Host line (keywords are case-insensitive, and may list several patterns)
    # that names either host.
    if [ -f "$cfg" ] && grep -qiE '^[[:space:]]*host[[:space:]=]+(.*[[:space:]=])?(github\.com|gitlab\.com)([[:space:]]|$)' "$cfg"; then
        echo "ssh config: github.com or gitlab.com already configured, nothing appended"
    elif [ "$dry" = 1 ]; then
        echo "+ append the cachy-dots block to $cfg"
    else
        # A new file is private like the directory; an existing one keeps its mode.
        [ -e "$cfg" ] || install -m 600 /dev/null "$cfg"
        {
            if [ -s "$cfg" ]; then echo; fi
            echo "$open"
            cat <<'EOF'
host github.com
  hostname github.com
  user git
  port 22
  identitiesonly yes

host gitlab.com
  hostname gitlab.com
  user git
  port 22
  identitiesonly yes
EOF
            echo "$close"
        } >> "$cfg"
        echo "ssh config: appended cachy-dots block to $cfg"
    fi
}

# The monitor layout is per host, so it is copied from i3/templates/ once and then
# left alone: neither install.sh nor sync.sh overwrites it, and a symlink or a real
# file already there is kept as it is.
import_monitors_conf() {
    local dst="${XDG_CONFIG_HOME:-$HOME/.config}/i3/conf.d/04-monitors.conf"
    local src="$REPO/i3/templates/04-monitors.conf"
    if [ -e "$dst" ] || [ -L "$dst" ]; then
        return 0
    fi
    run install -m 644 "$src" "$dst"
    echo "copied $src -> $dst (this host's monitor layout; edit it there)"
}

# Git's global config is the host's: git/config is copied to ~/.config/git/config
# once, on a host with no global config yet (neither that file nor ~/.gitconfig),
# and then left alone. A link would put what `git config --global` writes (the
# identity, credentials) into the repo. A link left by an earlier layout becomes a
# copy of what it points at, so settings made through it stay on the host.
import_git_config() {
    local dst="${XDG_CONFIG_HOME:-$HOME/.config}/git/config"
    local src="$REPO/git/config"
    if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
        run cp --remove-destination "$src" "$dst"
        echo "replaced the link $dst with a copy (this host's git config; edit it there)"
        return 0
    fi
    if [ -e "$dst" ] || [ -L "$dst" ] || [ -e "$HOME/.gitconfig" ] || [ -L "$HOME/.gitconfig" ]; then
        return 0
    fi
    run mkdir -p "$(dirname "$dst")"
    run install -m 644 "$src" "$dst"
    echo "copied $src -> $dst (this host's git config; edit it there)"
}

# A whole-directory link into the repo, left by an earlier layout. It is removed so
# the files can be linked into a real directory: a file link made through a
# directory link would land in the repo. Removing a symlink leaves its target alone.
retire_dir_link() {
    local dir="$1" target="$2"
    if [ -L "$dir" ] && [ "$(readlink "$dir")" = "$target" ]; then
        run rm "$dir"
        echo "removed the old $dir directory link"
    fi
}

# Every config is linked file by file, never as a directory, so a host can leave
# any file out (or keep a local one beside it) without touching the repo. Apps
# that write next to their config (qutebrowser, btop, nvim, starship's shared
# ~/.config) need this too, so runtime state stays out of the repo. link() makes
# the directories it needs.
#
# These are the links both sessions share. The i3 config, ~/.xprofile, dunst's
# config, the i3-only scripts, the Hyprland files and the colour slots (terminal,
# GTK and satty colours) belong to a session: apply_session (install/session.sh)
# makes them, right after this.
install_links() {
    say "Linking dots"
    local cfg="${XDG_CONFIG_HOME:-$HOME/.config}"

    local d
    # The four directories that were linked whole, and dunst and i3status-rust,
    # which were too: dunst now needs a real directory (its theme is a drop-in
    # beside dunstrc), and i3status-rust's config is rendered into the state
    # directory instead.
    for d in kitty alacritty rofi shell dunst i3status-rust; do
        retire_dir_link "$cfg/$d" "$REPO/$d"
    done

    # Files the rendered theme provides: ~/.local/state/omarchy/current/theme/
    # is replaced on every switch, so these links stay valid.
    local th="$HOME/.local/state/omarchy/current/theme"
    link "$th/btop.theme" "$cfg/btop/themes/current.theme"
    link "$th/yazi.toml" "$cfg/yazi/flavors/omarchy.yazi/flavor.toml"
    link "$REPO/yazi/theme.toml" "$cfg/yazi/theme.toml"
    link "$th/zathurarc" "$cfg/zathura/zathurarc"
    link "$th/imv.config" "$cfg/imv/config"
    link "$REPO/mpv/mpv.conf" "$cfg/mpv/mpv.conf"

    # omarchy-style theme-set hooks, run by x11-theme after every switch as
    # `bash <hook> <theme>`. vesktop composes the rendered
    # cachy-dots-vesktop.palette.css with vesktop/discord.css into Vesktop's themes
    # folder; it reads discord.css from the repo, which is why only the hook is
    # linked.
    local hook
    for hook in "$REPO"/hooks/theme-set.d/*; do
        link "$hook" "$cfg/omarchy/hooks/theme-set.d/$(basename "$hook")"
    done

    for pair in \
        "qutebrowser/config.py:qutebrowser/config.py" \
        "qutebrowser/omarchy_theme.py:qutebrowser/omarchy_theme.py" \
        "alacritty/alacritty.toml:alacritty/alacritty.toml" \
        "kitty/kitty.conf:kitty/kitty.conf" \
        "rofi/config.rasi:rofi/config.rasi" \
        "shell/init.sh:shell/init.sh" \
        "shell/aliases:shell/aliases" \
        "shell/integrations:shell/integrations" \
        "qutebrowser/vimium.py:qutebrowser/vimium.py" \
        "qutebrowser/startpage.html:qutebrowser/startpage.html" \
        "btop/btop.conf:btop/btop.conf" \
        "tmux/tmux.conf:tmux/tmux.conf" \
        "env/telemetry.conf:environment.d/telemetry.conf" \
        "starship/starship.toml:starship.toml"
    do
        link "$REPO/${pair%%:*}" "$cfg/${pair#*:}"
    done

    # Neovim is a LazyVim tree (init.lua + lua/config + colors). Individual
    # files are linked so runtime state (lazyvim.json, lazy-lock.json, :Mason,
    # spell, shada) stays out of the repo. lua/plugins/theme.lua is a slot the
    # session points (install/session.sh): under i3 the rendered theme
    # (aether.nvim with its palette), as on omarchy; replacing it is what
    # lazy.nvim's change detection sees, and omarchy-theme-hotreload.lua applies.
    link_nvim_tree
    # Links into the repo whose file has since been removed (pinkrot-theme.lua).
    [ "$dry" = 1 ] || find "$cfg/nvim" -xtype l -lname "$REPO/*" -print -delete 2>/dev/null | sed 's/^/removed dangling link /' || true

    import_git_config
    install_bashrc_block
    setup_ssh

    # ble.sh is opt-in here (opt/blesh.sh links ~/.blerc), so nothing for it.

    # Launcher entries for repo scripts: rofi's drun lists them on i3, dux's
    # launcher under Hyprland, where they are the way into these menus.
    local entry
    for entry in "$REPO"/applications/*.desktop; do
        link "$entry" "$HOME/.local/share/applications/$(basename "$entry")"
    done

    local script
    for script in "$REPO"/bin/*; do
        in_list "$(basename "$script")" "${I3_ONLY_BIN[@]}" && continue
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
