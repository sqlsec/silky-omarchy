-- Silky Omarchy: macOS traffic lights on Omarchy's floating-window titlebars.
--
-- Omarchy draws titlebars itself on floating workspaces (omarchy-hyprland-titlebars, a hyprbars build, loaded by
-- default/hypr/workspace-modes.lua). Under a macOS Tahoe theme this restyles them: a unified title bar, centred title,
-- and round red / green lights on the left. hypr/silky-titlebar-guard.lua (required before Omarchy's
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
      bar_color = light and "rgb(ececec)" or "rgb(2b2b2d)",
      bar_color_inactive = light and "rgb(f6f6f6)" or "rgb(232325)",
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

-- Left to right: close, zoom, in Apple's colours. %WINDOW% is the window the bar belongs to.
local window = [[window = "address:%WINDOW%"]]
local add = bars.silky_add_button or bars.add_button
add({ bg_color = "rgb(ff5f57)", fg_color = "rgba(4d0000c0)", size = 12, icon = "×",
  action = "hyprctl dispatch 'hl.dsp.window.close({ " .. window .. " })'" })
add({ bg_color = "rgb(28c840)", fg_color = "rgba(004d00c0)", size = 12, icon = "+",
  action = "hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = \"maximized\", action = \"toggle\", " .. window .. " })'" })

local with_bar = "^(foot|kitty|Alacritty|com\\.mitchellh\\.ghostty|org\\.wezfurlong\\.wezterm|org\\.localsend\\.localsend_app)$"
hl.window_rule({ name = "silky-macos-no-bar", match = { class = ".*" }, ["hyprbars:no_bar"] = true })
hl.window_rule({ name = "silky-macos-bar", match = { class = with_bar }, ["hyprbars:no_bar"] = false })
