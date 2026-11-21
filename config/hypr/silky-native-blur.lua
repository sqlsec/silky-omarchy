-- Silky Omarchy: MacShell surfaces use Hyprland's own blur instead of Liquid Glass (see docs/02-macshell.md).
-- With barStyle / dockStyle "blur" MacShell draws a light or dark translucent card and Hyprland blurs what is under it
-- in the same frame, so the glass follows windows without delay. hyprland.lua already covers macdock, macspot and
-- macbarbg; these add the menu bar's popovers (Control Center, menus, notifications), the window switcher, the
-- wallpaper picker and the volume / brightness OSD. ignore_alpha keeps transparent click catchers unblurred.
for _, ns in ipairs({ "macbar", "macswitch", "macwall", "macosd" }) do
  hl.layer_rule({ name = "silky-blur-" .. ns, match = { namespace = ns }, blur = true, ignore_alpha = 0.05 })
end
