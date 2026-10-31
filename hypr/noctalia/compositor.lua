-- What the Hyprland config needs under Noctalia and dux's modules would set: linked to
-- ~/.config/hypr/noctalia/compositor.lua and loaded by hypr/cachy.lua in their place.
-- dux's defaults first, so a host with no dux gets the same monitors and layout.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })
hl.config({
	general = { gaps_in = 4, gaps_out = 4, border_size = 2 },
	decoration = { rounding = 12 },
})
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

-- A host that also runs dux keeps what dux's Settings wrote for it: its monitor
-- layout, input and layout choices. Not dux's colours or binds.
local home = os.getenv("HOME")
for _, name in ipairs({ "outputs", "layout", "cursor", "input", "windowrules" }) do
	local f = io.open(home .. "/.config/hypr/dms/" .. name .. ".lua")
	if f then
		f:close()
		require("dms." .. name)
	end
end

-- The borders follow the palette: on-theme-change copies Noctalia's render here and
-- reloads Hyprland when it differs. Not there until its first start.
local colours = io.open(home .. "/.config/hypr/noctalia/colors.lua")
if colours then
	colours:close()
	require("noctalia.colors")
end

-- From Noctalia's Hyprland page: its settings window, and blur for its surfaces with
-- Hyprland's own layer animations off, since they would fight Noctalia's.
hl.window_rule({ match = { class = "dev.noctalia.Noctalia" }, float = true, size = { 1080, 920 } })
-- btop ($mod+p, bin/hypr-btop): floating and centred, as dux's process list.
hl.window_rule({ match = { class = "^(cachy-btop)$" }, float = true, center = true, size = { "monitor_w*0.7", "monitor_h*0.75" } })
hl.layer_rule({
	name = "noctalia",
	match = { namespace = "^noctalia-(bar-.+|notification|dock|panel|attached-panel|osd|window-switcher)$" },
	no_anim = true,
	ignore_alpha = 0.5,
	blur = true,
	blur_popups = true,
})
