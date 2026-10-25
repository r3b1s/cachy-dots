-- cachy-dots' additions to dux's Hyprland config. Linked to
-- ~/.config/hypr/cachy.lua and loaded by the one line cachy-session appends to
-- dux's hyprland.lua, require("cachy"), after dux's own modules.
--
-- Binds that only map a chord to an action are in dms/binds-user.lua, dux's own
-- override file (loaded after its stock dms/binds.lua), so its keybind editor can
-- see and change them. Each is an hl.unbind + hl.bind pair: a stock dux chord is
-- replaced, never doubled, and the i3 meaning wins wherever the two disagree.
-- That file is kept in the form the editor writes (sorted, one statement per
-- line, its header the only comment), so an edit made in dux's Settings, which
-- rewrites it through the link into the repo, shows up as just that change.
--
-- This file holds what the editor would drop: the session's environment, its
-- startup programs, and the submaps.

local home = os.getenv("HOME")

-- ── environment ──────────────────────────────────────────────────────────
-- ly reads ~/.xprofile for X sessions only, so this is where Hyprland gets what
-- i3 gets from it: ~/.local/bin on PATH, and the telemetry opt-outs (the
-- environment.d copy of env/telemetry.conf). The scripts pick their Wayland
-- backend from XDG_SESSION_TYPE, so it is set here too, whatever ly passed.
local path = os.getenv("PATH") or "/usr/local/bin:/usr/bin"
if not (":" .. path .. ":"):find(":" .. home .. "/.local/bin:", 1, true) then
	hl.env("PATH", home .. "/.local/bin:" .. path)
end
hl.env("XDG_SESSION_TYPE", "wayland")
local telemetry = io.open(home .. "/.config/environment.d/telemetry.conf")
if telemetry then
	for line in telemetry:lines() do
		local key, value = line:match("^([%a_][%w_]*)=(.*)$")
		if key then
			hl.env(key, value)
		end
	end
	telemetry:close()
end

-- ── startup ──────────────────────────────────────────────────────────────
hl.on("hyprland.start", function()
	-- dux's startup block without systemd only runs `dms run`; the D-Bus
	-- activated services (the portals among them) need the session's
	-- environment as well. The user manager can outlive a logout by a few
	-- seconds, so a quick switch from i3 finds its DISPLAY and its portals still
	-- there: drop i3's display first (XWayland's, if Hyprland has one, comes back
	-- with --all), and stop the portals so the next request starts them with this
	-- session's environment and portal config. A running Sunshine is restarted last,
	-- for this session's display and capture method (install/session.sh).
	hl.exec_cmd("systemctl --user unset-environment DISPLAY XAUTHORITY; dbus-update-activation-environment --systemd --all; systemctl --user stop xdg-desktop-portal.service xdg-desktop-portal-gtk.service xdg-desktop-portal-hyprland.service; systemctl --user try-restart sunshine.service")
	-- Dictation (bin/dictate). voxtype.service hangs off
	-- graphical-session.target, which this session does not reach. A daemon left
	-- by an i3 session outlives it, with i3's environment, so it is replaced.
	hl.exec_cmd('command -v voxtype >/dev/null || exit 0; pkill -x -u "$(id -u)" voxtype && sleep 1; exec voxtype -q daemon')
	-- dux's apps (opt/hyprland.sh), as their own units would start them, for the
	-- same reason: Dux Files hidden in the tray, so $mod+e opens a window at
	-- once; Dux Calendar, which syncs and reminds, and feeds dux's dash; Dux
	-- Search, the index behind the launcher's file search.
	hl.exec_cmd("command -v dfiles >/dev/null && exec dfiles run --session --hidden")
	hl.exec_cmd("command -v dcal >/dev/null && exec dcal run --session --hidden")
	hl.exec_cmd("command -v dsearch >/dev/null && exec dsearch serve")
end)

