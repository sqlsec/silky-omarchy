-- Chat text and media use the application’s own surfaces at full opacity.
o.window({
  class = "^wechat$",
  initial_title = "^(微信|WeChat)$",
}, {
  opacity = "1.0 override 1.0 override 1.0 override",
  rounding = 18,
  rounding_power = 3,
  border_size = 0,
})
