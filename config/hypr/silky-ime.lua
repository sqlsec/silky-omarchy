-- Silky Omarchy: crisp, glassy WowType / fcitx5 candidate window (docs/09-wowtype-glass.md).

-- WeChat draws its own candidate bar (its bundled fcitx5-qt client) as a Wayland popup and
-- recreates that popup on every keystroke. With popup fades on, the old bar fades out over
-- the new one, which reads as a blurry double image. Popups appear instantly instead.
hl.animation({ leaf = "fadePopups", enabled = false })

-- Frosted glass behind fcitx5's own candidate window (every other app). The transparent
-- rounded corners of the Silky Glass skin stay unblurred.
hl.config({
  decoration = {
    blur = {
      input_methods = true,
      input_methods_ignorealpha = 0.1,
      popups = true,
      popups_ignorealpha = 0.1,
    },
  },
})

-- Let Fcitx place and size its XWayland candidate popup at the text caret.
-- o.window registers the class as self-floating in Omarchy, so the workspace
-- does not apply its default window size or cascading position to the popup.
o.window({
  xwayland = true,
  class = "^fcitx$",
  initial_title = "^Fcitx5 Input Window$",
}, {
  name = "silky-fcitx-xwayland-candidate",
  float = true,
  no_blur = true,
  no_anim = true,
})

-- Match Fcitx5's XWayland candidate panel to the primary display's scale.
o.exec_on_start(os.getenv("HOME") .. "/.local/bin/silky-xwayland-dpi")

-- WPS Writer supplies its own geometry for the selection mini toolbar.
-- Keep no_initial_focus so the selection mini toolbar does not steal focus from the
-- document window (under click-to-focus, stealing focus turns the next drag-selection into
-- dragging/pasting the previous selection instead of starting a fresh selection).
o.window({
  xwayland = true,
  initial_class = "^wps$",
  title = "^wps$",
}, {
  name = "silky-wps-mini-toolbar",
  float = true,
  no_anim = true,
  no_blur = true,
  no_shadow = true,
  no_initial_focus = true,
})
