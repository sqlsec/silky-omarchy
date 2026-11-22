-- Silky Omarchy: per-app window placement (docs/10-shortcuts.md, "微信图片查看器始终浮动").

-- Prevent WeChat from stealing focus and popping above other floating windows on new messages or
-- background activation requests (matching Omarchy's default rule for Telegram).
o.window("^wechat$", {
  name = "silky-wechat-no-focus-steal",
  focus_on_activate = false,
})

-- WeChat's image and video viewer ("图片和视频") opens as its own toplevel. On a tiling workspace it was tiled
-- next to the chat window even when the main window floats. Float it and centre it on every open. WeChat sizes
-- it itself, which came out full-height on this screen (874px tall on a 920px logical screen, at y=-29, right
-- under the menu bar), so also pin a moderate default size; it stays freely resizable afterwards and WeChat's
-- own zoom is unaffected. o.window registers the title as self-floating, so floating-workspace mode leaves it
-- alone too. Sizes are logical pixels (screen: 1472x920 @ scale 2).
o.window({
  class = "^wechat$",
  title = "^图片和视频$",
}, {
  name = "silky-wechat-media-viewer",
  float = true,
  center = true,
  size = { 900, 620 },
})

-- The chat-history window ("群名"的聊天记录(条数)) opens oversized too, with large empty side margins from
-- WeChat's own layout. Float, centre and pin a moderate default size; matched without anchors so it hits any
-- chat/group name. Only WeChat windows carry this string in their title. Height floor: WeChat refuses any
-- size below 720 logical px for this window (2026-11-20: requests for 600/640/660/700 all snapped back to
-- 720; growing works), so 720 is as small as it gets - the win is the narrower width.
o.window({
  class = "^wechat$",
  title = "聊天记录",
}, {
  name = "silky-wechat-chat-history",
  float = true,
  center = true,
  size = { 820, 720 },
})

-- WeChat keeps both windows alive after you close them and shows the same window again next time, so the
-- open-time rules above only reach windows created after the rules were loaded. On every config load, float
-- any such window that is still tiled, shrink any that grew past the moderate size (WeChat re-shows them at
-- whatever size they had when it hid them), and centre. Already-resized smaller windows are left alone.
local function wechat_popup_size(window)
  if window.title == "图片和视频" then
    return { 900, 620 }
  end
  if window.title:find("聊天记录", 1, true) then
    return { 820, 720 }
  end
  return nil
end

local function fix_open_wechat_popups()
  for _, window in ipairs(hl.get_windows() or {}) do
    if window.class == "wechat" then
      local size = wechat_popup_size(window)
      if size then
        local target = "address:" .. window.address
        if not window.floating then
          hl.dispatch(hl.dsp.window.float({ action = "on", window = target }))
        end
        if window.size.y > size[2] or window.size.x > size[1] or not window.floating then
          hl.dispatch(hl.dsp.window.resize({ x = size[1], y = size[2], relative = false, window = target }))
        end
        hl.dispatch(hl.dsp.window.center({ window = target }))
      end
    end
  end
end

hl.on("config.reloaded", fix_open_wechat_popups)

-- 齐治堡垒机 AccessClient: the SSH console it opens. Depending on the bastion's setting that is either foot via
-- xdg-terminal-exec (app-id "accessclient-ssh") or the bundled PuTTY (XWayland, class "Putty").
-- Floating on its own account so floating-workspace mode doesn't shrink it to the standard box; open it large
-- and centred, since a remote shell wants the room.
o.window("^(accessclient-ssh|Putty)$", {
  name = "silky-accessclient-ssh",
  float = true,
  center = true,
  size = { 1280, 720 },
})

-- Keep the XWayland console opaque like Foot. The terminal tag also lets
-- Universal paste and the MacShell menu send Ctrl+Shift+V.
o.window("^Putty$", {
  name = "silky-accessclient-putty-terminal",
  tag = "+terminal",
  opacity = "1.0 override 1.0 override 1.0 override",
})
