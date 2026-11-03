# Tool integrations for zsh, the counterpart of ./integrations: completion,
# prompt, directory jumping, fzf. Each is skipped when its tool is not installed.

# mise (version manager).
if command -v mise &> /dev/null; then
  eval "$(mise activate zsh)"
fi

# xdg-desktop-portal gates its GTK backend (the one implementing
# org.freedesktop.portal.Settings) on XDG_CURRENT_DESKTOP, and i3/config sets it
# for everything i3 spawns. Repeat it here for shells that were already running
# before a reload.
export XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP:-GNOME}"

# zsh's own completion system, bash-completion's counterpart. Its cache goes in
# ~/.cache, not ~/.zcompdump.
autoload -Uz compinit
mkdir -p "${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
compinit -d "${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump"

# starship (the config is starship/starship.toml).
if [[ ${TERM:-} != "dumb" ]] && command -v starship &> /dev/null; then
  eval "$(starship init zsh)"
fi

# zoxide (provides `z`, used by the cd wrapper in ./aliases)
if command -v zoxide &> /dev/null; then
  eval "$(zoxide init zsh)"
fi

# fzf: key bindings only (Ctrl-R, Ctrl-T, Alt-C), after vi mode (./aliases) so
# they land in its keymaps. completion.zsh is skipped, as bash's is.
if command -v fzf &> /dev/null; then
  if [[ -f /usr/share/fzf/key-bindings.zsh ]]; then
    source /usr/share/fzf/key-bindings.zsh
  fi
fi
