-- cachy-dots' part of the Hyprland config, whichever shell runs on it. Copied to
-- ~/.config/hypr/cachy.lua (by import_cachy_lua in install/session.sh) and loaded
-- by the one line graphical-session appends to hyprland.lua, require("cachy"), at
-- the end of it.
--
-- The shell is picked here: HYPR_SHELL or the file graphical-session records it in,
-- and Noctalia unless that says dux. hyprland.lua has dux's own modules and startup
-- commented out for this (ensure_cachy_require), since it would otherwise load them
-- under either shell. dux's run from here, in the order it wrote them.
--
-- Binds that name a shell are in that shell's file: dms/binds-user.lua, dux's own
-- override file (loaded after its stock dms/binds.lua), so its keybind editor can
-- see and change them, and noctalia/binds-user.lua. Each is an hl.unbind + hl.bind
-- pair: a stock dux chord is replaced, never doubled, and the i3 meaning wins
-- wherever the two disagree. The dux file is kept in the form the editor writes
-- (sorted, one statement per line, its header the only comment), so an edit made in
-- dux's Settings, which rewrites it through the link into the repo, shows up as just
-- that change.
--
-- This file holds what is the same under both shells, or what the editor would drop:
-- the session's environment, its startup programs, the compositor's own binds, the
-- window rules, the submaps and eco mode. The compositor's binds come after dux's
-- files, so they win over its editor; a chord that should differ per shell moves to
-- those files.

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

-- ── the shell ────────────────────────────────────────────────────────────
local function get_hypr_shell()
	local env_shell = os.getenv("HYPR_SHELL")
	if env_shell and env_shell ~= "" then
		return env_shell
	end
	local state_file = (os.getenv("XDG_STATE_HOME") or (home .. "/.local/state"))
		.. "/graphical-session/hypr-shell"
	local f = io.open(state_file, "r")
	if f then
		local val = f:read("*l")
		f:close()
		if val and val ~= "" then
			return val
		end
	end
	return "noctalia"
end

local hypr_shell = get_hypr_shell()
-- Set in the session, so a reload keeps the shell it started with, whatever
-- graphical-session has recorded since, and the scripts can pick their backend.
hl.env("HYPR_SHELL", hypr_shell)

if hypr_shell == "dux" then
	require("dms.colors")
	require("dms.outputs")
	require("dms.layout")
	require("dms.cursor")
	require("dms.input")
	require("dms.binds")
	require("dms.binds-user")
	require("dms.windowrules")
else
	require("noctalia.compositor")
	require("noctalia.binds-user")
end

