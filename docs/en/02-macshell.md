# 02 · MacShell: localization, live glass and GPU tuning

[简体中文](../02-macshell.md) | English

## Goals

- Add Simplified Chinese to MacShell and fill in the untranslated text in menus, settings and system actions
- Give "About This Mac" a compact, macOS-like layout that correctly identifies the Snapdragon X Elite, Adreno X1-85, memory speed and Omarchy's full version
- Better touchscreen hit areas, swiping and scrolling
- Build the live glass from real window content instead of faking it with the wallpaper or a flat colour
- Leave blur, refraction and compositing to Vulkan, without pointless continuous full-screen capture
- Use the native 90 Hz mode of the Yoga Slim 7 14Q8X9's built-in screen

## How it is done

The MacShell 0.5.1 and 0.5.2 patches only contain files that differ from their upstream versions:

- `I18n.js` and `lang/zh-CN.js`: Chinese language registration and the full translation
- `AboutApp.qml`, `assets/about-info.sh`: the About layout and hardware detection
- `MacBar.qml`: touch support and on-demand live capture for menus and the Control Center; auto contrast is event-driven instead of taking timed screenshots
- `MacDock.qml`: Dock touch support, captures only intersecting windows, and shows thumbnails only for minimized windows
- `TouchWindowMove.qml` (new) plus `AboutApp.qml`, `MacDock.qml`, `ClockApp.qml`, `Installer.qml`: drag the About, Settings, Clock and Installer windows with a finger
- `shell.qml`: picks up Omarchy's current wallpaper and lowers the cost of window-geometry polling
- `MacLock/shell.qml`: the lock screen reads Omarchy's current wallpaper too (image or video)
- `MacBar.qml`: a new `appearance` IPC so the macOS Tahoe themes can switch light/dark; the battery icon drops the `%` and gets narrower
- `macshell.lua`: no longer binds `PRINT`, avoiding the clash with Omarchy's screenshots

Live glass still needs the CPU to enumerate Wayland windows and schedule captures, so it cannot be 100% CPU-free; the Qt Quick scene graph, blur, refraction and compositing run on the GPU through Vulkan. The GPU keeps `simple_ondemand` dynamic frequency scaling and is not locked at its top clock.

## Versions

This repository started on MacShell 0.5.1; this machine now runs **MacShell 0.5.2** (Omarchy 4.5.0, Hyprland 0.57.2, Quickshell 0.3.2), with every change from the 0.5.1 patch carried over to it. What supports which version:

| Part | 0.5.1 | 0.5.2 already carrying the Silky changes | Fresh 0.5.2 |
| --- | --- | --- | --- |
| `install-macshell-optimizations.sh` (the full patch: localization, touch, live glass, …) | Yes | Yes (only keeps the tuning current, no patching) | Yes (version-specific patch) |
| `tune-*.py`, `configure-macshell-reload.py` | Yes | Yes | Verified as part of the installer |
| `install-macshell-status.py` (menu-bar monitors) | Yes | Yes | Yes |
| `install-macshell-overview.py` ([13 window overview](13-window-overview.md)) | Not verified | Yes | Not verified |

The 0.5.2 patch targets upstream tag `0.5.2` (commit `5d17abadd5de192919416990ad2ecf7f31b38b51`). The current upstream 0.5.1 tag differs from the original patch baseline, so use 0.5.2 for clean installations. `--check` applies the patch and runs all tuners in a temporary directory.

## Install

Install MacShell 0.5.2 first, then from this repository run:

```bash
./scripts/install-macshell-optimizations.sh --check
./scripts/install-macshell-optimizations.sh
```

The script first checks that the patch applies cleanly, then backs up the original files to:

```text
~/.local/state/macshell/silky-backup-YYYYMMDD-HHMMSS/
```

When it is done, restart MacShell from the "Tools" page of MacShell's settings.

In Smart mode, the Dock hides when a visible window on its screen overlaps it, whether the window is floating or tiled. It returns when the window moves away. Move the pointer to the bottom edge to reveal it temporarily.

