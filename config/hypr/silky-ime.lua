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
