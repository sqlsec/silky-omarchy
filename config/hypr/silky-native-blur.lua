-- Silky Omarchy: MacShell surfaces use Hyprland's own blur instead of Liquid Glass (see docs/02-macshell.md).
-- With barStyle / dockStyle "blur" MacShell draws a light or dark translucent card and Hyprland blurs what is under it
-- in the same frame, so the glass follows windows without delay. hyprland.lua already covers macdock, macspot and
-- macbarbg; these add the menu bar's popovers (Control Center, menus, notifications), the window switcher, the
-- wallpaper picker and the volume / brightness OSD. ignore_alpha keeps transparent click catchers unblurred.
for _, ns in ipairs({ "macbar", "macswitch", "macwall", "macosd" }) do
  hl.layer_rule({ name = "silky-blur-" .. ns, match = { namespace = ns }, blur = true, ignore_alpha = 0.05 })
end

if silky_cached_window_blur then
  -- Keep the tuned blur passes and shader blend. A wallpaper-only cache can
  -- show the wallpaper through a new window while it submits its first buffers.
  -- Instead, disable compositor blur for ordinary windows by default and keep
  -- live backdrop blur only on windows with translucent glass surfaces.
  hl.config({
    decoration = { blur = { new_optimizations = true, passes = 2 } },
    render = { use_shader_blur_blend = true },
  })

  hl.window_rule({
    name = "silky-blur-default-off",
    match = { class = ".*" },
    no_blur = true,
  })
  hl.window_rule({
    name = "silky-blur-allowlist-apps",
    match = { class = "^(folio|md\\.obsidian\\.Obsidian|org\\.gnome\\.Nautilus)$" },
    no_blur = false,
  })
  hl.window_rule({
    name = "silky-blur-allowlist-macshell",
    match = { class = "^org\\.quickshell$", initial_title = "^(About Omarchy Linux|macshell Settings)$" },
    no_blur = false,
  })
end
