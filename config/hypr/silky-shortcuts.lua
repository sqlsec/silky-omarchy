-- Silky Omarchy: MacShell wins every shortcut it shares with Omarchy.
--
-- Hyprland runs EVERY bind on a key, so with MacShell installed one press of Super+Space opened Spotlight and the
-- Omarchy menu at once, Super+V pasted and opened the clipboard history, Alt+Tab cycled focus under the switcher,
-- and Super+L locked the screen and flipped the workspace layout. This file is loaded last (after hypr.macshell):
-- it clears those keys, gives them back to MacShell only (now with a description, so they show in Super+K), and
-- moves the Omarchy action to a key nothing else uses.
--
--   key                 MacShell (kept)              Omarchy action        moved to
--   SUPER + SPACE       Spotlight                    Omarchy menu          SUPER + CTRL + M
--   SUPER + V           clipboard history            Universal paste       SUPER + ALT + V
--   ALT + TAB           app switcher                 next window / raise   ALT + GRAVE  (the key left of 1)
--   ALT + SHIFT + TAB   app switcher, backwards      previous window       ALT + SHIFT + GRAVE
--   SUPER + L           lock (MacLock)               Cycle layout          SUPER + SHIFT + L
--
-- Check for new overlaps after an Omarchy or MacShell update:  scripts/silky-doctor.sh  (section "快捷键冲突").

local qs = "qs -c MacShell ipc call "

local function macshell(keys, description, call)
  pcall(hl.unbind, keys)
  hl.bind(keys, hl.dsp.exec_cmd(qs .. call), { description = description })
end

-- MacShell, one bind per key (macshell.lua binds these too, without a description; unbinding first keeps one).
macshell("SUPER + SPACE", "聚焦搜索 (MacShell)", "spotlight toggle")
macshell("SUPER + V", "剪贴板历史 (MacShell)", "spotlight clipboard")
macshell("SUPER + PERIOD", "表情与符号 (MacShell)", "spotlight emoji")
macshell("SUPER + Z", "系统设置 (MacShell)", "settings toggle")
macshell("ALT + TAB", "切换应用 (MacShell)", "switcher next")
macshell("ALT + SHIFT + TAB", "反向切换应用 (MacShell)", "switcher prev")
macshell("CTRL + ALT + W", "墙纸 (MacShell)", "wallpapers toggle")
pcall(hl.unbind, "SUPER + L")
hl.bind("SUPER + L", hl.dsp.exec_cmd("sh ~/.config/quickshell/MacLock/lock-via-ipc.sh"), { description = "锁屏 (MacLock)" })
pcall(hl.unbind, "SUPER + M")
hl.bind("SUPER + M", hl.dsp.exec_cmd([[sh -c '[ "$(qs -c MacShell ipc call window minimizeActive 2>/dev/null)" = true ] || exec omarchy-hyprland-window-minimize']]), { description = "Minimize window to the dock" })

