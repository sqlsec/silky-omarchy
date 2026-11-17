-- Silky Omarchy: Super+K opens Silky Keys, a searchable keyboard-shortcut panel in MacShell's macOS 27 look
-- (keys-panel/ in this repo, installed to ~/.config/quickshell/SilkyKeys). Needs hypr/silky-keys-registry.lua,
-- required at the top of hyprland.lua, for the list of binds.
hl.on("hyprland.start", function()
  hl.exec_cmd("qs -c SilkyKeys")
end)

-- Starts the panel first if it is not running (first press after an update, or after a crash).
o.rebind("SUPER + K", "Keybindings",
  "sh -c 'qs -c SilkyKeys ipc call keys toggle 2>/dev/null || { qs -c SilkyKeys -d && sleep 0.6 && qs -c SilkyKeys ipc call keys open; }'")

-- Frosted glass behind the card; the card animates itself.
hl.layer_rule({ name = "silky-keys", match = { namespace = "silky-keys" }, blur = true, ignore_alpha = 0.05, no_anim = true })
