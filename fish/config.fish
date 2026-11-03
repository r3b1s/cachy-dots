# Interactive and login fish configuration for cachy-dots.
# Linked into ~/.config/fish/config.fish.
#
# Prompt: starship (starship/starship.toml)
# Line editing: vi key bindings (fish_vi_key_bindings)
# Greeting: disabled (no fastfetch)

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

# Editor and portal settings
set -gx SOPS_EDITOR "nvim -u NONE -i NONE -n -c 'set number' -c 'set nowritebackup nobackup noundofile noswapfile'"

if not set -q XDG_CURRENT_DESKTOP
    set -gx XDG_CURRENT_DESKTOP GNOME
end

if status is-interactive
    # Vi-style key bindings
    fish_vi_key_bindings

    # Starship prompt (config in starship/starship.toml)
    if test "$TERM" != "dumb"; and type -q starship
        starship init fish | source
    end

    # Tool integrations: mise, zoxide, fzf
    if type -q mise
        mise activate fish | source
    end

    if type -q zoxide
        zoxide init fish | source
    end

    if type -q fzf
        fzf --fish | source

        # ff: fuzzy file finder with preview
        function ff --description "Fuzzy find files with preview"
            if test "$TERM" = "xterm-kitty"
                fzf --preview 'case (file --mime-type -b {}) in image/*) kitty icat --clear --transfer-mode=memory --stdin=no --place={$FZF_PREVIEW_COLUMNS}x{$FZF_PREVIEW_LINES}@0x0 {} ;; *) bat --style=numbers --color=always {} ;; esac'
            else if type -q bat
                fzf --preview 'bat --style=numbers --color=always {}'
            else
                fzf
            end
        end

        function eff --description "Edit fuzzy-found file"
            set -l editor (test -n "$EDITOR"; and echo "$EDITOR"; or echo "nvim")
            set -l file (ff)
            test -n "$file"; and $editor "$file"
        end
    end

    # Aliases
    if type -q eza
        alias ls='eza -lh --group-directories-first --icons=auto'
        alias lsa='ls -a'
        alias lt='eza --tree --level=2 --long --icons --git'
        alias lta='lt -a'
    end

    alias ..='cd ..'
    alias ...='cd ../..'
    alias ....='cd ../../..'

    # Secure secrets editor: no backup, swap or undo files
    alias svim="nvim -u NONE -i NONE -n -c 'set number' -c 'set nowritebackup nobackup noundofile noswapfile'"
end
