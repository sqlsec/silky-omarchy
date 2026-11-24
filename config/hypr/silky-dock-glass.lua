-- Silky Omarchy: Liquid Glass for MacShell Dock, menu bar popovers and overlays, refracted by Hyprland in the same frame.
-- Loads the plugin built by scripts/install-dock-glass-plugin.sh. The file name carries the Hyprland version it was
-- built for, so after a Hyprland update the stale build is simply not found (re-run the script) instead of failing to load.
-- When loaded, Hyprland's native blur is disabled on the plugin-owned layers so nested translucent controls don't double-blur.
-- macbarbg (the thin top menu bar strip) stays on native blur.
local version = type(hl.version) == "function" and hl.version() or hl.version
local plugin = os.getenv("HOME") .. "/.local/lib/silky-omarchy/silky-dock-glass-" .. tostring(version) .. ".so"

local file = io.open(plugin, "r")
if file then
  file:close()
  hl.plugin.load(plugin)
  for _, ns in ipairs({ "macdock", "macbar", "macspot", "macswitch", "macwall", "macosd" }) do
    hl.layer_rule({ name = "silky-liquid-glass-noblur-" .. ns, match = { namespace = ns }, blur = false })
  end
  -- About Omarchy Linux uses the plugin's half-resolution mipmap backdrop blur instead of Hyprland's multi-pass blur.
  hl.window_rule({
    name = "silky-mipmap-blur-about",
    match = { class = "^org\\.quickshell$", initial_title = "^About Omarchy Linux$" },
    no_blur = true,
  })
end
