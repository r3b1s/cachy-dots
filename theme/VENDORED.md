# Vendored from omarchy

`theme/` follows omarchy's own layout (`$OMARCHY_PATH/bin`, `$OMARCHY_PATH/default/themed`,
`$OMARCHY_PATH/themes`), so `bin/x11-theme` can point `OMARCHY_PATH` here and run omarchy's scripts
unmodified. Copied from https://github.com/omacom/omarchy (MIT, Copyright (c) David Heinemeier Hansson)
at commit `902fd8aebd98b6eedaa58276886a2f9f2876755f` (2026-10-07):

| File | Upstream path | Changes |
| --- | --- | --- |
| `bin/omarchy-theme-color` | `bin/omarchy-theme-color` | none |
| `bin/omarchy-theme-set-templates` | `bin/omarchy-theme-set-templates` | none |
| `default/themed/alacritty.toml.tpl` | same | none |
| `default/themed/kitty.conf.tpl` | same | none |
| `default/themed/btop.theme.tpl` | same | none |
| `default/themed/chromium.theme.tpl` | same | none |

Every other `default/themed/*.tpl` is ours, written for the i3 stack (omarchy has no i3, rofi, dunst,
i3status-rust or GTK templates). They use the same token syntax: `{{ key }}`, `{{ key_strip }}`,
`{{ key_rgb }}`, `{{ mix a b 30% }}`, resolved by `omarchy-theme-color`.

`themes/pinkrot/colors.toml` is the palette from https://github.com/r3b1s/omarchy-pinkrot-theme
(commit `b62455d`), kept here as a built-in fallback so a theme can be applied with no network.
`x11-theme install` of that repo overlays it with the full theme (backgrounds, previews).

To update: copy the upstream files over these, re-read the diff for new dependencies (both scripts
are self-contained today: `omarchy-theme-set-templates` only calls `omarchy-theme-color`), and bump the
commit above.
