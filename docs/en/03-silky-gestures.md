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

- Pinch travel: the panel is fully open once the spread shrinks by about 22% (was 35%), and fully closed after spreading about 28%; on release it completes past one third of the way, otherwise it goes back
- Troubleshooting: touchpad swipe gestures likewise emit `silkyswipe>>finger count`. If a pinch does nothing but `silkyswipe>>4` or `silkyswipe>>3` shows up, libinput classified the pinch as a swipe (see "Four- / five-finger pinch recognition on the touchpad" below)

The tunables are constants at the top of `main.cpp`: edge width `EDGE_PX`, finger count `MULTI_FINGERS`, flick speed `FLICK_PX_PER_SEC`, maximum rubber-band offset `RUBBER_LIMIT`, resistance `RUBBER_STIFFNESS`, plus the pinch finger count `PINCH_FINGERS` and the touchscreen threshold `PINCH_START`. Run the installer again after changing them.

## Four- / five-finger pinch recognition on the touchpad

Libinput classifies touchpad gestures before the Hyprland plugin receives them. Stock 1.32.0 compares only the topmost and bottommost contacts, can drop a stationary thumb so the remaining three fingers start a three-finger drag or swipe down, and caps gesture dispatch at four fingers. An earlier multi-finger patch lifted the four-finger cap, but still relied on a 100 ms thumb window, excluded stationary contacts in the bottom software-button area or side-pressed thumbs flagged as `PALM_TOUCH_SIZE`, and diluted vertical finger contraction with a 4:1 unweighted centroid when five wide fingers grabbed inward.

The updated [multi-finger pinch patch (`1.32.0-1.4`)](../../patches/libinput-1.32.0-multifinger-pinch.patch) models whole-hand landing timing and geometry:

- **350 ms whole-hand assembly and thumb exemption**: when 4 or 5 real MT slots assemble within 350 ms alongside at least 2 regular active fingers, a stationary thumb in the bottom software-button stripe and side-pressed thumb/pinky contacts flagged as `PALM_TOUCH_SIZE` / `PALM_PRESSURE` / `PALM_EDGE` remain part of the hand, and fast upper-finger motion no longer demotes the thumb from `THUMB_STATE_PINCH` to `SUPPRESSED`.
- **Combined radial dispersion and opposing thumb-to-cluster span**: both radial spread and the distance between the lowest contact (thumb) and the upper finger cluster are strictly translation-invariant under rigid four-finger horizontal/vertical swipes (zero change), while preserving full contraction magnitude during a wide five-finger vertical grab.
- **Dynamic `3 → 4 → 5` promotion and early-swipe recovery**: if the first three fingers start an early `3FG_DRAG_OR_SWIPE`, `SWIPE` (preventing false three-finger swipes down), or `HOLD` within 220 ms before the 4th/5th finger lands, the early gesture is cancelled and rebaselined to 4 or 5 fingers. If a 5th finger lands within 260 ms after a 4-finger pinch has already started, its initial distance is recalibrated against the current scale so the gesture upgrades to 5 fingers without a progress jump.
- **Clean lift completion and rapid post-pinch tap unlock**: lifting the first finger ends the whole-hand pinch so trailing fingers cannot start a swipe; the lift guard clears immediately once all fingers leave, a fresh touch begins (an immediate tap right after pinching), or a lone corner contact lingers past 120 ms.

| Condition | Result |
| --- | --- |
| 4 fingers: combined spread or opposing-span change ≥ 1.5 mm and ≥ 34% of centroid travel | Pinch or spread |
| 5 fingers: combined spread or opposing-span change ≥ 1.3 mm and ≥ 22% of centroid travel | Pinch or spread |
| 4 fingers: travel ≥ 4 mm (change < 22%) or ≥ 7 mm (change < 34%); 5 fingers: rigid travel ≥ 9 mm (change < 16%) | Swipe |
| Otherwise | Keep waiting |

On Arch Linux ARM aarch64, run these commands from the repository root. The build requires `base-devel`, libinput's runtime dependencies, and the stock Arch `libinput 1.32.0-1` package (if Meson or Ninja are not installed globally, the build script automatically extracts cached archives from `/var/cache/pacman/pkg/`). It preserves the package's device rules and configuration and applies the [immediate three-finger drag release patch](../../patches/libinput-1.32.0-immediate-3fg-release.patch).

```bash
./scripts/build-silky-libinput.sh
sudo pacman -U ~/.local/share/silky-omarchy/libinput/libinput-1.32.0-1.4-aarch64.pkg.tar.xz
```

Log out and back in after installation so Hyprland loads the new library. Verify `1.32.0-1.4` with `pacman -Q libinput`, then watch Hyprland's socket2 for `silkypinch>>4` and `silkypinch>>5`. Isolated C trajectory simulations verified staggered `3 → 5` landing with bottom-button/palm-sized thumbs, 4 mm wide-hand vertical grabs, seamless `4 → 5` mid-pinch promotion, rapid post-pinch taps with a lingering corner thumb, and crisp four-finger swipes; physical touchpad feel requires verification in the new login session.

To roll back, reinstall the stock package and log out and back in.

```bash
sudo pacman -U /var/cache/pacman/pkg/libinput-1.32.0-1-aarch64.pkg.tar.xz
```

## Rapid repeated clicks and Dock pass-through

