-- Resolve the user desktop entry even when the session PATH prefers /usr/bin.
if omarchy_default_bindings ~= false then
  o.rebind("SUPER + SHIFT + F", "File manager", "gtk-launch folio.desktop")
  o.rebind("SUPER + ALT + SHIFT + F", "File manager (cwd)",
    'gtk-launch folio.desktop "$(omarchy-cmd-terminal-cwd)"')
end

-- Keep Folio's content surface opaque. Its sidebar supplies its own alpha.
hl.window_rule({
  name = "silky-folio-surface-opacity",
  match = { class = "^folio$" },
  opacity = "1.0 override 1.0 override 1.0 override",
})

if silky_macos_titlebars then
  -- Sample what is behind the glass sidebar. Cached wallpaper blur leaks a bright
  -- fringe at its rounded corners, and the translucent border outlines that fringe.
  hl.window_rule({
    name = "silky-folio-rounded-glass-edge",
    match = { class = "^folio$", float = true },
    xray = false,
    border_size = 0,
  })
end

-- The render-thread animation controls the minimize overlay's visibility.
hl.layer_rule({
  name = "silky-folio-minimize-overlay",
  match = { namespace = "^silky-folio-scale-out$" },
  no_anim = true,
})

hl.layer_rule({
  name = "silky-folio-snap-preview",
  match = { namespace = "^silky-folio-snap$" },
  no_anim = true,
})

hl.layer_rule({
  name = "silky-foot-window-controls",
  match = { namespace = "^silky-foot-(layout|fullscreen)$" },
  no_anim = true,
})

local placements = {
  left = { column = 1 }, right = { column = 2 },
  top = { row = 1 }, bottom = { row = 2 },
  ["top-left"] = { column = 1, row = 1 }, ["top-right"] = { column = 2, row = 1 },
  ["bottom-left"] = { column = 1, row = 2 }, ["bottom-right"] = { column = 2, row = 2 },
}

local function logical_size(monitor)
  if monitor.transform % 2 ~= 0 then
    return monitor.height / monitor.scale, monitor.width / monitor.scale
  end
  return monitor.width / monitor.scale, monitor.height / monitor.scale
end

local function placement_rect(monitor, placement)
  local slot = placements[placement]
  if not slot then
    return
  end

  local width, height = logical_size(monitor)
  local reserved = monitor.reserved
  local left = math.ceil(monitor.x + reserved.left)
  local top = math.ceil(monitor.y + reserved.top)
  local right = math.floor(monitor.x + width - reserved.right)
  local bottom = math.floor(monitor.y + height - reserved.bottom)
  local center_x = (left + right) // 2
  local center_y = (top + bottom) // 2
  if slot.column == 1 then
    right = center_x
  elseif slot.column == 2 then
    left = center_x
  end
  if slot.row == 1 then
    bottom = center_y
  elseif slot.row == 2 then
    top = center_y
  end
  return { x = left, y = top, width = right - left, height = bottom - top }
end

local gestures = hl.plugin and hl.plugin.silky_gestures
local function titlebar_app(class)
  return class == "foot" or (o.silky_desktop_app_layouts or {})[class] == true
end

local function titlebar_height(window)
  if window.workspace and window.workspace.id >= 1 then
    return hl.get_config("plugin.hyprbars.bar_height") or 0
  end
  return 0
end

local function titlebar_slot(window, rect)
  if not rect then return end
  if gestures and gestures.window_layout_limits then
    local min_w, min_h, max_w, max_h = gestures.window_layout_limits(window.address)
    if min_w then
      local width = rect.width
      local height = rect.height - titlebar_height(window)
      if width < min_w or height < min_h or (max_w > 0 and width > max_w) or (max_h > 0 and height > max_h) then
        return
      end
    end
  end
  return rect
end

local function place_window(address, placement, monitor, app)
  local selector = "address:" .. address
  local window = hl.get_window(selector)
  if not window or (window.fullscreen or 0) >= 2
      or (app == "folio" and window.class ~= app)
      or (app == "titlebar" and not titlebar_app(window.class)) then
    return
  end
  monitor = monitor or window.monitor
  local rect = monitor and placement_rect(monitor, placement)
  if app == "titlebar" then rect = titlebar_slot(window, rect) end
  if not rect then
    return
  end

  if window.fullscreen == 1 then
    hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "unset", window = selector }))
  end
  if window.group and window.group.size > 1 then
    hl.dispatch(hl.dsp.window.move({ out_of_group = true, window = selector }))
  end
  if not window.floating then
    hl.dispatch(hl.dsp.window.float({ action = "on", window = selector }))
  end
  if window.monitor and window.monitor.name ~= monitor.name then
    hl.dispatch(hl.dsp.window.move({ monitor = monitor.name, follow = false, window = selector }))
  end
  if app == "titlebar" then
    -- Hyprbars is above the client surface. Place the whole frame in the slot.
    local bar = titlebar_height(window)
    rect.y = rect.y + bar
    rect.height = rect.height - bar
  end
  hl.dispatch(hl.dsp.window.resize({ x = rect.width, y = rect.height, relative = false, window = selector }))
  hl.dispatch(hl.dsp.window.move({ x = rect.x, y = rect.y, relative = false, window = selector }))
  hl.dispatch(hl.dsp.focus({ window = selector }))