-- Omarchy actions on their new keys. English descriptions on purpose: the keybindings menu translates them.
o.bind("SUPER + CTRL + M", "Omarchy menu", { menu = "root" })
o.bind("ALT + GRAVE", "Focus on next window", hl.dsp.window.cycle_next())
o.bind("ALT + GRAVE", "Reveal active window on top", hl.dsp.window.bring_to_top())
-- Going backwards lowers the window it leaves (see Omarchy's tiling.lua for why).
o.bind("ALT + SHIFT + GRAVE", "Reveal active window on top", hl.dsp.window.alter_zorder({ mode = "bottom" }))
o.bind("ALT + SHIFT + GRAVE", "Focus on previous window", hl.dsp.window.cycle_next({ next = false }))

-- In-process workspace layout switching: zero shell forks, instant MacShell OSD + top-bar sync.
local layout_paths = require("default.hypr.paths")
local layout_dir = layout_paths.state_home .. "/omarchy/workspace-layouts"
local valid_layouts = { floating = true, dwindle = true, scrolling = true }
local next_layout = { floating = "dwindle", dwindle = "scrolling", scrolling = "floating" }

local function read_layout_mode(path, key)
  local file = io.open(path, "r")
  if not file then return nil end
  local contents = file:read("*a")
  file:close()
  return contents:match(key .. '%s*=%s*"([a-z]+)"')
end

local function default_layout_mode()
  return read_layout_mode(layout_dir .. "/default.lua", "default") or hl.get_config("general.layout") or "floating"
end

local function current_layout_mode(id)
  local saved = read_layout_mode(layout_dir .. "/" .. tostring(id) .. ".lua", "mode")
  if saved and valid_layouts[saved] then return saved end
  local def = default_layout_mode()
  if def == "floating" then return "floating" end
  local ws = hl.get_workspace(id)
  return (ws and ws.tiled_layout) or def
end

local function persist_layout_mode(id, mode)
  local path = layout_dir .. "/" .. tostring(id) .. ".lua"
  if mode == default_layout_mode() then
    local removed, _, errno = os.remove(path)
    return removed or errno == 2
  end
  local tmp = path .. ".tmp"
  local file = io.open(tmp, "w")
  if not file and o.shell_succeeds("mkdir -p -- " .. o.shell_quote(layout_dir)) then
    file = io.open(tmp, "w")
  end
  if not file then return false end
  local ok = file:write(('o.workspace_mode({ workspace = "%d", mode = "%s" })\n'):format(id, mode))
  local closed = file:close()
  if ok and closed and os.rename(tmp, path) then return true end
  os.remove(tmp)
  return false
end

local function monitor_name_for_workspace(id)
  local ws = hl.get_workspace(id)
  if ws and ws.monitor and ws.monitor.name then
    return ws.monitor.name
  end
  local active = hl.get_active_monitor()
  return (active and active.name) or ""
end

function o.silky_workspace_layout_sync()
  local parts = {}
  for id = 1, 9 do
    parts[#parts + 1] = id .. ":" .. current_layout_mode(id)
  end
  hl.dispatch(hl.dsp.event("silky-ws-layout-map," .. table.concat(parts, ";")))
end

local floating_snapshots = {}

local function snapshot_floating_workspace(id)
  local windows = {}
  local order = {}
  local active = hl.get_active_window()
  local active_addr = (active and active.workspace and active.workspace.id == id) and active.address or nil
  for _, win in ipairs(hl.get_workspace_windows(tostring(id))) do
    if win.floating and win.mapped and not win.hidden and (win.fullscreen or 0) == 0 and win.at and win.size then
      windows[win.address] = {
        x = math.floor((win.at.x or 0) + 0.5),
        y = math.floor((win.at.y or 0) + 0.5),
        w = math.floor((win.size.x or 0) + 0.5),
        h = math.floor((win.size.y or 0) + 0.5),
      }
      order[#order + 1] = {
        address = win.address,
        rank = win.focus_history_id or 9999,
      }
    end
  end
  if #order == 0 then return end
  -- Higher focus_history_id = further back; raising from largest to smallest reproduces the original stack.
  table.sort(order, function(a, b) return a.rank > b.rank end)
  floating_snapshots[id] = {
    windows = windows,
    order = order,
    active = active_addr,
  }
end

local function restore_floating_workspace(id)
  local snap = floating_snapshots[id]
  if not snap then return end
  floating_snapshots[id] = nil

  for _, entry in ipairs(snap.order) do
    local selector = "address:" .. entry.address
    local win = hl.get_window(selector)
    local geom = snap.windows[entry.address]
    if win and geom and win.mapped and not win.hidden and win.floating
        and (win.fullscreen or 0) == 0 and win.workspace and win.workspace.id == id then
      hl.dispatch(hl.dsp.window.resize({ x = geom.w, y = geom.h, relative = false, window = selector }))
      hl.dispatch(hl.dsp.window.move({ x = geom.x, y = geom.y, relative = false, window = selector }))
      hl.dispatch(hl.dsp.window.alter_zorder({ mode = "top", window = selector }))
    end
  end
end

local function balance_dwindle_workspace(id)
  local tiled = {}
  for _, win in ipairs(hl.get_workspace_windows(tostring(id))) do
    if win.mapped and not win.hidden and not win.floating and not win.pinned and (win.fullscreen or 0) == 0 then
      tiled[#tiled + 1] = {
        address = win.address,
        rank = win.focus_history_id or 9999,
      }
    end
  end
  if #tiled < 3 then return end

  -- Keep recently focused windows first so they inherit the larger slots.
  table.sort(tiled, function(a, b) return a.rank < b.rank end)

  local prev_no_warps = hl.get_config("cursor.no_warps")
  if not prev_no_warps then
    pcall(hl.config, { cursor = { no_warps = true } })
  end

  for i = 2, #tiled do
    hl.dispatch(hl.dsp.window.float({ action = "on", window = "address:" .. tiled[i].address }))
  end

  -- Track each tile's fractional area in Lua instead of reading stale win.size mid-tick.
  -- Splitting the largest slot each time guarantees a balanced binary tree (max/min area <= 2:1).
  local slots = { { address = tiled[1].address, area = 1.0 } }
  for i = 2, #tiled do
    local best_idx = 1
    for j = 2, #slots do
      if slots[j].area > slots[best_idx].area then
        best_idx = j
      end
    end
    local best = slots[best_idx]
    hl.dispatch(hl.dsp.focus({ window = "address:" .. best.address }))
    hl.dispatch(hl.dsp.window.float({ action = "off", window = "address:" .. tiled[i].address }))
    local half = best.area * 0.5
    best.area = half
    slots[#slots + 1] = { address = tiled[i].address, area = half }
  end

  hl.dispatch(hl.dsp.focus({ window = "address:" .. tiled[1].address }))
  if not prev_no_warps then
    pcall(hl.config, { cursor = { no_warps = false } })
  end
end

function o.silky_workspace_layout_set(workspace_id, mode, show_osd)
  local id = tonumber(workspace_id)
  if not id or id < 1 or not valid_layouts[mode] or type(o.workspace_mode) ~= "function" then
    return false
  end
  local prev = current_layout_mode(id)
  if prev == "floating" and mode ~= "floating" then
    snapshot_floating_workspace(id)
  end
  o.workspace_mode({ workspace = tostring(id), mode = mode })
  if mode == "dwindle" then
    -- Let Hyprland finish switching the workspace's tiled layout (e.g. from scrolling -> dwindle)
    -- before balancing the dwindle split tree.
    hl.timer(function()
      if current_layout_mode(id) == "dwindle" then
        balance_dwindle_workspace(id)
      end
    end, { timeout = 30, type = "oneshot" })
  elseif prev ~= "floating" and mode == "floating" then
    restore_floating_workspace(id)
  end
  persist_layout_mode(id, mode)
  local mon = monitor_name_for_workspace(id)
  hl.dispatch(hl.dsp.event(string.format("silky-ws-layout,%d,%s,%s,%d", id, mode, mon, show_osd and 1 or 0)))
  return true
end

local prev_layout = { floating = "scrolling", scrolling = "dwindle", dwindle = "floating" }

function o.silky_workspace_layout_cycle(workspace_id)
  local id = tonumber(workspace_id)
  if not id then
    local active = hl.get_active_workspace()
    if not active or active.special or not active.id or active.id < 1 then return end
    id = active.id
  end
  local current = current_layout_mode(id)
  local target = next_layout[current] or "floating"
  o.silky_workspace_layout_set(id, target, true)
end

function o.silky_workspace_layout_cycle_back(workspace_id)
  local id = tonumber(workspace_id)
  if not id then
    local active = hl.get_active_workspace()
    if not active or active.special or not active.id or active.id < 1 then return end
    id = active.id
  end
  local current = current_layout_mode(id)
  local target = prev_layout[current] or "floating"
  o.silky_workspace_layout_set(id, target, true)
end

function o.silky_workspace_layout_reset_all(monitor_name)
  if type(o.workspace_mode) ~= "function" then return end
  for id = 1, 9 do
    if current_layout_mode(id) ~= "floating" then
      o.workspace_mode({ workspace = tostring(id), mode = "floating" })
      restore_floating_workspace(id)
    end
    persist_layout_mode(id, "floating")
  end
  o.silky_workspace_layout_sync()
  local mon = (type(monitor_name) == "string" and monitor_name ~= "") and monitor_name or monitor_name_for_workspace(1)
  hl.dispatch(hl.dsp.event("silky-ws-layout,0,floating," .. mon .. ",1"))
end

o.bind_expressions[o.silky_workspace_layout_cycle] = "o.silky_workspace_layout_cycle"
o.bind_expressions[o.silky_workspace_layout_cycle_back] = "o.silky_workspace_layout_cycle_back"
o.bind("SUPER + SHIFT + L", "Cycle workspace layout", o.silky_workspace_layout_cycle)
o.rebind("SUPER + ALT + L", "Cycle workspace layout back", o.silky_workspace_layout_cycle_back)
o.rebind("XF86Display", "Cycle workspace layout", o.silky_workspace_layout_cycle)
hl.on("config.reloaded", function()
  hl.timer(function() o.silky_workspace_layout_sync() end, { timeout = 150, type = "oneshot" })
end)

local tiling_sessions = {}

hl.on("window.destroy", function(window)
  local address = window.address
  if not address then return end
  tiling_sessions[address] = nil
  for _, session in pairs(tiling_sessions) do
    session.displaced[address] = nil
  end
  for _, snap in pairs(floating_snapshots) do
    if snap.windows then snap.windows[address] = nil end
    if snap.active == address then snap.active = nil end
  end
end)

local function on_workspace(window, id)
  return window and window.mapped and window.workspace and window.workspace.id == id
end

local function restore_displaced(session)
  local source = tostring(session.source)
  local returning = {}
  for address in pairs(session.displaced) do
    local window = hl.get_window("address:" .. address)
    if on_workspace(window, session.destination) and not window.pinned then
      returning[address] = true
    end
  end
  for address in pairs(returning) do
    local selector = "address:" .. address
    local window = hl.get_window(selector)
    if on_workspace(window, session.destination) and not window.pinned then
      local can_move = true
      -- A group may have gained unrelated windows since the original move.
      if window.group then
        for _, member in ipairs(window.group.members) do
          if not returning[member.address] then
            can_move = false
            break
          end
        end
      end
      if can_move then
        hl.dispatch(hl.dsp.window.move({ workspace = source, follow = false, window = selector }))
      end
    end
  end
  for address in pairs(returning) do
    if session.displaced[address] then
      local selector = "address:" .. address
      local window = hl.get_window(selector)
      if on_workspace(window, session.source) and window.floating and not window.pinned then
        hl.dispatch(hl.dsp.window.pin({ action = "on", window = selector }))
      end
    end
  end
end

local function release_fullscreen(window)
  -- Let the app keep its presentation mode inside the tile.
  local client = (window.fullscreen_client or 0) >= 2 and 2 or 0
  hl.dispatch(hl.dsp.window.fullscreen_state({ internal = 0, client = client, window = window }))
end

local function float_below_menu_bar(window)
  local target = "address:" .. window.address
  hl.dispatch(hl.dsp.window.float({ action = "on", window = target }))

  local floated = hl.get_window(target)
  local monitor = floated and floated.monitor
  if not floated or not floated.floating or not monitor or monitor.reserved.top <= 0 then
    return floated
  end

  local top_inset = 0
  local gestures = hl.plugin and hl.plugin.silky_gestures
  if gestures and gestures.window_top_inset and floated.address then
    local ok, inset = pcall(gestures.window_top_inset, floated.address)
    if ok and type(inset) == "number" and inset > 0 then
      top_inset = math.ceil(inset)
    end
  elseif o.silky_titlebar_height then
    top_inset = o.silky_titlebar_height(floated) or 0
  end

  local top = math.ceil(monitor.y + monitor.reserved.top + top_inset + 4)
  if floated.at.y < top then
    -- Hyprland can restore a floating size as large as the whole output.
    local output_height = monitor.transform % 2 == 0 and monitor.height or monitor.width
    local bottom = math.floor(monitor.y + output_height / monitor.scale - monitor.reserved.bottom)
    local height = math.max(1, bottom - top)
    if floated.size.y > height then
      hl.dispatch(hl.dsp.window.resize({ x = floated.size.x, y = height, relative = false, window = target }))
    end
    hl.dispatch(hl.dsp.window.move({ x = floated.at.x, y = top, relative = false, window = target }))
  end
  return floated
end

local pending_layouts = {}
local mode_floated_tag = "omarchy-mode-floated"

local function is_dragging_window(address)
  local gestures = hl.plugin and hl.plugin.silky_gestures
  return gestures and gestures.is_dragging_window and gestures.is_dragging_window(address)
end

local function restore_mode_tag(target)
  hl.dispatch(hl.dsp.window.tag({ tag = "+" .. mode_floated_tag, window = target }))
end

local function apply_arrival_layout(address, arrival)
  if pending_layouts[address] ~= arrival then return end

  if is_dragging_window(address) then
    -- A native drag temporarily floats tiled windows and tiles them again on release.
    hl.timer(function() apply_arrival_layout(address, arrival) end, { timeout = 32, type = "oneshot" })
    return
  end

  local target = "address:" .. address
  local window = hl.get_window(target)
  pending_layouts[address] = nil
  if not on_workspace(window, arrival.id) or window.hidden then return end
  if window.pinned then
    if arrival.restore_tag then restore_mode_tag(target) end
    return
  end
  if (window.fullscreen or 0) ~= 0 then
    pending_layouts[address] = arrival
    return
  end

  local floating = current_layout_mode(arrival.id) == "floating"
  if floating then
    if not window.floating then
      local floated = float_below_menu_bar(window)
      if floated and floated.floating then restore_mode_tag(target) end
    elseif arrival.restore_tag then
      restore_mode_tag(target)
    end
  elseif window.floating then
    hl.dispatch(hl.dsp.window.float({ action = "off", window = target }))
  end
end

hl.on("window.move_to_workspace", function(window, workspace)
  local address = window.address
  if not address then return end
  local previous = pending_layouts[address]
  local restore_tag = previous and previous.restore_tag
  local arrival = workspace and workspace.id > 0 and { id = workspace.id, restore_tag = restore_tag } or nil
  pending_layouts[address] = arrival
  if not arrival then
    if restore_tag then restore_mode_tag("address:" .. address) end
    return
  end

  if not window.pinned and is_dragging_window(address) and current_layout_mode(arrival.id) ~= "floating" then
    -- Omarchy would tile a window it floated as soon as it crosses the monitor edge.
    -- Temporarily release the tag so the compositor can keep dragging it until drop.
    for _, tag in ipairs(window.tags or {}) do
      if tag == mode_floated_tag then
        arrival.restore_tag = true
        hl.dispatch(hl.dsp.window.tag({ tag = "-" .. mode_floated_tag, window = "address:" .. address }))
        break
      end
    end
  end
  -- Let the compositor commit the move and Omarchy apply its normal workspace tags.
  hl.timer(function() apply_arrival_layout(address, arrival) end, { timeout = 2, type = "oneshot" })
end)

hl.on("window.fullscreen", function(window)
  local address = window.address
  local arrival = address and pending_layouts[address]
  if arrival then
    hl.timer(function() apply_arrival_layout(address, arrival) end, { timeout = 2, type = "oneshot" })
  end
end)

hl.on("window.destroy", function(window)
  if window.address then pending_layouts[window.address] = nil end
end)

-- MacShell's View and Window menus dispatch this same action.
function o.silky_toggle_window_floating()
  local window = hl.get_active_window()
  if not window then
    return
  end

  if (window.fullscreen or 0) ~= 0 then
    release_fullscreen(window)
    if not window.floating then
      return
    end
  end
  if window.floating and window.workspace then
    for _, peer in ipairs(hl.get_workspace_windows(window.workspace)) do
      if peer.address ~= window.address and (peer.fullscreen or 0) ~= 0 then
        release_fullscreen(peer)
      end
    end
  end
  if window.floating then
    hl.dispatch(hl.dsp.window.float({ action = "off", window = window }))
  else
    float_below_menu_bar(window)
  end
end

-- Keep the chosen window on its workspace and restore its peers on the return toggle.
function o.silky_toggle_isolated_tiling()
  local window = hl.get_active_window()
  if not window then
    return
  end

  local target = "address:" .. window.address
  local workspace = window.workspace
  local workspaces = o.workspaces
  if (window.fullscreen or 0) ~= 0 then
    release_fullscreen(window)
  end
  if not window.floating then
    local floated = float_below_menu_bar(window)
    if floated and floated.floating then
      local session = tiling_sessions[window.address]
      tiling_sessions[window.address] = nil
      if session and on_workspace(floated, session.source) then
        restore_displaced(session)
        hl.dispatch(hl.dsp.focus({ window = target }))
      end
    end
    return
  end
  if not workspace or workspace.special or workspace.id < 1
    or not workspaces or not window.monitor then
    hl.dispatch(hl.dsp.window.float({ action = "toggle", window = target }))
    return
  end

  local first, last
  if workspaces.range then
    first, last = workspaces.range(window.monitor)
  else
    first = workspaces.workspace_id(window.monitor, 1)
    last = first + workspaces.slots - 1
  end
  if workspace.id < first or workspace.id > last then
    hl.dispatch(hl.dsp.window.float({ action = "toggle", window = target }))
    return
  end
  local next_workspace = workspace.id == last and first or workspace.id + 1

  -- Hyprland tiles an entire group together. Detach the chosen window first.
  if window.group and window.group.size > 1 then
    hl.dispatch(hl.dsp.window.move({ out_of_group = true, window = target }))
  end
  hl.dispatch(hl.dsp.window.float({ action = "off", window = target }))

  local tiled = hl.get_window(target)
  if not tiled or tiled.floating then
    return
  end

  local peers = {}
  for _, other in ipairs(hl.get_workspace_windows(tostring(workspace.id))) do
    if other.address ~= window.address and other.mapped then
      table.insert(peers, { address = other.address, pinned = other.pinned == true })
    end
  end
  for _, peer in ipairs(peers) do
    local selector = "address:" .. peer.address
    local current = hl.get_window(selector)
    -- Moving a group may have already carried this member along.
    if on_workspace(current, workspace.id) then
      if current.pinned then
        hl.dispatch(hl.dsp.window.pin({ action = "off", window = selector }))
      end
      hl.dispatch(hl.dsp.window.move({ workspace = tostring(next_workspace), follow = false, window = selector }))
      local moved = hl.get_window(selector)
      if peer.pinned and on_workspace(moved, workspace.id) and not moved.pinned then
        hl.dispatch(hl.dsp.window.pin({ action = "on", window = selector }))
      end
    end
  end
  local displaced = {}
  for _, peer in ipairs(peers) do
    if on_workspace(hl.get_window("address:" .. peer.address), next_workspace) then
      displaced[peer.address] = peer.pinned
    end
  end
  tiling_sessions[window.address] = { source = workspace.id, destination = next_workspace, displaced = displaced }

  hl.dispatch(hl.dsp.focus({ window = target }))
end

o.bind_expressions[o.silky_toggle_window_floating] = "o.silky_toggle_window_floating"
o.rebind("SUPER + T", "Toggle window floating/tiling", o.silky_toggle_window_floating)
o.bind_expressions[o.silky_toggle_isolated_tiling] = "o.silky_toggle_isolated_tiling"
o.bind("SUPER + ALT + T", "Toggle isolated tiling", o.silky_toggle_isolated_tiling)

-- Universal paste: Ctrl+V, or Ctrl+Shift+V in a terminal (same as Omarchy's clipboard.lua, whose helpers are local).
local function send_once(mods, key)
  hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "down" }))
  hl.timer(function()
    hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "up" }))
  end, { timeout = 50, type = "oneshot" })
end

o.bind("SUPER + ALT + V", "Universal paste", function()
  local window = hl.get_active_window()
  for _, tag in ipairs((window and window.tags) or {}) do
    if tag:gsub("%*$", "") == "terminal" then
      return send_once("CTRL SHIFT", "V")
    end
  end
  send_once("CTRL", "V")
end)
