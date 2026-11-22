# 03 · Touchscreen workspace gestures and rubber-band

[简体中文](../03-silky-gestures.md) | English

## Goals

- When a four-finger touchpad swipe reaches the first or last workspace, it follows your fingers with macOS-style resistance and springs back, signalling the end
- On the touchscreen, a horizontal swipe with three or more fingers switches workspaces, tracking 1:1
- On the touchscreen, a single finger swiped inward from the left or right edge switches workspaces
- Both touchscreen swipes rubber-band at the ends too
- Move and resize floating windows by finger on the touchscreen: drag the title area to move, drag edges and corners to resize, and long-press anywhere in a window, then drag, to move it as well

## Why a plugin

Hyprland 0.57.2 only ships touchpad gestures and the `gestures.workspace_swipe_touch` edge swipe:

- At the ends it simply zeroes the offset internally: no feedback, no rubber-band option
- There are no multi-finger touchscreen gestures, and the Lua config cannot see touch events
- The built-in edge swipe's hot zone is only `gaps_out + border_size` (12 px here), and taps on the edge get swallowed

So this is done by a small Hyprland plugin: [`plugins/silky-gestures/main.cpp`](../../plugins/silky-gestures/main.cpp). It only listens on Hyprland's event bus and leaves switching and animation to Hyprland's own workspace-swipe logic; it does not modify Hyprland itself and uses no function hooks (hooks only work on x86_64, and this machine is aarch64).

## Behaviour

