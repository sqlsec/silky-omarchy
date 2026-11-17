-- Silky Omarchy: Omarchy's own menus (Super+Esc, Super+Ctrl+M, clipboard, emojis) as macOS 27 glass.
-- The colours come from bin/silky-menu-glass (light / dark with the system); this file adds the blur behind
-- the card and the font. ignore_alpha keeps the invisible full-screen click catcher around the card unblurred.
for _, ns in ipairs({ "omarchy-menu", "omarchy-clipboard", "omarchy-emojis" }) do
  hl.layer_rule({ name = "silky-" .. ns, match = { namespace = ns }, blur = true, ignore_alpha = 0.05 })
end

-- A proportional face like macOS menus instead of the terminal font. Read by the Omarchy shell when it starts
-- (omarchy-restart-shell spawns it from Hyprland, so it inherits this).
hl.env("OMARCHY_MENU_FONT", "Inter")
