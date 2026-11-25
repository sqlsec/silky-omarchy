-- Silky Omarchy: crisp, glassy WowType / fcitx5 candidate window (docs/09-wowtype-glass.md).

-- WeChat draws its own candidate bar (its bundled fcitx5-qt client) as a Wayland popup and
-- recreates that popup on every keystroke. With popup fades on, the old bar fades out over
-- the new one, which reads as a blurry double image. Popups appear instantly instead.
hl.animation({ leaf = "fadePopups", enabled = false })

-- Frosted glass behind fcitx5's own candidate window (every other app). The transparent
-- rounded corners of the Silky Glass skin stay unblurred.
hl.config({
  decoration = {
    blur = {
      input_methods = true,
      input_methods_ignorealpha = 0.1,
      -- Keep Wayland IME popups (40% / 50% opacity) blurred while skipping faint
      -- client-side drop-shadow margins on app context menus (alpha < 0.35).
      popups = true,
      popups_ignorealpha = 0.35,
    },
  },
})

-- Let Fcitx place and size its XWayland candidate popup at the text caret.
-- o.window registers the class as self-floating in Omarchy, so the workspace
-- does not apply its default window size or cascading position to the popup.
o.window({
  xwayland = true,
  class = "^fcitx$",
  initial_title = "^Fcitx5 Input Window$",
}, {
  name = "silky-fcitx-xwayland-candidate",
  float = true,
  no_blur = true,
  no_anim = true,
})

-- Match Fcitx5's XWayland candidate panel to the primary display's scale.
o.exec_on_start(os.getenv("HOME") .. "/.local/bin/silky-xwayland-dpi")

-- Omarchy's default Super+I binding calls `omarchy-input-method cycle`, which
-- delegates to `omarchy-shell shell cycleInput`. When MacShell replaces
-- omarchy-shell, that IPC fails and Super+I stops switching input methods.
-- Bind Super+I / Super+Shift+I to talk to Fcitx5's D-Bus controller directly,
-- surviving Omarchy updates because this user module loads after default.hypr.omarchy.
local input_cycle = os.getenv("HOME") .. "/.local/bin/silky-input-cycle"
pcall(hl.unbind, "SUPER + I")
hl.bind("SUPER + I", hl.dsp.exec_cmd(input_cycle), { description = "Switch input language" })
pcall(hl.unbind, "SUPER + SHIFT + I")
hl.bind("SUPER + SHIFT + I", hl.dsp.exec_cmd(input_cycle .. " back"), { description = "Switch input language back" })

-- WPS Office components (Writer, Spreadsheets, Presentation, PDF, and All-in-One shell)
-- supply their own geometry for floating mini toolbars, context menus, and page-number tips.
-- The scrollbar tip maps as KToolTipWidget instead of using the component name.
-- Keep no_initial_focus so the selection mini toolbar does not steal focus from the
-- document window (under click-to-focus, stealing focus turns the next drag-selection into
-- dragging/pasting the previous selection instead of starting a fresh selection).
o.window({
  xwayland = true,
  initial_class = "^(wps|et|wpp|wpspdf|wpsoffice)$",
  title = "^(wps|et|wpp|wpspdf|wpsoffice|KToolTipWidget)$",
}, {
  name = "silky-wps-popups",
  float = true,
  no_anim = true,
  no_blur = true,
  no_shadow = true,
  no_initial_focus = true,
})

-- WPS's Find and Replace dialog is modeless, so the floating workspace treated it as a new
-- app window and stretched it to the standard open box (942x626 on a 1472x920 screen),
-- leaving a large empty area. Float it on its own account so it keeps the compact size and
-- position WPS asks for. Matched by initial_class + title, so only the title is added to the
-- floating-workspace exclusions and WPS document windows keep the mode's default size.
o.window({
  xwayland = true,
  initial_class = "^(wps|et|wpp|wpspdf|wpsoffice)$",
  title = "^(查找和替换|Find and Replace)$",
}, {
  name = "silky-wps-find-dialog",
  float = true,
})

-- The dialog is frameless and WPS does not move it when its header is dragged, and WPS is a
-- self-framed app (no Hyprland titlebar), so it could only be moved with Super+drag. Treat
-- the empty header strip to the right of the 查找/替换/定位 tabs as a title bar: a left press
-- there that travels past a small threshold moves the dialog with the cursor until release.
-- The binds are non-consuming, so WPS still gets every click; the tabs and everything below
-- the header keep their normal behaviour. Sizes are logical pixels.
local WPS_FIND_TITLE = { ["查找和替换"] = true, ["Find and Replace"] = true }
local WPS_FIND_CLASS = { wps = true, et = true, wpp = true, wpspdf = true, wpsoffice = true }
local WPS_FIND_HEADER_HEIGHT = 40
local WPS_FIND_TABS_WIDTH = 200
local WPS_FIND_DRAG_THRESHOLD = 3

local wps_find_drag
local wps_find_drag_timer

local function wps_find_dialog_at(cursor)
  for _, window in ipairs(hl.get_windows() or {}) do
    if WPS_FIND_TITLE[window.title or ""] and WPS_FIND_CLASS[window.initial_class or window.class or ""]
        and window.floating and not window.hidden and (window.fullscreen or 0) == 0
        and window.at and window.size then
      local active = window.monitor and hl.get_active_workspace(window.monitor)
      local x, y = cursor.x - window.at.x, cursor.y - window.at.y
      if (not active or not window.workspace or active.id == window.workspace.id)
          and x >= WPS_FIND_TABS_WIDTH and x < window.size.x
          and y >= 0 and y < WPS_FIND_HEADER_HEIGHT then
        return window
      end
    end
  end
end

local function stop_wps_find_drag()
  wps_find_drag = nil
  if wps_find_drag_timer then
    wps_find_drag_timer:set_enabled(false)
  end
end

wps_find_drag_timer = hl.timer(function()
  local drag = wps_find_drag
  if not drag then
    stop_wps_find_drag()
    return
  end
  local cursor = hl.get_cursor_pos()
  if not cursor or not hl.get_window("address:" .. drag.address) then
    stop_wps_find_drag()
    return
  end
  local dx, dy = cursor.x - drag.cursor_x, cursor.y - drag.cursor_y
  if not drag.moving then
    if math.abs(dx) < WPS_FIND_DRAG_THRESHOLD and math.abs(dy) < WPS_FIND_DRAG_THRESHOLD then
      return
    end
    drag.moving = true
  end
  local x, y = math.floor(drag.window_x + dx + 0.5), math.floor(drag.window_y + dy + 0.5)
  if x ~= drag.last_x or y ~= drag.last_y then
    drag.last_x, drag.last_y = x, y
    hl.dispatch(hl.dsp.window.move({ x = x, y = y, relative = false, window = "address:" .. drag.address }))
  end
end, { timeout = 8, type = "repeat" })
wps_find_drag_timer:set_enabled(false)

hl.bind("mouse:272", function()
  stop_wps_find_drag()
  local cursor = hl.get_cursor_pos()
  local window = cursor and wps_find_dialog_at(cursor)
  if not window then return end
  wps_find_drag = {
    address = window.address,
    cursor_x = cursor.x,
    cursor_y = cursor.y,
    window_x = window.at.x,
    window_y = window.at.y,
  }
  wps_find_drag_timer:set_enabled(true)
end, { non_consuming = true })

hl.bind("mouse:272", stop_wps_find_drag, { release = true, non_consuming = true, ignore_mods = true })

hl.on("config.unload", stop_wps_find_drag)
