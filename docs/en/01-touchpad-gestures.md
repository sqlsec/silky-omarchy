# 01 · Touchpad gestures

[简体中文](../01-touchpad-gestures.md) | English

## Goals

- Two-finger scrolling: macOS-style natural scrolling, the content follows your fingers
- Three-finger move: drag windows, files, selected text and sliders like macOS "three-finger drag"
- Four-finger horizontal swipe: switch workspaces on the current monitor with a full-page animation that tracks your fingers
- Rubber-band at the first / last workspace instead of creating a new empty one

## Why this split

If dragging and workspace switching used the same number of fingers, the gestures would fight. Fixing drag to three fingers and workspaces to four is close to macOS habits and is done natively by Hyprland and libinput, with no extra gesture daemon.

## Configuration

Add the contents of [`config/hypr/input-touchpad.lua`](../../config/hypr/input-touchpad.lua) to `~/.config/hypr/input.lua`, and the contents of [`config/hypr/looknfeel-workspaces.lua`](../../config/hypr/looknfeel-workspaces.lua) to `~/.config/hypr/looknfeel.lua`.

Key settings:

```lua
hl.config({
  input = {
    touchpad = {
      natural_scroll = true,
      drag_3fg = 1,
    },
  },
  gestures = {
    workspace_swipe_create_new = false,
    workspace_swipe_use_r = false,
  },
})

hl.gesture({ fingers = 4, direction = "horizontal", action = "workspace" })
```

`touchpad.natural_scroll = true` flips the touchpad scroll direction: moving two fingers up moves the page content up. The outer `input.natural_scroll = true` gives the mouse wheel the same direction. MacShell used to write that at start-up, so it was lost whenever MacShell was not running; it now lives in the Hyprland config. `drag_3fg = 1` selects three-finger drag; `2` would use four fingers and clash with the four-finger workspace gesture, so do not use it.

### Workspace transition animation

Omarchy turns the `workspaces` animation off by default. With only the touchpad gesture added, workspaces would still switch abruptly. This override enables a full-page horizontal slide and, after you lift your fingers, finishes the switch or the rubber-band with a fast-out, slow-in ease:

```lua
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
```

`speed = 4.0` means the animation after release takes at most about 400 ms; while dragging, your fingers control the progress directly.

## Apply and verify

```bash
hyprctl reload
hyprctl configerrors
hyprctl getoption input:touchpad:natural_scroll
hyprctl getoption input:natural_scroll
hyprctl getoption input:touchpad:drag_3fg
hyprctl animations
```

Expected:

- `hyprctl configerrors` prints nothing
- `natural_scroll` shows `bool: true` and `set: true`
- `drag_3fg` shows `int: 1` and `set: true`
- In `hyprctl animations`, `workspaces` shows `enabled: 1` and `style: slide`
- Moving three fingers on the touchpad drags the item under the pointer
- A four-finger horizontal swipe moves the workspace with your fingers and switches or springs back on release

## Rollback

Remove the `hl.config`, `hl.gesture`, `hl.curve` and `hl.animation` blocks above, then run again:

```bash
hyprctl reload
hyprctl configerrors
```

## Tested on

- Omarchy Linux
- Hyprland 0.57.2
- Built-in HID-over-I2C touchpad
