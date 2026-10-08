# satty — screenshot annotation. Fed by bin/x11-screenshot (maim | satty -f -).
# Reference: /usr/share/doc/satty/README.md ("Configuration").
#
# A template: x11-theme renders it with the active theme's colours to
# ~/.local/state/omarchy/current/theme/satty.config.toml, which
# ~/.config/satty/config.toml links to (theme/default/themed/ links here).
[general]
# Enter copies and closes; Escape just closes. Ctrl+S saves to output-filename.
early-exit = ["all"]
actions-on-enter = ["save-to-clipboard", "exit"]
actions-on-escape = ["exit"]
# X11 clipboard; satty's default is wl-copy.
copy-command = "xclip -selection clipboard -t image/png"
output-filename = "~/Pictures/Screenshots/satty-%Y-%m-%d_%H-%M-%S.png"
initial-tool = "arrow"
corner-roundness = 6
annotation-size-factor = 1.5
default-round-caps = true
brush-smooth-history-size = 5
primary-highlighter = "block"
notification-thumbnail = "screenshot"

[font]
family = "JetBrainsMono Nerd Font"
style = "Regular"

# The theme's accent and highlight colours, plus white and the theme background
# for contrast on arbitrary screenshots. Keys 1-6 pick these in order.
[color-palette]
palette = [
    "{{ accent }}ff",
    "{{ red }}ff",
    "{{ magenta }}ff",
    "{{ cyan }}ff",
    "#ffffffff",
    "{{ background }}ff",
]
