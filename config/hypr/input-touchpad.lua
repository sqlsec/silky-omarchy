-- Silky Omarchy: macOS-style touchpad gestures for Hyprland 0.57+

hl.config({
  input = {
    touchpad = {
      -- Content follows the two-finger movement, as on macOS.
      natural_scroll = true,

      -- Three-finger movement acts as a held left mouse button.
      drag_3fg = 1,
    },
  },
  gestures = {
    -- Stay within existing workspaces at both edges.
    workspace_swipe_create_new = false,
    workspace_swipe_use_r = false,
  },
})

-- Four-finger horizontal swipe switches workspaces with a 1:1 animation.
hl.gesture({ fingers = 4, direction = "horizontal", action = "workspace" })

