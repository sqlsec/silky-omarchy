-- Map new windows at their final size and opacity to avoid exposing the desktop on open.
hl.animation({ leaf = "windowsIn", enabled = false })
hl.animation({ leaf = "fadeIn", enabled = false })

-- Firefox-based browsers are opaque; skipping compositor blur prevents the
-- first-frame GTK3 CSD shadow margin from flashing as a blurred halo.
hl.window_rule({
  name = "silky-firefox-no-blur",
  match = { tag = "firefox-based-browser" },
  no_blur = true,
})

-- Firefox maps detached extension windows with a generic title first, so
-- Omarchy's floating workspace can give Passbolt the standard app size.
local function fit_passbolt_popup(window)
  if window.class ~= "firefox" or not window.title:match("^Extension: %(Passbolt [^)]*%) %- Passbolt — Mozilla Firefox$") then
    return
  end

  if not window.floating then
    hl.dispatch(hl.dsp.window.float({ action = "on", window = window }))
  end
  if window.size.x ~= 380 or window.size.y > 400 then
    hl.dispatch(hl.dsp.window.resize({
      x = 380,
      y = math.min(window.size.y, 400),
      relative = false,
      window = window,
    }))
  end
end

hl.on("window.open", fit_passbolt_popup)
hl.on("window.title", fit_passbolt_popup)
hl.on("config.reloaded", function()
  for _, window in ipairs(hl.get_windows({ class = "firefox" })) do
    fit_passbolt_popup(window)
  end
end)

-- Silky Omarchy: MacShell's own windows (About This Mac, Settings, Clock, Installer: class org.quickshell).
--
-- * float on their own account: Omarchy's floating-workspace mode then leaves them alone. Otherwise it resizes every
--   new window to its standard 1100x760 box, which stretches the narrow macOS-style About window.
-- * no Hyprland border and centred from the first frame: these windows draw their own macOS edge, and they only
--   switched Hyprland's border off from a timer after they were already on screen, so the white 1 px outline showed
--   for a few frames of the open animation and then snapped away.
o.window("^(org\\.quickshell)$", { float = true, center = true, border_size = 0 })

-- AppAbout ("关于 <App>" / "About <App>") draws its own 18 px rounded card.
-- Skip compositor blur and match its 18 px radius to avoid a blurred halo.
hl.window_rule({
  name = "silky-app-about-no-blur",
  match = { class = "^org\\.quickshell$", initial_title = "^(关于 |About )" },
  no_blur = true,
  rounding = 18,
})
-- About Omarchy Linux uses the window backdrop, with the same tint as the system menu.
hl.window_rule({
  name = "silky-about-omarchy-glass",
  match = { class = "^org\\.quickshell$", initial_title = "^About Omarchy Linux$" },
  no_blur = false,
  xray = false,
  rounding = 18,
})

-- These are transparent, click-through animation/control overlays. Compositor blur on them blurred the whole desktop
-- while a restored window was handing over from its captured copy to the real surface.
hl.layer_rule({ name = "silky-minimize-fx", match = { namespace = "^macshell-minimize$" }, no_anim = true, animation = "none", blur = false })
hl.layer_rule({ name = "silky-window-controls", match = { namespace = "^macwinbar$" }, no_anim = true, animation = "none", blur = false })
