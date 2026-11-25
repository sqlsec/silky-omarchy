# 01 · Touchpad gestures

[简体中文](../01-touchpad-gestures.md) | English

## Goals

- Two-finger scrolling: macOS-style natural scrolling, the content follows your fingers
- Three-finger move: drag windows, files, selected text and sliders like macOS "three-finger drag"
- Four-finger horizontal swipe: switch workspaces on the current monitor with a full-page animation that tracks your fingers
- Four fingers up / down: window overview (every window of the workspace / of the current app), also with four fingers on the touch screen, done by the silky-gestures plugin and MacShell, see [13](13-window-overview.md)
- Rubber-band at the first / last workspace instead of creating a new empty one
- Visual gesture previews and live switches in MacShell Settings → **Trackpad**, see [02 · Trackpad gesture animations and Touchscreen guide](02-macshell.md#trackpad-gesture-animations-and-touchscreen-guide)

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

### Touchscreen scrolling in WeChat’s conversation list

WeChat 4.x is a closed-source frameless Qt client that paints its own top bar and window controls (minimize `—`, maximize `□`, close `×`) inside the app, so we keep its built-in controls rather than stacking a duplicate compositor title bar. Previously, native Wayland startup depended on a binary patch and SHA-256 check pinned to `wechat-bin 4.1.13.26` on ARM64; upgrading to `4.1.13.29` broke the hash check and silently fell back to XWayland (`QT_QPA_PLATFORM=xcb`), which broke top-bar mouse dragging, disabled touchscreen scrolling in both the conversation list and chat pane, and left the minimize button inert.

The updated Wayland adapter [plugins/wechat-wayland/touch-scroll.c](../../plugins/wechat-wayland/touch-scroll.c) and launcher [bin/wechat-wayland-touch](../../bin/wechat-wayland-touch) fix these issues at the Wayland protocol layer without patching the WeChat binary:

- **Empty `wl_touch.frame` guard**: WeChat’s bundled `QWaylandInputDevice::Touch::touch_frame()` dereferences an empty touch-point list and segfaults whenever an empty `wl_touch.frame` arrives (for example, right after `silky-gestures` sends `touch_cancel` + `touch_frame`). The `LD_AUDIT` adapter only forwards `touch_frame` when the current frame actually delivered a `down`, `motion`, or `up` event, keeping native Wayland stable across WeChat upgrades.
- **Top-bar drag and built-in window controls**: under native Wayland, dragging the top bar uses `xdg_toplevel.move` natively and close hides to the tray. Because WeChat sends void `xdg_toplevel` requests through `wl_proxy_marshal_array`, Omarchy sets global `suppress_event = "maximize"`, and Hyprland ignores `set_minimized`, the adapter intercepts both `wl_proxy_marshal_array` and `wl_proxy_marshal_array_flags` and only forwards requests that follow an in-window pointer button or touch tap within 500 ms: `xdg_toplevel.set_minimized` (opcode 13) minimizes to the Dock (via MacShell Genie or `omarchy-hyprland-window-minimize`), and `set_maximized` (opcode 9) / `unset_maximized` (opcode 10) toggle maximization on the active WeChat window via `hyprctl eval`, while blocking unsolicited `set_maximized` requests emitted by bundled Qt when reopening from the tray or launcher.
- **Touchscreen scrolling in the conversation list and chat pane**: single-finger touches below the top bar (`y >= 54` logical px) buffer `touch_down` instead of forwarding it immediately, preventing WeChat from opening the conversation or item under your finger on press before a scroll starts; moving vertically by 6 px drops the buffered press silently and enters 1:1 zero-lag scrolling (`WL_POINTER_AXIS_SOURCE_FINGER`) across both the conversation list and chat history pane, while lifting in place (tap) or dragging horizontally by 6 px flushes the buffered press normally so taps and text selection still work. On release, a main-thread `wl_surface_frame` VSync callback drives exponential kinetic glide from the last 90 ms of finger velocity (piggybacking on Qt's own surface commits so it stops cleanly at list bounds), and touching the screen during glide brakes immediately while suppressing an accidental tap. Touchpad scrolling and mouse wheel stay intact. Set `WECHAT_TOUCH_SCROLL_SCALE` (default `1.0`) to tune scroll gain, `WECHAT_TOUCH_SCROLL=0` to disable touch-to-scroll while keeping the empty-frame guard and minimize forwarding, or `WECHAT_WAYLAND=0` to fall back to XWayland temporarily.

Run the installer from the repository root to build the adapter, install the launcher and user desktop entry, and reload Hyprland:

```bash
./scripts/install-wechat-touch-scroll.sh
```

It requires GCC or a compatible C compiler, `pkg-config`, the Wayland client development files, and Hyprland Lua configuration. It backs up before overwriting `~/.local/share/wechat-wayland/touch-scroll.so`, `~/.local/bin/wechat-wayland-touch`, `~/.local/share/applications/wechat.desktop`, and `~/.config/hypr/silky-wechat-glass.lua`. Quit WeChat completely and reopen it from the app launcher to apply.

To verify:

- Run `hyprctl clients -j | jq -c '.[] | select(.class=="wechat") | {title, xwayland}'` and confirm `xwayland` is `false`, and that `/proc/$(pgrep -x wechat | head -n 1)/maps` maps `touch-scroll.so`.
- Live testing on this machine confirmed WeChat `4.1.13.29` (ARM64) launches directly in native Wayland with the adapter loaded. Isolated unit tests verified empty `touch_frame` suppression, post-cancel empty-frame filtering, normal tap forwarding, vertical drag-to-scroll below the top bar, and top-bar exclusion. Physical touchscreen feel across both panes and live click checks on the signed-in main window controls remain to be checked interactively.

To roll back, quit WeChat and restore the installer’s `*.bak.*` copies of `touch-scroll.c` and `touch-scroll.so` in `~/.local/share/wechat-wayland/`, `~/.local/bin/wechat-wayland-touch`, `~/.local/share/applications/wechat.desktop`, and `~/.config/hypr/silky-wechat-glass.lua`. Run `hyprctl reload`, then reopen WeChat.


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

- Omarchy 4.5.0
- Hyprland 0.57.2
- libinput 1.32.0
- Built-in HID-over-I2C touchpad
