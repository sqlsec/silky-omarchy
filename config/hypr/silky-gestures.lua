-- Silky Omarchy: touch-screen workspace swipes and the end-of-list rubber band.
-- Loads the plugin built by scripts/install-silky-gestures.sh. The file name carries the Hyprland version it was
-- built for, so after a Hyprland update the stale build is simply not found (re-run the script) instead of failing to load.
local version = type(hl.version) == "function" and hl.version() or hl.version
local plugin = os.getenv("HOME") .. "/.local/lib/silky-omarchy/silky-gestures-" .. tostring(version) .. ".so"

local file = io.open(plugin, "r")
if file then
  file:close()
  hl.plugin.load(plugin)
end

-- The plugin handles the screen edges itself (wider zone, taps still reach the app), so the built-in edge swipe stays off.
hl.config({ gestures = { workspace_swipe_touch = false } })

-- Launchpad: the plugin also turns a four- or five-finger pinch (touchpad or touch screen) into MacShell's Applications
-- panel, following the fingers both ways. hl.gesture's pinch actions only fire once the fingers lift, so they are not used.

-- Window overview: the plugin also registers a four-finger VERTICAL touchpad gesture (up: every window of the workspace,
-- down: every window of the focused app) and streams it to MacShell's SilkyOverview. Do not add a four-finger vertical
-- hl.gesture here: it would take the swipe and the plugin would step aside.
-- The overview layer is parked off-screen while closed and moved on screen by the swipe itself: no Hyprland open / close
-- animation of its own (it would fade in on top of the finger-driven one).
hl.layer_rule({ name = "silkyoverview", match = { namespace = "silkyoverview" }, no_anim = true })
