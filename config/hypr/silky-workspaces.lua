-- Fixed workspace numbers for the laptop and its external display.
require("default.hypr.helpers")
local workspaces = require("default.hypr.monitor-workspaces")
local main = "eDP-1"
local external = "desc:BOE 0x0A52"

for id = 1, 9 do
  local first = id <= 5 and 1 or 6
  hl.workspace_rule({
    workspace = tostring(id),
    monitor = first == 1 and main or external,
    default = id == first,
    persistent = true,
  })
end

local function external_monitor(gone)
  local monitor = hl.get_monitor(external)
  if monitor and not monitor.is_mirror and monitor.name ~= gone then
    return monitor
  end
  for _, candidate in ipairs(hl.get_monitors()) do
    if not candidate.is_mirror and candidate.name ~= main and candidate.name ~= gone then
      return candidate
    end
  end
  return nil
end

local function primary_monitor(gone)
  local laptop = hl.get_monitor(main)
  if laptop and laptop.name ~= gone then
    return laptop
  end
  local active = hl.get_active_monitor()
  if active and active.name ~= gone then
    return active
  end
  for _, candidate in ipairs(hl.get_monitors()) do
    if not candidate.is_mirror and candidate.name ~= gone then
      return candidate
    end
  end
  return nil
end

local function owner(id, gone)
  return (id >= 6 and external_monitor(gone)) or primary_monitor(gone)
end

local function needs_move(workspace, monitor, gone)
  if not workspace or not monitor then return false end
  local current = workspace.monitor
  return (not current) or current.name ~= monitor.name or (gone ~= nil and current.name == gone)
end

local function monitor_work_area(monitor)
  if not monitor then return nil end
  local scale = monitor.scale or 1
  if scale <= 0 then scale = 1 end
  local rotated = (monitor.transform or 0) % 2 == 1
  local mon_w = math.floor(((rotated and monitor.height or monitor.width) / scale) + 0.5)
  local mon_h = math.floor(((rotated and monitor.width or monitor.height) / scale) + 0.5)
  local reserved = monitor.reserved or {}
  local left = reserved.left or 0
  local top = reserved.top or 0
  local right = reserved.right or 0
  local bottom = reserved.bottom or 0
  local area_x = (monitor.x or 0) + left
  local area_y = (monitor.y or 0) + top
  local area_w = math.max(200, mon_w - left - right)
  local area_h = math.max(200, mon_h - top - bottom)
  return area_x, area_y, area_w, area_h
end

local function window_top_inset(window)
  if not window then return 0 end
  local gestures = hl.plugin and hl.plugin.silky_gestures
  if gestures and gestures.window_top_inset and window.address then
    local ok, inset = pcall(gestures.window_top_inset, window.address)
    if ok and type(inset) == "number" and inset > 0 then
      return math.ceil(inset)
    end
  end
  if o.silky_titlebar_height then
    return o.silky_titlebar_height(window) or 0
  end
  return 0
end

local function clamp_floating_windows(workspace_id, monitor, force)
  local area_x, area_y, area_w, area_h = monitor_work_area(monitor)
  if not area_x then return end

  local margin = 12
  local max_w = math.max(200, area_w - margin * 2)

  for _, window in ipairs(hl.get_workspace_windows(tostring(workspace_id))) do
    if window.floating and window.mapped and not window.hidden and (window.fullscreen or 0) == 0 then
      local at = window.at
      local size = window.size
      if at and size then
        local wx, wy = at.x or 0, at.y or 0
        local ww, wh = size.x or 0, size.y or 0
        local top_inset = window_top_inset(window)
        local avail_h = math.max(120, area_h - top_inset)
        local max_h = math.max(120, avail_h - margin * 2)
        local offscreen = (wx + ww <= area_x + 40)
          or (wx >= area_x + area_w - 40)
          or (wy - top_inset < area_y)
          or (wy >= area_y + area_h - 40)
        local oversized = ww > area_w or wh > avail_h

        if force or offscreen then
          local selector = "address:" .. window.address
          local target_w = ww
          local target_h = wh
          if oversized then
            target_w = math.min(ww, max_w)
            target_h = math.min(wh, max_h)
            hl.dispatch(hl.dsp.window.resize({
              x = math.floor(target_w + 0.5),
              y = math.floor(target_h + 0.5),
              relative = false,
              window = selector,
            }))
          end

          local min_x = area_x
          local max_x = math.max(min_x, area_x + area_w - target_w)
          local min_y = area_y + top_inset
          local max_y = math.max(min_y, area_y + area_h - target_h)
          local target_x = math.min(math.max(wx, min_x), max_x)
          local target_y = math.min(math.max(wy, min_y), max_y)

          if target_x ~= wx or target_y ~= wy then
            hl.dispatch(hl.dsp.window.move({
              x = math.floor(target_x + 0.5),
              y = math.floor(target_y + 0.5),
              relative = false,
              window = selector,
            }))
          end
        end
      end
    end
  end
