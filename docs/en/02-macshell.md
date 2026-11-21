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

## Per-application menu bar

The menu bar follows the foreground window. Chrome and Chromium show History, Bookmarks, and Tab. Firefox shows History, Bookmarks, and Tools. Nautilus shows Go. History opens the browser's history page or library, and bookmark and download commands act on the current window. Other applications use MacShell's general menus.

Install from the repository root. The patch supports MacShell 0.5.3 and requires Python 3, Git, and Hyprland's Lua shortcut dispatcher.

```bash
python3 scripts/install-macshell-app-menus.py --check
python3 scripts/install-macshell-app-menus.py
qs -c MacShell ipc call macshell reload
```

The [menu definitions](../../config/macshell/app-menus/SilkyAppMenus.js) match window application IDs, and the [MacBar patch](../../config/macshell/app-menus/MacBar.patch) adds those menus to the existing bar. Commands use each application's shortcuts, so coverage depends on known application IDs and supported shortcuts. History and bookmark contents are viewed in the application. To verify, focus Chrome, Firefox, and Nautilus in turn, then try History → Show Full History in Chrome or Go → Parent Folder in Nautilus.

The installer writes to `~/.config/quickshell/MacShell/`. To roll back, restore `MacBar.qml` from the backup directory printed by the installer. Restore `SilkyAppMenus.js` if that directory contains an earlier copy, or remove the newly installed copy. Then reload MacShell again. If a MacShell update restores the general menus, run the installer with `--check` to review compatibility.

## Menu bar system monitors

Network speed, CPU temperature and battery panels can be installed separately on MacShell 0.5.1–0.5.3.

```bash
python3 scripts/install-macshell-status.py --check
python3 scripts/install-macshell-status.py
```

Network speed and temperature are sampled every 1.5 s, and the panels show roughly the last minute. The menu bar shows network speed on two lines, upload (↑) on top and download (↓) below so they match the arrows; the order comes from the `Repeater` `model` in [`SilkyStatusButton.qml`](../../config/macshell/status/SilkyStatusButton.qml). Click the network speed to see per-app traffic and this machine's IPv4 / IPv6; click an address to copy it. The app ranking uses TCP sockets visible to the current user that still exist at sampling time; UDP and QUIC are not counted. Traffic forwarded by a proxy may show up under the proxy's process name.

