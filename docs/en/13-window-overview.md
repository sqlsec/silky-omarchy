# 13 · Four fingers up / down: window overview

[简体中文](../13-window-overview.md) | English

## Goal

The same as macOS:

| Gesture | Effect |
| --- | --- |
| Touchpad / touchscreen four fingers up | Show workspace previews above the windows of the current workspace |
| Touchpad four fingers left or right while the workspace overview is open | Switch workspaces and keep the overview open. Clicking a workspace preview also switches. |
| Four fingers down on the touchpad or touch screen | Every window of the current app (App Exposé), including its windows on other workspaces |
| The opposite swipe once open | Back to the desktop |

Animation requirements:

- **Follows the fingers**: while the fingers are on the touchpad, progress depends only on how far they have moved; moving back goes back
- **Linear**: each window's position and size is a linear interpolation between where it really is and its place in the grid, with no easing curve on top; after release it finishes at a constant speed
- **Interruptible and reversible**: put four fingers down while the release animation is still running and they take over from the current progress, in either direction
- **Natural transitions**: the first frame matches the real desktop (same windows, same positions and stacking, same wallpaper), with no flash and no jump

## How it works

Two parts, the same split as the four-finger pinch that opens the Applications panel:

1. **The Hyprland plugin** (`CSilkyOverviewGesture` in [`plugins/silky-gestures/main.cpp`](../../plugins/silky-gestures/main.cpp)) recognizes the gesture and sends its progress out as socket2 events
2. **A MacShell component** ([`config/macshell/overview/SilkyOverview.qml`](../../config/macshell/overview/SilkyOverview.qml)) draws it

### Plugin: a native four-finger vertical gesture

Hyprland 0.57's touchpad gesture table (`g_pTrackpadGestures`) is open to plugins. The plugin adds a four-finger `vertical` gesture to it:

```cpp
g_pTrackpadGestures->addGesture(makeUnique<CSilkyOverviewGesture>(), 4, TRACKPAD_GESTURE_DIR_VERTICAL,
                                Input::HL_MODIFIER_NONE, 1.F, false);
```

Hyprland decides from the first ~5 units of travel whether a swipe is horizontal or vertical: horizontal goes to the existing four-finger workspace gesture, vertical comes here, so the two never fight. `hl.gesture` Lua function actions are not used: each update could only start a process to tell MacShell, which cannot keep up with the fingers.

Events sent by the plugin:

```text
silkyoverview>>begin,up       four fingers started, first moving up (down for down)
silkyoverview>>update,<travel>,<time> total travel since the start, in touchpad units, up is positive; time = when the fingers were there, wall-clock ms (since 0.8.1)
silkyoverview>>end            fingers lifted (end,cancel: the gesture was cancelled)
```

Notes:

- Hyprland clears the gesture table on every config reload (between `config.preReload` and `config.reloaded`). The plugin listens for `reloaded` and registers again. The plugin itself is loaded while a config is being read, after the clear, and registers once then; `preReload` sets a flag so the first `reloaded` does not register it a second time
- The gesture must be removed from the table before the plugin unloads, or Hyprland would call virtual functions in unloaded code and crash
- If the config already has a four-finger `vertical` / `up` / `down` / `swipe` gesture, registering fails and the plugin shows a notification saying why
- Nothing happens while the session is locked

### Plugin: four fingers up / down on the touch screen

A touch screen has no libinput gestures, so the plugin tracks the touch points itself (the same code as the three-finger workspace swipe and the four-finger pinch, see `checkTouchOverview`):

- Exactly four fingers whose centre moves up or down more than `OVERVIEW_START_PX` (28 px), with the vertical travel more than 1.2× the sideways travel and more than the change in finger spread, is the overview gesture; those 28 px are taken off the start so the picture does not jump
- The travel is converted to touchpad units and sent as the same `silkyoverview` events: `OVERVIEW_SPAN` (22 %) of the screen height = 240 units = fully open, so MacShell needs no second tuning
- The first finger to lift ends it (as with the pinch); adding or removing a finger mid-way does not make the picture jump
- The four-finger pinch still comes first, but only a spread change larger than half the distance the fingers' centre moved counts as a pinch, so fingers drifting apart a little while sliding up together are not taken for one; the four-finger workspace swipe likewise needs more sideways than vertical travel
- Once the overview is open, tap a window with one finger to pick it; swipe four fingers the other way to close

### MacShell: one number drives everything