end

function workspaces.range(monitor)
  local second = external_monitor()
  if second and monitor and monitor.name == second.name then
    return 6, 9
  end
  return 1, second and 5 or 9
end

local function action(fn, expression)
  o.bind_expressions[fn] = expression
  return fn
end

function workspaces.focus(id)
  return action(function()
    if id < 1 or id > 9 then return end
    local monitor = owner(id)
    if not monitor then return end
    local workspace = hl.get_workspace(id)
    if needs_move(workspace, monitor) then
      hl.dispatch(hl.dsp.workspace.move({ workspace = tostring(id), monitor = monitor.name }))
      clamp_floating_windows(id, monitor, true)
    end
    if not monitor.focused then
      hl.dispatch(hl.dsp.focus({ monitor = monitor.name }))
    end
    hl.dispatch(hl.dsp.focus({ workspace = tostring(id) }))
  end, "o.workspaces.focus(" .. id .. ")")
end

function workspaces.move_window(id, follow)
  return action(function()
    if id < 1 or id > 9 then return end
    hl.dispatch(hl.dsp.window.move({ workspace = tostring(id), follow = follow ~= false }))
  end, "o.workspaces.move_window(" .. id .. (follow == false and ", false" or "") .. ")")
end

local function move_windows(source, destination)
  for _, window in ipairs(hl.get_workspace_windows(tostring(source))) do
    hl.dispatch(hl.dsp.window.move({
      workspace = tostring(destination),
      window = "address:" .. window.address,
      follow = false,
    }))
  end
end

-- Transfer the windows to the destination monitor's active workspace.
function workspaces.move_to_monitor(direction)
  return action(function()
    local source = hl.get_active_workspace()
    local monitor = hl.get_monitor(direction)
    local target = monitor and monitor.active_workspace
    if not source or source.special or not target or source.id == target.id then return end
    move_windows(source.id, target.id)
    clamp_floating_windows(target.id, monitor, true)
    hl.dispatch(hl.dsp.focus({ monitor = monitor.name }))
  end, string.format("o.workspaces.move_to_monitor(%q)", direction))
end

-- Omarchy's existing startup, reload and monitor callbacks call this hook.
function workspaces.reconcile(added, gone)
  local second = external_monitor(gone)
  local focused = hl.get_active_monitor()
  local laptop = primary_monitor(gone)

  for id = 1, 9 do
    local workspace = hl.get_workspace(id)
    local monitor = owner(id, gone)
    if workspace and monitor then
      if needs_move(workspace, monitor, gone) then
        hl.dispatch(hl.dsp.workspace.move({ workspace = tostring(id), monitor = monitor.name }))
        clamp_floating_windows(id, monitor, true)
      else
        clamp_floating_windows(id, monitor, false)
      end
    end
  end

  -- Preserve windows from the previous external workspace numbering.
  for id = 11, 20 do
    local workspace = hl.get_workspace(id)
    if workspace and (workspace.windows or 0) > 0 then
      local dest = math.min(id - 5, 9)
      move_windows(id, dest)
      local monitor = owner(dest, gone)
      if monitor then
        clamp_floating_windows(dest, monitor, true)
      end
    end
  end

  -- Rescue any other orphaned regular workspaces whose monitor disappeared.
  if laptop then
    for _, workspace in ipairs(hl.get_workspaces()) do
      if workspace and not workspace.special and (workspace.id or 0) > 9 and (workspace.windows or 0) > 0 then
        if needs_move(workspace, laptop, gone) then
          hl.dispatch(hl.dsp.workspace.move({ workspace = tostring(workspace.id), monitor = laptop.name }))
          clamp_floating_windows(workspace.id, laptop, true)
        end
      end
    end
  end

  for _, monitor in pairs({ laptop = laptop, external = second }) do
    local first, last = workspaces.range(monitor)
    local active = monitor.active_workspace
    if not active or active.id < first or active.id > last then
      workspaces.focus(first)()
    end
  end

  if focused and focused.name ~= gone and not focused.focused and hl.get_monitor(focused.name) then
    hl.dispatch(hl.dsp.focus({ monitor = focused.name }))
  end

  if gone then
    hl.timer(function()
      workspaces.reconcile()
    end, { type = "oneshot", timeout = 150 })
  end
end
