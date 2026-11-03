-- The binds that name the shell, under Noctalia: linked to
-- ~/.config/hypr/noctalia/binds-user.lua and loaded by hypr/cachy.lua. The chords of
-- hypr/dms/binds-user.lua and of the dux stock binds that survive it, each given to
-- what Noctalia has for it; what both shells share is in hypr/cachy.lua. Two dux
-- chords have no counterpart, so they are unbound here: $mod+Alt+r (rename a
-- workspace) and $mod+Shift+w (window rules).
local ipc = "noctalia msg "

local function msg(chord, command, opts)
	hl.bind(chord, hl.dsp.exec_cmd(ipc .. command), opts)
end

-- The launcher, and the panels it shares a surface with.
msg("SUPER + Return", "panel-toggle launcher", { description = "App launcher" })
msg("SUPER + space", "panel-toggle launcher", { description = "App launcher" })
msg("ALT + space", "panel-toggle launcher", { description = "App launcher" })
msg("SUPER + CTRL + E", "panel-toggle launcher /emo", { description = "Emoji picker" })
msg("SUPER + ALT + space", "window-switcher", { description = "Window switcher" })
msg("SUPER + CTRL + V", "panel-toggle clipboard", { description = "Clipboard history" })
msg("SUPER + V", "panel-toggle clipboard", { description = "Clipboard history" })
msg("SUPER + CTRL + space", "panel-toggle wallpaper", { description = "Wallpaper picker" })
msg("SUPER + CTRL + W", "wallpaper-next", { description = "Next wallpaper" })
msg("SUPER + SHIFT + CTRL + space", "settings-toggle", { description = "Settings" })
msg("SUPER + CTRL + equal", "panel-toggle control-center calendar", { description = "Calendar" })

-- Noctalia's own colour picker and keybind pages cannot be reached from outside.
hl.bind("SUPER + SHIFT + CTRL + ALT + P", hl.dsp.exec_cmd("hyprpicker -a"), { description = "Colour picker" })
hl.bind("SUPER + SHIFT + C", hl.dsp.exec_cmd("hyprpicker -a"), { description = "Colour picker" })
hl.bind("SUPER + SHIFT + CTRL + ALT + K", hl.dsp.exec_cmd("~/.local/bin/hypr-keybinds-menu"), { description = "Keybind cheatsheet" })
hl.bind("SUPER + SHIFT + Slash", hl.dsp.exec_cmd("~/.local/bin/hypr-keybinds-menu"), { description = "Keybind cheatsheet" })

-- System monitor: Noctalia has no process list, so btop stands in for dux's, floating
-- and centred, opened, focused or closed by the same chord (bin/hypr-btop).
hl.bind("SUPER + P", hl.dsp.exec_cmd("~/.local/bin/hypr-btop"), { description = "System monitor" })
hl.bind("CTRL + ALT + Delete", hl.dsp.exec_cmd("~/.local/bin/hypr-btop"), { description = "System monitor" })
hl.bind("CTRL + ALT + M", hl.dsp.exec_cmd("~/.local/bin/hypr-btop"), { description = "System monitor" })

-- Files: nautilus, as under i3.
hl.bind("SUPER + E", hl.dsp.exec_cmd("nautilus --new-window"), { description = "Files (nautilus)" })

-- The session.
msg("SUPER + Escape", "panel-toggle session", { description = "Power menu" })
msg("XF86PowerOff", "panel-toggle session", { description = "Power menu" })
msg("SUPER + CTRL + Escape", "session lock", { description = "Lock" })
msg("SUPER + ALT + L", "session lock", { description = "Lock" })
msg("SUPER + CTRL + I", "caffeine-toggle", { description = "Toggle idle inhibit" })
msg("SUPER + ALT + I", "caffeine-toggle", { description = "Toggle idle inhibit" })
msg("SUPER + CTRL + N", "nightlight-force-toggle", { description = "Toggle night mode" })
msg("SUPER + ALT + N", "nightlight-force-toggle", { description = "Toggle night mode" })
msg("SUPER + SHIFT + space", "bar-toggle", { description = "Toggle the bar" })
msg("SUPER + SHIFT + CTRL + ALT + D", "theme-mode-toggle", { description = "Toggle dark and light mode" })

-- Notifications.
msg("SUPER + X", "notification-clear-active", { description = "Dismiss notifications" })
msg("SUPER + SHIFT + X", "notification-clear-active", { description = "Dismiss all notifications" })
msg("SUPER + CTRL + X", "notification-dnd-toggle", { description = "Toggle do not disturb" })
msg("SUPER + ALT + X", "panel-toggle control-center notifications", { description = "Notification center" })

-- Clipboard.
hl.bind("SUPER + SHIFT + CTRL + ALT + V", hl.dsp.exec_cmd("wl-copy --clear; wl-copy --primary --clear; noctalia msg clipboard-clear"), { description = "Wipe clipboard history" })

-- Screenshots.
msg("SUPER + semicolon", "screenshot-region --annotate", { description = "Screenshot, region" })
msg("Print", "screenshot-fullscreen", { description = "Screenshot, full screen" })
msg("CTRL + Print", "screenshot-fullscreen", { description = "Screenshot, full screen" })
msg("ALT + Print", "screenshot-window", { description = "Screenshot, window" })

-- Volume and brightness, 3% and 5% steps as under dux, 1% with Alt.
local held = { locked = true, repeating = true }
msg("XF86AudioRaiseVolume", "volume-up 3", held)
msg("XF86AudioLowerVolume", "volume-down 3", held)
msg("ALT + XF86AudioRaiseVolume", "volume-up 1", { locked = true, repeating = true, description = "Volume up 1%" })
msg("ALT + XF86AudioLowerVolume", "volume-down 1", { locked = true, repeating = true, description = "Volume down 1%" })
msg("XF86AudioMute", "volume-mute", { locked = true })
msg("XF86AudioMicMute", "mic-mute", { locked = true })
msg("SUPER + SHIFT + M", "mic-mute", { description = "Mute microphone" })
msg("XF86MonBrightnessUp", "brightness-up", held)
msg("XF86MonBrightnessDown", "brightness-down", held)
msg("ALT + XF86MonBrightnessUp", "brightness-up current 1", { locked = true, repeating = true, description = "Brightness up 1%" })
msg("ALT + XF86MonBrightnessDown", "brightness-down current 1", { locked = true, repeating = true, description = "Brightness down 1%" })

-- Media.
msg("XF86AudioPlay", "media toggle", { locked = true })
msg("XF86AudioPause", "media toggle", { locked = true })
msg("XF86AudioNext", "media next", { locked = true })
msg("XF86AudioPrev", "media previous", { locked = true })
msg("XF86AudioStop", "media stop", { locked = true, description = "Stop playback" })
msg("CTRL + XF86AudioRaiseVolume", "media volume-up 3", held)
msg("CTRL + XF86AudioLowerVolume", "media volume-down 3", held)
