#!/usr/bin/env bash
# The vm profile (install_vm.sh): a lean desktop for a throwaway guest. What it
# leaves out is listed here and nowhere else; the lists in packages.sh stay
# complete, and apply_profile() takes these out of them. Edit freely.
PROFILE_DESC="vm: a lean desktop for a guest"

# The guest agents (spice-vdagent, qemu-guest-agent) go in whether or not
# systemd-detect-virt says VM, since this profile is for one.
PROFILE_FORCE_VM=1

# Packages left out, with why.
PROFILE_SKIP_PKGS=(
    # An application a test guest does not need.
    rclone
    # Hardware a guest does not have.
    blueman bluez bluez-utils        # bluetooth
    brightnessctl                    # backlight keys
    power-profiles-daemon
    gammastep                        # nightlight
    autorandr arandr                 # monitor profiles; bin/x11-display pins the mode with x11-monitor in a VM
    tesseract-data-eng               # OCR for $mod+Print (tesseract itself comes with zathura's mupdf)
)

# Pinned packages left out (by package name, either repo's).
PROFILE_SKIP_PINNED=(
    vesktop-bin vesktop              # Discord
)

# AUR packages left out.
PROFILE_SKIP_AUR=(voxtype-bin)       # dictation: no microphone, a GPU-less guest

# Setup steps left out (checked with `want`).
PROFILE_SKIP_FEATURES=(
    touchpad                         # /etc/X11/xorg.conf.d/30-touchpad.conf
)
