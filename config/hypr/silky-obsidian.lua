-- Silky Omarchy: native Hyprland blur behind Obsidian's translucent sidebar while
-- keeping the editor pane opaque (docs/15-obsidian.md).
-- Chromium on Wayland marks wl_surface.opaque_region full-window, so Hyprland skips
-- compositor blur at exact 1.0 opacity; 0.995 triggers the blur pass without visibly
-- thinning the solid editor surface, and fullscreen stays 1.0.
hl.window_rule({
  name = "silky-obsidian-glass",
  match = { class = "^md\\.obsidian\\.Obsidian$" },
  opacity = "0.995 override 0.995 override 1.0 override",
  xray = false,
  border_size = 0,
})
