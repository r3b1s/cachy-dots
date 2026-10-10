#!/usr/bin/env bash
# Installing: the pacman transaction, AUR builds, the Qt 6 stack.
# Sourced by install.sh, install_vm.sh and sync.sh through install/lib.sh; defines
# functions and package lists only, and runs nothing.

# Everything goes into ONE pacman transaction: on CachyOS each transaction also
# takes a pre/post snapper snapshot pair, so separate calls per package would
# litter the snapshot list.
# Arch's rule: never -S against a stale sync database (a partial upgrade). The
# database is a snapshot of the mirror from the last sync. Once the mirror
# replaces a package (CachyOS rebuilding qt6-* from 6.11.2 to 6.12.0, say), the
# old file is gone and pacman fails with "failed retrieving file ... 6.11.2".
# So sync first, as a full -Syu: an -Sy alone is the partial upgrade.
refresh_databases() {
    say "Refreshing package databases (pacman -Syu)"
    run $SUDO pacman -Syu --noconfirm || { warn "pacman -Syu failed"; FAILED=1; }
}

install_packages() {
    command -v pacman >/dev/null || { warn "pacman not found; skipping package install"; return; }

    say "Checking packages"
    local missing=() p c entry chosen installed need_refresh=0
    for p in "${PKGS[@]}"; do
        pacman -Qq "$p" >/dev/null 2>&1 || { missing+=("$p"); need_refresh=1; }
    done
    for entry in "${PINNED[@]}"; do
        installed=0
        for c in $entry; do pacman -Qq "${c#*/}" >/dev/null 2>&1 && installed=1; done
        [ "$installed" = 1 ] || need_refresh=1
    done
    # Only when something is missing, so a re-run on a finished install does not
    # upgrade the whole system. The -Si checks below need a current database too.
    [ "$need_refresh" = 1 ] && refresh_databases
    for entry in "${PINNED[@]}"; do
        installed=0
        for c in $entry; do pacman -Qq "${c#*/}" >/dev/null 2>&1 && installed=1; done
        [ "$installed" = 1 ] && continue
        chosen=
        for c in $entry; do
            if pacman -Si "$c" >/dev/null 2>&1; then chosen=$c; break; fi
        done
        if [ -z "$chosen" ]; then
            warn "none of these has the package: $entry (is the repo enabled and synced?)"
            warn "not installing it from any other repo; fix that and re-run"
            FAILED=1
            continue
        fi
        missing+=("$chosen")
    done

    if [ "${#missing[@]}" -eq 0 ]; then
        echo "all packages already installed"
        return
    fi

    # Conflicting plain packages: --noconfirm answers pacman's "remove X?" with
    # its default, No, so they have to go first.
    local pair plain pkg
    for pair in "${PINNED_REPLACES[@]}"; do
        plain=${pair%%:*}; pkg=${pair#*:}
        case " ${missing[*]} " in *"/$pkg "*|*"/$pkg") ;; *) continue ;; esac
        if [ "$(pacman -Qq "$plain" 2>/dev/null)" = "$plain" ]; then
            warn "replacing $plain with $pkg"
            run $SUDO pacman -Rns --noconfirm "$plain"
        fi
    done

    say "Installing: ${missing[*]}"
    # A failure is reported, not fatal: the rest of the install (Qt sync, theme,
    # links) still runs and the summary at the end says what is missing.
    if ! run $SUDO pacman -S --needed --noconfirm "${missing[@]}"; then
        warn "pacman could not install everything; syncing and retrying once"
        refresh_databases
        if ! run $SUDO pacman -S --needed --noconfirm "${missing[@]}"; then
            warn "still not installed: ${missing[*]}"
            warn "a mirror may be behind; re-run install.sh later"
            FAILED=1
        fi
    fi
}

