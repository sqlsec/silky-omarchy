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

-- Omarchy actions on their new keys. English descriptions on purpose: the keybindings menu translates them.
o.bind("SUPER + CTRL + M", "Omarchy menu", { menu = "root" })
o.bind("SUPER + SHIFT + L", "Cycle workspace layout", "omarchy-hyprland-workspace-layout-toggle")
o.bind("ALT + GRAVE", "Focus on next window", hl.dsp.window.cycle_next())
o.bind("ALT + GRAVE", "Reveal active window on top", hl.dsp.window.bring_to_top())
-- Going backwards lowers the window it leaves (see Omarchy's tiling.lua for why).
o.bind("ALT + SHIFT + GRAVE", "Reveal active window on top", hl.dsp.window.alter_zorder({ mode = "bottom" }))
o.bind("ALT + SHIFT + GRAVE", "Focus on previous window", hl.dsp.window.cycle_next({ next = false }))

local tiling_sessions = {}

hl.on("window.destroy", function(window)
  local address = window.address
  if not address then return end
  tiling_sessions[address] = nil
  for _, session in pairs(tiling_sessions) do
    session.displaced[address] = nil
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

  local top = math.ceil(monitor.y + monitor.reserved.top + 4)
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
