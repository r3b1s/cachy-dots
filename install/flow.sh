#!/usr/bin/env bash
# The install, step by step, for the profile in PROFILE. Called by install.sh and
# install_vm.sh after parse_args. Steps a profile leaves out are guarded by
# `want`, or are no-ops because their package was taken out of the lists.

# Written on every run so sync.sh brings the system up to date with the profile
# it was installed with, not another.
profile_state_file() { echo "${XDG_CONFIG_HOME:-$HOME/.config}/cachy-dots/profile"; }

record_profile() {
    [ "$dry" = 1 ] && { echo "+ record the profile ($PROFILE)"; return; }
    mkdir -p "$(dirname "$(profile_state_file)")"
    echo "$PROFILE" > "$(profile_state_file)"
}

install_main() {
    apply_profile
    say "Profile: $PROFILE_DESC"

    if [ "$do_packages" = 1 ]; then
        check_cachy_repos
        setup_chaotic_aur
        install_packages
        install_aur
        sync_qt_stack
        setup_login_shell
        setup_theme_helper
        install_ly_theme
        enable_services
        enable_nix
        setup_dark_theme
        setup_gtk
        setup_firefox
        setup_chromium
        setup_firewall
        want touchpad && setup_touchpad
        check_keyring_pam
    fi
    if [ "$do_links" = 1 ]; then
        install_links
        setup_theme
        setup_default_apps
        setup_voxtype
        validate_i3
    fi
    record_profile

    echo
    # A kernel upgraded by this run leaves the running one without modules; anything
    # netfilter-based (ufw, libvirt's NAT) stays broken until a reboot.
    if [ ! -d "/usr/lib/modules/$(uname -r)" ]; then
        warn "reboot needed: kernel $(uname -r) is running but its modules are gone (it was upgraded)"
    fi
    if [ "$FAILED" = 1 ]; then
        warn "finished with errors (see the warnings above)"
        exit 1
    fi
    echo "Done. Log into the i3 session, or reload with \$mod+Shift+Ctrl+Mod1+c (i3-msg reload)."
}
