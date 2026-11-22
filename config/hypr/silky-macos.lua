-- Silky Omarchy: macOS traffic lights on Omarchy's floating-window titlebars.
--
-- Omarchy draws titlebars itself on floating workspaces (omarchy-hyprland-titlebars, a hyprbars build, loaded by
-- default/hypr/workspace-modes.lua). Under a macOS Tahoe theme this restyles them: a unified title bar, centred title,
-- and round red / yellow / green lights on the left. hypr/silky-titlebar-guard.lua (required before Omarchy's
-- defaults) keeps Omarchy's own square buttons out, so there is only one set.
--
-- Apps that draw their own window controls (Claude, Chrome, Electron apps, GTK / libadwaita, MacShell) get no bar
-- at all, so no window shows two sets of buttons. Add a class to `with_bar` to give another app the lights.
local bars = hl.plugin and hl.plugin.hyprbars
-- Nothing floats yet, so Omarchy has not loaded the plugin: no bars, and no hyprbars rules to register.
if not (bars and silky_macos_titlebars) then return end

local function read(path)
  local file = io.open(path, "r")
  if not file then return "" end
  local text = file:read("*a")
  file:close()
  return text
end
local light = read(os.getenv("HOME") .. "/.local/state/omarchy/current/theme/colors.toml"):match('mode%s*=%s*"light"') ~= nil

hl.config({
  plugin = {
    hyprbars = {
      bar_height = 30,
      bar_color = light and "rgba(ecececcc)" or "rgba(2b2b2dcc)",
      bar_color_inactive = light and "rgba(f6f6f6d6)" or "rgba(232325d6)",
      bar_blur = true,
      col = { text = light and "rgba(000000d9)" or "rgba(ffffffd9)" },
      bar_title_enabled = true,
      bar_text_font = "Open Runde, Inter, sans-serif",
      bar_text_size = 11,
      bar_text_weight = "semibold",
      bar_text_align = "center",
      bar_buttons_alignment = "left",
      bar_padding = 12,
      bar_button_padding = 8,
      -- 12 px lights with a 6 px radius: circles, not squares.
      button_rounding = 6,
      button_border_size = 0,
      -- Glyphs only while the pointer is over the lights; an unfocused window's lights turn grey, like macOS.
      icon_on_hover = true,
      inactive_button_color = light and "rgb(d1d0d2)" or "rgb(4e4e50)",
    },
  },
})

local gestures = hl.plugin.silky_gestures
local draw_marks = gestures and gestures.enable_titlebar_marks
if draw_marks then draw_marks() end

-- Left to right: close, minimize to Dock, zoom. %WINDOW% targets the clicked window.
local window = [[window = "address:%WINDOW%"]]
local add = bars.silky_add_button or bars.add_button
add({ bg_color = "rgb(ff5f57)", fg_color = "rgb(4d0000)", size = 12, icon = draw_marks and "" or "╳",
  action = "hyprctl dispatch 'hl.dsp.window.close({ " .. window .. " })'" })
function o.silky_yellow_light(address)
  if not address:match("^0x%x+$") then return end
  local target = hl.get_window("address:" .. address)
  if not target or (target.fullscreen or 0) >= 2 then return end
  local fallback = "omarchy-hyprland-window-minimize " .. address
  hl.exec_cmd([[sh -c '[ "$(qs -c MacShell ipc call window minimizeFoot ]] .. address ..
    [[ 2>/dev/null)" = true ] || exec ]] .. fallback .. [[']])
end
add({ bg_color = "rgb(febc2e)", fg_color = "rgb(553700)", size = 12, icon = draw_marks and "" or "―",
  action = [[hyprctl eval 'o.silky_yellow_light("%WINDOW%")']] })
function o.silky_green_light(address)
  local selector = "address:" .. address
  local target = hl.get_window(selector)
  if not target then return end
  local desktop_app = o.silky_desktop_app_layouts[target.class]
  -- The gestures plugin runs the green action on release, after ruling out a hold.
  if (target.class == "foot" and silky_foot_layout_enabled)
      or (desktop_app and silky_desktop_app_layout_enabled) then return end
  local mode = desktop_app and "fullscreen" or "maximized"
  hl.dispatch(hl.dsp.window.fullscreen({ mode = mode, action = "toggle", window = selector }))
end
add({ bg_color = "rgb(28c840)", fg_color = "rgb(004d00)", size = 12, icon = draw_marks and "" or "＋",
  action = [[hyprctl eval 'o.silky_green_light("%WINDOW%")']] })

-- These Qt apps leave their outer window controls to the compositor.
local desktop_apps = { "omacalc", "omacut", "omaview", "omawrite", "io.github.elberacasa.omalogi" }
o.silky_desktop_app_layouts = {}
local desktop_classes = {}
for _, app in ipairs(desktop_apps) do
  o.silky_desktop_app_layouts[app] = true
  desktop_classes[#desktop_classes + 1] = app:gsub("%.", "\\.")
end

local with_bar = "^(foot|kitty|Alacritty|com\\.mitchellh\\.ghostty|org\\.wezfurlong\\.wezterm|org\\.localsend\\.localsend_app|Putty|accessclient-ssh|" .. table.concat(desktop_classes, "|") .. ")$"
hl.window_rule({ name = "silky-macos-no-bar", match = { class = ".*" }, ["hyprbars:no_bar"] = true })
hl.window_rule({ name = "silky-macos-bar", match = { class = with_bar }, ["hyprbars:no_bar"] = false })
