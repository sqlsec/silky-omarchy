-- Match the main WeChat window, excluding auxiliary windows and fullscreen.
o.window({
  class = "^wechat$",
  initial_title = "^(微信|WeChat)$",
  fullscreen = false,
}, {
  opacity = "0.91 override 0.91 override",
  no_blur = false,
  rounding = 18,
  rounding_power = 3,
  border_size = 1,
  border_color = {
    colors = { "rgba(ffffff78)", "rgba(bdcbe225)", "rgba(ffffff40)" },
    angle = 135,
  },
})
