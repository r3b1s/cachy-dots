#!/usr/bin/env bash
# Repos: the CachyOS ordering check and the chaotic-aur repo.
# Sourced by install.sh, install_vm.sh and sync.sh through install/lib.sh; defines
# functions and package lists only, and runs nothing.

PACMAN_CONF=/etc/pacman.conf

# CachyOS's own repos must come before core/extra, or pacman takes the generic
# Arch builds. The CachyOS installer writes them that way; this only checks, and
# warns rather than rewriting pacman.conf. (cachyos-rate-mirrors and
# cachyos-repo tooling own that file's repo section.)
check_cachy_repos() {
    command -v pacman >/dev/null || return 0

    if ! grep -qx 'ID=cachyos' /etc/os-release 2>/dev/null; then
        warn "this does not look like CachyOS (/etc/os-release); continuing anyway"
    fi

    local repos first_cachy first_arch
    repos=$(pacman-conf --repo-list 2>/dev/null || true)
    # A miss (no cachyos repos, as on vanilla Arch) is a result, not an error.
    first_cachy=$(printf '%s\n' "$repos" | grep -n '^cachyos' | head -1 | cut -d: -f1 || true)
    first_arch=$(printf '%s\n' "$repos" | grep -nxE 'core|extra' | head -1 | cut -d: -f1 || true)

    if [ -z "$first_cachy" ]; then
        warn "no [cachyos*] repos in $PACMAN_CONF: packages will come from plain Arch"
        return 0
    fi
    if [ -n "$first_arch" ] && [ "$first_cachy" -gt "$first_arch" ]; then
        warn "the [cachyos*] repos are listed after core/extra in $PACMAN_CONF;"
        warn "pacman will prefer the generic Arch builds. Move them above [core]."
        return 0
    fi
    say "CachyOS repos: $(printf '%s\n' "$repos" | grep '^cachyos' | paste -sd' ')"
}

# chaotic-aur exists here for qutebrowser-git alone (and blesh-git, if opted in
# with opt/blesh.sh); nothing else is installed from it. It is appended at the
# END of pacman.conf, below the Cachy and Arch repos, so it can never shadow
# their builds of anything: packages are only taken from it by qualified name.
#
# Setup follows https://aur.chaotic.cx/docs: trust the signing key, install the
# keyring and mirrorlist packages from its CDN, then add the repo. A repo that
# has just been added has no sync database, and the only supported way to get
# one is a full -Syu (a bare -Sy followed by -S is a partial upgrade).
CHAOTIC_KEY=3056513887B78AEB
CHAOTIC_CDN=https://cdn-mirror.chaotic.cx/chaotic-aur

setup_chaotic_aur() {
    command -v pacman >/dev/null || return 0

    if ! pacman-conf --repo-list 2>/dev/null | grep -qx chaotic-aur; then
        say "Adding the chaotic-aur repo (for qutebrowser-git)"
        # One -U for both packages: every pacman transaction costs a pre/post
        # snapper snapshot pair on CachyOS (cachyos-snapper-support).
        local pkgs=()
        pacman -Qq chaotic-keyring >/dev/null 2>&1 || pkgs+=("$CHAOTIC_CDN/chaotic-keyring.pkg.tar.zst")
        pacman -Qq chaotic-mirrorlist >/dev/null 2>&1 || pkgs+=("$CHAOTIC_CDN/chaotic-mirrorlist.pkg.tar.zst")
        if [ "${#pkgs[@]}" -gt 0 ]; then
            { run $SUDO pacman-key --recv-key "$CHAOTIC_KEY" --keyserver keyserver.ubuntu.com \
                && run $SUDO pacman-key --lsign-key "$CHAOTIC_KEY" \
                && run $SUDO pacman -U --needed --noconfirm "${pkgs[@]}"; } \
                || { warn "could not install chaotic-keyring/chaotic-mirrorlist"; FAILED=1; return 0; }
        fi
        if [ "$dry" = 1 ]; then
            echo "+ append [chaotic-aur] to $PACMAN_CONF"
        else
            $SUDO cp -a "$PACMAN_CONF" "$PACMAN_CONF.bak.$(date +%s)"
            printf '\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist\n' \
                | $SUDO tee -a "$PACMAN_CONF" >/dev/null
            echo "chaotic-aur: appended to $PACMAN_CONF (last, below the Cachy and Arch repos)"
        fi
    fi

    if [ ! -f "$(pacman-conf DBPath 2>/dev/null || echo /var/lib/pacman/)sync/chaotic-aur.db" ]; then
        say "Syncing the new repo (full -Syu; a bare -Sy would be a partial upgrade)"
        run $SUDO pacman -Syu --noconfirm || { warn "pacman -Syu failed"; FAILED=1; }
    fi
}
