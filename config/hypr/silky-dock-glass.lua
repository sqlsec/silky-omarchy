-- Silky Omarchy (prototype): Liquid Glass for the MacShell Dock, refracted by Hyprland in the same frame.
-- Loads the plugin built by scripts/install-dock-glass-plugin.sh. The file name carries the Hyprland version it was
-- built for, so after a Hyprland update the stale build is simply not found (re-run the script) instead of failing to load.
-- Without the plugin, MacDock (SILKY_DOCK_GLASS_PLUGIN=1) has no glass of its own: re-run the script or roll back.
local version = type(hl.version) == "function" and hl.version() or hl.version
local plugin = os.getenv("HOME") .. "/.local/lib/silky-omarchy/silky-dock-glass-" .. tostring(version) .. ".so"

local file = io.open(plugin, "r")
if file then
  file:close()
  hl.plugin.load(plugin)
end
