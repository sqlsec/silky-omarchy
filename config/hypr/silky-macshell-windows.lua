-- Silky Omarchy: MacShell's own windows (About This Mac, Settings, Clock, Installer: class org.quickshell).
--
-- * float on their own account: Omarchy's floating-workspace mode then leaves them alone. Otherwise it resizes every
--   new window to its standard 1100x760 box, which stretches the narrow macOS-style About window.
-- * no Hyprland border and centred from the first frame: these windows draw their own macOS edge, and they only
--   switched Hyprland's border off from a timer after they were already on screen, so the white 1 px outline showed
--   for a few frames of the open animation and then snapped away.
o.window("^(org\\.quickshell)$", { float = true, center = true, border_size = 0 })

-- These are transparent, click-through animation/control overlays. Compositor blur on them blurred the whole desktop
-- while a restored window was handing over from its captured copy to the real surface.
hl.layer_rule({ name = "silky-minimize-fx", match = { namespace = "^macshell-minimize$" }, no_anim = true, animation = "none", blur = false })
hl.layer_rule({ name = "silky-window-controls", match = { namespace = "^macwinbar$" }, no_anim = true, animation = "none", blur = false })