`SilkyOverview.qml` has a single progress value `p` (0 = desktop, 1 = overview):

- With fingers down: `p = starting progress ± travel / distance`; up opens the workspace overview, down opens the app's windows; clamped to 0–1
- Every window is a window capture (MacShell's own `SafeCapture`, which never releases a capture while a frame is in flight, so the Wayland connection cannot die), and its rectangle is `lerp(real rect, grid rect, p)`. The picture keeps the window's own fixed size: a new frame is only copied into a texture (`ShaderEffectSource`, no effect pass), and a small shader, [`silkyround.frag`](../../config/macshell/overview/silkyround.frag), draws it with anti-aliased rounded corners at the current size, so moving and scaling cost nothing extra. The overview requests a batch of frames when a gesture begins and refreshes active windows once a workspace switch settles. See “Smoothness” for why the pictures are snapshots.
- In app mode the workspace's other windows stay where they are with opacity `1 − p`; the app's windows on other workspaces grow linearly in their grid places from 88 % size and opacity 0 to 100 %
- The static wallpaper keeps the desktop’s brightness and crop. When Omarchy’s background layer draws the wallpaper, the overview reads Omarchy’s current wallpaper link. Otherwise it prefers the image currently shown by awww or swww. The menu bar and Dock keep their reserved desktop strips.
- Each thumbnail has a Hyprland-like shadow from the first frame on
- On release: the fingers' speed over the last ~90 ms projects where `p` would be 0.12 s later; past half opens, otherwise closes. It then moves to the end at a **constant speed** of `max(finger speed, minSpeed)`
- Four fingers down again mid-animation: the animation stops and the fingers carry on from the current `p`
- **Solid all the way back**: opening cross-fades the overview in over the first 12 % of the progress; once it has been fully opaque, the thumbnails stay opaque on the way back until they sit exactly on the real windows (same places and stacking, the picked one on top), and only then does the whole layer fade out over 80 ms (`outroMs`). The only thing that changes then is what a capture does not have: Hyprland's borders, title bars and shadows. Earlier versions cross-faded on the way back too: the half-transparent overview over the real desktop made a double image, and after a fast swipe the fade started as early as p = 0.5, so the windows went see-through half-way back and the picked one turned solid again at the end
- **The fingers are sampled by time**: the plugin adds to every `update` the time the fingers were really there (libinput's event time as wall-clock ms). socket2 delivers the events to MacShell in bursts (more than half arrive within 1 ms of each other, then nothing for 30 ms or more), so setting the progress on arrival moved the picture in jumps although every frame was on time. Now each frame reads the progress off the timestamped finger track at its own time minus `lagMs` (10 ms), extrapolating at the fingers' speed for at most `extrapMs` (16 ms) past the newest sample, so every step matches the fingers' real speed. The release speed uses these times too
- **By the clock**: the constant-speed animation after release computes its position from the clock, not by adding up the last frame's duration: a late frame used to make the next one take a double step, a visible hitch. A stall longer than 50 ms does not make it jump; it carries on from where it stopped
- **The layer fades as one picture**: while the overview is on screen it has `layer.enabled`, so it is flattened first and its opacity applied to the result. QML's `opacity` is otherwise applied to every child on its own: each thumbnail turned half-transparent and the windows stacked under it showed through (Firefox and Claude through Chrome), so the two or three frames of the fade were a mix of every window, seen as a flash at the very end. Flattened, the fading picture is exactly the real desktop underneath and nothing shows through. In a frame-by-frame screen recording, the brightness change between frames dropped from 10–20 to about 1

Details that make the start seamless:

- **The window stays mapped, parked off-screen**: the overview layer is always mapped and, while closed, sits at full size just left of the screen (like MacShell's Spotlight), taking no input or keyboard focus, and Hyprland does not draw it; a swipe only moves it in. An earlier version created the window when the swipe began, building its Vulkan surface, swapchain and shader pipelines on the GUI thread: measured at about 0.5 s with no frames on every swipe, so the fingers were a third of the way before anything appeared, and then the picture "caught up" in one go. Frames now start about 10 ms after `begin`, at a steady 90 Hz. Also: right after startup everything is drawn once at 1 % opacity so the shaders are compiled in advance; the effect layers stay enabled, so nothing is allocated mid-gesture; the layer has a `no_anim` rule, so Hyprland's own layer fade does not play on top of the finger-driven animation
- **Captures stay attached**: windows on the current workspace keep a capture attached (no frames requested, so practically free while idle), and a fresh frame is requested the moment the fingers come down, so the pictures are already there when the swipe starts. This does not follow the Dock's "live window capture" switch (that one is about Dock previews); only MacShell's crash-safety pauses (a capture storm, a close in progress, Game Mode) hold it. An earlier version followed that switch: with it off the overview had no pictures at all and showed every window as a grey app-icon card (each looking up and rendering its icon synchronously on the GUI thread), which was the flash and the stall at the start
- **Wait for the first frame, cross-fade in**: fresh frames get at most 60 ms (at least 24 ms, so the refreshed ones arrive); finger travel during that wait still counts. Once the picture appears the overview cross-fades from fully transparent to opaque over the next 12 % of travel, so the real windows' Hyprland shadow, border and title bar (none of them is in a window capture) dissolve instead of vanishing in one frame
- **Stacking order**: fullscreen windows on top, then floating windows, each ordered by most recent focus, matching Hyprland's real order

### Workspace previews and navigation

The preview cards show each workspace’s windows in their desktop positions and stacking order. Empty workspaces show the wallpaper. A highlighted outline and label mark the current workspace. Click a card or use the existing Hyprland four-finger horizontal gesture. The lower window grid slides in the selected direction. A four-finger swipe moves the windows with your fingers, then settles on the new workspace or slides back when you release. The wallpaper and preview strip stay in place. Closing the overview leaves you on the selected workspace. The cards reuse the overview’s window snapshots and show placeholders when the compositor cannot supply a frame. Silky Gestures 0.8.3 publishes native swipe progress, and Hyprland decides whether to commit the switch. Reinstall both the gesture plugin and the overview component, then reload MacShell.

Once open:

- Hovering a window: blue outline, title below it
- Clicking / tapping a window (or Enter while hovering): focuses it and closes the overview, flying back a little faster than a plain close (`pickSpeed`: about 0.3 s from fully open, about 0.4 s from click to done; it was about 0.75 s), the clicked window on top as it flies back; if it is on another workspace, that workspace is switched to and the overview fades out as a whole. The open overview holds exclusive keyboard focus, and while a layer does Hyprland refuses to focus any window: earlier versions lost the focus command and the old window stayed on top. Now the overview closes first (releasing the keyboard) and the focus command follows 40 ms later
- Clicking empty space or Esc: closes
- Windows opening, closing or moving lay the grid out again

Grid layout: windows keep their relative sizes (one uniform scale, at most 0.88), are split into rows by their centres top to bottom and left to right; every row count is tried and the one with the largest scale wins.

### Smoothness

No frame may be late, so nothing extra is asked of Hyprland or the apps during the motion. All of this was measured on this machine (`ipc call overview debug true` logs every frame; a second script asks Hyprland's socket every 4 ms to see whether its main loop stalls):

- **The keyboard goes back only after landing**: the overview takes the keyboard as soon as it appears and keeps it until the windows have flown back. An app that has keyboard focus keeps redrawing (a blinking caret, a focus ring), and every redraw makes Hyprland composite every window under the full-screen overview again: as long as an app had focus, about one frame in six was missed. Handing the keyboard back when closing began missed ~18 % of the closing frames; now it is ~5 %. In the last 20 % of the way back (`handoverAt`, about the last 60 ms) the keyboard goes back and the picked window is focused (the keyboard release is double-buffered Wayland state that only takes effect with the overview's next commit, so the focus is re-sent every 50 ms until the window is active). By the landing it is normally active and raised already and the fade starts at once; otherwise it waits at most 200 ms. Earlier versions handed over only at the landing, which measured a 230 ms standstill before the fade, so picking a window felt slow
- **No live streaming**: every request for a new window picture stalls Hyprland's main loop for tens of ms (every app, the mouse pointer and the overview with it). A batch stalls it once, so all windows are requested together when a gesture begins, while the overview is waiting for its first frames anyway. A workspace switch requests one refresh of its active windows. While the overview stands open, nothing streams: all 16 windows streaming live stalled Hyprland for 45–70 ms about once a second, and even the hovered window alone did whenever it redrew; with no stream, an open overview never stalled Hyprland. Spreading the refreshes out (one every 10 ms, or one every 150 ms in rotation while open) was tried and was worse: every request stalled on its own
- Result: about 5 % missed frames (frame gap > 16 ms) both opening and closing. Hyprland still stalls for 40–70 ms now and then; how often varies a lot with what the apps are doing at the time, with no clear link to the overview

## Install

```bash
./scripts/install-silky-gestures.sh                 # the plugin (touchpad four fingers up / down since 0.7.0, touch screen since 0.8.0, timestamped events since 0.8.1)
python3 scripts/install-macshell-overview.py        # copies SilkyOverview.qml into MacShell, adds one line to shell.qml
qs -c MacShell ipc call macshell reload
```

`install-macshell-overview.py` backs `shell.qml` up as `shell.qml.bak-overview` and only adds `SilkyOverview { id: silkyOverview; hub: sharedHub }` after the `AboutApp { … }` line. Re-running the installer backs up and updates `SilkyOverview.qml` and `silkyround.frag.qsb` in `~/.config/quickshell/MacShell/`. `--check` checks without changing anything. To roll back, restore the matching `.bak-overview-<timestamp>` files to their original names and run `qs -c MacShell ipc call macshell reload`.

## Tuning

Constants at the top of `SilkyOverview.qml`:

| Constant | Default | Meaning |
| --- | --- | --- |
| `distance` | 240 | Finger travel for a full open / close, in touchpad units (libinput gives ≈ 11.7 units per mm, so 240 ≈ 20 mm; this touchpad is 77 mm tall); smaller is more sensitive |
| `minSpeed` | 2.4 | Lowest speed after release (progress per second), about 0.4 s for the whole way |
| `maxSpeed` | 10 | Highest speed after release |
| `project` | 0.12 | How many seconds ahead the release speed is projected to decide open or close |
| `primeMs` | 60 | Longest wait for the first frames |
| `fadeIn` | 0.12 | Travel the cross-fade at the start takes |
| `maxScale` | 0.88 | Largest scale of a window in the grid |

Re-run `install-macshell-overview.py` and reload MacShell after a change.

## Verify

The whole path can be driven without a touchpad (the same functions the gesture uses):

```bash
qs -c MacShell ipc call overview begin up     # or down
qs -c MacShell ipc call overview update 120   # half-way
qs -c MacShell ipc call overview state        # {"mode":"workspace","p":0.5,...}
qs -c MacShell ipc call overview end          # release
qs -c MacShell ipc call overview toggle workspace   # or app: open / close directly
```

With the workspace overview open, click cards for occupied and empty workspaces and check that the highlight and window grid update together. To verify compositor events, run `hyprctl dispatch 'hl.dsp.focus({ workspace = "2" })'` and check that `overview state` reports the target workspace with `p` still at 1. The reported `workspacePosition` passes through intermediate values. From workspace 1, `qs -c MacShell ipc call overview workspaceSwipe 2 40` simulates a 40% swipe toward workspace 2. Call `qs -c MacShell ipc call overview workspaceSwipeEnd` to check that the windows slide back. On a physical touchpad, swipe four fingers left and right while open, then close the overview and confirm the selected workspace stays active.

Check that the plugin sends events:

```bash
socat - UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock | grep silkyoverview
```

Swiping four fingers up or down should print `begin`, a run of `update`s and `end`.

Verified on this machine (the built-in `sim` pushes an update every 7 ms, like the real touchpad): handling `begin` takes about 2 ms (258 ms before), all 6 windows already have a picture at the start; the picture appears at about 5 % of travel and fades in from transparent; while moving, frames hold at about 11 ms (90 Hz) with a worst case around 22 ms (an occasional missed refresh, down from 85–100 ms stalls). A log of real fast swipes: 246 of 259 frames on time. `qs -c MacShell ipc call overview debug true` turns on a per-event and per-frame log (`qs log -n -c MacShell | grep overview`); `qs -c MacShell ipc call overview sim up 700` replays a 700 ms swipe.

## Known limitations

- Hyprland borders and title bars are not part of a window capture: they dissolve during the cross-fade at the start, and windows in the overview have no title bar
- The overview background supports static wallpaper. Video wallpaper, desktop icons, and widgets are omitted.
- An app window on another workspace that Hyprland will not capture shows as an app-icon card
- Only shown on the focused monitor

## Disable

Remove the `SilkyOverview { … }` line from `~/.config/quickshell/MacShell/shell.qml` (or restore `shell.qml.bak-overview`) and reload MacShell. Plugin events that nobody listens to have no effect; to keep four-finger vertical swipes away from the plugin entirely, define your own four-finger `vertical` gesture in the Hyprland config and the plugin steps aside.
