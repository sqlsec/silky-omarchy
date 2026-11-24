# 16 · Desktop priority: Hyprland and MacShell get the CPU / GPU first

[简体中文](../16-desktop-priority.md) | English

## What it does

When background programs saturate the CPU (builds, Chromium / Electron renderers, proxies, speech recognition), the compositor, menu bar and Dock are still scheduled first, so animations and the pointer stay smooth.

- Every thread of Hyprland, Xwayland, MacShell (`qs` / `quickshell`) and fcitx5 gets a negative nice value, so these threads run before ordinary apps when they compete for CPU time.
- Those threads also get a `uclamp.min` floor. As soon as one wakes, schedutil raises its CPU cluster to a higher clock, so the first frame doesn't wait for the clock to ramp up.
- On AC power the Adreno GPU's minimum clock is raised to 550 MHz, so the first animation after idle no longer starts at 300 MHz. On battery the original floor is restored and no extra power is used.
- Threads the app has already deprioritised keep their settings: Mesa's `disk$` / `traceq` cache threads (`SCHED_BATCH`), threads with a nice value of their own and rtkit-managed threads. Disk caching and other background work are not pulled forward.

Cause, confirmed on this machine: Hyprland and MacShell ran at nice 0, with the same weight as a dozen Chromium / Electron renderers. `hyprland.log` had dozens of libinput warnings `scheduled expiry is in the past … your system is too slow`, which means the compositor's input handling was delayed. Hyprland 0.57 does not request realtime scheduling. On the GPU side, aquamarine already gets a high-priority EGL context (`IMG_context_priority … Got a high priority context`), so nothing is needed there.

| Process | nice | uclamp.min (0–1024) |
| --- | --- | --- |
| `Hyprland` | -11 | 512 |
| `qs`, `quickshell` (MacShell / Omarchy Shell) | -8 | 384 |
| `Xwayland` | -6 | 256 |
| `fcitx5` | -6 | 256 |

No realtime policy (`SCHED_RR` / `SCHED_FIFO`) is used, so a hung compositor cannot lock up the machine. nice is capped at -15.

## Install and use

Run from the repository root. It asks for your sudo password:

```bash
./scripts/install-desktop-priority.sh
```

The script checks syntax, backs up an existing `/etc/silky/desktop-priority.conf` if it differs (`*.bak.<time>`), then installs and starts the service. It is safe to re-run:

| Repository file | Installed to |
| --- | --- |
| [`bin/silky-desktop-priority`](../../bin/silky-desktop-priority) | `/usr/local/bin/silky-desktop-priority` |
| [`config/silky/desktop-priority.conf`](../../config/silky/desktop-priority.conf) | `/etc/silky/desktop-priority.conf` |
| [`config/systemd/system/silky-desktop-priority.service`](../../config/systemd/system/silky-desktop-priority.service) | `/etc/systemd/system/silky-desktop-priority.service` |

Dependencies: `python3` and systemd. No re-login is needed. The service scans for new threads every 2 seconds, so a restarted Hyprland or MacShell is boosted again automatically.

To change processes or values, edit `/etc/silky/desktop-priority.conf` (format: `name = nice uclamp.min`), then run:

```bash
sudo systemctl restart silky-desktop-priority.service
```

Set `ac_min_freq_mhz` under `[gpu]` to `0` to drop the GPU clock floor.

## Implementation and compatibility

