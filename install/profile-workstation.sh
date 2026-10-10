#!/usr/bin/env bash
# The workstation profile (install.sh): everything, on bare metal or in a VM.
PROFILE_DESC="workstation: the full install"
PROFILE_SKIP_PKGS=()
PROFILE_SKIP_PINNED=()
PROFILE_SKIP_AUR=()
PROFILE_SKIP_FEATURES=(
    vm-scripts                       # vm/: x11-autoresize follows the host window; a guest has no use for it elsewhere
)
