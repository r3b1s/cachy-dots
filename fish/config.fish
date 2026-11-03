# fish configuration for cachy-dots: shell/ (bash and zsh) ported to fish, with
# the same aliases, functions and tools. Linked into ~/.config/fish/config.fish by
# opt/fish.sh, which makes fish the login shell.
#
# Prompt: starship (starship/starship.toml)
# Line editing: vi key bindings (fish_vi_key_bindings)
# Greeting: disabled (no fastfetch)
#
# Not ported, since fish does it itself: completion (bash-completion), ble.sh's
# autosuggestions and highlighting, `..` (fish's implicit cd), and the colour
# flags CachyOS's ~/.bashrc gives ls and grep.

# Disable greeting and fastfetch
set -g fish_greeting ""

# Ensure ~/.local/bin is on PATH
if not contains "$HOME/.local/bin" $PATH
    set -gx PATH "$HOME/.local/bin" $PATH
end

# Telemetry opt-outs (env/telemetry.conf, linked into environment.d)
set -l config_dir "$HOME/.config"
if set -q XDG_CONFIG_HOME
    set config_dir "$XDG_CONFIG_HOME"
end
set -l telem_conf "$config_dir/environment.d/telemetry.conf"
if test -r "$telem_conf"
    while read -l line
        string match -qr '^[A-Za-z_][A-Za-z0-9_]*=' -- "$line" || continue
        set -l kv (string split -m 1 = -- "$line")
        set -gx $kv[1] $kv[2]
    end < "$telem_conf"
end

if status is-interactive
    # ── aliases and functions (shell/aliases) ─────────────────────────────────

    # eza
    if type -q eza
        alias ls='eza -lh --group-directories-first --icons=auto'
        alias lsa='ls -a'
        alias lt='eza --tree --level=2 --long --icons --git'
        alias lta='lt -a'
    end

    # fzf: ff is a fuzzy file finder with a preview (bat for text, kitty icat for
    # images). eff opens the picked file in $EDITOR, sff scps it somewhere. fzf
    # runs a preview with $SHELL, fish here, so the kitty one, which is sh, says
    # to run it with sh.
    function ff --description "Fuzzy find files with preview" --wraps fzf
        if test "$TERM" = xterm-kitty
            fzf --with-shell 'sh -c' --preview 'case $(file --mime-type -b {}) in image/*) kitty icat --clear --transfer-mode=memory --stdin=no --place=${FZF_PREVIEW_COLUMNS}x${FZF_PREVIEW_LINES}@0x0 {} ;; *) bat --style=numbers --color=always {} ;; esac' $argv
        else
            fzf --preview 'bat --style=numbers --color=always {}' $argv
        end
    end

    function eff --description "Edit fuzzy-found file"
        set -l editor (test -n "$EDITOR"; and echo "$EDITOR"; or echo "nvim")
        set -l file (ff)
        test -n "$file"; and $editor "$file"
    end

    function sff --description "scp a fuzzy-found file somewhere"
        if test (count $argv) -eq 0
            echo "Usage: sff <destination> (e.g. sff host:/tmp/)"
            return 1
        end
        set -l file (find . -type f -printf '%T@\t%p\n' | sort -rn | cut -f2- | ff)
        and test -n "$file"
        and scp "$file" $argv[1]
    end

    # zoxide: cd falls back to a zoxide jump when the argument is not a
    # directory. zd uses a copy of fish's own cd, which keeps the history prevd,
    # nextd and cdh read; the check keeps a re-sourced config from copying zd.
    if type -q zoxide
        functions -q __cachy_cd; or functions --copy cd __cachy_cd
        function zd --description "cd, or a zoxide jump when the argument is not a directory"
            # fish's implicit cd (`..`, `dir/`) calls `cd -- <dir>`.
            test "$argv[1]" = --; and set -e argv[1]
            if test (count $argv) -eq 0
                __cachy_cd ~
            else if test -d "$argv[1]"
                __cachy_cd $argv[1]
            else
                if not z $argv
                    echo "Error: Directory not found"
                    return 1
                end
                printf '\U000F17A9 '
                pwd
            end
        end
        alias cd=zd
    end

    # directories
    alias ...='cd ../..'
    alias ....='cd ../../..'

    # vi-style line editing. Before fzf's bindings below, which it would reset.
    fish_vi_key_bindings

    # Secure secrets editor: no viminfo, no swap/backup/undo files, no plugins.
    # SOPS_EDITOR reuses it for sops decrypts.
    alias svim="nvim -u NONE -i NONE -n -c 'set number' -c 'set nowritebackup nobackup noundofile noswapfile'"
    set -gx SOPS_EDITOR "nvim -u NONE -i NONE -n -c 'set number' -c 'set nowritebackup nobackup noundofile noswapfile'"

    # ── tool integrations (shell/integrations) ───────────────────────────────

    # mise (version manager)
    if type -q mise
        mise activate fish | source
    end

    # xdg-desktop-portal gates its GTK backend on XDG_CURRENT_DESKTOP; i3/config
    # sets it for everything i3 spawns. Repeated here for shells already running.
    if not set -q XDG_CURRENT_DESKTOP
        set -gx XDG_CURRENT_DESKTOP GNOME
    end

    # Starship prompt (config in starship/starship.toml)
    if test "$TERM" != "dumb"; and type -q starship
        starship init fish | source
    end

    # zoxide (provides z, used by zd above)
    if type -q zoxide
        zoxide init fish | source
    end

    # fzf: key bindings (Ctrl-R, Ctrl-T, Alt-C)
    if type -q fzf
        fzf --fish | source
    end
end