- Prefers the native C++ implementation ([`plugins/silky-desktop-priority/main.cpp`](../../plugins/silky-desktop-priority/main.cpp)), built and installed to `/usr/local/bin/silky-desktop-priority` by [`scripts/install-desktop-priority.sh`](../../scripts/install-desktop-priority.sh); falls back to the Python script [`bin/silky-desktop-priority`](../../bin/silky-desktop-priority) when `g++` is unavailable. The C++ binary filters non-target PIDs via `/proc/<pid>/comm` first, cutting `--status` runtime from ~50 ms to ~6.4 ms and substantially lowering resident CPU and memory compared to Python.
- The service runs as root but keeps only `CAP_SYS_NICE`, which is required to give other processes a negative nice and a `uclamp.min`. It uses `ProtectSystem=strict`, `ProtectHome` and `PrivateNetwork`, a 64 MB memory cap, and runs at nice 5 itself.
- `sched_setattr(2)` writes `SCHED_OTHER`, nice and `SCHED_FLAG_UTIL_CLAMP_MIN` in one call, thread by thread, because nice applies per thread on Linux. Syscall numbers are included for aarch64 and x86_64; other architectures fall back to nice only.
- Only processes with UID ≥ 1000 are matched, by exact `/proc/<pid>/comm`, so children of MacShell such as `python3` and `inotifywait` are not boosted. PIDs and threads are cached by start time, so each pass reads only new processes.
- On stop (`SIGTERM`), boosted threads go back to nice 0 and `uclamp.min` 0, and the GPU floor is restored.
- AC detection: any non-battery supply under `/sys/class/power_supply` with `online=1`.
- Why not cgroup weights: Hyprland starts from the greetd session, and `session-N.scope` also holds Chromium, ChatGPT and other apps launched straight from the session. Raising the scope's `CPUWeight` would boost them too, so per-process settings are more precise.
- Tested on: Lenovo Yoga Slim 7x (Snapdragon X Elite, 12 Oryon cores in 3 clusters of 4, Adreno X1-85), kernel 7.3 (`CONFIG_UCLAMP_TASK=y`, `CONFIG_PREEMPT=y`), Hyprland 0.57.2, quickshell 0.3.2, schedutil. Without uclamp in the kernel only nice applies; without a devfreq GPU the GPU part is skipped.
- Limits: the GPU context priority of Qt / quickshell can't be changed from outside, so MacShell benefits only from CPU priority and the GPU clock floor. Boosting Xwayland also helps drawing in X11 apps such as WPS and WeChat a little.

## Verify

```bash
systemctl status silky-desktop-priority.service
/usr/local/bin/silky-desktop-priority --config /etc/silky/desktop-priority.conf --status
ps -L -o tid,ni,cls,comm -p "$(pgrep -x Hyprland)"
```

Expected: the service is `active (running)`. In `--status`, `boosted` is close to the thread count for each target (the gap is the `SCHED_BATCH` cache threads and the `module-rt` reset-on-fork thread), and the main thread's nice and `uclamp.min` match the config. On AC the GPU line shows `min=550000000`.

Stress comparison (on hardware): run 12 busy processes, `stress-ng --cpu 12 --timeout 60s` (or `for i in $(seq 12); do timeout 60 sh -c 'while :; do :; done' & done`), and meanwhile drag windows, open the Control Center and switch workspaces. With the service on, animations should stay smooth and `hyprland.log` should get no new `your system is too slow` lines.

To preview which threads would change, without installing or root:

```bash
bin/silky-desktop-priority --config config/silky/desktop-priority.conf --dry-run
```

## Roll back

```bash
./scripts/install-desktop-priority.sh --uninstall
```

This stops and disables the service (which restores nice, `uclamp.min` and the GPU floor), removes `/usr/local/bin/silky-desktop-priority` and the unit file, and runs `daemon-reload`. `/etc/silky/desktop-priority.conf` and its backups are kept; delete them by hand if unwanted. No reboot or re-login is needed.

## Completely covered windows stop redrawing

### What it does

A window on the current workspace that other windows cover completely no longer redraws at the display refresh rate; as soon as any part of it shows, it updates live again. Covered browsers, chat clients, Electron apps and windows with live charts stop rendering at 90 / 110 Hz in the background and stop scheduling compositor frames nobody sees.

Cause (confirmed in the Hyprland 0.57.2 source): Hyprland skips drawing a surface that opaque windows cover, but `CSurfacePassElement::discard()` still calls `presentFeedback()`, whose first step answers the surface's `wl_surface.frame`. So a covered app is told every frame that it may draw the next one. Windows on hidden workspaces already get no frame callbacks and are not affected by this change.

- A window counts as completely covered when the opaque parts of the windows above it hide its whole content box. A window above only hides what it declares opaque (`wl_surface` opaque region or an alpha-less buffer), at full opacity, minus its rounded corners. Glass, blurred and translucent windows never hide the windows below, which keep updating.
- While covered, one frame per second still goes through (keepalive), so thumbnails and apps that time things off frame callbacks never stop completely.
- Everything updates normally while a window capture is pending (overview, Dock thumbnails, window sharing; plus 1.5 s afterwards), on a monitor with a special workspace open, on a workspace with a fullscreen window, during a workspace slide, and for windows tagged `silky-live`.

### Install and use

From the repository root:

```bash
./scripts/install-occlusion-plugin.sh
```

