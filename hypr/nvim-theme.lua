-- Neovim's colours under Hyprland: ~/.config/nvim/lua/plugins/theme.lua links here
-- while that session is active (install/session.sh), and to x11-theme's rendered
-- aether.nvim spec under i3. dux's own colourscheme, `dms`, which dux's matugen
-- template writes to ~/.config/nvim/colors/dms.lua and which needs its base46
-- plugin; it follows dux's colours as they change. dux's Neovim template is off by
-- default, so opt/hyprland.sh turns it on.
return {
	{ "duxlabs-dev/base46", lazy = true, opts = {} },
	{ "LazyVim/LazyVim", opts = { colorscheme = "dms" } },
}
