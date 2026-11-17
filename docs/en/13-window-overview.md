# 13 · Four fingers up / down: window overview

[简体中文](../13-window-overview.md) | English

## Goal

The same as macOS:

| Gesture | Effect |
| --- | --- |
| Four fingers up on the touchpad | Every window of the current workspace (Mission Control) |
| Four fingers down on the touchpad | Every window of the current app (App Exposé), including its windows on other workspaces |
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
silkyoverview>>update,<travel> total travel since the start, in touchpad units, up is positive
silkyoverview>>end            fingers lifted (end,cancel: the gesture was cancelled)
```

Notes:

- Hyprland clears the gesture table on every config reload (between `config.preReload` and `config.reloaded`). The plugin listens for `reloaded` and registers again. The plugin itself is loaded while a config is being read, after the clear, and registers once then; `preReload` sets a flag so the first `reloaded` does not register it a second time
- The gesture must be removed from the table before the plugin unloads, or Hyprland would call virtual functions in unloaded code and crash
- If the config already has a four-finger `vertical` / `up` / `down` / `swipe` gesture, registering fails and the plugin shows a notification saying why
- Nothing happens while the session is locked

### MacShell: one number drives everything

`SilkyOverview.qml` has a single progress value `p` (0 = desktop, 1 = overview):

- With fingers down: `p = starting progress ± travel / distance`; up opens the workspace overview, down opens the app's windows; clamped to 0–1
- Every window is a window capture (MacShell's own `SafeCapture`, which never releases a capture while a frame is in flight, so the Wayland connection cannot die), and its rectangle is `lerp(real rect, grid rect, p)`. The picture keeps the window's own fixed size: a new frame is only copied into a texture (`ShaderEffectSource`, no effect pass), and a small shader, [`silkyround.frag`](../../config/macshell/overview/silkyround.frag), draws it with anti-aliased rounded corners at the current size, so moving and scaling cost nothing extra. During the gesture only the frame taken at the start is used; the live stream starts once the overview has settled open
- In app mode the workspace's other windows stay where they are with opacity `1 − p`; the app's windows on other workspaces grow linearly in their grid places from 88 % size and opacity 0 to 100 %
- The background is the current wallpaper (the same image and crop as the desktop) under a `0.22·p` dim, with no blur: a full-screen blur recomputed every frame took longer than a 90 Hz frame on this GPU; the menu bar's reserved strip is left uncovered, so the menu bar stays as it is
- Each thumbnail has a Hyprland-like shadow from the first frame on
- On release: the fingers' speed over the last ~90 ms projects where `p` would be 0.12 s later; past half opens, otherwise closes. It then moves to the end at a **constant speed** of `max(finger speed, minSpeed)`
- Four fingers down again mid-animation: the animation stops and the fingers carry on from the current `p`

Details that make the start seamless:

- **The window stays mapped, parked off-screen**: the overview layer is always mapped and, while closed, sits at full size just left of the screen (like MacShell's Spotlight), taking no input or keyboard focus, and Hyprland does not draw it; a swipe only moves it in. An earlier version created the window when the swipe began, building its Vulkan surface, swapchain and shader pipelines on the GUI thread: measured at about 0.5 s with no frames on every swipe, so the fingers were a third of the way before anything appeared, and then the picture "caught up" in one go. Frames now start about 10 ms after `begin`, at a steady 90 Hz. Also: right after startup everything is drawn once at 1 % opacity so the shaders are compiled in advance; the effect layers stay enabled, so nothing is allocated mid-gesture; the layer has a `no_anim` rule, so Hyprland's own layer fade does not play on top of the finger-driven animation
- **Captures stay attached**: windows on the current workspace keep a capture attached (no frames requested, so practically free while idle), and a fresh frame is requested the moment the fingers come down, so the pictures are already there when the swipe starts. This does not follow the Dock's "live window capture" switch (that one is about Dock previews); only MacShell's crash-safety pauses (a capture storm, a close in progress, Game Mode) hold it. An earlier version followed that switch: with it off the overview had no pictures at all and showed every window as a grey app-icon card (each looking up and rendering its icon synchronously on the GUI thread), which was the flash and the stall at the start
- **Wait for the first frame, cross-fade in**: fresh frames get at most 60 ms (at least 24 ms, so the refreshed ones arrive); finger travel during that wait still counts. Once the picture appears the overview cross-fades from fully transparent to opaque over the next 12 % of travel, so the real windows' Hyprland shadow, border and title bar (none of them is in a window capture) dissolve instead of vanishing in one frame
- **Stacking order**: fullscreen windows on top, then floating windows, each ordered by most recent focus, matching Hyprland's real order
- **Dock**: the Dock is another layer below the overview, so covering it would make it vanish on the first frame. While the Dock is shown a rounded hole is left where it is and closes over the first 35 % of the progress, so the Dock fades out. While the Dock is auto-hidden there is no hole (it would show the real windows behind it)

Once open:

- Hovering a window: blue outline, title below it
- Clicking a window (or Enter while hovering): focuses it and closes the overview, the clicked window on top as it flies back; if it is on another workspace, that workspace is switched to and the overview fades out as a whole
- Clicking empty space or Esc: closes
- Windows opening, closing or moving lay the grid out again

Grid layout: windows keep their relative sizes (one uniform scale, at most 0.88), are split into rows by their centres top to bottom and left to right; every row count is tried and the one with the largest scale wins.

## Install

```bash
./scripts/install-silky-gestures.sh                 # the plugin (four fingers up / down since 0.7.0)
python3 scripts/install-macshell-overview.py        # copies SilkyOverview.qml into MacShell, adds one line to shell.qml
qs -c MacShell ipc call macshell reload
```

`install-macshell-overview.py` backs `shell.qml` up as `shell.qml.bak-overview` and only adds `SilkyOverview { id: silkyOverview; hub: sharedHub }` after the `AboutApp { … }` line. Running it again only refreshes the QML file. `--check` checks without changing anything.

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
| `dim` | 0.22 | How much the wallpaper darkens when fully open |
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

Check that the plugin sends events:

```bash
socat - UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock | grep silkyoverview
```

Swiping four fingers up or down should print `begin`, a run of `update`s and `end`.

Verified on this machine (the built-in `sim` pushes an update every 7 ms, like the real touchpad): handling `begin` takes about 2 ms (258 ms before), all 6 windows already have a picture at the start; the picture appears at about 5 % of travel and fades in from transparent; while moving, frames hold at about 11 ms (90 Hz) with a worst case around 22 ms (an occasional missed refresh, down from 85–100 ms stalls). A log of real fast swipes: 246 of 259 frames on time. `qs -c MacShell ipc call overview debug true` turns on a per-event and per-frame log (`qs log -n -c MacShell | grep overview`); `qs -c MacShell ipc call overview sim up 700` replays a 700 ms swipe.

## Known limitations

- Hyprland borders and title bars are not part of a window capture: they dissolve during the cross-fade at the start, and windows in the overview have no title bar
- MacShell's desktop icons and widgets are not shown in the overview (the wallpaper covers them)
- An app window on another workspace that Hyprland will not capture shows as an app-icon card
- Only shown on the focused monitor

## Disable

Remove the `SilkyOverview { … }` line from `~/.config/quickshell/MacShell/shell.qml` (or restore `shell.qml.bak-overview`) and reload MacShell. Plugin events that nobody listens to have no effect; to keep four-finger vertical swipes away from the plugin entirely, define your own four-finger `vertical` gesture in the Hyprland config and the plugin steps aside.