The script builds the [silky-occlusion plugin](../../plugins/silky-occlusion/main.cpp) against the installed Hyprland headers, installs it as `~/.local/lib/silky-omarchy/silky-occlusion-<Hyprland version>.so`, writes the [loader](../../config/hypr/silky-occlusion.lua) to `~/.config/hypr/silky-occlusion.lua`, appends `require("hypr.silky-occlusion")` to `~/.config/hypr/hyprland.lua` (backing it up as `hyprland.lua.bak.<time>` first), then reloads Hyprland and loads the plugin. No re-login is needed. Build dependencies: `g++`, `make`, `pkg-config` and the Hyprland headers (`pkg-config hyprland`). Re-run the script after a Hyprland update; until then the old build is not found for the new version and simply doesn't load.

Runtime control:

```bash
hyprctl silkyocclusion                 # statistics and the windows covered right now
hyprctl silkyocclusion all             # every window's content box and what it hides
hyprctl silkyocclusion off             # disable for now (answers every paused window at once)
hyprctl silkyocclusion on
hyprctl silkyocclusion keepalive 0     # pause covered windows completely; default 1000 ms
```

Runtime settings return to their defaults when Hyprland restarts. To keep an app always live, tag it in the Hyprland config, for example `hl.window_rule({ name = "keep-player-live", match = { class = "^mpv$" }, tag = "+silky-live" })`.

### Implementation and compatibility

The plugin hooks no functions (not safe on aarch64); it only listens to the public `RENDER_PRE` render-stage event. Each time a monitor is about to render, it walks the windows of that monitor's current workspace from the top down in Hyprland's draw order (tiled, the focused tiled window, floating, pinned), accumulates their opaque regions, decides which windows are completely covered, and takes the pending frame callbacks of those windows and their subsurfaces out before Hyprland answers them. The held callbacks are answered at once when the window shows again, when the keepalive is due, or when the plugin is turned off or unloaded. Capture detection uses Hyprland's `Screenshare::mgr()->outputCopyFBState()`.

- Built for Hyprland 0.57.2 (aarch64, Snapdragon X). The plugin checks the ABI hash and refuses to load on a mismatch; Hyprland keeps running.
- Native Wayland and XWayland surfaces are both handled. How much XWayland windows benefit depends on whether the X11 app paces itself with Present; not verified separately.
- At the moment a window is uncovered, the newly revealed area may show the old picture for a frame or two before the app draws a new one.
- Covered video freezes its picture (sound continues), as macOS and Windows do for covered windows. Exclude windows that need a running picture with the `silky-live` tag.

### Verify

Isolated test (a nested Hyprland instance; the test client redraws on every frame callback and counts fps):

- Without the plugin, a window completely covered by another opaque window still runs at 90 fps.
- With the plugin it drops to 1 fps (keepalive); uncovering a 50 px strip brings it straight back to 90 fps; `off` brings it back to 90 fps; with `keepalive 0` it draws no frame at all in 3 seconds.
- Killing the client while it is paused, and unloading the plugin while it holds callbacks, both leave Hyprland running normally.

On real hardware (2026-11-24, Hyprland 0.57.2, built-in panel 2944×1840 @ 90 Hz, scale 2):

- The same test window under Chrome drops from 90 fps to 1 fps and returns to 90 fps at once when raised.
- Right after loading, `hyprctl silkyocclusion` listed 8 completely covered windows on the current workspace. When MacShell captured a new window, `captureSkips` went up and every window updated normally during the capture.
- Those 8 covered windows were all idle at the time (`held=0`, no frame requested), so an on/off comparison showed no measurable change in Hyprland's GPU load. Resources are saved only while covered windows animate, play video or refresh charts. Drag frame times have not been measured yet.

To check:

```bash
hyprctl plugin list | grep -A2 silky-occlusion
hyprctl silkyocclusion
```

Expect the plugin to be listed and `enabled=true`. Cover an animating window completely for a few seconds: it appears in the `covered` list, and `held` and `keepalives` go up.

### Roll back

```bash
./scripts/install-occlusion-plugin.sh --remove
```

This removes `require("hypr.silky-occlusion")` from `~/.config/hypr/hyprland.lua` (backing it up as `hyprland.lua.bak.<time>` first), unloads the running plugin and reloads Hyprland. Covered windows return to full-rate redraws at once, with no re-login. `~/.local/lib/silky-omarchy/silky-occlusion-*.so` and `~/.config/hypr/silky-occlusion.lua` are kept; delete them by hand if unwanted. To pause it only for now, run `hyprctl silkyocclusion off`.