Click the temperature to see the 10 processes using the most CPU right now, plus a hardware overview of the GPU, SSD, Wi-Fi card, fans and so on. Below the overview are whole-machine CPU, memory and system disk (`/`) usage. Process usage is the CPU-time delta between two samples; 100% means one logical core fully used. Click the battery icon to see the power source, power, voltage, charge, capacity, cycle count and health; what appears depends on what the hardware exposes. While MacShell runs it samples every 3 seconds; the "System power" chart in the middle of the panel keeps about the last 5 minutes, and sampling continues with the panel closed. Whole-system power can only be measured on battery, where the battery's discharge rate is everything the laptop draws. On external power the Yoga Slim 7x (Snapdragon X, `qcom-battmgr`) reports neither the adapter input (the USB-C port's `voltage_now` is 0 and `2.00 A` is only the PD contract) nor the system load (the battery's `power_now` is 0 when not charging), so the chart leaves a gap while plugged in and the "System power" row under "Power source" reads "Unavailable on external power". Charge and discharge power are shown as numbers in the "Battery" group ("Charging power / Discharging power / Battery power"). Health is the battery fuel gauge's full-charge capacity `energy_full` divided by the design capacity `energy_full_design`. The gauge recalibrates its full-charge capacity from time to time, so health can jump several points at once; with a charge limit on, recalibration happens less often and the jumps are larger. So you can look back at changes, the menu bar checks every 10 minutes and appends a row to `~/.local/state/silky/battery-health.csv` once a day and whenever the full-charge capacity changes (time, model, full/design capacity, health, cycle count). On the Yoga Slim 7 14Q8X9 you can drag a slider in the battery panel to set a 55%–100% charge limit; "Apply" writes it with system authorization and checks the kernel's read-back. Right-click the battery icon to switch between the power modes the system offers; Omarchy remembers the choice separately for AC and battery power. At the bottom of the right-click panel there is also a "Show battery percentage" switch; turned off, the battery shows only the charge bar without the number. It is MacShell's `showBatteryPercent` setting and is saved to `~/.config/macbar/settings.json`.

Tray icons are unified as monochrome line icons like the rest of the menu bar (following light/dark): each tray item is matched by id to a hand-drawn icon in `SilkyStatusIcon`, currently Chrome, ChatGPT, Clippy, Netcatty, Remmina, Clash Verge and WeChat (id `wechat`, two overlapping speech bubbles). Other apps keep their own icons, and so does any item that needs attention (`NeedsAttention`). To find a tray id: `busctl --user get-property <service> /StatusNotifierItem org.kde.StatusNotifierItem Id`. After installing, run `qs -c MacShell ipc call macshell reload` so MacShell reloads.

## Notification Center widgets

The "Notification system" panel that opens from the bell in the menu bar now has macOS-style widgets under the notification list. Each comes in small (172×172), medium (356×172) and large (356×356); two small widgets side by side are exactly one medium wide. The widgets' accent color comes from the current wallpaper (the same `wallpaperAccent` as the [battery icon](#battery-icon)) and follows wallpaper changes.

| Widget | Small | Medium | Large | Data |
| --- | --- | --- | --- | --- |
| Weather | City, temperature, conditions, high / low | Adds feels-like, humidity, wind and the next 6 hours | Adds a 6-day forecast with temperature range bars | [Open-Meteo](https://open-meteo.com/), no key, refreshed every 15 min |
| Stocks | Chart, price and change of the first symbol | 3 symbols | 6 symbols | Tencent quotes (`qt.gtimg.cn`) for A-shares, Hong Kong and US; Yahoo Finance for every other market (Tokyo, Europe, global indices, crypto, futures); refreshed every minute |
| Screen Time | Today's total and top 3 apps | Adds an hourly chart and the change vs yesterday | Adds the last 7 days and the top 6 apps | Recorded locally, see below |
| Batteries | Rings for this laptop and devices (up to 4) | 4 rings with names | A device list | UPower: laptop battery, Bluetooth mice / keyboards / headphones… |
| Calendar | Weekday, date, lunar date or festival (Chinese UI) | Adds this month | The whole month with lunar dates, festivals and make-up workday marks | Local date and [`ChinaCalendar.js`](../../config/macshell/calendar/ChinaCalendar.js) |
| System | CPU, memory and disk bars | Three rings with usage | Adds a 5-minute CPU chart, uptime and load | `/proc`, `statvfs("/")` |
| AI usage | One row each for Claude, Codex and DeepSeek: main figure and caption, with Codex's quota bar on the caption line under the figure | Three columns with the same structure: icon and name, main figure, caption, two detail lines | Adds tokens per hour (Claude and Codex stacked) and Codex 5-hour / weekly quota bars with reset times | See "AI usage" below |

Widget cards use the Control Center tiles' material: another layer of the panel's liquid glass (`GGlass` with the `notifPopGlass.ctx` context) with the same thin border (`CornerBorder`) and a faint dark veil, so they sit a little darker than the panel. With the glass off they fall back to a dark translucent tile. The weather card adds only a faint sky tint (clear, cloudy, rain, night) over its top half, and its text follows the panel's light / dark colors; in medium and large the condition and high / low share one line, so they no longer overlap the hourly forecast.

Stock colors default to red up / green down in the Chinese UI and green up / red down otherwise; switch them in the right-click menu. During trading hours the chart is today's intraday line with the previous close dashed; when intraday data is unavailable it shows the last month of daily closes. You can follow up to 12 entries, each one of:

| Entry | Resolves to | Quotes from |
| --- | --- | --- |
| A prefixed code such as `sh000001`, `hkHSI`, `usIXIC` | Used as is | Tencent |
| 6 digits, such as `600519` | Shanghai if it starts with `6` / `9`, Shenzhen for `0` / `3`, Beijing for `4` / `8` | Tencent |
| 4–5 digits, such as `00700` | Hong Kong | Tencent |
| 1–5 letters, such as `AAPL` | US listing | Tencent |
| A code containing `^ . = -`, such as `^N225`, `^GDAXI`, `7203.T`, `SAP.DE`, `BTC-USD`, `GC=F` | Yahoo symbol | Yahoo Finance |
| A name, such as `茅台`, `nvidia`, `toyota` | Tencent's search first (Chinese names), then Yahoo's | Whichever it resolved to |

Resolutions are cached while the data process runs; an entry that cannot be resolved shows as typed in the menu and is retried next round. Drag a row (or its ≡ handle) up or down in the right-click menu to reorder; the widget shows entries in that order, and the small size shows the first one.

### Install

Requires MacShell 0.5.1–0.5.3 with the [menu bar system monitors](#menu-bar-system-monitors) (for the wallpaper accent) and the lunar calendar (`ChinaCalendar.js`) installed.

```bash
python3 scripts/install-macshell-widgets.py --check
python3 scripts/install-macshell-widgets.py
qs -c MacShell ipc call macshell reload
```

The installer copies the QML in [`config/macshell/widgets/`](../../config/macshell/widgets/) to `~/.config/quickshell/MacShell/`, copies [`widgets.py`](../../config/macshell/widgets/widgets.py) to `assets/silky-widgets.py`, and patches `MacBar.qml` in three places: the panel height includes the widget area, `SilkyWidgetDeck` sits under the notification list, and the popup window accepts keyboard input while the right-click menu edits the weather city or stock symbols (`WlrKeyboardFocus.OnDemand`). It backs up `MacBar.qml` as `MacBar.qml.bak.silky-widgets-*` before changing it and does nothing on a repeat run.

### Use

- Right-click any widget for a menu: switch Small / Medium / Large or remove the widget. The weather menu takes a city (any language; empty = locate by IP), saved with Enter or by clicking elsewhere, and shows the city currently shown. The stocks menu lists the followed entries with their resolved names; click "−" to drop one, type a code or name and press Enter to add one, and switch the up/down colors. The menu itself is frosted glass (the same liquid-glass material under a translucent veil). While the menu is open the panel accepts keyboard input; `Esc` closes it.
- Click "Edit Widgets" at the bottom of the panel. The widgets wiggle; click one to cycle Small → Medium → Large, drag to reorder, and click the "−" at the top-left to remove it.
- Below them, "Add Widget" lets you pick a kind and a size. The preview is the real widget; click it or "＋ Add Widget" to add it. The city and stock symbols are set from the right-click menu.
- Layout and settings live in `~/.config/silky/widgets.json`; you can edit it directly and MacShell picks it up.

### How Screen Time is counted

Every 5 s the data process reads the focused window's `class` over the Hyprland socket and adds that time to the app and the current hour. Not counted: 2 minutes without keyboard or mouse input (Quickshell `IdleMonitor`; idle inhibitors from video players count as use), a locked screen (`hyprlock` / `swaylock` / `gtklock` running), and suspend. Days are stored in `~/.local/state/silky/screen-time/YYYY-MM-DD.json`, written once a minute and kept for 30 days. App names and icons come from desktop entries matched by `class` (`DesktopEntries.heuristicLookup`), falling back to the `class`. Counting starts at install and only runs while MacShell runs.

### AI usage

The AI usage widget shows today's usage (local time), refreshed every 30 s. All three providers share one structure: the official logo on a white rounded tile (brand colors: Claude `#D97757`, Codex `#7A6CFF`, DeepSeek `#4D6BFE`), one main figure, a caption and two detail lines. The main figures are Claude's tokens today, Codex's 5-hour quota left and DeepSeek's spend today; the details are requests and output tokens, the weekly quota left and the reset time, and the balance.

- **Claude Code**: reads `~/.claude/projects/**/*.jsonl` (the `projects` directory under `CLAUDE_CONFIG_DIR` when that is set, and also `~/.config/claude/projects`) and adds up today's `usage` per reply, de-duplicated by message ID and request ID. The token total covers input, output, cache reads and cache writes. Cache reads are usually most of it, so the large size lists output and cache separately. Claude Code only logs `rate_limit_info` (type and reset time) when a request is refused because the plan limit is used up; while such a record's reset time is still ahead, the Claude column shows "5-hour quota left 0%", "Limit reached" and the reset time. The running percentage is only available from Anthropic's OAuth usage endpoint, which needs the Claude Code CLI's sign-in credentials; the Claude desktop app manages its own sign-in and this machine has no such credentials, so it is not shown for now.
- **Codex**: reads the sessions changed today under `~/.codex/sessions` and `~/.codex/archived_sessions`. Tokens are each session's `total_token_usage` increase today; the 5-hour and weekly quotas come from `rate_limits` in the latest `token_count` event and are shown as "left", like the Codex app (100 − `used_percent`). Codex only writes them after a reply, so when the recorded reset time (`resets_at`) has passed, that window counts as reset: 100% left, "Fresh window". Before this, the widget showed the stale record, for example "5h 12% · resets in 0 min" while the Codex app showed 100% left. Reset times are shown as a clock time (today) or a date and time.
- **DeepSeek**: DeepSeek has no account sign-in, so paste an API key (created on the [DeepSeek platform](https://platform.deepseek.com/api_keys)) in the right-click menu and press Enter. The key is handed to the data process on stdin and written to `~/.config/silky/ai-keys.json` (mode `0600`); it never goes into `widgets.json` or a process argument. Every 10 minutes the data process calls [`GET /user/balance`](https://api-docs.deepseek.com/api/get-user-balance). The first balance read each day is the baseline, and "spent today" = baseline − current balance; a higher balance (a top-up) resets the baseline. "Remove key" in the menu deletes the key and the baseline.

Logs are read incrementally (only newly appended lines): about 0.1 s for the first scan, about 1 ms after that. Nothing is read or called while the AI usage widget is not on the panel.

The logos come from [LobeHub Icons](https://github.com/lobehub/lobe-icons), npm package `@lobehub/icons-static-svg` (MIT, pinned at 1.104.0): `claude-color.svg`, `codex-color.svg`, `deepseek-color.svg`. The logos themselves are their companies' trademarks, so they are not kept in this repository: the installer downloads them from jsDelivr into `~/.config/quickshell/MacShell/assets/ai-logos/` on first install and only accepts plain SVG without scripts or external links. If the download fails the widget shows brand-colored letter tiles; re-running the installer fetches them later.

### Offscreen preview

[`scripts/preview-macshell-widgets.sh`](../../scripts/preview-macshell-widgets.sh) renders widgets into a PNG under `QT_QPA_PLATFORM=offscreen`, with a snapshot of real data (weather from the cache, a sample balance when no DeepSeek key is set). Nothing appears on screen and the panel layout is untouched. The script prints QML errors (`TypeError`, `ReferenceError`, property clashes and so on).

```bash
scripts/preview-macshell-widgets.sh /tmp/widgets.png              # default: AI small / medium / large, weather medium / large, stocks small
scripts/preview-macshell-widgets.sh /tmp/ai.png ai:small ai:large
SILKY_PREVIEW_LANG=en scripts/preview-macshell-widgets.sh /tmp/en.png
```

The preview's panel colors and glass are approximations (no liquid glass); use it to check layout and data.


### Implementation and limitations

- `SilkyWidgetDeck` starts the data process `assets/silky-widgets.py`. It stays running (Screen Time needs continuous recording), prints one JSON line every 5 s, and is restarted 5 s after it exits. Weather and stocks only go online while those widgets are on the panel; weather is cached in `~/.cache/silky/widgets-weather.json` and shown offline.
- Data is not pushed into QML while the panel is closed; the widgets update when it opens.
- Behind a proxy, IP location resolves to the proxy's exit (for example Los Angeles); set a city in the edit panel.
- Tencent quotes and Yahoo Finance are public web endpoints with no stability guarantee; outside US trading hours, US symbols show the last close. Yahoo prices are in the exchange's currency, without conversion.
- The panel never grows past the screen; with many widgets the widget area scrolls.

### Verify

```bash
# data process: after about 15 s it prints weather, stocks, screen time and system data
(sleep 14; echo refresh) | timeout 16 python3 -I config/macshell/widgets/widgets.py | tail -1 | python3 -m json.tool | head -40
# open the notification panel
qs -c MacShell ipc call notifications open
```

Verified on the machine (Yoga Slim 7x, MacShell 0.5.3, Quickshell 0.3.2): widgets appear under the notifications with the Monterey wallpaper's violet accent; edit mode shows the wiggle, "−" badges, hint and add panel; the user has reordered and resized widgets in the panel. The stocks and weather right-click menus (opened directly by temporary code) render correctly, and symbol resolution was tested in the data process: `600519`, `00700`, `AAPL`, `^N225`, `7203.T`, `SAP.DE`, `BTC-USD`, `GC=F`, `茅台`, `英伟达` and `toyota` all return a price and an intraday line. A panel screenshot confirms the cards now use the liquid glass with a thin border, and weather shows 南京 after the city was set. AI usage data was tested in the data process (that day: Claude Code about 31.7M tokens over 217 requests; Codex about 6.27M tokens, 12% of the 5-hour limit and 37% of the week). The AI usage widget's small, medium and large layouts were checked in Chinese and English with the offscreen preview, and the Codex quotas match the Codex app (5 hours 100% left, week 63% left). Dragging stock rows, typing in the menu and the DeepSeek key still need to be confirmed in the panel.

```bash
# AI usage (run from the repository root)
python3 -I -c 'import importlib.util as u; s=u.spec_from_file_location("w", "config/macshell/widgets/widgets.py"); m=u.module_from_spec(s); s.loader.exec_module(m); r=m.AiUsage().summary(); print(r["claude"] and r["claude"]["tokens"], r["codex"] and (r["codex"]["tokens"], r["codex"]["primary"]))'
# symbol resolution and quotes (run from the repository root)
python3 -I -c 'import importlib.util as u; s=u.spec_from_file_location("w", "config/macshell/widgets/widgets.py"); m=u.module_from_spec(s); s.loader.exec_module(m); [print(q["entry"], q.get("symbol"), q["name"], q.get("price")) for q in m.stocks(["600519", "^N225", "SAP.DE", "茅台"])]'
```

### Roll back

Restore the `MacBar.qml.bak.silky-widgets-*` backup the installer printed, delete `SilkyWidget*.qml`, `SilkyW*.qml`, `SilkyWidgetsFormat.js` and `assets/silky-widgets.py` from `~/.config/quickshell/MacShell/`, then run `qs -c MacShell ipc call macshell reload`. Remove `~/.config/silky/widgets.json`, `~/.config/silky/ai-keys.json`, `~/.local/state/silky/screen-time/`, `~/.local/state/silky/deepseek-balance.json` and `~/.cache/silky/widgets-weather.json` if you no longer want the data.

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

## Hyprland blur instead of Liquid Glass (Normal Blur)

**Effect**: the menu bar's dropdown menus, Control Center, Notification Center, Applications panel, Spotlight and the Dock all use MacShell's "Normal Blur" style (`barStyle` / `dockStyle` = `"blur"`). Hyprland does the blur while compositing, so when you drag a window past the Dock or an open panel, the glass moves with the window in the same frame instead of trailing it. The colours follow the old Liquid Glass maths: the blurred backdrop keeps its full brightness, and dark mode adds only about a 21% tint plus a white sheen that fades from the top. In light mode it is a translucent white with the same sheen. Both follow the system appearance. The trade-off is no bevel refraction or dispersion.

**Cause**: Liquid Glass does not use compositor blur. MacShell captures every window behind the glass, then blurs and refracts the captures in QML. Window positions come from polling Hyprland every 33 ms. So the glass always trails the real window by about 50–90 ms, and MacShell redraws every frame while a window moves. With the menu bar's `glassRealtime` set to `false`, the backdrop behind menus was a periodic snapshot, not live at all.

**Performance comparison**: same machine (Snapdragon X Elite, Adreno X1-85, 2944×1840 @ 90 Hz). `hyprctl` dragged a 700×300 floating window back and forth across the Dock in 192 steps (about 3.1 s), twice per style. MacShell frame times come from `QT_LOGGING_RULES="qt.scenegraph.time.renderloop=true"`, GPU time from `drm-engine-gpu` in `/proc/<pid>/fdinfo`:

| Metric | Liquid Glass | Normal Blur |
| --- | --- | --- |
| MacShell redraws | 90–106 frames/s | about 1 frame/s (nothing to redraw while dragging) |
| MacShell frame time | mean 9–11 ms, p95 22 ms, max 23 ms | under 1 ms |
| MacShell CPU | 23–28% | 0.6% |
| MacShell GPU | 7.2–7.5% | 0% |
| Hyprland CPU | 21% | 24–25% |
| Hyprland GPU | 53% | 61% |

A frame at 90 Hz has 11.1 ms. Liquid Glass's p95 of 22 ms means a good share of frames missed that budget while dragging, so the glass skipped frames. With Normal Blur, MacShell does almost no work during the drag and Hyprland blurs in the same frame. Hyprland itself spends about 8 more percentage points of GPU time, so total GPU use is roughly the same. What you save is MacShell's CPU time and the 50–90 ms delay.

**Install**: from the repository root (safe to run repeatedly):

```bash
./scripts/install-native-blur.sh
```

The script installs [`config/hypr/silky-native-blur.lua`](../../config/hypr/silky-native-blur.lua) and `require`s it from `~/.config/hypr/hyprland.lua`. That file turns on blur for the `macbar` (dropdown menus, Control Center, notifications), `macswitch` (window switcher), `macwall` (wallpaper picker) and `macosd` (volume / brightness OSD) layers. `macdock`, `macspot` and `macbarbg` are already covered by MacShell's install block. It also sets `barStyle` in `~/.config/macbar/settings.json` and `dockStyle` in `~/.config/macdock/settings.json` to `"blur"`, backing each file up as `settings.json.bak.<timestamp>`. Then restart MacShell from Settings > Tools > Restart. `install-macshell-optimizations.sh` now defaults to Normal Blur too.

[`tune-native-blur.py`](../../scripts/tune-native-blur.py) adjusts the Normal Blur tints. Both `install-native-blur.sh` and `install-macshell-optimizations.sh` run it; the former first backs up the QML files it changes to `~/.local/state/macshell/silky-backup-native-blur-<timestamp>/`; you can also run it on its own with `python3 scripts/tune-native-blur.py ~/.config/quickshell/MacShell`.

- The dark tint of the Dock and panels (`GGlass`) drops from 100% to 55% of Glass Opacity, the same as the Liquid Glass shader's `tintMix` (about 21% by default).
- Dropdown menus (`LGlass`) drop from 0.30 + 0.9 × opacity to 0.10 + 0.5 × (dark) or 0.12 + 0.45 × (light).
- The fade behind a clear menu bar (`barFeather`) used to peak at 30%; it now peaks at 4.5%. It sits on the `macbar` layer, and anything above that layer's `ignore_alpha` gets blurred by Hyprland into a dark band. Kept below 0.05, the menu bar is almost fully clear, with only a very faint layer.
- All three get a white sheen fading downward: 7% → 1.5% in dark mode, 12% → 3% in light mode.
- It also turns About This Mac's "More Info…" button from a 75% white slab in light mode into a 4.5% grey fill (8% white in dark mode), matching macOS secondary buttons.

The dark theme's Hyprland blur used to dim the backdrop to 82% (`decoration:blur:brightness = 0.82`), so the blurred background was darkened before the tint went on and looked much darker than Liquid Glass (which blurs on its own and skips that step). The dark theme now uses `1.0`, like the light theme; see [04](04-macos-theme.md).

**Limitations**: blur strength comes from Hyprland's global `decoration:blur` (here `size = 7`, `passes = 3`, `vibrancy = 0.45`). MacShell's Blur slider has no effect on Normal Blur. It requires `decoration:blur:enabled = true`. Desktop widgets (`MacWidgets`) and the glass switches and sliders inside the Settings window are still Liquid Glass. Desktop widgets are not enabled on this machine, and the Settings glass only runs while Settings is open.

**Verify**: verified on Hyprland 0.57.2 with MacShell 0.5.3: `hyprctl configerrors` is empty. Screenshots of the Dock, Control Center and Applications panel in both light and dark mode show the windows and wallpaper behind them blurred. In the drag test above, MacShell no longer redraws every frame.

**Roll back**: set `barStyle` / `dockStyle` back to `"liquid"` in the two `settings.json` files, or restore their `.bak.<timestamp>` copies. Delete the `require("hypr.silky-native-blur")` line from `hyprland.lua`. To bring back the darker dark-mode blur, set `brightness` back to `0.82` in `~/.config/omarchy/themes/macos-tahoe-dark/hyprland.lua` and `~/.local/state/omarchy/current/theme/hyprland.lua`. Then run `hyprctl reload`. To undo the tint changes, restore `MacBar.qml`, `MacDock.qml` and `AboutApp.qml` from the installer's backup (`~/.local/state/macshell/silky-backup-*/MacShell/`). Then restart MacShell.

## Dock glass follows the light / dark appearance

[`tune-dock-follow-appearance.py`](../../scripts/tune-dock-follow-appearance.py): MacDock used to pin `dockDark` to `true`, so the Dock glass stayed dark for good — the `dark` tint of dockglass.frag, the Normal Blur fallback rectangle, the launch preview bar and the edge highlights never changed with the appearance, while the theme switch only reached the right-click menu, hover labels and the indicator dots. `dockDark` now follows `darkMode`: whenever the Menu Bar's appearance changes (the theme hook, the Dock's own Appearance setting, "auto" mode and the `color-scheme` watcher all keep it in step), the whole Dock glass switches between light and dark.

- **Install**: `install-macshell-optimizations.sh` applies it automatically. Standalone: `python3 scripts/tune-dock-follow-appearance.py ~/.config/quickshell/MacShell`, then reload MacShell (Settings > Tools > Restart, or `qs -c MacShell ipc call macshell reload`).
- **Verify**: in light mode the Dock glass should show the translucent white tint; in dark mode it returns to the original dark tint. Verified on Hyprland 0.57.2 with MacShell 0.5.3: after reloading in light mode, a screenshot shows the Dock glass turned light, matching the wallpaper and light appearance.
- **Roll back**: restore `MacDock.qml` from `~/.local/state/silky-omarchy/backup-dock-appearance-<timestamp>/` (installer scenario: `~/.local/state/macshell/silky-backup-*/MacShell/`), then reload MacShell.

## Liquid Glass Dock plugin (prototype)

**Effect**: the Dock gets Liquid Glass's bevel refraction, dispersion and edge light back, but Hyprland draws it while compositing the same frame, so when you drag a window past the Dock the glass moves with it with no delay. MacShell no longer captures windows and uses almost no CPU during a drag. This is a prototype covering the Dock only, and it needs the Dock in the Normal Blur style (see the previous section). Plugin 0.2 also took over the menu bar glass (dropdown menus, Control Center, Notification Center, Applications panel); that was tried and reverted, and the menu bar stays on Normal Blur. The marker format (up to 16 rectangles per layer, with opacity and kind) and the per-kind parameters remain in the plugin and [`SilkyGlassMarker.qml`](../../config/macshell/SilkyGlassMarker.qml) for a later extension.

**Why it can be lag-free**: on macOS, Liquid Glass is drawn by the compositor (WindowServer), which reads the freshly drawn pixels below it while compositing a frame, so there is no delay. Wayland does not let clients read what is under them, so MacShell has to capture windows, poll their positions and hand the result to the compositor, which costs at least 1–2 frames. A lag-free version therefore has to live in the compositor: [`plugins/silky-dock-glass`](../../plugins/silky-dock-glass/main.cpp) is a Hyprland plugin that works like this:

1. Hyprland 0.57 has no function hooks on aarch64, so the plugin only uses the public render-stage event: at `RENDER_POST_WINDOWS` (windows queued, Top layers not yet) it inserts a render element.
2. When that element runs, the framebuffer holds exactly what is under the Dock in this frame. The plugin copies the area around the Dock's input region at half resolution (`glBlitFramebuffer`) and builds mipmaps. Hyprland binds only the draw framebuffer, so the read framebuffer has to be bound to the same one by hand; otherwise the copy comes from a stale buffer from the previous frame, and the Dock refracts its own icons.
3. The shader is ported from MacShell's `dockglass.frag`: rounded-rect bevel, Snell refraction, edge dispersion, blur sampled from mipmaps, adaptive tint and edge light. The defaults are tuned toward macOS 27's Dock: only 6 px of blur and a 10% tint (22% in dark mode, a little deeper like macOS dark glass), so the glass is see-through and what is behind it stays readable; a 14 px bending rim with a refraction strength of 20: only that narrow band lenses, and the middle is flat glass that blurs without distorting. The rim refraction keeps the background continuous: the shift is 0 at the glass edge and at the inner end of the bevel and peaks in between, pointing outward, so the content near the edge is stretched across the whole bevel like a lens; the shift changes by less than 1 px per px, so the image never folds back on itself. The first version copied `dockglass.frag`: Snell refraction on the bevel, with the largest shift (about 50 px) at the very edge. Pixels on either side of the edge showed content 50 px apart, so the image jumped at the glass edge and the strip just outside the glass appeared a second time, squashed inside the rim (for example, a duplicated bright band where a diagonal wallpaper edge meets the Dock). Merely flipping the direction only moved the duplicate to the other side. `thickness` sets the stretch (peak shift = 0.32 × the value, at most 30% of the bevel width); a negative value stretches the other way.

How to check: with every parameter neutral (`blur`, `tint`, `thickness`, `dispersion`, `magnify`, `lift` and `rim` at 0, `saturation` at 1), the area under the Dock is pixel-identical to the plugin being unloaded, so the sampling position is right and any remaining difference comes from the optical effects. Compared against the original wallpaper, a diagonal crossing the Dock bent into an S: the vertical lens of the whole slab (`magnify` 0.04) plus the opposite stretches at the top and bottom edges. The defaults are therefore `magnify = 0` and `thickness = 20` (previously 0.04 and 52), which keeps such lines nearly straight, with only a slight bend at the edge. The bevel is also capped at 80% of the Dock's half height. It used to reach about 46 px deep on a Dock only about 70 px tall, so the top and bottom bevels overlapped: on the centre line the nearest edge switched from top to bottom and the shift flipped from pulling up to pulling down, tearing the background along the middle of the Dock so the glass looked split into an upper and a lower layer (most visible over windows). The middle is now plain, continuous glass. Windows sliding under the Dock still looked distorted in the middle, though: `bezel` was multiplied by 1.45 and, even with the cap, took 80% of the half height, so the two bending bands covered most of the Dock. `bezel` is now the real width of the bending band (default 14 px, at most 60% of the half height), and the middle ~60% of the Dock no longer distorts. Colour changes are kept minimal too (`saturation` 1.05, `lift` 0.015, `dispersion` 0.06, previously 1.15, 0.03 and 0.10), so the wallpaper under the glass keeps the same colours as around it. Hyprland then draws the Dock layer (icons) on top as usual.
4. The Dock's shape changes every frame while icons magnify. MacDock writes the glass position, size, corner radius and light/dark flag into 45 pixels on the bottom row of its own layer (alpha 1–4 / 255 per pixel = 2 bits, invisible). The plugin's vertex shader decodes them from the very buffer Hyprland is about to draw, so shape and refraction are always in the same frame.
5. The copied backdrop must all come from this frame. Whenever anything within the glass's refraction reach changes, the plugin adds the whole glass area to this frame's damage. Only that area, not the whole screen: full-screen damage makes Hyprland re-blur every surface.

**Performance** (real hardware, Snapdragon X Elite, 2944×1840 @ 90 Hz, the same drag test as [the previous section](#hyprland-blur-instead-of-liquid-glass-normal-blur), averaged over 3 runs each):

| Dragging a window across the Dock | MacShell CPU | MacShell GPU | Hyprland CPU | Hyprland GPU | Delay |
| --- | --- | --- | --- | --- | --- |
| MacShell Liquid Glass (old) | 23–28% | 7% | 21% | 53% | 50–90 ms |
| Normal Blur | about 1% | 0% | 24% | 54% | 0 |
| Plugin Liquid Glass | about 1% | 0% | 25% | 63% | 0 |

When nothing near the Dock moves (other windows still updating elsewhere), the plugin adds only about 1 point of Hyprland GPU (45.4% vs 44.4%). The first prototype asked for full-screen damage and reached 78% GPU while dragging, plus 18 points at idle; damaging only the glass area brought it down to the numbers above. The half-resolution copy and edge-only dispersion made no measurable GPU difference; they are kept because they use less memory. Compared with the old Liquid Glass, total GPU use is about the same (old: MacShell 7% + Hyprland 53%), but MacShell's CPU drops from about 25% to 1%, and there is no delay.

**Install**: switch to Normal Blur with `install-native-blur.sh` first, then from the repository root:

```bash
./scripts/install-dock-glass-plugin.sh
```

The script builds the plugin against the installed Hyprland headers and installs it to `~/.local/lib/silky-omarchy/silky-dock-glass-<version>.so`. It installs [`config/hypr/silky-dock-glass.lua`](../../config/hypr/silky-dock-glass.lua), `require`s it from `hyprland.lua` (loaded at login), and loads the plugin right away. It also runs [`tune-dock-glass-plugin.py`](../../scripts/tune-dock-glass-plugin.py), so MacDock writes the hidden marker and stops drawing its own tint, and adds `export SILKY_DOCK_GLASS_PLUGIN=1` to `~/.config/macshell/env`. The changed `MacDock.qml` and `env` are backed up to `~/.local/state/macshell/silky-backup-dock-glass-<timestamp>/`. Then restart MacShell from Settings > Tools > Restart. Re-run the script after every Hyprland update. Requires `g++`, `make`, `pkg-config` and the Hyprland headers.

**Tuning**: when `~/.config/silky-omarchy/dock-glass.conf` does not exist, the installer puts a commented [default config](../../config/silky-omarchy/dock-glass.conf) there and never overwrites it afterwards. One `key = value` per line: `blur` (blur radius, logical px), `tint` (light-mode tint, 0–1), `tint_dark` (dark-mode tint, default 0.22, a little deeper), `bezel` (widest rim), `thickness` (refraction strength), `dispersion`, `magnify` (vertical lens of the whole slab), `saturation`, `lift` (brightness) and `rim` (edge light). The plugin re-reads the file within a second of saving, with no Hyprland reload. Delete a line to get its default back. With the defaults, Hyprland GPU in the drag test is about 57% (with a slightly larger test window than in the table); a smaller blur radius costs less.

**Limitations**:

- Dock only. The right-click menu and hover labels still use Normal Blur.
- The glass parameters do not follow MacShell's glass sliders; tune them in `~/.config/silky-omarchy/dock-glass.conf` instead (see Tuning below).
- It relies on Hyprland 0.57's internal render interfaces (render-stage event, render elements, `requiresFullDamage`), so a Hyprland upgrade may need code changes.
- With `SILKY_DOCK_GLASS_PLUGIN=1` set but the plugin not loaded, the Dock has no glass background (icons only).
- Verified only on a single, unrotated built-in display at scale 2.

**Verify**: the plugin was first loaded and unloaded repeatedly in a nested Hyprland (Hyprland running in a window, with a test Dock that writes the same marker) to confirm it does not crash, and only then installed on the real session. On the real session, `hyprctl plugin list` shows `silky-dock-glass`, and the Dock shows bevel refraction and edge light. Screenshots taken while `hyprctl` drags a window across the Dock show the window edge inside the glass lining up exactly with its edge outside (same frame), with no leftover Dock icons in the glass. Starting Hyprland with `SILKY_DOCK_GLASS_DEBUG=1` paints magenta where the marker fails to decode; `SILKY_DOCK_GLASS_RAW=1` shows the raw copied backdrop.

**Roll back**: delete `require("hypr.silky-dock-glass")` from `hyprland.lua` and run `hyprctl plugin unload ~/.local/lib/silky-omarchy/silky-dock-glass-<version>.so`. Restore `MacDock.qml` and `~/.config/macshell/env` from the backup directory (or delete the `SILKY_DOCK_GLASS_PLUGIN=1` line), then restart MacShell; the Dock goes back to Normal Blur.

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
