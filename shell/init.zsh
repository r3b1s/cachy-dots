# Interactive zsh setup for the normal user, the counterpart of init.sh: bash's
# aliases and functions (aliases, shared) and the same tools (integrations.zsh).
# Sourced from the managed block opt/zsh.sh adds to ~/.zshrc; the files below
# live next to this one, in ~/.config/shell/.
[[ -o interactive ]] || return

DOTS=${${(%):-%x}:a:h}

# bin/ is linked into ~/.local/bin.
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) PATH="$HOME/.local/bin:$PATH" ;;
esac

# Telemetry opt-outs (env/telemetry.conf, linked into environment.d). A terminal
# started before a re-login would otherwise miss newly added keys.
if [[ -r "${XDG_CONFIG_HOME:-$HOME/.config}/environment.d/telemetry.conf" ]]; then
  set -a
  source "${XDG_CONFIG_HOME:-$HOME/.config}/environment.d/telemetry.conf"
  set +a
fi

# History: bash keeps ~/.bash_history unasked, zsh keeps none until told where.
HISTFILE=${HISTFILE:-$HOME/.zsh_history}
HISTSIZE=10000
SAVEHIST=10000

source "$DOTS/aliases"
source "$DOTS/integrations.zsh"
