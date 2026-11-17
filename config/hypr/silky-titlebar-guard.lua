-- Silky Omarchy: must be required BEFORE require("default.hypr.omarchy") in hyprland.lua.
--
-- On floating workspaces Omarchy loads its titlebar plugin (omarchy-hyprland-titlebars, a hyprbars build) and adds
-- three square buttons (× □ −) on the right. Under a macOS Tahoe theme, hypr/silky-macos.lua replaces them with round
-- traffic lights; buttons can only be added, never removed, so Omarchy's are skipped here as they are added.
local function read(path)
  local file = io.open(path, "r")
  if not file then return "" end
  local text = file:read("*a")
  file:close()
  return text
end

local theme = read(os.getenv("HOME") .. "/.local/state/omarchy/current/theme.name"):gsub("%s+", "")
silky_macos_titlebars = theme:match("^macos%-tahoe") ~= nil

local bars = hl.plugin and hl.plugin.hyprbars
if silky_macos_titlebars and bars and bars.add_button and not bars.silky_add_button then
  bars.silky_add_button = bars.add_button
  bars.add_button = function() end
end