| Gesture | Effect |
|---|---|
| Four-finger touchpad swipe, continuing past the end | The current workspace follows with resistance and springs back on release |
| Touchscreen horizontal swipe with three or more fingers | Workspaces track 1:1; past halfway or with a quick flick it switches, otherwise it returns |
| Touchscreen single finger swiped inward from within 20 px of the left / right edge | Same as above; swiping right from the left edge shows the workspace on the left |
| Either touchscreen swipe past the end | Resistance, spring back on release |
| Four- or five-finger pinch on touchpad / touchscreen | Opens MacShell's Applications panel (Launchpad) |
| Four- or five-finger spread on touchpad / touchscreen | Closes the Applications panel |
| Four fingers up / down on the touchpad or touch screen | MacShell window overview: every window of the workspace / of the current app, following the fingers (see [13](13-window-overview.md)) |
| Rapid clicks without moving the pointer, where each click changes which layer takes input (the Dock's Applications icon) | Every click takes effect |

Details:

- When a third finger lands, the touches the first two fingers already sent to the app are cancelled, and nothing more goes to the app until all fingers lift
- Single-finger taps on the edge, and dragging up and down along the edge (for example a scrollbar), are still handed back to the app
- The rubber-band uses the `workspaces` animation's curve and speed
- Inactive while the screen is locked
- Four- / five-finger pinch tracks your fingers: the plugin sends the progress to MacShell as socket2 events `silkylaunchpad>>begin`, `update,<amount>`, `end[,cancel]`. "amount" is `1 − scale` (positive when pinching, negative when spreading). On the touchpad it uses libinput's pinch gesture (two- and three-finger pinches are not intercepted); on the touchscreen it uses the average distance of the fingers to their centre, and a change of more than 6% counts as a pinch
- On the touchscreen with four or more fingers, it counts as a workspace switch only if the horizontal movement exceeds 28 px and is larger than both the change in finger spacing and the vertical movement; exactly four fingers moving up or down more than 28 px open the window overview (see [13](13-window-overview.md))
- `hl.gesture`'s pinch is not used: its function actions run only after the fingers lift, so they cannot track the fingers
- Troubleshooting: every touchpad pinch emits `silkypinch>>finger count`. If a four-finger pinch does nothing, run `socat - UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock | grep silky`, pinch again, and see how many fingers libinput reported

- Pinch travel: the panel is fully open once the spread shrinks by about 25% (was 35%), and fully closed after spreading about 30%; on release it completes past one third of the way, otherwise it goes back
- Troubleshooting: touchpad swipe gestures likewise emit `silkyswipe>>finger count`. If a pinch does nothing but `silkyswipe>>4` shows up, libinput classified the pinch as a swipe (see "Four- / five-finger pinch recognition on the touchpad" below)

The tunables are constants at the top of `main.cpp`: edge width `EDGE_PX`, finger count `MULTI_FINGERS`, flick speed `FLICK_PX_PER_SEC`, maximum rubber-band offset `RUBBER_LIMIT`, resistance `RUBBER_STIFFNESS`, plus the pinch finger count `PINCH_FINGERS` and the touchscreen threshold `PINCH_START`. Run the installer again after changing them.

## Four- / five-finger pinch recognition on the touchpad

On the touchpad, "pinch or swipe" is decided by libinput; the plugin only gets the result. For gestures with more than three fingers, libinput 1.32 tracks only the topmost and bottommost touch points:

- In a whole-hand pinch the thumb usually moves less than the other fingers. When the other fingers move more than 8 mm while the thumb moves under 2.5 mm, libinput decides the thumb is "resting", masks it and cancels the gesture, and the remaining fingers are taken as a three-finger drag or a swipe
- When the two tracked points move in neighbouring directions (say one down and one down-right), it is classified as a swipe

That is why four- and five-finger pinches often failed to bring up the Applications panel. [`patches/libinput-1.32.0-multifinger-pinch.patch`](../../patches/libinput-1.32.0-multifinger-pinch.patch) makes gestures with four or more fingers use all touch points: it compares the change in "hand spread" (the average distance of the points to their common centre) with how far that centre moved.

| Condition | Result |
| --- | --- |
| Spread changes ≥ 2.5 mm and by at least 35% of the centre's movement | Pinch |
| Centre moves ≥ 3 mm and the spread changes by less than 35% of that | Swipe |
| Otherwise | Keep waiting |

Verified with simulated traces: a five-finger pinch (thumb moving or not), three fingers plus thumb, and four fingers held together are all classified as pinches about 30% into the motion; four-finger left/right and up/down swipes (including fingers spreading slightly) are classified as swipes at about 8–10%. Two- and three-finger gestures are unaffected. **The effect with real fingers needs confirming on this machine after installing.**

The patch has to be applied to libinput 1.32.0 sources together with [`libinput-1.32.0-immediate-3fg-release.patch`](../../patches/libinput-1.32.0-immediate-3fg-release.patch) (3fg first, then multifinger). The packages already built on this machine are in `~/.local/share/silky-omarchy/libinput/`:

```bash
sudo pacman -U ~/.local/share/silky-omarchy/libinput/libinput-1.32.0-1.2-aarch64.pkg.tar.xz
```

Log out and back in after installing (Hyprland loads libinput at start-up). To go back to the version with only the three-finger-drag patch:

```bash
sudo pacman -U ~/.local/share/silky-omarchy/libinput/libinput-1.32.0-1.1-aarch64.pkg.tar.xz
```

## Rapid repeated clicks

Hyprland decides which window is under the pointer only when the pointer moves. MacShell's Spotlight / Applications panel is a full-screen layer: while open it takes input for the whole screen, closed it takes none. Clicking the Dock's Applications icon rapidly without moving the pointer, every click after the second one (which lands on the panel and closes it) was still delivered to the now-closed panel layer, and nothing happened until the mouse moved.

The plugin listens for mouse buttons: on press, if no other button is held, the pointer is not locked, and the current pointer focus is a layer surface (or nothing), it first makes Hyprland re-resolve the surface under the pointer (`simulateMouseMovement`), then handles the click. With focus on a normal window it does nothing.

Measured with a virtual mouse (pointer resting on the icon): bursts of 8, 9 and 11 clicks at 6–9 clicks per second toggled the panel on every click, ending in the state matching the parity of the click count; before the fix only the first two clicks worked.

## Install

```bash
./scripts/install-silky-gestures.sh
```

The script:

1. Builds the plugin against the installed Hyprland headers
2. Installs it to `~/.local/lib/silky-omarchy/silky-gestures-<Hyprland version>.so`
3. Copies [`config/hypr/silky-gestures.lua`](../../config/hypr/silky-gestures.lua) to `~/.config/hypr/` and appends `require("hypr.silky-gestures")` to `hyprland.lua` (after a backup)
4. Reloads the configuration

Add `--build-only` to just build it without enabling it.

### After a Hyprland update

The plugin is tied to the Hyprland version. The file name carries the version, so after a Hyprland update the old file is not loaded; the gestures are simply inactive for a while, with no errors. Log in again and run the installer once more.

## Moving and resizing floating windows on the touchscreen

Hyprland 0.57 only accepts `xdg_toplevel.move` / `resize` requests carrying a mouse-button serial and drops those started by a finger, so floating windows could not be dragged on the touchscreen (before, only MacShell's About window and friends had their own `TouchWindowMove.qml`). The plugin takes over at the compositor level:

| Where the finger goes down | Behaviour |
| --- | --- |
| The top 44 px of a floating window (Omarchy's title bar, the app's own title bar or toolbar) | Starts moving the window after 10 px of movement |
| 8 px inside and outside the window edge (16 px in total); 16 px along both sides at the corners | Starts resizing after 10 px of movement; corners change width and height together |
| Anywhere else in the window | Hold still for 0.4 s, then drag to move; moving before that counts as the app's own drag (scrolling, selecting text) |

**Every touch goes to the app immediately**, exactly as without the plugin; only once it is sure this is a window operation (title area or edge dragged past the threshold, or held still for 0.4 s) does it send the app a standard touch cancel (`wl_touch.cancel`) and take over to move or resize the window. So taps, scrolling and press highlights behave as before, with no delay. If another finger is added after the press (say for a two-finger zoom), the plugin stops paying attention to that touch.

> An early version held the down event back and replayed it to the app on release. The replayed "down" and the real "up" landed in the same `wl_touch.frame`, and Chromium / Electron apps (Claude, Chrome, VS Code) drop such clicks outright, so many places in those windows did not respond to taps. Nothing is held back anymore; the edge workspace swipe still has to hold the down event, and when it replays it, it sends a frame right away, separate from the up event.

Moving and resizing take the same path as Hyprland's mouse drags (`g_layoutManager->beginDragTarget` → `moveMouse` → `endDragTarget`), so snapping and the like behave as with the mouse. Before the drag starts, the pointer is moved to the finger, because the layout reads the drag origin from the pointer position.

Folio handles touches in its file area directly. A swipe scrolls the files and a hold can open the file menu. Drag the top of Folio to move the window. See [Finder-style Folio](04-macos-theme.md#finder-style-folio).

Only floating windows are handled; tiled windows and windows filling the whole screen go to the app as usual. The 20 px workspace swipe at the left and right screen edges takes priority. A finger on a shell layer above the windows (MacShell's Applications / Spotlight panel, the menu bar, the Dock, popup menus: any top or overlay layer, judged by its input region) is left to that layer alone, so it never drags the window behind it.

### Floating windows cannot be dragged under the menu bar

The menu bar uses a reserved area at the top of the screen (the top of `monitor.reserved`, 21 px on this machine). Hyprland only keeps tiled windows out of it; floating windows could be dragged right under the menu bar. The plugin listens to Hyprland's drag controller (`g_layoutManager->dragController()->m_events.motion / ended`, used by both mouse and touch): after each drag step, if the top of the window (title bar included) is above the bottom of the reserved area + 4 px, it is put back below; when resizing from the top edge, the top stops there while the bottom stays put. After the drag ends (`doLater`) it checks once more.

### Windows with a title bar (terminals) and Omarchy's title bar

Omarchy's title-bar plugin (`omarchy-hyprland-titlebars`) handles touch drags on the title bar itself too, but with two problems:

- To decide whether a touch belongs to it, it looks at the **mouse pointer** position (`getMouseCoordsInternal()` in `inputIsValid()`); touches do not move the pointer, so most of the time it ignores the finger and single-finger drags on the title bar do nothing
- When it does take over, it is designed for tiled workspaces: it makes the window floating and pinned when the drag starts and **makes it tiled again on release** (`if (m_bTouchEv) floatWindow(TOGGLE_ACTION_DISABLE)` in `handleUpEvent`), without unpinning it

So drags on the title bar are handled by this plugin (like the title area of any other window); it also notes whether the window was pinned, and after release (`doLater`, before the next frame), if Omarchy's title bar happened to take over too and made the window tiled, it restores floating, puts the window back where it was released, and unpins it if it was not pinned before.

### Places where the app itself does not support touch

Confirmed with diagnostic logging: touch events all reach the window correctly. The terminal pane in the Claude desktop app is a web terminal component (xterm.js) that responds only to the mouse wheel and touchpad scrolling, not to touch-drag scrolling; it behaves the same with this plugin unloaded, so it is a limitation of the app.

### Never send the app "moves without a down"

The plugin temporarily holds back some fingers' down events. If that finger's later motion or up event were then passed to the app, the app would get a touch point it never saw go down; Qt programs (MacShell / Quickshell) crash on that (`QEventPoint::device()` null pointer, crashing in `QQuickDeliveryAgentPrivate::deliverUpdatedPoints`). The first version hit exactly this: while dragging a window a second finger landed and was held back, the state was cleared when the first finger lifted, and the second finger's later events leaked to the app.

Now every touch event goes through a wrapper: the plugin records the ID of every finger whose down event it holds back, and holds back that finger's motion and up events too until it lifts; they pass only when the plugin itself hands the touch back to the app (by replaying the down event). However the gesture state is reset, no unpaired events leak. When the plugin is unloaded with fingers still held back, it sends the app a touch cancel first.

Do not touch the screen while reinstalling the plugin: a finger held down at the moment of reload can produce unpaired events.

Tested on the Yoga Slim 7 14Q8X9's touchscreen: title-area drags, edge/corner resizing, long-press drags, tapping buttons and scrolling all work.

Tunables at the top of `main.cpp`: `TITLE_PX`, `RESIZE_PX`, `CORNER_PX`, `HOLD_MS`.

## Verify

```bash
hyprctl plugin list
```

It should list `silky-gestures`.

## Disable

```bash
hyprctl plugin unload ~/.local/lib/silky-omarchy/silky-gestures-$(pkg-config --modversion hyprland).so
```

To disable it permanently, delete the `require("hypr.silky-gestures")` line from `~/.config/hypr/hyprland.lua`.

## Risk

This is native code running inside the compositor process; a bug can crash Hyprland, and every open app closes with it. Loading, unloading and config reloads were tested in a nested Hyprland instance; the gestures themselves can only be tested with real fingers on real hardware.