With Silky shortcuts installed, the floating and tiling actions in MacShell’s View and Window menus behave like `Super+T`, keeping windows on the same workspace for split tiling. ([10 · Super+T](10-shortcuts.md#supert))

### Applying QML updates

The menu bar and the Dock share one Quickshell instance, so saving menu-bar code made the automatic reload rebuild the Dock too. The Silky optimization script for 0.5.1 turns off the QML file watcher. On a running 0.5.2 you can apply just that setting:

```bash
python3 scripts/configure-macshell-reload.py "${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/MacShell/shell.qml"
```

After that, once you finish a set of file changes or install the menu-bar monitors, run once:

```bash
qs ipc -c MacShell call macshell reload
```

### 90 Hz built-in screen

The monitor configuration for this machine is in [`config/hypr/monitor-yoga-slim-7-14q8x9.lua`](../../config/hypr/monitor-yoga-slim-7-14q8x9.lua). Add it to `~/.config/hypr/monitors.lua`, then run:

```bash
hyprctl reload
hyprctl configerrors
hyprctl monitors
```

Use this snippet only if your panel really is `eDP-1` and supports `2944x1840@90`.

## Menu bar system monitors

Network speed, CPU temperature and battery panels can be installed separately on MacShell 0.5.1–0.5.3.

```bash
python3 scripts/install-macshell-status.py --check
python3 scripts/install-macshell-status.py
```

Network speed and temperature are sampled every 1.5 s, and the panels show roughly the last minute. The menu bar shows network speed on two lines, upload (↑) on top and download (↓) below so they match the arrows; the order comes from the `Repeater` `model` in [`SilkyStatusButton.qml`](../../config/macshell/status/SilkyStatusButton.qml). Click the network speed to see per-app traffic and this machine's IPv4 / IPv6; click an address to copy it. The app ranking uses TCP sockets visible to the current user that still exist at sampling time; UDP and QUIC are not counted. Traffic forwarded by a proxy may show up under the proxy's process name.

Click the temperature to see the 10 processes using the most CPU right now, plus a hardware overview of the GPU, SSD, Wi-Fi card, fans and so on. Below the overview are whole-machine CPU, memory and system disk (`/`) usage. Process usage is the CPU-time delta between two samples; 100% means one logical core fully used. Click the battery icon to see the power source, power, voltage, charge, capacity, cycle count and health; what appears depends on what the hardware exposes. While MacShell runs it samples every 3 seconds; the "System power" chart in the middle of the panel keeps about the last 5 minutes, and sampling continues with the panel closed. Whole-system power can only be measured on battery, where the battery's discharge rate is everything the laptop draws. On external power the Yoga Slim 7x (Snapdragon X, `qcom-battmgr`) reports neither the adapter input (the USB-C port's `voltage_now` is 0 and `2.00 A` is only the PD contract) nor the system load (the battery's `power_now` is 0 when not charging), so the chart leaves a gap while plugged in and the "System power" row under "Power source" reads "Unavailable on external power". Charge and discharge power are shown as numbers in the "Battery" group ("Charging power / Discharging power / Battery power"). Health is the battery fuel gauge's full-charge capacity `energy_full` divided by the design capacity `energy_full_design`. The gauge recalibrates its full-charge capacity from time to time, so health can jump several points at once; with a charge limit on, recalibration happens less often and the jumps are larger. So you can look back at changes, the menu bar checks every 10 minutes and appends a row to `~/.local/state/silky/battery-health.csv` once a day and whenever the full-charge capacity changes (time, model, full/design capacity, health, cycle count). On the Yoga Slim 7 14Q8X9 you can drag a slider in the battery panel to set a 55%–100% charge limit; "Apply" writes it with system authorization and checks the kernel's read-back. Right-click the battery icon to switch between the power modes the system offers; Omarchy remembers the choice separately for AC and battery power. At the bottom of the right-click panel there is also a "Show battery percentage" switch; turned off, the battery shows only the charge bar without the number. It is MacShell's `showBatteryPercent` setting and is saved to `~/.config/macbar/settings.json`.

Tray icons are unified as monochrome line icons like the rest of the menu bar (following light/dark): each tray item is matched by id to a hand-drawn icon in `SilkyStatusIcon`, currently Chrome, ChatGPT, Clippy, Netcatty, Remmina, Clash Verge and WeChat (id `wechat`, two overlapping speech bubbles). Other apps keep their own icons, and so does any item that needs attention (`NeedsAttention`). To find a tray id: `busctl --user get-property <service> /StatusNotifierItem org.kde.StatusNotifierItem Id`. After installing, run `qs -c MacShell ipc call macshell reload` so MacShell reloads.

## Applications panel interaction

[`tune-apps-panel.py`](../../scripts/tune-apps-panel.py): the mouse wheel moves the Applications panel 320 px per notch, and touchpad and touchscreen flicks decelerate smoothly after release; the glass panel fades in together with the icons, following the click or pinch progress. The installer applies these changes to existing installs, and scrolling is still limited by the list bounds. On the touchscreen the finger only moves the scroll target and the list follows it frame by frame at 1.1× the finger distance (the same per-frame animation as the touchpad); on release, fast or slow, it glides on along the same deceleration curve, instead of stepping with each touch event or stopping dead after a slow release.

### Open / close animation

The whole panel (glass frame and content) animates as one picture: it shrinks from 114% to 100%, goes from blurred to sharp and from transparent to solid; each icon adds a little scaling of its own on top (outer ring first). Before, only the icons scaled and the frame merely faded in. The frame and content now live in one `appsStage`, rendered offscreen and blurred once, which is cheaper than the old "frame layer plus content layer, then blur".

Closing (Esc, a click outside the panel, the Dock icon again, launching an app) no longer zooms back up and no longer uses the spring (its acceleration and slow settling tail read as a bounce): it is a single 0.15 s fade of the whole panel as one picture: no blur, no separate glass and content curves, no per-icon stagger, and it stays at 100% size. Opening and pinch releases keep the spring.

The entrance runs light-to-solid like macOS: the light frosted glass comes first (opacity t^1.6: a pinch starts faint and it deepens faster towards the end) and the icons and text solidify on top of it (t^1.8, always a step behind the glass). It used to be the other way round (content t^0.55, glass t^1.35), so the first frames were blurred icons over the window behind, darker than the finished panel, which then lightened.

The other cause was the picture behind the glass: with real-time glass (`glassRealtime`) windows are only captured where glass is showing, so on opening every window behind the panel started capturing from scratch, and for the first frames the glass blurred the dark placeholder (`#1e1e20`) or an old frame before jumping to the real, often lighter, windows. While the panel is closed, the windows in the area where it opens now get a single snapshot every 1.5 s (not a live stream), so it opens on a current picture. A close released mid-pinch, or a reopening during the close, eases the zoom over 0.18 s so the size never jumps.

A spring advanced by real frame time drives the animation; on the 90 Hz built-in screen the whole run measured 11.0 ms per frame on average with no dropped frames. Three things that made it "hiccup" were also fixed:

| Symptom | Cause | Fix |
| --- | --- | --- |
| A jump right at the start | The first frames after toggling are the most expensive (about 25 ms opening, about 20 ms to rebuild the offscreen layer when closing), and a spring advanced by real time overshoots | For the first 3 frames after a start or reversal, advance at most one display frame; when closing, build the offscreen layer in the very frame the request arrives |
| The first open after login stalls for about 200 ms | Shaders, offscreen layers and icon textures are all created in the first frame | 3 seconds after the shell starts, draw the panel once at 0.4% opacity (below one 8-bit step, invisible and taking no input) |
| Repeated clicks on Dock icons stall for 60–70 ms | Pointer focus bounces between the Dock and the full-screen panel, and every return to the Dock rebuilds the icon's hover label (a whole glass bubble) | As on macOS: after an icon is clicked, its label does not appear again until the pointer moves 4 px ([`tune-dock-hover-label.py`](../../scripts/tune-dock-hover-label.py)) |

Clicking the Dock's Applications icon rapidly makes the spring reverse immediately on every click (velocity stays continuous, no stop-and-restart). This relies on the `silky-gestures` plugin re-resolving the window under the pointer on button press, see [03 · Touchscreen workspace gestures](03-silky-gestures.md#rapid-repeated-clicks).

## Default glass settings

The installer merges these values without overwriting other personal settings such as Dock icons or widget order:

```json
{
  "glassOpacity": 0.38,
  "glassBlur": 24,
  "glassRealtime": true,
  "glassLive": true
}
```

Menus and the Control Center capture only while visible, and only windows that intersect the glass; the Dock likewise handles only nearby windows. Window-geometry polling slows down automatically when windows are still or the glass is off.

## Periodic pointer stutter

MacShell 0.5.1's "auto contrast" grabbed the screen behind the menu bar with `grim` every 1.2 seconds, and again every 0.7 seconds while a menu was open. On the Adreno X1-85 each grab stalled Hyprland's main thread for 60–110 ms (about 6 frames at 90 Hz): with nothing open, moving the mouse in steady circles made the pointer randomly hitch and drift. In the Hyprland log this shows up as libinput's `event processing lagging behind by …ms`.

The patch removes both timers and measures again only when what is behind the menu bar may really have changed: switching workspaces, windows opening/closing/moving, toggling full screen, wallpaper or appearance changes, and the moment a menu opens.

Screenshots and screen recording themselves still cause the same stall; that is Hyprland's capture cost on this GPU and outside this patch.

## Stutter when opening menus and the Control Center

Same cause: auto contrast grabbed the screen behind a menu at the moment it opened, right in the middle of the pop-up animation, and grabbed the area behind the menu bar again after any window change, such as a menu closing or a window changing its title.

The patch makes three changes:

- In dark mode menu text is always white, so menus are no longer grabbed (the measurement was never used)
- The menu bar is measured again only when windows appear, close, move or resize; title and focus changes no longer trigger it
- When only the wallpaper is behind the menu bar (the normal case, since the bar has its own reserved area), the new `assets/tone-wall.sh` computes the brightness from the wallpaper file instead of grabbing the screen; the result is cached per wallpaper. It falls back to a screen grab only when a window really extends under the bar (floating windows, full screen, special workspaces) or with a video wallpaper

Measured: the pause when opening the Control Center went from about 76 ms to about 19 ms, and switching workspaces no longer grabs the screen. The remaining short pause comes from the live glass capturing the windows behind the menu; turning live glass off removes it too.

## Mouse settings lost after a config reload

MacShell's natural scrolling, tracking speed, key repeat and touchpad options are written into Hyprland temporarily with `hyprctl eval`, only once when the setting changes. Any config reload (`hyprctl reload`, a theme switch, saving a config file) wipes them: natural scrolling is on in settings, yet the wheel direction is back to the default.

The patch makes MacBar re-apply these settings when it receives the `configreloaded` event.

## Dragging windows by touch

MacShell windows are dragged with `startSystemMove()` (that is `xdg_toplevel.move`). Hyprland 0.57.2 only accepts move requests carrying a mouse-button serial, and drops those triggered by a finger, so they could not be dragged on the touchscreen.

The patch makes the existing drag handling respond only to mouse and touchpad, and adds `TouchWindowMove.qml` for the touchscreen: every time the finger moves, the window is moved by the same distance through Hyprland IPC, with the window's move animation turned off while dragging so it sticks to the finger. The draggable areas match the mouse: the whole About window, and the top bar of Settings, Clock and the Installer.

## No wallpaper on the lock screen

MacLock only read the wallpaper from MacShell's `wallpaperPath` setting or from `awww query`. Omarchy 4.x manages the desktop wallpaper itself, so both are usually empty and the lock screen was plain black.

The patch makes MacLock read `~/.local/state/omarchy/current/background` before those two: an image becomes the lock background, a video becomes a live lock wallpaper (a video wallpaper set in MacShell itself still wins).

Preview the lock screen (without really locking):

```bash
MACLOCK_PREVIEW=1 qs -c MacLock
```

## Menu bar and Dock gone after a reboot, wheel direction reversed

MacShell is launched at Hyprland start by `~/.config/hypr/macshell.lua`, and `hyprland.lua` needs a `-- >>> MacShell (added by install.sh) >>>` block to load it. With those two gone, a MacShell started by hand in the current session works fine, but after a reboot neither the menu bar nor the Dock appears.

Natural scrolling for the mouse wheel is a MacShell setting, written into Hyprland with `hyprctl eval` after MacShell starts. Without MacShell the setting does not exist and the wheel goes back to the Linux default.

Fix:

- The installer checks and restores the loading blocks in `macshell.lua` and `hyprland.lua`
- [`config/hypr/input-touchpad.lua`](../../config/hypr/input-touchpad.lua) turns on mouse `natural_scroll` directly in the Hyprland config, effective from login and independent of MacShell

Check:

```bash
grep -n 'hypr.macshell' ~/.config/hypr/hyprland.lua
pgrep -af '^qs -c MacShell'
hyprctl getoption input:natural_scroll
```

## Screenshots needing two presses, then popping up again

Omarchy binds `PRINT` to omasnap, and MacShell's `macshell.lua` bound the same key to its own region capture. One press started two capture overlays that cancelled each other: the first press seemed to do nothing, then another capture overlay popped up.

The patch removes the `PRINT` bind from `macshell.lua`, leaving the key to omasnap. MacShell's own capture is still available in the Control Center.

## No more screenshot notifications

Every screenshot used to post two notifications: omasnap's "screenshot saved and copied" and MacShell's "Screenshot saved".

- Omarchy's default screenshot command passes `--notify`. [`config/hypr/bindings-screenshot.lua`](../../config/hypr/bindings-screenshot.lua) makes `PRINT` run plain `omasnap`: the shot is still saved and copied to the clipboard, and a macOS-style floating preview appears at the bottom right (gone after 7 seconds; drag it out or click "Edit" to annotate) instead of going to the notification center
- MacShell's `screenshotNotify` is set to `false`

## Battery icon

The menu-bar battery uses the macOS 26 style: a narrower pill (24 px battery body, 32 px button) with only the number inside, no `%`. The number is usually two digits, so it does not need to be longer. Right-click the battery to turn the number on or off (see "Menu bar system monitors" above).

The battery icon and the battery panel share one set of colors for the power state. Only states worth noticing get a color; the everyday on-battery state stays neutral, as on macOS. Yellow and orange both read as warnings and are hard to tell apart on a 14 px icon, so neither is used:

| State | Color | Condition |
| --- | --- | --- |
| Charging | Green | Battery status is `Charging` |
| Running directly on external power (not charging, e.g. at the charge limit) | The current wallpaper's accent, meaning "connected and steady"; blue when none can be read | Plugged in, battery not charging |
| On battery | Neutral (white in dark mode, dark grey in light mode) | No external power |
| Low battery | Red | Below 20% (macOS's threshold) and not charging |

Charging wins over low battery: a low battery that is charging shows green.

The external-power color comes from the current wallpaper and follows it when the wallpaper changes. The menu-bar sampler (`wallpaper_accent` in [`status.py`](../../config/macshell/status/status.py)) resolves Omarchy's wallpaper link `~/.local/state/omarchy/current/background`, has ImageMagick (`magick`) shrink it to 96×96 and quantize it to 16 colors, and picks the most vivid dominant color by area × chroma². It keeps that hue and makes two tones, 72% lightness for a dark menu bar and 38% for a light one (saturation clamped to 50%–85%), and sends them as `wallpaperAccent` with each sample to the menu-bar battery and the battery panel. The result is cached by wallpaper path and modification time, so it updates within about 1.5 s of a wallpaper change and is only recomputed when the image changes (about 0.3 s for a 6K PNG). A near-grey wallpaper (dominant chroma below 0.12), a video wallpaper, or a missing `magick` falls back to the old blue. Limitation: green wallpapers (such as Bliss) give a color close to the charging green. To verify: while plugged in and not charging, run `omarchy-theme-bg-set ~/Pictures/Wallpapers/<another>.jpg`; within a few seconds the battery icon and the panel accent change. macOS Monterey gives violet and Sierra a warm orange. To see the picked color directly:

```bash
python3 -c 'import importlib.util as u; s=u.spec_from_file_location("s", "config/macshell/status/status.py"); m=u.module_from_spec(s); s.loader.exec_module(m); print(m.wallpaper_accent())'
```

To deploy, re-run `python3 scripts/install-macshell-status.py`; it replaces the old blue `indicatorColor` with one that reads `wallpaperAccent`. Then restart MacShell so the new sampler runs. To roll back, restore the `MacBar.qml.bak.silky-status-*` backup the installer prints, put the previous `SilkyStatusPanel.qml` and `assets/silky-status.py` back, and restart MacShell.

 The panel's "System power" chart is data, not state, so it always uses violet. [`scripts/install-macshell-status.py`](../../scripts/install-macshell-status.py) writes the colors into `MacBar.qml` (`indicatorColor`); the panel's colors come from `powerState` in [`SilkyStatusPanel.qml`](../../config/macshell/status/SilkyStatusPanel.qml). Re-running the installer replaces the old three-color version; restart MacShell afterwards so the background sampler is replaced by the new script. To verify: plugged in with the battery at its charge limit, the icon takes the wallpaper accent (blue if none); unplugged, it turns neutral. When only QML changed, `qs ipc -c MacShell call macshell reload` is enough to reload. To roll back, restore the `MacBar.qml.bak.silky-status-*` backup the installer prints and restart MacShell.

## No icons on the desktop

By default MacShell draws the files and folders of the Desktop directory as desktop icons (`desktopIcons` in `macdock/settings.json`). The installer sets it to `false`, so the desktop shows only the wallpaper. You can turn it back on in MacShell's settings.

## Only MacShell's Dock

The Omarchy shell has its own Dock (plugin `omarchy.dock`). MacShell normally covers it, but whenever the Omarchy shell restarts (`omarchy restart shell`, after toggling plugins) it reappears at the bottom of the screen, on top of MacShell's Dock. To turn it off for good:

```bash
omarchy plugin disable omarchy.dock
```

`scripts/install-maclock.sh` does this as well, since it has to restart the Omarchy shell anyway.

## "About This Mac" too wide and a white edge flash on open

Both come from Hyprland window rules and are fixed by one rule in [`config/hypr/silky-macshell-windows.lua`](../../config/hypr/silky-macshell-windows.lua):

```lua
o.window("^(org\\.quickshell)$", { float = true, center = true, border_size = 0 })
```

- **Too wide**: Omarchy's floating-workspace mode enlarges every newly opened window to a standard size (up to 1100×760, 64%×68% of the screen), except apps that "bring their own float rule". MacShell's windows (About, Settings, Clock, Installer, all with class `org.quickshell`) were not exempt, so they were stretched. Registered with `o.window(..., { float = true })`, Omarchy no longer resizes them
- **White edge flash**: these windows draw their own macOS-style edges, and used to ask Hyprland, with a timer (every 60 ms), to remove the 1 px border and re-centre them only **after** the window appeared, so the first frames of the open animation showed Hyprland's white outline, which then vanished abruptly while the window jumped slightly. Now the rule sets no border and centring when the window is created, so it looks final from the first frame

How it was checked: record the opening with `wf-recorder` at 60 fps and inspect the edges frame by frame.

Note: rules apply only to newly created windows; restart MacShell once after changing it.

## Two menu bars and two Docks after a crash

When MacShell crashed, two mechanisms brought it back at the same time: Quickshell's own crash handler showed a report window and **started a copy by itself** (process name `/usr/bin/quickshell` without arguments, with `__QUICKSHELL_CRASH_*` in its environment), and `macshell-start` started another one. Each drew its own menu bar and Dock.

- `QS_DISABLE_CRASH_HANDLER=1` in `~/.config/macshell/env`: no crash window and no self-restart; only `macshell-start` restarts it quietly. Crash details are still in `~/.local/state/macshell/MacShell.log` and the system core dumps
- `macshell-start` uses `qs -n -c MacShell`: if MacShell is already running the new one exits right away (exit code 0, and the guard script then ends quietly), so there is always exactly one

## "system.lock" showing in the Omarchy menu

Overriding a menu item with only `action` drops its original `icon` and `label`, so the menu shows the raw id. Write all three when overriding: `"system.lock": {"icon":"󰌾","label":"锁屏","action":"silky-lock"}`. The icon is a Nerd Font private-use character (here Material Design's lock U+F033E, the same set as the other menu icons), which is easily swallowed into an empty string when copied in a terminal or script, leaving only the text; writing it with an escape (such as Python's `"\U000F033E"`) is safer, and `od -c` confirms it afterwards.

## Misaligned glass panel edges

Panels popping out of the menu bar (calendar, Control Center and so on) showed a dark band at the edge that did not line up with the background, as if the background were shifted. The Liquid Glass shader's edge refraction was too strong: popup panels multiplied the refraction to 1.6× the base (and `liquidglass.frag` multiplied again by 1.35) with a 26 px bevel, so the edge "folded in" the background from 50–60 px outside the panel; with a window edge right next to the panel, that was the misaligned dark band.

The patch lowers the multiplier for the two popup glass instances in `MacBar.qml` from 1.6 to 0.6 and the bevel cap from 26 px to 18 px: the edges keep their glass thickness and highlight but bend only about 18 px, close to the restraint of Apple's Liquid Glass. The Dock's glass is unaffected.

The calendar needed its own fix: it scales from its top-right corner, but the old code sampled the background from the unscaled top-left, so after a menu-bar size or display scale change the wallpaper inside the panel was shifted sideways. The calendar now samples the real screen rectangle, its fixed 42 px blur becomes at most 18 px, tint and refraction are lowered, and saturation goes back to 1.05. It keeps a light glass feel, but its backdrop is continuous with the wallpaper outside the panel instead of looking like a separately pasted, recoloured blurred image.

## Control Center

[`tune-control-center-glass.py`](../../scripts/tune-control-center-glass.py): the grouped Control Center shares one glass material with the menu-bar dropdowns (the same slab, gradient and outline, so adjusting one changes both). MacShell 0.5.2 forced the Control Center dark, even in the light appearance; it now follows the appearance and is light glass in light mode.

[`tune-display-controls.py`](../../scripts/tune-display-controls.py): the Control Center gets a new "Display" page, entered like "Sound" (click the name on the left to open the page, drag the slider on the right directly). The page has a brightness slider plus "Night Shift" and "Appearance" (dark / light) switches.

## Dock icons and the Settings window

- [`tune-dock-icons.py`](../../scripts/tune-dock-icons.py): optical scaling of Dock icons is centred on the icon, so icons do not drift to one side when magnified on hover; the pivot for rotation (the wiggle) is unchanged.
- [`tune-settings-scroll.py`](../../scripts/tune-settings-scroll.py): the Settings window's left navigation list used to move only a few pixels per wheel notch. It now moves 140 px per notch, adding up several notches and easing there frame by frame; pixel-precise touchpad scrolling is still left to the list itself, keeping native inertia.

## Glass refreshes when focus changes

[`tune-glass-stacking.py`](../../scripts/tune-glass-stacking.py): the "fingerprint" of the windows behind the glass used to cover only position and size, so clicking to change which floating window is in front left the glass showing the old stacking order. The focus order (`focusHistoryID`) is now part of it, so the glass refreshes immediately on focus changes; windows changing their titles (terminals, browser tabs, players) still do not wake the 60 Hz refresh.

## Window minimizing

Silky no longer offers ways to minimize windows ([`disable-minimize.py`](../../scripts/disable-minimize.py)): title bars keep only close and maximize, and the MacShell menu entry and client-request forwarding are turned off. The Dock can still restore windows that were minimized before.
