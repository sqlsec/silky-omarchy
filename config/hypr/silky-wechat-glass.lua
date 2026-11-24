-- Chat text and media use the application’s own surfaces at full opacity.
o.window({
  class = "^wechat$",
  initial_title = "^(微信|WeChat)$",
}, {
  opacity = "1.0 override 1.0 override 1.0 override",
  rounding = 18,
  rounding_power = 3,
  border_size = 0,
  no_blur = true,
})

-- WeChat’s opaque windows and floating popups (context menus, sticker previews/suggestions)
-- draw their own shadow margins; skip compositor blur so those transparent paddings never
-- turn into frosted halos.
o.window({
  class = "^wechat$",
}, {
  name = "silky-wechat-no-blur",
  no_blur = true,
})

-- Untitled / "wechat"-titled WeChat popups (message context menus, sticker previews,
-- sticker suggestion bar) already paint their own card border and shadow; drop
-- Hyprland’s extra frame, rounding, shadow and blur.
o.window({
  class = "^wechat$",
  title = "^(|wechat)$",
}, {
  name = "silky-wechat-popup-clean",
  opacity = "1.0 override 1.0 override 1.0 override",
  no_blur = true,
  no_shadow = true,
  border_size = 0,
  rounding = 0,
})