While Applications is open, `macspot` carves the Dock capsule out of its overlay input mask ([`tune-apps-dock-passthrough.py`](../../scripts/tune-apps-dock-passthrough.py) and [`tune-apps-panel.py`](../../scripts/tune-apps-panel.py)) so the Dock stays directly interactive: clicking the Dock's Applications icon smoothly closes or reverses the panel, and rapid repeated clicks always hit the same `MacDock` surface without cross-layer region races; clicking any other Dock icon launches or switches to that app while dismissing Applications; clicking empty desktop space anywhere outside the panel and Dock still closes Applications immediately.

In addition, `onMouseButton` in `silky-gestures` only triggers synthetic pointer focus re-evaluation when the currently focused surface differs from the top `LayerSurface` actually under a stationary cursor, avoiding redundant motion events during rapid taps on Dock or panel icons.

Reload the [gesture plugin](../../scripts/install-silky-gestures.sh) and update both `MacBar.qml` and `MacDock.qml` via [`restore-silky-apps-panel.py`](../../scripts/restore-silky-apps-panel.py) or the [MacShell optimizations installer](../../scripts/install-macshell-optimizations.sh):

```bash
python3 scripts/restore-silky-apps-panel.py
qs ipc -c MacShell call macshell reload
```

Verify outside click-to-dismiss with a stationary pointer, rapid repeated clicks on the Dock Applications icon, clicking other Dock icons while Applications is open, rapid icon taps immediately after opening the panel, and typing in the search field. Roll back by restoring the `MacBar.qml.before-apps-update.*` and `MacDock.qml.before-apps-update.*` backups in `~/.local/state/silky-omarchy/` along with the versioned plugin backup, then reloading both.

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

### Automatic recovery after system updates

`./scripts/install-silky-gestures.sh` registers the [Omarchy post-update hook](../../hooks/post-update-silky-gestures) once. It runs after package changes during `omarchy update` and skips work that is already current.

- **Hyprland** checks the installed ABI in addition to the version. It rebuilds and hot-loads when the running ABI matches, or prebuilds for the next login when it differs.
- **Applications and Dock integration**: [`restore-silky-apps-panel.py`](../../scripts/restore-silky-apps-panel.py) restores pinch handling, the critically-damped Tahoe transition, Dock pass-through, and `silky-dock-glass` panel markers across compatible `MacBar.qml` and `MacDock.qml` layouts (verified against MacShell 0.5.2 and 0.5.3), backing up existing files before writing.
- **libinput** tracks the digest of the local `1.32.0-1.4` archive. If stock `1.32.0-1` (or an older `1.1`–`1.3` local build) replaces it, the hook verifies the archive and restores `1.32.0-1.4` automatically. Other upstream versions keep the new system package and report that an updated patch is needed.

Run the gesture installer once after installing the patched libinput to enroll it. To check the hook separately, run the following command. A current installation needs no rebuild or file changes.

```bash
~/.config/omarchy/hooks/post-update.d/silky-gestures.hook
```

To stop libinput recovery, remove `${XDG_STATE_HOME:-$HOME/.local/state}/silky-omarchy/libinput-maintained` before restoring the stock package. To disable all three recovery steps, move `silky-gestures.hook` out of `post-update.d`. The same state directory holds the MacBar backups.

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

### Floating windows cannot cross the menu bar

The menu bar uses a reserved area at the top of the screen (the top of `monitor.reserved`, e.g. 23 px). Hyprland only keeps tiled windows out of it; floating windows can otherwise end up under the menu bar during drags, multi-monitor layout changes, workspace moves, leaving fullscreen, or window open — especially windows like `foot` whose server-side `hyprbars` title bar extends 30 px above `window.at.y`.

Since 0.8.4, the plugin enforces two layers of protection in the compositor:
- **During drags**: listens to `g_layoutManager->dragController()->m_events.motion / ended` (both mouse and touch). After each drag step, if the top of the window (title bar included, `RESERVED_EXTENTS`) is above the bottom of the reserved area + 4 px, it is put back below; when resizing from the top edge, the top stops there while the bottom stays put. Checked once more in `doLater` after the drag ends.
- **Non-drag lifecycle and multi-monitor guard**: listens to `window.openLate`, `window.floating`, `window.fullscreen`, `window.moveToWorkspace`, `workspace.moveToMonitor`, `monitor.added / removed / layoutChanged`, `layer.opened`, `config.reloaded`, and plugin load. Skipping fullscreen and hidden windows, any floating window whose frame actually crosses `monitor.y + reserved.top` is moved back below the menu bar (reducing height if needed to stay within the work area), while snapped half/quarter windows flush with `monitor.y + reserved.top` are left untouched.
- **Exact title-bar inset for Lua**: exposes `hl.plugin.silky_gestures.window_top_inset(address)` returning the real distance from the client surface top to the outer decorated top (`hyprbars` included), used by [`silky-workspaces.lua`](../../config/hypr/silky-workspaces.lua) and [`silky-shortcuts.lua`](../../config/hypr/silky-shortcuts.lua).

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

### Native snap preview overlay (`0.8.5`)

[`plugins/silky-gestures/snap-preview.hpp`](../../plugins/silky-gestures/snap-preview.hpp) renders the half-screen and corner drag-snap preview directly inside Hyprland at `RENDER_POST_WINDOWS` using `CRectPassElement` and `CBorderPassElement` (65 ms fade-in, 45 ms fade-out, 90 ms smooth move on the same output), exposed to [`config/hypr/silky-folio.lua`](../../config/hypr/silky-folio.lua) via `hl.plugin.silky_gestures.snap_preview(output, x, y, w, h)` and `snap_preview_hide()`. This avoids waking a fullscreen transparent Vulkan layer in MacShell over socket2, while falling back automatically to [`FolioSnapPreview.qml`](../../config/macshell/FolioSnapPreview.qml) if the plugin is not loaded.

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
