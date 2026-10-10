#!/usr/bin/env bash
# Package lists: what is installed, and where the pinned ones come from.
# Sourced by install.sh, install_vm.sh and sync.sh through install/lib.sh; defines
# functions and package lists only, and runs nothing.

# ── packages ──────────────────────────────────────────────────────────────

# Packages are named plainly, never as cachyos-extra-v3/foo: CachyOS lists its
# optimised repos (cachyos-v3/-v4/-znver4, cachyos-core-*, cachyos-extra-*,
# cachyos) above core/extra in pacman.conf, so pacman already takes the Cachy
# build whenever one exists, and which of v3/v4/znver4 that is depends on the
# CPU the installer picked. Hard-coding a level would break on other hardware.
# check_cachy_repos() verifies that ordering; see AGENTS.md, "Repos".

# Core stack (see AGENTS.md).
PKGS=(
    i3-wm i3status-rust autotiling   # window manager, bar, auto-split
    rofi dunst kitty neovim btop     # launcher, notifications, terminal, editor, monitor
    alacritty                        # default terminal ($terminal in i3/config)
    chromium                         # browser that follows the system colour scheme
    firefox                          # second browser; themed and preconfigured by policy
    mise nix                         # package / language managers

    # i3-wm depends on neither of these. See AGENTS.md, "Starting i3".
    xorg-server                     # the X server itself
    xorg-xinit                      # startx / xinit
    xorg-xrandr                     # monitor size, set by bin/x11-monitor
    xorg-xauth                      # X authentication (ly and startx)
    ly                              # display manager; runs i3 (see AGENTS.md)
)

# What the config calls at runtime.
PKGS+=(
    jq                               # x11-ws-app
    git                              # x11-theme clones theme repos; a vanilla Arch cloud image has none
    eza zoxide fzf bat               # shell integrations (shell/); bat previews fzf's ff
    bash-completion
    maim xclip xcolor                # screenshots, clipboard, colour picker
    feh                              # wallpaper, set by bin/x11-wallpaper
    numlockx
    xdotool                          # pointer warp (bin/x11-focus) and dictation paste (bin/x11-voxtype)
    libnotify                        # dunstify links against it (dunst's optdep); the OSDs use it
    curl                             # fetches the seeded wallpaper
    rofimoji                         # emoji picker, bound in i3/conf.d/30-apps.conf

    # System-wide dark mode. There is no desktop here, so dconf is the system
    # theme: GTK4/libadwaita read it directly, and the portal reads it for
    # everything sandboxed (see setup_dark_theme).
    gsettings-desktop-schemas        # without this the color-scheme key does not exist
    dconf                            # the store gsettings writes to
    xdg-desktop-portal               # org.freedesktop.portal.Settings
    xdg-desktop-portal-gtk           # its backend; the one that implements Settings
    adwaita-icon-theme               # the base icon theme pinkrot inherits from
    pipewire-pulse                   # pactl, used by x11-volume
    pavucontrol                      # mixer and default-device picker; the bar's volume blocks open it
    ttf-jetbrains-mono-nerd          # font used by the terminals / i3 / bar
    starship                         # shell prompt (config in starship/)
    tmux                             # terminal multiplexer (config in tmux/)
    rclone                           # cloud storage sync
    obsidian                         # notes
    base-devel                       # makepkg and the toolchain, for yay and AUR builds
)

# Desktop tools for daily use (not just disposable VMs).
PKGS+=(
    copyq                            # clipboard history; bin/x11-clipboard puts it in rofi
    satty                            # screenshot annotation (bin/x11-screenshot annotate-*)
    xss-lock                         # locks on suspend and idle (i3lock-color is pinned below)
    xorg-xset                        # xset: sets the idle timer xss-lock watches (05-autostart.conf)
    gammastep                        # nightlight, toggled by bin/x11-nightlight
    blueman bluez bluez-utils        # bluetooth manager GUI + tray applet, the stack under it
    yazi                             # TUI file manager ($mod+Shift+e)
    nautilus gvfs                    # GUI file manager ($mod+e); gvfs: trash, mounts, network
    adw-gtk-theme                    # adw-gtk3: GTK3 drawn like libadwaita, recoloured by x11-theme's gtk.css
    zaproxy                          # web proxy ($mod+z workspace)
    # yazi's previewers and helpers (its optdepends): archives, PDFs, video
    # thumbnails, SVG, images, search. jq/fzf/zoxide are already above.
    7zip poppler ffmpegthumbnailer resvg imagemagick fd ripgrep
)

