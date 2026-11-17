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
