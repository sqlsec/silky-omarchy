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
-- own zoom is unaffected. Register only the popup titles in o.floating_apps.title (instead of o.window with
-- class = "^wechat$") so the main WeChat window still opens floating on its first frame on floating workspaces.
-- Sizes are logical pixels (screen: 1472x920 @ scale 2).
hl.window_rule({
  name = "silky-wechat-media-viewer",
  match = {
    class = "^wechat$",
    title = "^图片和视频$",
  },
  float = true,
  center = true,
  size = { 900, 620 },
})

-- The chat-history window ("群名"的聊天记录(条数)) opens oversized too, with large empty side margins from
-- WeChat's own layout. Float, centre and pin a moderate default size; matched without anchors so it hits any
-- chat/group name. Only WeChat windows carry this string in their title. Height floor: WeChat refuses any
-- size below 720 logical px for this window (2026-11-20: requests for 600/640/660/700 all snapped back to
-- 720; growing works), so 720 is as small as it gets - the win is the narrower width.
hl.window_rule({
  name = "silky-wechat-chat-history",
  match = {
    class = "^wechat$",
    title = "聊天记录",
  },
  float = true,
  center = true,
  size = { 820, 720 },
})

if o.floating_apps and o.floating_apps.title then
  table.insert(o.floating_apps.title, "^图片和视频$")
  table.insert(o.floating_apps.title, "聊天记录")
  if o.floating_apps_changed then
    o.floating_apps_changed()
  end
end

-- Remember the main WeChat window's state (normal floating geometry vs maximized / fullscreen) across
-- hide-to-tray and reopen cycles so reopening restores the exact state it had when closed.
local wechat_state_dir = (os.getenv("XDG_STATE_HOME") or ((os.getenv("HOME") or "") .. "/.local/state")) .. "/silky-omarchy"
local wechat_state_path = wechat_state_dir .. "/wechat-main-window.state"
local wechat_state = {}

local function is_wechat_main(window)
  if not window or window.class ~= "wechat" then return false end
  local title = window.title or ""
  local initial = window.initial_title or ""
  return title == "微信" or title == "WeChat" or initial == "微信" or initial == "WeChat"
end

local function load_wechat_state()
  local file = io.open(wechat_state_path, "r")
  if not file then return end
  for line in file:lines() do
    local key, value = line:match("^([%w_]+)=(%-?%d+)$")
    if key and value then
      wechat_state[key] = tonumber(value)
    end
  end
  file:close()
end

local function write_wechat_state()
  local file = io.open(wechat_state_path, "w")
  if not file then
    local pipe = io.popen("mkdir -p -- '" .. wechat_state_dir:gsub("'", "'\\''") .. "'")
    if pipe then pipe:close() end
    file = io.open(wechat_state_path, "w")
    if not file then return end
  end
  for _, key in ipairs({ "fullscreen", "x", "y", "w", "h" }) do
    if wechat_state[key] ~= nil then
      file:write(key, "=", tostring(math.floor(wechat_state[key])), "\n")
    end
  end
  file:close()
end

local function save_wechat_state(window)
  local fs = window.fullscreen or 0
  wechat_state.fullscreen = fs
  if fs == 0 and window.floating and window.at and window.size and window.size.x >= 300 and window.size.y >= 300 then
    wechat_state.x = math.floor(window.at.x)
    wechat_state.y = math.floor(window.at.y)
    wechat_state.w = math.floor(window.size.x)
    wechat_state.h = math.floor(window.size.y)
  end
  write_wechat_state()
end

local function clamp_wechat_geometry(window, x, y, w, h)
  local monitor = window.monitor
  if not monitor or not monitor.width or not monitor.height then
    return x, y, w, h
  end
  local scale = monitor.scale or 1
  local mw = math.floor(monitor.width / scale)
  local mh = math.floor(monitor.height / scale)
  if (monitor.transform or 0) % 2 == 1 then
    mw, mh = mh, mw
  end
  local reserved = monitor.reserved or {}
  local left = (monitor.x or 0) + (reserved.left or 0)
  local top = (monitor.y or 0) + (reserved.top or 0)
  local avail_w = math.max(300, mw - (reserved.left or 0) - (reserved.right or 0))
  local avail_h = math.max(300, mh - (reserved.top or 0) - (reserved.bottom or 0))
  w = math.min(w, avail_w)
  h = math.min(h, avail_h)
  x = math.max(left, math.min(x, left + avail_w - w))
  y = math.max(top, math.min(y, top + avail_h - h))
  return x, y, w, h
end

local function restore_wechat_main(address)
  local window = hl.get_window("address:" .. address)
  if not window or not is_wechat_main(window) then return end
  local wanted = wechat_state.fullscreen
  if wanted == nil then return end
  local target = "address:" .. window.address
  local current = window.fullscreen or 0
  if wanted == 1 then
    if current ~= 1 then
      hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "set", window = target }))
    end
    return
  end
  if wanted >= 2 then
    if current < 2 then
      hl.dispatch(hl.dsp.window.fullscreen({ mode = "fullscreen", action = "set", window = target }))
    end
    return
  end
  if current == 1 then
    hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "unset", window = target }))
  elseif current >= 2 then
    hl.dispatch(hl.dsp.window.fullscreen({ mode = "fullscreen", action = "unset", window = target }))
  end
  if window.floating and wechat_state.w and wechat_state.h and wechat_state.x and wechat_state.y then
    local x, y, w, h = clamp_wechat_geometry(window, wechat_state.x, wechat_state.y, wechat_state.w, wechat_state.h)
    hl.dispatch(hl.dsp.window.resize({ x = w, y = h, relative = false, window = target }))
    hl.dispatch(hl.dsp.window.move({ x = x, y = y, relative = false, window = target }))
  end
end

load_wechat_state()

hl.on("window.open", function(window)
  if not is_wechat_main(window) then return end
  local address = window.address
  hl.timer(function()
    restore_wechat_main(address)
  end, { type = "oneshot", timeout = 20 })
end)

hl.on("window.fullscreen", function(window)
  if is_wechat_main(window) then
    save_wechat_state(window)
  end
end)

hl.on("window.destroy", function(window)
  if is_wechat_main(window) then
    save_wechat_state(window)
  end
end)

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
