-- Silky Omarchy: completely covered windows stop redrawing until any part of them shows again.
-- Loads the plugin built by scripts/install-occlusion-plugin.sh. The file name carries the Hyprland version it was
-- built for, so after a Hyprland update the stale build is simply not found (re-run the script) instead of failing
-- to load. A build whose ABI no longer matches refuses to load on its own. See docs/02-macshell.md.
--
-- Exempt a window from throttling with a tag, for example:
--   hl.window_rule({ name = "keep-player-live", match = { class = "^mpv$" }, tag = "+silky-live" })
local version = type(hl.version) == "function" and hl.version() or hl.version
local plugin = os.getenv("HOME") .. "/.local/lib/silky-omarchy/silky-occlusion-" .. tostring(version) .. ".so"

local file = io.open(plugin, "r")
if file then
  file:close()
  hl.plugin.load(plugin)
end
