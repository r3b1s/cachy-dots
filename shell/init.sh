# Interactive bash setup for the normal user. Sourced from the managed block
# install.sh adds to ~/.bashrc; the files below live next to this one, in
# ~/.config/shell/.
[[ $- != *i* ]] && return

DOTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# bin/ is linked into ~/.local/bin, which CachyOS's stock ~/.bashrc does not
# put on PATH.
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) PATH="$HOME/.local/bin:$PATH" ;;
esac

# ble.sh is opt-in (opt/blesh.sh). When installed it is loaded first, as the
# AthenaOS image did, so starship below registers through blehook instead of
# PROMPT_COMMAND. Its default --attach=prompt defers attaching to the first
# prompt, so nothing has to run at the end of ~/.bashrc.
if [[ -r /usr/share/blesh/ble.sh ]]; then
  source /usr/share/blesh/ble.sh
fi

source "$DOTS/aliases"
source "$DOTS/integrations"