# Session helpers.
PKGS+=(
    polkit-gnome                     # polkit authentication agent
    network-manager-applet           # nm-applet
    gnome-keyring libsecret seahorse # secrets (Wi-Fi, browsers, Vesktop); unlocked at login by ly's PAM
)

# Default applications (setup_default_apps), each themed by x11-theme.
PKGS+=(
    imv                              # images
    zathura zathura-pdf-mupdf        # PDFs
    mpv                              # video and audio
)

# Bare-metal desktop: media and brightness keys, monitors, touchpad, power.
PKGS+=(
    playerctl                        # play/pause/next/previous for any MPRIS player
    brightnessctl                    # backlight keys (bin/x11-brightness)
    autorandr arandr                 # monitor profiles (bin/x11-display); arandr to arrange them
    xf86-input-libinput              # the X input driver xorg/30-touchpad.conf configures
    power-profiles-daemon            # power profile, switched from the $mod+Escape menu
    tesseract tesseract-data-eng     # OCR: $mod+Print copies the text in a region
)

# Network and security.
PKGS+=(
    wireguard-tools                  # wg, wg-quick (openvpn comes with CachyOS)
    ufw                              # firewall, set up by setup_firewall
)

# VM guest integration, only inside a VM: on bare metal these have nothing to
# talk to, so they are not installed at all.
IS_VM=0
if [ "${PROFILE_FORCE_VM:-0}" = 1 ] || { command -v systemd-detect-virt >/dev/null && systemd-detect-virt -q --vm; }; then
    IS_VM=1
    PKGS+=(
        spice-vdagent                # shared clipboard + display resize (SPICE)
        qemu-guest-agent             # host <-> guest control channel
    )
fi

# Pinned packages. Each entry lists the repos it may come from, best first:
# the first one that has it is installed, by its qualified name, so pacman can
# never pick the same package from another repo. Order follows AGENTS.md:
# CachyOS's repos, then official Arch, then chaotic-aur. A pin with a single repo
# has no fallback:
#   chaotic-aur/qutebrowser-git  no CachyOS or official build; extra's plain
#                                `qutebrowser` is not wanted (they conflict, so
#                                an installed `qutebrowser` is removed first)
#   chaotic-aur/yaru-icon-theme  the icon themes omarchy themes name in icons.theme
#                                (Yaru-red, Yaru-blue, ...); in no official repo
# With a fallback list:
#   cachyos/yay                  CachyOS's build, else chaotic-aur's (never plain AUR)
#   cachyos/i3lock-color         the lock screen; i3lock with colour options, which
#                                plain extra/i3lock lacks (they conflict, so an
#                                installed `i3lock` is removed first)
#   cachyos/vesktop-bin          Discord client (Vencord), else chaotic-aur/vesktop
# If no listed repo has a package, it is skipped with a warning, the rest still
# installs, and the run exits non-zero.
PINNED=(
    chaotic-aur/qutebrowser-git
    chaotic-aur/yaru-icon-theme
    "cachyos/yay chaotic-aur/yay"
    "cachyos/i3lock-color chaotic-aur/i3lock-color"
    "cachyos/vesktop-bin chaotic-aur/vesktop"
)
# Plain package each pinned one conflicts with: the plain one is removed first
# when the pin is chosen (--noconfirm would answer the conflict prompt with No).
PINNED_REPLACES=(qutebrowser:qutebrowser-git i3lock:i3lock-color vesktop:vesktop-bin)

# AUR packages: the few that no pacman repo carries. A repo build always wins:
# when pacman can see the package in an enabled repo (Cachy, Arch, chaotic-aur)
# it is installed from there like any other; yay builds it only otherwise.
#   voxtype-bin  push-to-talk dictation (voxtype/, bin/x11-voxtype). The AUR
#                package is kept by voxtype's own authors.
# makepkg refuses to run as root, so yay runs as the invoking user (yay itself
# is pinned above and installed first).
AUR_PKGS=(voxtype-bin)
# Signing keys the AUR packages above verify their sources with (from their
# PKGBUILDs: validpgpkeys), imported best effort before the build.
AUR_KEYS=(E79F5BAF8CD51A806AA27DBB7DA2709247D75BC6 9CCF7915B750CAE8B095ED1AA3FC9F33FD209279)