install_aur() {
    command -v pacman >/dev/null || return 0
    local pkg missing=() key
    for pkg in "${AUR_PKGS[@]}"; do
        pacman -Qq "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
    done
    [ "${#missing[@]}" -gt 0 ] || return 0

    say "AUR packages: ${missing[*]}"
    for pkg in "${missing[@]}"; do
        if pacman -Si "$pkg" >/dev/null 2>&1; then
            # Some enabled repo has it after all.
            run $SUDO pacman -S --needed --noconfirm "$pkg" \
                || { warn "could not install $pkg"; FAILED=1; }
            continue
        fi
        if [ "$TARGET_USER" = root ]; then
            warn "not building $pkg as root (makepkg refuses); run install.sh as your user"
            FAILED=1; continue
        fi
        if ! command -v yay >/dev/null && [ "$dry" = 0 ]; then
            warn "no yay, so $pkg cannot be built from the AUR"
            FAILED=1; continue
        fi
        for key in "${AUR_KEYS[@]}"; do
            as_user gpg --quiet --keyserver hkps://keyserver.ubuntu.com --recv-keys "$key" >/dev/null 2>&1 || true
        done
        as_user yay -S --needed --noconfirm --answerclean None --answerdiff None "$pkg" \
            || { warn "could not build $pkg from the AUR"; FAILED=1; }
    done
}

# Keep the Qt 6 stack on one minor version.
#
# Qt modules link against qt6-base's *private* API, which is versioned per
# release (Qt_6_PRIVATE_API, QtPrivate_6_11_2), so qt6-svg 6.11.2 cannot load
# next to qt6-base 6.12.0 even though pacman sees nothing wrong: the
# dependencies are unversioned. That mix happens whenever Arch moves to a new Qt
# minor and CachyOS rebuilds it piecemeal. Both were hit on 2026-10-07:
#   * extra's python-pyqt6 (no Cachy build) was built for Qt 6.12 while
#     cachyos-extra-v3 still had qt6-base 6.11.2 -> qutebrowser died with
#     "version `Qt_6.12' not found";
#   * hours later cachyos-extra-v3 had qt6-base 6.12.0 but qt6-svg 6.11.2, so
#     CopyQ died with "undefined symbol ... QtPrivate_6_11_2" on a pure-Cachy
#     install.
#
# Rule: once qt6-base is at minor N, every installed qt6-* module still below N
# is taken from extra if extra has it at N. The newest qt6-base wins whichever
# repo it is in. Modules that extra itself ships at an older minor
# (qt6-webengine trails qt6-base by design) are left alone. It heals itself:
# CachyOS versions a rebuild as Arch's pkgrel plus ".1" (6.12.0-1 ->
# 6.12.0-1.1), so the next -Syu after CachyOS catches up moves each one back.
qt_minor() { printf '%s\n' "${1#*:}" | cut -d. -f1,2; }

sync_qt_stack() {
    pacman -Qq qt6-base >/dev/null 2>&1 || return 0

    local base_ver base_min p inst ext behind=()
    base_ver=$(pacman -Q qt6-base | cut -d' ' -f2)
    # extra may already be a minor ahead of an installed (Cachy) qt6-base.
    ext=$(pacman -Sl extra 2>/dev/null | awk '$2 == "qt6-base" { print $3 }')
    if [ -n "$ext" ] && [ "$(vercmp "$(qt_minor "$base_ver")" "$(qt_minor "$ext")")" -lt 0 ]; then
        behind+=(extra/qt6-base)
        base_ver=$ext
    fi
    base_min=$(qt_minor "$base_ver")

    for p in $(pacman -Qq | grep '^qt6-' | grep -vx qt6-base); do
        inst=$(pacman -Q "$p" | cut -d' ' -f2)
        [ "$(vercmp "$(qt_minor "$inst")" "$base_min")" -lt 0 ] || continue
        ext=$(pacman -Sl extra 2>/dev/null | awk -v p="$p" '$2 == p { print $3 }')
        [ -n "$ext" ] && [ "$(qt_minor "$ext")" = "$base_min" ] && behind+=("extra/$p")
    done

    if [ "${#behind[@]}" -gt 0 ]; then
        say "Qt modules behind qt6-base $base_min (CachyOS mid-rebuild); taking from extra: ${behind[*]}"
        refresh_databases
        run $SUDO pacman -S --noconfirm "${behind[@]}" || { warn "could not sync the Qt stack"; FAILED=1; }
    fi

    [ "$dry" = 1 ] && return 0
    if pacman -Qq qutebrowser-git >/dev/null 2>&1 \
        && ! python3 -c 'import PyQt6.QtWebEngineWidgets' >/dev/null 2>&1; then
        warn "PyQt6 still does not load; qutebrowser will not start:"
        python3 -c 'import PyQt6.QtWebEngineWidgets' 2>&1 | tail -1 >&2
        FAILED=1
    fi
}
