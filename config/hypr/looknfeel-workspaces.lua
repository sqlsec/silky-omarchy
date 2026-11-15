-- Silky Omarchy: smooth macOS-style workspace transitions for Hyprland 0.57+
-- Omarchy disables workspace animations by default, so this companion config
-- is required for the workspace gesture in input-touchpad.lua to animate.

hl.curve("silkyWorkspaceEaseOut", {
  type = "bezier",
  points = { { 0.16, 1.0 }, { 0.30, 1.0 } },
})

hl.animation({
  leaf = "workspaces",
  enabled = true,
  speed = 4.0,
  bezier = "silkyWorkspaceEaseOut",
  style = "slide",
})