end

function o.silky_folio_place(address, placement, monitor)
  place_window(address, placement, monitor, "folio")
end

if silky_macos_titlebars and gestures and gestures.enable_foot_layout then
  silky_foot_layout_enabled = true
  silky_desktop_app_layout_enabled = gestures.window_layout_limits ~= nil
  local apps = {}
  for app in pairs(o.silky_desktop_app_layouts or {}) do
    apps[#apps + 1] = app
  end
  gestures.enable_foot_layout(table.unpack(apps))
end

function o.silky_foot_place(address, placement, output)
  place_window(address, placement, output and hl.get_monitor(output), "titlebar")
end

function o.silky_foot_fullscreen(address)
  local selector = "address:" .. address
  local window = hl.get_window(selector)
  if window and titlebar_app(window.class) then
    hl.dispatch(hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle", window = selector }))
  end
end

local down = false
local drag
local drag_timer

local function publish_preview(payload)
  hl.dispatch(hl.dsp.event("silky-folio-snap," .. payload))
end

function o.silky_foot_menu(address, output, x, y)
  local window = hl.get_window("address:" .. address)
  local monitor = hl.get_monitor(output)
  if not window or not monitor or not titlebar_app(window.class) then return end
  local fields = { address, output, x, y }
  if (window.fullscreen or 0) < 2 then
    for name in pairs(placements) do
      if titlebar_slot(window, placement_rect(monitor, name)) then
        fields[#fields + 1] = name
      end
    end
  end
  hl.dispatch(hl.dsp.event("silky-window-menu," .. table.concat(fields, ",")))
end

function o.silky_foot_preview(address, output, placement)
  local monitor = output and hl.get_monitor(output)
  local window = address and hl.get_window("address:" .. address)
  local rect = window and monitor and titlebar_slot(window, placement_rect(monitor, placement))
  publish_preview(rect and table.concat({
    output, rect.x - monitor.x, rect.y - monitor.y, rect.width, rect.height,
  }, ",") or "hide")
end

local function stop_drag()
  if drag and drag.preview then
    publish_preview("hide")
  end
  drag = nil
  drag_timer:set_enabled(false)
end

local function snap_zone(monitor, cursor)
  local width, height = logical_size(monitor)
  local x, y = cursor.x - monitor.x, cursor.y - monitor.y
  local side
  if x < 28 then
    side = "left"
  elseif x >= width - 28 then
    side = "right"
  end
  if not side then
    return
  end
  if y < height / 4 then
    return "top-" .. side
  end
  if y >= height * 3 / 4 then
    return "bottom-" .. side
  end
  return side
end

drag_timer = hl.timer(function()
  local window = hl.get_active_window()
  if not drag or not window or window.address ~= drag.address then
    stop_drag()
    return
  end
  local cursor = hl.get_cursor_pos()
  local monitor = hl.get_monitor_at_cursor()
  local zone = monitor and snap_zone(monitor, cursor)
  local preview
  if zone then
    local rect = placement_rect(monitor, zone)
    preview = table.concat({ monitor.name, rect.x - monitor.x, rect.y - monitor.y, rect.width, rect.height }, ",")
  end
  if preview ~= drag.preview then
    publish_preview(preview or "hide")
    drag.preview = preview
  end
end, { timeout = 16, type = "repeat" })
drag_timer:set_enabled(false)

local drop_timer
drop_timer = hl.timer(function()
  drop_timer:set_enabled(false)
  local window = hl.get_active_window()
  if drag and drag.zone and window and window.address == drag.address then
    o.silky_folio_place(drag.address, drag.zone, drag.monitor)
  end
  stop_drag()
end, { timeout = 1, type = "repeat" })
drop_timer:set_enabled(false)

hl.bind("mouse:272", function() down = true end, { non_consuming = true, ignore_mods = true })
hl.bind("mouse:272", function()
  down = false
  if not drag then
    return
  end
  drag.monitor = hl.get_monitor_at_cursor()
  drag.zone = drag.monitor and snap_zone(drag.monitor, hl.get_cursor_pos())
  drag_timer:set_enabled(false)
  -- Let Hyprland finish the native drag before applying the drop geometry.
  drop_timer:set_enabled(true)
end, { release = true, non_consuming = true, ignore_mods = true })

function o.silky_folio_begin_drag(pid)
  local window = hl.get_active_window()
  if down and window and window.class == "folio" and window.pid == pid and (window.fullscreen or 0) == 0 then
    drop_timer:set_enabled(false)
    stop_drag()
    drag = { address = window.address }
    drag_timer:set_enabled(true)
  end
end

hl.on("config.unload", function()
  if drag and drag.preview then
    publish_preview("hide")
  end
end)
