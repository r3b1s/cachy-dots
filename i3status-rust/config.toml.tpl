[icons]
icons = "material-nf"

# This file is a template: x11-theme renders it, with the active theme's
# colours, to ~/.local/state/omarchy/current/theme/i3status-rust.config.toml,
# which is what i3/conf.d/15-bar.conf runs. theme/default/themed/ holds a link
# to it, which is how the renderer finds it. Edit blocks here, then run
# `x11-theme refresh` (or switch theme) to apply.
#
# Colours: {{ key }} is a colors.toml key (with omarchy's derived keys);
# {{ mix a b N% }} blends b into a. Each block is a hue mixed into the
# background, getting stronger from idle to critical.

[theme]
theme = "plain"
[theme.overrides]
idle_bg = "{{ background }}"
idle_fg = "{{ foreground }}"
info_bg = "{{ background }}"
info_fg = "{{ bright_foreground }}"
good_bg = "{{ background }}"
good_fg = "{{ green }}"
warning_bg = "{{ orange }}"
warning_fg = "{{ background }}"
critical_bg = "{{ red }}"
critical_fg = "{{ background }}"
separator = "\uE0B2"
separator_bg = "auto"
separator_fg = "auto"

# VPN: shows the tun0 address (HTB / THM / OpenVPN), hidden when it is down.
# Left-click copies the IP to the clipboard, ready to paste into a payload.
[[block]]
block = "net"
device = "tun0"
format = " VPN $ip "
missing_format = ""
interval = 5
[[block.click]]
button = "left"
cmd = "~/.local/bin/x11-vpn-ip --copy"
[block.theme_overrides]
idle_bg = "{{ mix background accent 60% }}"
idle_fg = "{{ bright_foreground }}"
info_bg = "{{ mix background accent 60% }}"
info_fg = "{{ bright_foreground }}"
good_bg = "{{ mix background accent 60% }}"
good_fg = "{{ bright_foreground }}"
warning_bg = "{{ mix background accent 60% }}"
warning_fg = "{{ bright_foreground }}"
critical_bg = "{{ mix background accent 60% }}"
critical_fg = "{{ bright_foreground }}"

[[block]]
block = "net"
format = " $icon {$signal_strength $ssid $frequency|Wired} via $device "
format_alt = " $icon {$ip|Down} "
interval = 10
[block.theme_overrides]
start_separator = ""
start_separator_bg = "{{ background }}"
start_separator_fg = "{{ background }}"
idle_bg = "{{ mix background cyan 55% }}"
idle_fg = "{{ bright_foreground }}"
info_bg = "{{ mix background cyan 55% }}"
info_fg = "{{ bright_foreground }}"
good_bg = "{{ mix background cyan 55% }}"
good_fg = "{{ bright_foreground }}"
warning_bg = "{{ mix background cyan 55% }}"
warning_fg = "{{ bright_foreground }}"
critical_bg = "{{ mix background cyan 55% }}"
critical_fg = "{{ bright_foreground }}"

[[block]]
block = "disk_space"
path = "/"
info_type = "available"
alert_unit = "GB"
interval = 30
warning = 20.0
alert = 10.0
format = " $icon $available.eng(w:2) "
[block.theme_overrides]
idle_bg = "{{ mix background magenta 25% }}"
idle_fg = "{{ foreground }}"
info_bg = "{{ mix background magenta 40% }}"
info_fg = "{{ bright_foreground }}"
good_bg = "{{ mix background magenta 40% }}"
good_fg = "{{ bright_foreground }}"
warning_bg = "{{ mix background magenta 65% }}"
warning_fg = "{{ bright_foreground }}"
critical_bg = "{{ mix background magenta 85% }}"
critical_fg = "{{ bright_foreground }}"

[[block]]
block = "memory"
format = " $icon $mem_total_used_percents.eng(w:2) "
format_alt = " $icon_swap $swap_used_percents.eng(w:2) "
interval = 5
[block.theme_overrides]
idle_bg = "{{ mix background purple 25% }}"
idle_fg = "{{ foreground }}"
info_bg = "{{ mix background purple 40% }}"
info_fg = "{{ bright_foreground }}"
good_bg = "{{ mix background purple 40% }}"
good_fg = "{{ bright_foreground }}"
warning_bg = "{{ mix background purple 65% }}"
warning_fg = "{{ bright_foreground }}"
critical_bg = "{{ mix background purple 85% }}"
critical_fg = "{{ bright_foreground }}"

[[block]]
block = "cpu"
interval = 5
info_cpu = 20
warning_cpu = 50
critical_cpu = 90
[block.theme_overrides]
idle_bg = "{{ mix background accent 25% }}"
idle_fg = "{{ foreground }}"
info_bg = "{{ mix background accent 40% }}"
info_fg = "{{ bright_foreground }}"
good_bg = "{{ mix background accent 40% }}"
good_fg = "{{ bright_foreground }}"
warning_bg = "{{ mix background accent 65% }}"
warning_fg = "{{ bright_foreground }}"
critical_bg = "{{ mix background accent 85% }}"
critical_fg = "{{ bright_foreground }}"

[[block]]
block = "load"
format = " $icon $1m.eng(w:4) "
interval = 5
[block.theme_overrides]
idle_bg = "{{ mix background red 25% }}"
idle_fg = "{{ foreground }}"
info_bg = "{{ mix background red 40% }}"
info_fg = "{{ bright_foreground }}"
good_bg = "{{ mix background red 40% }}"
good_fg = "{{ bright_foreground }}"
warning_bg = "{{ mix background red 65% }}"
warning_fg = "{{ bright_foreground }}"
critical_bg = "{{ mix background red 85% }}"
critical_fg = "{{ bright_foreground }}"

[[block]]
block = "sound"
format = " $icon $volume "
[block.theme_overrides]
idle_bg = "{{ mix background orange 25% }}"
idle_fg = "{{ foreground }}"
info_bg = "{{ mix background orange 40% }}"
info_fg = "{{ bright_foreground }}"
good_bg = "{{ mix background orange 40% }}"
good_fg = "{{ bright_foreground }}"
warning_bg = "{{ mix background orange 65% }}"
warning_fg = "{{ bright_foreground }}"
critical_bg = "{{ mix background orange 85% }}"
critical_fg = "{{ bright_foreground }}"

[[block]]
block = "time"
interval = 5
format = " $icon $timestamp.datetime(f:'%a %d %b %R') "
[block.theme_overrides]
idle_bg = "{{ background }}"
idle_fg = "{{ bright_foreground }}"
info_bg = "{{ background }}"
info_fg = "{{ bright_foreground }}"
good_bg = "{{ background }}"
good_fg = "{{ bright_foreground }}"
warning_bg = "{{ background }}"
warning_fg = "{{ bright_foreground }}"
critical_bg = "{{ background }}"
critical_fg = "{{ bright_foreground }}"
