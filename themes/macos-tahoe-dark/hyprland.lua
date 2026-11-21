-- macOS Tahoe · Dark: window chrome. Loaded by Omarchy in place of the generated border colours.
-- A hairline edge, continuous-curve corners, a deep soft shadow under the focused window,
-- and Liquid-Glass style frosting behind anything translucent.
local active_border_color = "rgba(ffffff3d)"
local inactive_border_color = "rgba(ffffff1f)"

hl.config({
  general = {
    border_size = 1,
    col = {
      active_border = active_border_color,
      inactive_border = inactive_border_color,
    },
  },

  group = {
    col = {
      border_active = active_border_color,
      border_inactive = inactive_border_color,
    },
  },

  decoration = {
    rounding = 14,
    rounding_power = 2.6,

    shadow = {
      enabled = true,
      range = 36,
      render_power = 3,
      offset = { 0, 14 },
      scale = 0.97,
      color = "rgba(00000099)",
      color_inactive = "rgba(00000055)",
    },

    blur = {
      enabled = true,
      size = 7,
      passes = 3,
      new_optimizations = true,
      xray = false,
      contrast = 1.05,
      brightness = 1.0,         -- same as the light theme: MacShell glass looks like Liquid Glass (no extra darkening)
      noise = 0.012,
      vibrancy = 0.45,
      vibrancy_darkness = 0.45,
      popups = true,
      special = true,
    },
  },
})