-- ── window rules ─────────────────────────────────────────────────────────
-- Apps that belong to a named workspace (bin/ws-app launches them when it is
-- empty). ws-app's launch rule only places the first window, and Vesktop opens a
-- loading window before its main one, so its windows are sent there by class:
-- the main window lands on special:slash once the loading one has gone.
hl.window_rule({ match = { class = "^(vesktop)$" }, workspace = "special:slash" })
-- Dux Calendar ($mod+Shift+=). Its daemon is already running (hyprland.start
-- below), so `dcal show` makes the window in that process, not in the one ws-app
-- started: the rule is what puts it on the workspace.
hl.window_rule({ match = { class = "^(dev.duxlabs.calendar)$" }, workspace = "special:plus" })
-- RetroArch (opt/omarchy-retroarch.sh): fullscreen, and no idle lock while it is, as
-- Omarchy's default/hypr/apps/retroarch.lua.
hl.window_rule({ match = { class = "^(com.libretro.RetroArch)$" }, fullscreen = true, idle_inhibit = "fullscreen" })
-- Every Moonlight window belongs to special:moonlight: the client comes back by itself when a
-- stream ends, and the workspace closes with the stream window, so it would land on the
-- regular workspace underneath.
hl.window_rule({ match = { class = "^(com.moonlight_stream.Moonlight)$" }, workspace = "special:moonlight" })
-- Moonlight ($mod+Ctrl+m): the stream window is fullscreen with no idle lock, as Omarchy's
-- default/hypr/apps/moonlight.lua, but not the client. Both share a class; the stream
-- window's title is "<host> - Moonlight" (session.cpp), the client's plain "Moonlight".
hl.window_rule({ match = { class = "^(com.moonlight_stream.Moonlight)$", title = "^.+ - Moonlight$" }, fullscreen = true, idle_inhibit = "fullscreen" })

-- ── submaps ──────────────────────────────────────────────────────────────
local function notify(title, body)
	hl.exec_cmd("dunstify -a cachy-dots -r 9994 '" .. title .. "' '" .. body .. "'")
end

-- passthru, as i3's mode of that name: every key goes to the focused window (a
-- VM viewer, say) until Delete.
hl.define_submap("passthru", function()
	hl.bind("Delete", function()
		hl.dispatch(hl.dsp.submap("reset"))
		notify("Passthrough off", "Hyprland has the keyboard again")
	end)
end)
hl.unbind("SUPER + Delete")
hl.bind("SUPER + Delete", function()
	hl.dispatch(hl.dsp.submap("passthru"))
	notify("Passthrough on", "Every key goes to the window; Delete ends it")
end, { description = "Pass every key to the window (Delete ends it)" })

-- gaps, as i3's mode: h/l the outer gaps left and right, j/k top and bottom,
-- arrows the inner gaps; Return or Escape leaves. Until the next reload, as on i3.
local function gaps(option, dx, dy)
	local g = hl.get_config("general." .. option)
	if type(g) == "number" then
		g = { top = g, right = g, bottom = g, left = g }
	elseif type(g) ~= "table" then
		g = {}
	end
	local function side(v, d)
		return math.max(0, (tonumber(v) or 0) + d)
	end
	local n = { top = side(g.top, dy), right = side(g.right, dx), bottom = side(g.bottom, dy), left = side(g.left, dx) }
	if n.top == n.right and n.right == n.bottom and n.bottom == n.left then
		n = n.top
	end
	hl.config({ general = { [option] = n } })
end

hl.define_submap("gaps", function()
	hl.bind("l", function() gaps("gaps_out", 20, 0) end, { repeating = true })
	hl.bind("h", function() gaps("gaps_out", -20, 0) end, { repeating = true })
	hl.bind("k", function() gaps("gaps_out", 0, 20) end, { repeating = true })
	hl.bind("j", function() gaps("gaps_out", 0, -20) end, { repeating = true })
	hl.bind("Right", function() gaps("gaps_in", 2, 2) end, { repeating = true })
	hl.bind("Up", function() gaps("gaps_in", 2, 2) end, { repeating = true })
	hl.bind("Left", function() gaps("gaps_in", -2, -2) end, { repeating = true })
	hl.bind("Down", function() gaps("gaps_in", -2, -2) end, { repeating = true })
	hl.bind("Return", hl.dsp.submap("reset"))
	hl.bind("Escape", hl.dsp.submap("reset"))
end)
hl.unbind("SUPER + CTRL + G")
hl.bind("SUPER + CTRL + G", function()
	hl.dispatch(hl.dsp.submap("gaps"))
	notify("Gaps", "h/l j/k: outer, arrows: inner, Escape: done")
end, { description = "Adjust gaps" })

-- dictate_suppress: entered and left by bin/dictate around voxtype's paste
-- (pre_output_command and post_output_command). It swallows the modifier keys,
-- since wtype cannot clear physically held ones the way xdotool
-- --clearmodifiers does on X11. Delete leaves it by hand if a paste never ends.
hl.define_submap("dictate_suppress", function()
	hl.bind("Delete", hl.dsp.submap("reset"))
	for _, key in ipairs({ "Super_L", "Super_R", "Alt_L", "Alt_R", "Control_L", "Control_R" }) do
		hl.bind(key, hl.dsp.exec_cmd("true"), { transparent = true, ignore_mods = true })
	end
end)
