# zathura — rendered by x11-theme from the active theme; ~/.config/zathura/zathurarc
# links here. Settings live in this template too (zathurarc has no include that
# takes a path outside its directory).
set selection-clipboard clipboard
set font "JetBrainsMono Nerd Font 10"
set recolor true
set recolor-keephue true

set default-bg "{{ background }}"
set default-fg "{{ foreground }}"
set statusbar-bg "{{ dark_background }}"
set statusbar-fg "{{ foreground }}"
set inputbar-bg "{{ dark_background }}"
set inputbar-fg "{{ bright_foreground }}"
set notification-bg "{{ dark_background }}"
set notification-fg "{{ foreground }}"
set notification-error-bg "{{ red }}"
set notification-error-fg "{{ background }}"
set notification-warning-bg "{{ orange }}"
set notification-warning-fg "{{ background }}"
set highlight-color "{{ accent }}"
set highlight-active-color "{{ bright_red }}"
set completion-bg "{{ dark_background }}"
set completion-fg "{{ foreground }}"
set completion-highlight-bg "{{ accent }}"
set completion-highlight-fg "{{ selection_foreground }}"
set index-bg "{{ background }}"
set index-fg "{{ foreground }}"
set index-active-bg "{{ accent }}"
set index-active-fg "{{ selection_foreground }}"
# Recolouring (ctrl+r toggles): pages drawn in the theme's colours.
set recolor-lightcolor "{{ background }}"
set recolor-darkcolor "{{ foreground }}"
