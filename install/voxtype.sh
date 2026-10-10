#!/usr/bin/env bash
# Voxtype: the speech model.
# Sourced by install.sh, install_vm.sh and sync.sh through install/lib.sh; defines
# functions and package lists only, and runs nothing.

# Voxtype needs a speech model before its daemon (05-autostart.conf) can do
# anything. The config names base.en, which is what `voxtype setup --download`
# fetches. Needs network; a failure is only a warning, since it can be re-run.
setup_voxtype() {
    command -v voxtype >/dev/null || return 0
    if ls "${XDG_DATA_HOME:-$HOME/.local/share}"/voxtype/models/*.bin >/dev/null 2>&1; then
        return 0
    fi
    say "Voxtype: downloading the speech model (base.en)"
    as_user voxtype setup --download \
        || warn "voxtype model download failed; run: voxtype setup --download"
}