-- ── startup ──────────────────────────────────────────────────────────────
hl.on("hyprland.start", function()
	-- The startup block of dux's hyprland.lua without systemd only ran `dms run`; the D-Bus
	-- activated services (the portals among them) need the session's
	-- environment as well. The user manager can outlive a logout by a few
	-- seconds, so a quick switch from i3 finds its DISPLAY and its portals still
	-- there: drop i3's display first (XWayland's, if Hyprland has one, comes back
	-- with --all), and stop the portals so the next request starts them with this
	-- session's environment and portal config.
	hl.exec_cmd("systemctl --user unset-environment DISPLAY XAUTHORITY; dbus-update-activation-environment --systemd --all; systemctl --user stop xdg-desktop-portal.service xdg-desktop-portal-gtk.service xdg-desktop-portal-hyprland.service")
	if hypr_shell == "dux" then
		hl.exec_cmd("dms run")
		-- dux's apps (opt/hyprland.sh), as their own units would start them, for the
		-- same reason: Dux Files hidden in the tray, so $mod+e opens a window at
		-- once; Dux Calendar, which syncs and reminds, and feeds dux's dash; Dux
		-- Search, the index behind the launcher's file search.
		hl.exec_cmd("command -v dfiles >/dev/null && exec dfiles run --session --hidden")
		hl.exec_cmd("command -v dcal >/dev/null && exec dcal run --session --hidden")
		hl.exec_cmd("command -v dsearch >/dev/null && exec dsearch serve")
	else
		hl.exec_cmd("noctalia")
	end
	-- Opt-in services (opt/services/*).
	local services_file = home .. "/.config/hypr/cachy-services.lua"
	local sf = io.open(services_file, "r")
	if sf then
		sf:close()
		pcall(dofile, services_file)
	end
end)

-- ── window rules ─────────────────────────────────────────────────────────
-- Apps that belong to a named workspace (bin/ws-app launches them when it is
-- empty). ws-app's launch rule only places the first window, and Vesktop opens a
-- loading window before its main one, so its windows are sent there by class:
-- the main window lands on special:slash once the loading one has gone.
hl.window_rule({ match = { class = "^(vesktop)$" }, workspace = "special:slash" })
-- Dux Calendar ($mod+Shift+= under dux). Its daemon is already running (hyprland.start
-- above), so `dcal show` makes the window in that process, not in the one ws-app
-- started: the rule is what puts it on the workspace.
hl.window_rule({ match = { class = "^(dev.duxlabs.calendar)$" }, workspace = "special:plus" })
-- RetroArch (opt/omarchy-retroarch.sh): fullscreen, and no idle lock while it is, as
-- Omarchy's default/hypr/apps/retroarch.lua.
hl.window_rule({ match = { class = "^(com.libretro.RetroArch)$" }, fullscreen = true, idle_inhibit = "fullscreen" })
-- Every Moonlight window belongs to special:ctl_m. The client closes when a stream starts
-- and comes back when it ends, and each time the workspace has closed with the window
-- before the other one opens, so without this the stream window and the client would
-- land on the regular workspace underneath. In Moonlight's exclusive "Fullscreen" display
-- mode the stream window asks for fullscreen on a named output, and Hyprland honours
-- that by moving it to the output's regular workspace, so that part is ignored.
hl.window_rule({ match = { class = "^(com.moonlight_stream.Moonlight)$" }, workspace = "special:ctl_m", suppress_event = "fullscreenoutput" })
-- Moonlight ($mod+Ctrl+m): the stream window is fullscreen with no idle lock, as Omarchy's
-- default/hypr/apps/moonlight.lua, but not the client. Both share a class; the stream
-- window's title is "<host> - Moonlight" (session.cpp), the client's plain "Moonlight".
hl.window_rule({ match = { class = "^(com.moonlight_stream.Moonlight)$", title = "^.+ - Moonlight$" }, fullscreen = true, idle_inhibit = "fullscreen" })

-- ── binds, under both shells ──────────────────────────────────────────────
-- The compositor's own and the repo's scripts: nothing here names a shell. Under dux
-- each replaces the stock chord, if there is one, so rebind is unbind + bind.
local function rebind(chord, action, opts)
	hl.unbind(chord)
	hl.bind(chord, action, opts)
end

-- Windows.
rebind("SUPER + W", hl.dsp.window.close(), { description = "Close window" })
rebind("SUPER + F", hl.dsp.exec_cmd("~/.local/bin/maximize"), { description = "Maximize active window" })
rebind("SUPER + SHIFT + F", hl.dsp.window.fullscreen_state({ internal = 2, client = 0, action = "toggle" }), { description = "Window fullscreen (client unaware)" })
rebind("SUPER + CTRL + F", hl.dsp.window.fullscreen_state({ internal = 0, client = 2, action = "toggle" }), { description = "In-client fullscreen (window unaware)" })
rebind("SUPER + ALT + F", hl.dsp.window.fullscreen_state({ internal = 3, client = 3, action = "toggle" }), { description = "Typical fullscreen" })
rebind("SUPER + SHIFT + CTRL + F", hl.dsp.window.fullscreen_state({ internal = 0, client = 0, action = "set" }), { description = "Default window state" })
rebind("SUPER + SHIFT + CTRL + ALT + F", hl.dsp.window.float({ action = "toggle" }), { description = "Toggle floating" })
rebind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true, description = "Move window" })
rebind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true, description = "Resize window" })

-- Focus, moving, resizing. Each direction by its letter and its arrow.
for _, d in ipairs({ { "H", "left", "l", -20, 0 }, { "J", "down", "d", 0, 20 }, { "K", "up", "u", 0, -20 }, { "L", "right", "r", 20, 0 } }) do
	local letter, arrow, dir, nudge_x, nudge_y = d[1], d[2], d[3], d[4], d[5]
	for _, key in ipairs({ letter, arrow }) do
		rebind("SUPER + " .. key, hl.dsp.focus({ direction = dir }), { description = "Focus " .. arrow })
		rebind("SUPER + SHIFT + " .. key, hl.dsp.window.move({ direction = dir }), { description = "Move window " .. arrow })
		rebind("SUPER + SHIFT + CTRL + " .. key, hl.dsp.window.move({ monitor = dir }), { description = "Move window to " .. arrow .. " monitor" })
	end
	rebind("SUPER + SHIFT + ALT + " .. letter, hl.dsp.window.move({ x = nudge_x, y = nudge_y, relative = true }), { repeating = true, description = "Nudge window " .. arrow })
	rebind("SUPER + SHIFT + ALT + " .. arrow, hl.dsp.workspace.move({ monitor = dir }), { description = "Move workspace to " .. arrow .. " monitor" })
end
rebind("SUPER + CTRL + left", hl.dsp.focus({ monitor = "l" }), { description = "Focus left monitor" })
rebind("SUPER + CTRL + right", hl.dsp.focus({ monitor = "r" }), { description = "Focus right monitor" })
rebind("CTRL + ALT + TAB", hl.dsp.focus({ monitor = "+1" }), { description = "Next monitor" })
rebind("SUPER + Home", hl.dsp.focus({ window = "first" }), { description = "First window" })
rebind("SUPER + End", hl.dsp.focus({ window = "last" }), { description = "Last window" })
rebind("SUPER + CTRL + H", hl.dsp.window.resize({ x = 100, y = 0, relative = true }), { repeating = true, description = "Grow width" })
rebind("SUPER + CTRL + L", hl.dsp.window.resize({ x = -100, y = 0, relative = true }), { repeating = true, description = "Shrink width" })
rebind("SUPER + CTRL + K", hl.dsp.window.resize({ x = 0, y = 100, relative = true }), { repeating = true, description = "Grow height" })
rebind("SUPER + CTRL + J", hl.dsp.window.resize({ x = 0, y = -100, relative = true }), { repeating = true, description = "Shrink height" })
rebind("SUPER + SHIFT + minus", hl.dsp.window.resize({ x = 0, y = -100, relative = true }), { repeating = true, description = "Shrink height" })

-- Layout: what the master chords do needs that layout, and dux's default is dwindle.
rebind("SUPER + R", hl.dsp.layout("togglesplit"), { description = "Toggle split" })
rebind("SUPER + bracketleft", hl.dsp.layout("preselect l"), { description = "Preselect left" })
rebind("SUPER + bracketright", hl.dsp.layout("preselect r"), { description = "Preselect right" })
rebind("SUPER + S", hl.dsp.layout("swapwithmaster"), { description = "Swap Focused Window <-> Master" })
rebind("SUPER + SHIFT + S", hl.dsp.layout("orientationnext"), { description = "Cycle Workspace Orientation (Master Layout)" })
rebind("SUPER + N", hl.dsp.layout("rollprev"), { description = "Roll to Prev Window (Master Layout)" })
rebind("SUPER + SHIFT + N", hl.dsp.layout("rollnext"), { description = "Roll to Next Window (Master Layout)" })
rebind("SUPER + CTRL + S", hl.dsp.window.move({ workspace = "+0" }), { description = "Move window out of the scratchpad" })

-- Numbered workspaces; 0 is 10.
for i = 0, 9 do
	local key, ws = tostring(i), tostring(i == 0 and 10 or i)
	rebind("SUPER + " .. key, hl.dsp.focus({ workspace = ws }), { description = "Workspace " .. ws })
	rebind("SUPER + SHIFT + " .. key, hl.dsp.window.move({ workspace = ws }), { description = "Move window to workspace " .. ws })
	rebind("SUPER + SHIFT + ALT + " .. key, hl.dsp.window.move({ workspace = ws, follow = false }), { description = "Send window to workspace " .. ws })
end
rebind("SUPER + TAB", hl.dsp.focus({ workspace = "e+1" }), { description = "Next workspace" })
rebind("SUPER + SHIFT + TAB", hl.dsp.focus({ workspace = "e-1" }), { description = "Previous workspace" })
rebind("SUPER + CTRL + TAB", hl.dsp.focus({ workspace = "previous" }), { description = "Last workspace" })
for _, key in ipairs({ "Page_Down", "mouse_down" }) do
	rebind("SUPER + " .. key, hl.dsp.focus({ workspace = "e+1" }), { description = "Next workspace" })
end
for _, key in ipairs({ "Page_Up", "mouse_up" }) do
	rebind("SUPER + " .. key, hl.dsp.focus({ workspace = "e-1" }), { description = "Previous workspace" })
end
for _, chord in ipairs({ "SUPER + CTRL + down", "SUPER + CTRL + U", "SUPER + CTRL + mouse_down", "SUPER + SHIFT + Page_Down", "SUPER + SHIFT + U" }) do
	rebind(chord, hl.dsp.window.move({ workspace = "e+1" }), { description = "Move window to next workspace" })
end
for _, chord in ipairs({ "SUPER + CTRL + up", "SUPER + CTRL + mouse_up", "SUPER + SHIFT + Page_Up", "SUPER + SHIFT + I" }) do
	rebind(chord, hl.dsp.window.move({ workspace = "e-1" }), { description = "Move window to previous workspace" })
end

-- Named workspaces (bin/ws-app; AGENTS.md has the naming). Plain ones toggle, the
-- others launch their app into an empty one, and each can be sent a window.
rebind("SUPER + Q", hl.dsp.workspace.toggle_special("q"), { description = "Workspace q" })
rebind("SUPER + Y", hl.dsp.workspace.toggle_special("y"), { description = "Workspace y" })
rebind("SUPER + comma", hl.dsp.workspace.toggle_special("comma"), { description = "Workspace comma" })
rebind("SUPER + minus", hl.dsp.workspace.toggle_special("minus"), { description = "Workspace minus" })
rebind("SUPER + period", hl.dsp.workspace.toggle_special("period"), { description = "Workspace period" })
rebind("SUPER + SHIFT + P", hl.dsp.workspace.toggle_special("sft_p"), { description = "Plain workspace sft_p" })
rebind("SUPER + A", hl.dsp.exec_cmd("~/.local/bin/ws-app a claude-desktop"), { description = "Claude workspace" })
rebind("SUPER + G", hl.dsp.exec_cmd("~/.local/bin/ws-app g $TERMINAL"), { description = "Second terminal workspace" })
rebind("SUPER + I", hl.dsp.exec_cmd("~/.local/bin/ws-app i ~/.local/bin/default-browser launch https://www.onelook.com/thesaurus"), { description = "Thesaurus workspace" })
rebind("SUPER + M", hl.dsp.exec_cmd("~/.local/bin/ws-app m grayjay"), { description = "Grayjay workspace" })
rebind("SUPER + O", hl.dsp.exec_cmd("~/.local/bin/ws-app o obsidian"), { description = "Obsidian workspace" })
rebind("SUPER + T", hl.dsp.exec_cmd("~/.local/bin/ws-app t $TERMINAL"), { description = "Terminal workspace" })
rebind("SUPER + U", hl.dsp.exec_cmd("~/.local/bin/ws-app u qutebrowser"), { description = "Browser workspace" })
rebind("SUPER + Z", hl.dsp.exec_cmd("~/.local/bin/ws-app --notify 'ZAProxy' 'now launching...' z ~/.local/bin/zaproxy"), { description = "ZAP workspace" })
rebind("SUPER + equal", hl.dsp.exec_cmd("~/.local/bin/ws-app equal thunderbird"), { description = "Thunderbird workspace" })
rebind("SUPER + slash", hl.dsp.exec_cmd("~/.local/bin/ws-app slash vesktop"), { description = "Vesktop workspace" })
rebind("SUPER + CTRL + M", hl.dsp.exec_cmd("~/.local/bin/ws-app ctl_m moonlight"), { description = "Moonlight workspace" })
for _, ws in ipairs({ "A", "G", "I", "M", "O", "Q", "T", "U", "Y", "Z", "comma", "equal", "minus", "period", "slash" }) do
	local name = #ws == 1 and ws:lower() or ws
	rebind("SUPER + SHIFT + CTRL + " .. ws, hl.dsp.window.move({ workspace = "special:" .. name, follow = false }), { description = "Send window to " .. name })
end

-- Applications.
rebind("SUPER + B", hl.dsp.exec_cmd("~/.local/bin/default-browser launch"), { description = "Default browser" })
rebind("SUPER + SHIFT + CTRL + B", hl.dsp.exec_cmd("~/.local/bin/default-browser launch --private"), { description = "Default browser, private" })
rebind("SUPER + SHIFT + B", hl.dsp.exec_cmd("qutebrowser"), { description = "qutebrowser" })
rebind("SUPER + CTRL + B", hl.dsp.exec_cmd("firefox"), { description = "Firefox" })
rebind("SUPER + ALT + B", hl.dsp.exec_cmd("chromium"), { description = "Chromium" })
rebind("SUPER + SHIFT + T", hl.dsp.exec_cmd("$TERMINAL"), { description = "New terminal" })
rebind("SUPER + SHIFT + E", hl.dsp.exec_cmd("$TERMINAL -e yazi"), { description = "yazi" })
rebind("SUPER + SHIFT + O", hl.dsp.exec_cmd("obsidian"), { description = "New Obsidian window" })
rebind("SUPER + D", hl.dsp.exec_cmd("~/.local/bin/dictate toggle"), { description = "Dictation" })
rebind("SUPER + Print", hl.dsp.exec_cmd("~/.local/bin/screenshot ocr"), { description = "Copy text in a region (OCR)" })
rebind("SUPER + SHIFT + semicolon", hl.dsp.exec_cmd("~/.local/bin/screenshot annotate-region"), { description = "Annotate a region" })
rebind("SUPER + CTRL + semicolon", hl.dsp.exec_cmd("~/.local/bin/screenshot annotate-full"), { description = "Annotate the screen" })

-- The session.
rebind("SUPER + SHIFT + R", hl.dsp.exec_cmd("hyprctl reload"), { description = "Reload Hyprland" })
rebind("SUPER + SHIFT + CTRL + ALT + C", hl.dsp.exec_cmd("hyprctl reload"), { description = "Reload Hyprland" })

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

-- ── eco mode ─────────────────────────────────────────────────────────────
-- Hyprland's own effects off, to save battery. Only what the compositor draws: what
-- a shell animates inside its own surfaces stays, and so does an app's own
-- transparency. Blur behind a shell's surfaces is Hyprland's, so that goes.
--
-- Last in the file, so it wins over the shells' modules and outlasts a reload, which
-- a theme change or dux's Settings set off at any time. The flag lives in Hyprland's
-- instance directory, so the next login starts with the mode off. Both directions
-- are a reload, which also brings every value back from the files: no snapshot to go
-- stale, though gaps set by hand in the gaps submap go too.
local eco_flag = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/hypr/"
	.. (os.getenv("HYPRLAND_INSTANCE_SIGNATURE") or "") .. "/eco-mode"

local function eco_active()
	local f = io.open(eco_flag, "r")
	if f then
		f:close()
	end
	return f ~= nil
end

if eco_active() then
	hl.config({
		animations = { enabled = false },
		decoration = {
			blur = { enabled = false, special = false, popups = false, input_methods = false },
			shadow = { enabled = false },
			glow = { enabled = false },
			wobble = { enabled = false },
			motion_blur = { enabled = false },
			screen_shader = "",
			active_opacity = 1,
			inactive_opacity = 1,
			fullscreen_opacity = 1,
			dim_inactive = false,
			dim_special = 1,
			rounding = 0,
		},
		general = { gaps_in = 0, gaps_out = 0, border_size = 1 },
	})
end

rebind("SUPER + SHIFT + CTRL + ALT + G", function()
	if eco_active() then
		os.remove(eco_flag)
		notify("Eco mode off", "Compositor effects restored")
	else
		local f = io.open(eco_flag, "w")
		if f then
			f:close()
		end
		notify("Eco mode on", "Compositor effects off, no gaps or rounding")
	end
	hl.exec_cmd("hyprctl reload")
end, { description = "Toggle eco mode" })
