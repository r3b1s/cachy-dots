-- The window borders, in the colours Noctalia's own Hyprland template gives them.
-- Rendered by Noctalia (noctalia/templates.toml); noctalia/hooks/on-theme-change puts
-- it where hypr/noctalia/compositor.lua loads it.
hl.config({
	general = {
		col = {
			active_border = "rgb({{colors.primary.default.hex_stripped}})",
			inactive_border = "rgb({{colors.surface.default.hex_stripped}})",
		},
	},
	group = {
		col = {
			border_active = "rgb({{colors.secondary.default.hex_stripped}})",
			border_inactive = "rgb({{colors.surface.default.hex_stripped}})",
			border_locked_active = "rgb({{colors.error.default.hex_stripped}})",
			border_locked_inactive = "rgb({{colors.surface.default.hex_stripped}})",
		},
		groupbar = {
			col = {
				active = "rgb({{colors.secondary.default.hex_stripped}})",
				inactive = "rgb({{colors.surface.default.hex_stripped}})",
				locked_active = "rgb({{colors.error.default.hex_stripped}})",
				locked_inactive = "rgb({{colors.surface.default.hex_stripped}})",
			},
		},
	},
})
