-- Silky Omarchy: per-app window placement (docs/10-shortcuts.md, "微信图片查看器始终浮动").

-- WeChat's image and video viewer ("图片和视频") opens as its own toplevel. On a tiling workspace it was tiled
-- next to the chat window even when the main window floats. Float it and centre it on every open; WeChat picks
-- the size itself. o.window registers the title as self-floating, so floating-workspace mode leaves it alone too.
o.window({
  class = "^wechat$",
  title = "^图片和视频$",
}, {
  name = "silky-wechat-media-viewer",
  float = true,
  center = true,
})

-- WeChat keeps the viewer alive after you close it and shows the same window again for the next picture, so the
-- open-time rule above only reaches a viewer created after the rule was loaded. On every config load, float and
-- centre any viewer that is still tiled (one opened before the rule existed).
local function float_open_wechat_viewers()
  for _, window in ipairs(hl.get_windows() or {}) do
    if window.class == "wechat" and window.title == "图片和视频" and not window.floating then
      local target = "address:" .. window.address
      hl.dispatch(hl.dsp.window.float({ action = "on", window = target }))
      hl.dispatch(hl.dsp.window.center({ window = target }))
    end
  end
end

hl.on("config.reloaded", float_open_wechat_viewers)
