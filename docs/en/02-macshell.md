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

**No version gate**: the installer no longer refuses other MacShell versions. 0.5.1 uses its own patch, and every other version uses the newest patch, 0.5.2. The patch check then decides what to do: an installation that already has the Silky changes is recognized as "applied" by its runtime markers, and only the tuning is updated; a fresh installation the patch does not fit stops before any file is changed and reports why. Tuners also recognize when upstream already ships their change. For example, 0.5.3's Dock already pauses glass capture while tucked away, so `tune-macshell-performance.py` leaves that spot alone. Checked on this machine's **MacShell 0.5.3**, which already had the Silky changes: `--check` passes, and a full install into an isolated `HOME` left every QML file identical to the existing installation. A fresh 0.5.3 has not been tested.

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

The same file also adds a **110 Hz** custom `modeline` for the external `BOE 0x0A52` (3840×2400, 60–120 Hz continuous in EDID). On Snapdragon X Elite (`x1e80100`, kernel `7.3.0-77-omarchy`), the device-tree `opp-table` for `display-controller@ae01000` caps the DPU core clock at `575 MHz`; `msm`'s `dpu_crtc_mode_valid` allocates 2 Layer Mixers for `hdisplay <= 5120` with a `1.05` inefficiency factor, so the EDID 120 Hz mode (`1176.01 MHz`) requires `617.4 MHz/LM > 575 MHz` (and exceeds uncompressed DP 1.4 HBR3 4-lane bandwidth of `25.92 Gbps`), causing the kernel to drop it and expose only 60 Hz. Keeping the panel's exact EDID blanking (`4000×2450`) at `110 Hz` (`1078.00 MHz`) fits both caps (`565.95 MHz/LM <= 575 MHz` and `25.87 Gbps <= 25.92 Gbps`). Verified live on 2026-11-23: after `hyprctl reload`, `DP-1` runs at `3840x2400@110.00Hz` with zero kernel errors. Roll back by restoring `~/.config/hypr/monitors.lua.bak.*` and running `hyprctl reload`.

## Wi-Fi scanning and recovery

The menu bar, Control Center, and System Settings Wi-Fi page share one scanner. When opening Wi-Fi with an empty list, MacShell first loads NetworkManager's cached networks immediately (~50–100 ms) so the connected and nearby networks appear right away, then runs an `auto` refresh in the background: scans completed within the last 30 seconds reuse the cache, while older caches or clicking Scan Again trigger D-Bus `RequestScan` and wait for `LastScan` to advance (up to 22 seconds, covering the ~16 s tri-band scan on WCN7850, and falling back cleanly to the latest cache if NetworkManager rate-limits the request). While networks are already shown, background scans display a subtle "Searching…" label on the right of the Networks header without shifting or hiding the list. A timeout keeps the previous list and displays a retry message. The menu bar status and panel list polls read cached results, and new panel scans pause during connection attempts. System Settings shows connection progress and errors.

On November 22, 2026, wpa_supplicant first reported lost access-point beacons. The Qualcomm WCN7850 driver `ath12k_wifi7_pci` then failed to flush its transmit queue, and NetworkManager logged `ssid-not-found`. MacShell was reading its cache immediately after requesting an asynchronous scan, so the panel could show an empty list prematurely. This patch fixes the panel behavior. Determining whether the underlying incident originated in the driver, firmware, or access point requires more evidence.

Run from the repository root. Requires Bash, Python 3, NetworkManager's `nmcli`, systemd's `busctl`, and GNU `patch`. Tested on the local MacShell 0.5.3 installation. Run preflight to check other builds.

```bash
./scripts/install-macshell-wifi.sh --check
./scripts/install-macshell-wifi.sh
```

The installer applies the [patch](../../patches/macshell-wifi-scan.patch) and [scan helper](../../config/macshell/silky-wifi-scan.py) to `~/.config/quickshell/MacShell/` and reloads a running MacShell. The `silky-macshell-wifi.hook` checks and restores compatible files after each `omarchy update`. Keep the checkout at its installed path. When upstream code no longer matches the patch, preflight reports the mismatch and leaves the files intact. To verify, open the Wi-Fi popover and System Settings and check that the list updates after the scan. The commands below show the interface and request a scan. Use `omarchy restart wifi` if you need to clear a soft block and request a new scan.

```bash
nmcli -f DEVICE,TYPE,STATE device
nmcli -f IN-USE,SIGNAL,FREQ device wifi list --rescan yes
```

To roll back, remove `~/.config/omarchy/hooks/post-update.d/silky-macshell-wifi.hook`. Restore `MacBar.qml`, `MacDock.qml`, and `lang/zh-CN.js` from the printed `~/.local/state/macshell/silky-backup-wifi.*` directory, remove `assets/silky-wifi-scan.py` if it was added in the first installation, and run `qs -c MacShell ipc call macshell reload`. After an update, use the backup that matches the installed version.

## Control Center

### Bluetooth panel and Settings page

**Effect**: the Control Center Bluetooth list and Settings → Bluetooth now split the work the way macOS does.

- The Control Center and menu-bar Bluetooth lists show paired devices only and no longer scan when opened. Each device has a round type badge (headphones, gamepad, keyboard, mouse, trackpad, speaker, phone, computer). A connected device's badge uses the accent color, and the battery percentage appears on the right when the device reports it.
- The Settings page opens with a card that has a blue icon, a description and the switch. The small text below it shows the real visibility state. While the page is open, the computer is discoverable and searches for nearby devices. Closing the page restores the previous state.
- Each row in "My Devices" shows the type badge, the name, and either "Connected · battery" or "Not Connected". A Connect or Disconnect button appears on hover, and tapping a row on a touch screen shows it too. The ⓘ on the right opens a device sheet where you can rename the device (Return saves, `Esc` cancels), see its address, connect or disconnect, and "Forget This Device…" (click again to confirm).
- "Nearby Devices" lists only devices that broadcast a name. A spinner next to the heading shows that a search is running. The hundreds of MAC-address rows that used to appear were all unnamed devices and are now hidden.
- When an action fails, the reason appears in red under that device's row, with the specific cause BlueZ reported, such as rejected pairing, no response, or no usable profile. The single English line at the bottom of the page is gone.
- Devices that need a code (keyboards, some headphones) bring up a pairing request in one of three forms: confirm a code, enter a PIN or passkey, or type a code on the device.

This change fixes several problems. The color escape `ESC[0m` from `bluetoothctl devices` leaked into device names and showed up as `[0m` on the Settings page. Unnamed devices flooded the list as addresses. The page said the computer was discoverable while `Discoverable: no`. "Connected" and "Not Connected" were not translated. The old backend also ran `bluetoothctl info` once for every cached device every 6 s, and every 2.5 s while scanning. This machine caches about 110 devices, so each round started more than a hundred processes. The backend is now event driven and no longer polls.

**Install**: [`scripts/tune-bluetooth.py`](../../scripts/tune-bluetooth.py) runs from `install-macshell-optimizations.sh`. It copies `SilkyBluetooth.qml` and `SilkyBtIcon.qml` from [`config/macshell/bluetooth/`](../../config/macshell/bluetooth/) into `~/.config/quickshell/MacShell/`, and `silky-bt-helper.py` into that directory's `assets/`. It then replaces the Bluetooth backend and list rows in `MacBar.qml`, inserts the `settings-components.qml.in` and `settings-pane.qml.in` blocks into `MacDock.qml`, and adds the Chinese strings to `lang/zh-CN.js`. The inserted blocks carry `Silky Bluetooth … begin/end` markers, so re-running the script updates them to the repository version. To update an installed MacShell only:

```bash
python3 scripts/tune-bluetooth.py --check
python3 scripts/tune-bluetooth.py --install
```

`--install` first backs up the files it changes to `~/.local/state/silky-omarchy/bluetooth-backup-*`, then runs `macshell reload`. If the log reports `SBtRow is not a type` after the first install, the running instance did not pick up the newly added inline components on reload. Restart MacShell once, either by logging in again or by running `qs kill -c MacShell` followed by `macshell-start`. The change needs `/usr/bin/python3` with PyGObject (`python-gobject`) and Quickshell's built-in `Quickshell.Bluetooth` module.

**Implementation and compatibility**:

- Reading state: `SilkyBluetooth.qml` reads adapter and device state through `Quickshell.Bluetooth` (BlueZ over D-Bus) and batches refreshes when device properties change. `MacBar.qml` keeps its old interface (`btOn`, `btDevices`, `connectBt`, `toggleBt` and so on) as aliases and wrappers, so the rest of the menu-bar code is unchanged. The device type comes from BlueZ's `Icon` property, for example `audio-headset`, `input-gaming` or `input-tablet`, and falls back to the device name when that property is missing.
- Device actions: `silky-bt-helper.py` runs pair, connect, disconnect and forget over D-Bus, so it can report error names such as `AuthenticationFailed` and `ConnectionAttemptFailed`. The helper registers an `org.bluez.Agent1` with the `KeyboardDisplay` capability but does not ask to be the default agent. BlueZ sends pairing requests to the client that called `Pair`, so the helper handles pairings started from Settings, and Omarchy's `bt-agent.service` (`NoInputNoOutput`) still handles all other requests. The helper starts on demand and exits after 120 s of idle time.
- Visibility and search: the Settings page undoes only the states it turned on itself. A computer that was already discoverable before the page opened stays discoverable, and a search started by another client is not stopped. Another client on this machine keeps searching (it did before this change too), so `Discovering` can stay `yes` after Settings closes.
- Known limitations: pairings that the device starts are still auto-accepted by `bt-agent`, without a prompt. During a search, nearby devices are sorted by name, not by signal strength.

**Verification**: tested on this machine on 2026-11-24 with Hyprland 0.57, MacShell 0.5.3, BlueZ 5.88 and Quickshell 0.3.2:

- After restarting MacShell, the log showed no QML errors.
- An isolated test read 110 cached devices: 1 in "My Devices" and 7 named nearby devices, where the old page showed more than 100 MAC-address rows.
- Opening the Settings page made `bluetoothctl show` report `Discoverable: yes`, and closing it restored `no`.
- Screenshots confirmed the Settings card, badges, spinner, the hover Connect button, the ⓘ device sheet, and both the confirm-code and enter-code request sheets.
- The Control Center Bluetooth page showed only the badge row for the paired trackpad.
- The helper returned `DoesNotExist` for a device that does not exist.

Pairing, connecting, disconnecting, forgetting and renaming a real device, and the battery display, still need manual checks. Open Settings → Bluetooth, put a device in pairing mode and click Connect. The row should show "Pairing…" and then "Connecting…", and the device should move to "My Devices" when it succeeds. Pairing a keyboard should bring up the enter-code or type-code sheet.

**Roll back**: restore `MacBar.qml`, `MacDock.qml` and `lang/zh-CN.js` from `~/.local/state/silky-omarchy/bluetooth-backup-*` (or the installer's `silky-backup-*`). Delete `SilkyBluetooth.qml`, `SilkyBtIcon.qml` and `assets/silky-bt-helper.py` from `~/.config/quickshell/MacShell/`. Remove the `tune-bluetooth.py` line and the added `managed_files` entry from `install-macshell-optimizations.sh`, then run `qs -c MacShell ipc call macshell reload`.

## Rapidly toggling the system menu

Repeated clicks on the top-left icon reverse the menu's animation from its current position, with text, glass, and scale moving together. Opening the menu previously queried the foreground window and rebuilt its fixed menu items, and fading out discarded the glass component. Frame-by-frame capture showed that the text could appear a frame before the compositor glass. The system menu now reuses its items, and menu bar dropdowns use a single animation with glass markers refreshed as opacity changes. With Reduce Motion enabled, the menu opens and closes immediately.

Restart, Shut Down, and Log Out in the top-left system menu take effect on the first click. To verify them without interrupting a session, test with stubbed commands and check that each action runs and closes the menu on the first click.

The standard `scripts/install-macshell-optimizations.sh` applies this change. To update only the menu, back up `~/.config/quickshell/MacShell/MacBar.qml` and run the following from the repository root.

```bash
python3 scripts/tune-macshell-system-menu.py ~/.config/quickshell/MacShell/MacBar.qml
qs -c MacShell ipc call macshell reload
```

On MacShell 0.5.3 in a Hyprland Wayland session, position a dark window over a bright wallpaper so the dropdown straddles both. Click the icon repeatedly at different speeds, then dismiss the menu by clicking outside. Check that the text and glass fade together. Simulated clicks were recorded on the built-in 90 Hz display at 2× scale, and the transitions were inspected frame by frame across the wallpaper and window boundary. To roll back, restore the backup of `MacBar.qml` and reload MacShell.

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

## Occupied workspace indicators in the menu bar

The centered workspace numbers in the menu bar distinguish three states: occupied inactive workspaces show a 3 px indicator dot underneath (matching the running-app dot on the Dock); the active workspace is marked only by its translucent rounded pill and full-brightness `DemiBold` text, without a dot, so one state does not carry two marks; occupied inactive workspaces brighten the digit (90% opacity, `Medium` weight), and empty workspaces stay dim with no dot. Previously, occupied inactive and empty workspaces differed only by `fg2` (~62%) versus `fg3` (~34%), making them hard to tell apart over light or colorful wallpapers. Hovering an inactive workspace also now shows a subtle pill highlight instead of staying transparent.

The standard [install-macshell-optimizations.sh](../../scripts/install-macshell-optimizations.sh) applies [tune-workspace-indicators.py](../../scripts/tune-workspace-indicators.py) automatically. To apply it standalone, back up `~/.config/quickshell/MacShell/MacBar.qml` and run from the repository root:

```bash
cp -a ~/.config/quickshell/MacShell/MacBar.qml ~/.local/state/macshell/MacBar.qml.bak.workspace-indicators
python3 scripts/tune-workspace-indicators.py ~/.config/quickshell/MacShell/MacBar.qml
qs -c MacShell ipc call macshell reload
```

The script is idempotent and targets MacShell 0.5.3 in a Hyprland Wayland session. Verified on the built-in display at 2× scale with windows open on workspaces 1 and 2 and empty workspaces 3–5: while focused on workspace 1, workspace 1 shows only its pill and no dot, and workspace 2 shows a brighter digit with a crisp centered 3 px dot underneath, clearly separated from workspaces 3–5.

The layout icon to the right of the numbers ([`SilkyWorkspaceLayoutIcon.qml`](../../config/macshell/SilkyWorkspaceLayoutIcon.qml)) now idles at about 90% opacity like the occupied digits, with a 1.3 px stroke instead of 1.2 px and the back window of the floating glyph at 60% instead of 45%, so it no longer reads lighter than the numbers beside it. Re-running [`install-workspace-layout-ui.py`](../../scripts/install-workspace-layout-ui.py) installs the new icon and replaces the old `fg2` tint. To roll back, restore the backed-up `MacBar.qml` and run `qs -c MacShell ipc call macshell reload`.

## Wallpaper-adaptive menu bar contrast

Each display samples the top of its wallpaper, and **each control** picks light or dark ink on its own: every menu title, every workspace number and every tray icon is judged separately, while the fixed status buttons on the right (Bluetooth, volume, input method, network speed, temperature, battery, Wi-Fi, search, Control Center, clock, notifications) share one judgement. When the edge of a split wallpaper falls in the middle of the workspaces, the numbers left of it take one ink and those right of it the other, instead of the whole group sharing one. Popovers continue to follow system appearance.

Only when the edge runs through a control's glyph does that control get a backing plate the size of its hover pill (6 px corners, kept inside the bar). Its opacity is solved for WCAG 4.5:1 and capped at 0.56, and the faint ink of an empty workspace steps up from 53% to 76% on a plate so the plate's contrast is not thrown away. A control is judged by its middle half, where the glyph sits, so an edge that only crosses its padding draws no plate. If the shared status group is mixed, its plate spans the group; that only happens when the edge falls inside the right-hand status area.

Before, the left, center and right groups each got a single ink, and a mixed group got a horizontally feathered dark or light scrim that also hung 24 px down onto the desktop. The workspace group is centered, so the edge of a split wallpaper always fell under it: the white side became a dirty grey under 53% black, and the faint inactive digits nearly disappeared.

Run the following from the repository root to update the menu bar. The [full installer](../../scripts/install-macshell-optimizations.sh) also includes this change. Earlier per-group installs are upgraded in place.

```bash
python3 scripts/tune-macshell-bar-contrast.py ~/.config/quickshell/MacShell
qs -c MacShell ipc call macshell reload
```

The [contrast sampler](../../config/macshell/menubar/silky-bar-tone.py) uses Python 3 and ImageMagick to read the visible top of the wallpaper with a centered cover crop and prints, for a column about every 2 logical pixels, the 12th percentile, median and 88th percentile of the luminance within the bar height. [`SilkyBarContrast.qml`](../../config/macshell/menubar/SilkyBarContrast.qml) caches these columns; each control's `SilkyBarContrast.Palette` reads the columns under its own position and picks its ink, with a 200 ms color transition. The three Repeater delegates (menu titles, workspaces, tray) each declare a local palette with the shared id (`barMenuPalette`, `barWorkspacePalette`, `bpal`); references outside the delegates still resolve to the shared palettes, so other installers' anchors keep working.

Sampling only runs when the wallpaper, output size, bar height or bar fill opacity changes. Switching apps, which changes the width of the menus, no longer starts Python and ImageMagick. After a still wallpaper is set from MacShell Settings, the shell queries the live wallpaper as soon as awww has taken it, so the ink follows the wallpaper transition instead of the 4 s poll; wallpapers changed by other means still update on the next poll (about 4 s). It uses the active Omarchy wallpaper when the Omarchy background layer is visible and otherwise the wallpaper backend's reported image for each output. Detecting the Omarchy layer requires `jq`. A failed read (for example a video wallpaper without a readable still frame) falls back to white ink without plates.

Tested on MacShell 0.5.3, Hyprland and awww on the 2944×1840 built-in display at 2× scale. To verify, set the built-in display's wallpaper to `split_L-white_R-black_2560x1440.png` and then `split_L-black_R-white_2560x1440.png` (2560×1440 images, half black and half white) and capture the bar: workspaces 1–3 and 4–5 should take dark and white ink respectively, with no grey scrim at the edge. Then use an image whose edge runs through one digit: only that digit gets a rounded plate.

To roll back, copy `MacBar.qml`, `SilkyBarContrast.qml` and `assets/silky-bar-tone.py` from the backup directory the tuner prints into the MacShell directory (after a first install, also restore `shell.qml` and remove the two added files), then reload MacShell.

## Menu bar system monitors

Network speed, CPU temperature and battery panels can be installed separately on MacShell 0.5.1–0.5.3.

```bash
python3 scripts/install-macshell-status.py --check
python3 scripts/install-macshell-status.py
```

Network speed and temperature are sampled every 1.5 s, and the panels show roughly the last minute. The menu bar shows network speed on one line, 12 px `DemiBold` like the temperature: the busier direction with its arrow (for example `↓ 26K/s`). The panel still shows both upload and download, and the accessible description includes both. The other direction has to be clearly ahead (1.5× and above 1 KB/s) before it switches, so a near tie does not flip the arrow on every sample. The button reserves `↓888K/s`; the arrow stays next to the digits, right-aligned, with spare room on its left, so the tray does not move as the reading changes, and it only widens while a rate is above 100 MB/s. Tabular figures (`tnum`) are requested too, but `Open Runde` is missing on this machine and the PingFang fallback ignores the feature. It used to be two 10 px lines for upload and download, about 22 px tall, noticeably taller than the other icons. Arrows and numbers use the menu bar ink, with the arrow stroke as heavy as the `DemiBold` digits (the cyan and violet upload and download colors stay in the panel). The thermometer grew from 14 px to 16 px with a heavier stroke and a filled bulb, matching the solid Wi-Fi and search glyphs, about 3.5 px from its digits, and the temperature reserves two digits. The network and temperature buttons keep about 6 px of visible space on each side, after the blank space built into the arrow and thermometer canvases, so their gaps to neighbours match Wi-Fi to search (about 8–9 px). The switching rule is `lead` in [`SilkyStatusButton.qml`](../../config/macshell/status/SilkyStatusButton.qml). Click the network speed to see per-app traffic and this machine's IPv4 / IPv6; click an address to copy it. The app ranking uses TCP sockets visible to the current user that still exist at sampling time; UDP and QUIC are not counted. Traffic forwarded by a proxy may show up under the proxy's process name.

Click the temperature to see the 10 processes using the most CPU right now, plus a hardware overview of the GPU, SSD, Wi-Fi card, fans and so on. Below the overview are whole-machine CPU, memory and system disk (`/`) usage. Process usage is the CPU-time delta between two samples; 100% means one logical core fully used. Click the battery icon to see the power source, power, voltage, charge, capacity, cycle count and health; what appears depends on what the hardware exposes. While MacShell runs it samples every 3 seconds; the "System power" chart in the middle of the panel keeps about the last 5 minutes, and sampling continues with the panel closed. Whole-system power can only be measured on battery, where the battery's discharge rate is everything the laptop draws. On external power the Yoga Slim 7x (Snapdragon X, `qcom-battmgr`) reports neither the adapter input (the USB-C port's `voltage_now` is 0 and `2.00 A` is only the PD contract) nor the system load (the battery's `power_now` is 0 when not charging), so the chart leaves a gap while plugged in and the "System power" row under "Power source" reads "Unavailable on external power". Charge and discharge power are shown as numbers in the "Battery" group ("Charging power / Discharging power / Battery power"). Health is the battery fuel gauge's full-charge capacity `energy_full` divided by the design capacity `energy_full_design`. The gauge recalibrates its full-charge capacity from time to time, so health can jump several points at once; with a charge limit on, recalibration happens less often and the jumps are larger. So you can look back at changes, the menu bar checks every 10 minutes and appends a row to `~/.local/state/silky/battery-health.csv` once a day and whenever the full-charge capacity changes (time, model, full/design capacity, health, cycle count). On the Yoga Slim 7 14Q8X9 you can drag a slider in the battery panel to set a 55%–100% charge limit; "Apply" writes it with system authorization and checks the kernel's read-back. Right-click the battery icon to switch between the power modes the system offers; Omarchy remembers the choice separately for AC and battery power. The Power & Battery panel (left-click) also has a Power mode card below Charge limit: a three-part segmented control (power saver, balanced, performance) with the current mode on a raised pill; one click switches it, using the same `omarchy-powerprofiles-set autodetect` call and per-source memory as the right-click panel. While switching, the title shows "Applying…", and a failure is reported inside the card. The read-only Power mode row in the Power source group is hidden, and only kept when the system offers no modes. At the bottom of the right-click panel there is also a "Show battery percentage" switch; turned off, the battery shows only the charge bar without the number. It is MacShell's `showBatteryPercent` setting and is saved to `~/.config/macbar/settings.json`.

Tray icons are unified as monochrome line icons like the rest of the menu bar (following the wallpaper under the right-side controls): each tray item is matched by id or title to a hand-drawn icon in `SilkyStatusIcon`, currently Antigravity (hollow sweeping A arch), Chrome, ChatGPT, Clippy, Netcatty, Remmina, Clash Verge, NetEase Cloud Music and WeChat (id `wechat`, two overlapping speech bubbles). Other apps keep their own icons, and so does any item that needs attention (`NeedsAttention`). To find a tray id: `busctl --user get-property <service> /StatusNotifierItem org.kde.StatusNotifierItem Id`. After installing, run `qs -c MacShell ipc call macshell reload` so MacShell reloads.

The three status panels (plus the right-click power-mode panel) match the Control Center's motion and material: they are narrowed to `356 px` (matching the Notification Center widgets; `272 px` for right-click power modes), open with the same 520 ms `OutBack` (overshoot 1.5) spring scale from 94% to 100% and focus-in morph blur, and close in 150 ms (`OutCubic`) while latching the last mode and horizontal anchor so the panel does not jump as it folds away. They pass `silkyKind: 2` through `PopGlassCtx` to reuse the Control Center's `silky-dock-glass` Liquid Glass (26 px radius); when owned by the compositor, the outer `MenuBorder` and opaque panel tint are hidden and inner cards drop their 1 px borders, relying on soft translucent fills for separation (falling back to the tinted panel and `MenuBorder` if the plugin is not active).

The menu-bar thermometer uses the menu bar ink until the CPU reaches `65 °C`, then turns amber, and red from `80 °C` (`barThermalColor`), keeping the bar monochrome like macOS. The thermal panel accent follows a four-tier temperature scale (`thermalColor` in [`SilkyStatusFormat.js`](../../config/macshell/status/SilkyStatusFormat.js)) with green marking the healthiest state and separate high-contrast dark and light tones: `< 50 °C` green, `50–64 °C` cyan, `65–79 °C` warm amber, and `≥ 80 °C` hot red (neutral foreground before the first sample arrives). The CPU, memory and system-disk usage rings and per-process CPU load bars share the same four-tier palette (`loadColor`): `< 35%` green, `35–64%` cyan, `65–84%` amber, and `≥ 85%` red.

## Notification Center widgets

The "Notification system" panel that opens from the bell in the menu bar now has macOS-style widgets under the notification list. Each comes in small (172×172), medium (356×172) and large (356×356); two small widgets side by side are exactly one medium wide. The widgets' accent color comes from the current wallpaper (the same `wallpaperAccent` as the [battery icon](#battery-icon)) and follows wallpaper changes.

| Widget | Small | Medium | Large | Data |
| --- | --- | --- | --- | --- |
| Weather | City, temperature, conditions, high / low | Adds feels-like, humidity, wind and the next 6 hours | Adds a 6-day forecast with temperature range bars | [Open-Meteo](https://open-meteo.com/), no key, refreshed every 15 min |
| Stocks | Chart, price and change of the first symbol | 3 symbols | 6 symbols | Tencent quotes (`qt.gtimg.cn`) for A-shares, Hong Kong and US; Yahoo Finance for every other market (Tokyo, Europe, global indices, crypto, futures); refreshed every minute |
| Screen Time | Today's total and top 3 apps | Adds an hourly chart and the change vs yesterday | Adds the last 7 days and the top 6 apps | Recorded locally, see below |
| Batteries | Rings for this laptop and devices (up to 4) | 4 rings with names | A device list | UPower: laptop battery, Bluetooth mice / keyboards / headphones… |
| Calendar | Weekday, date, lunar date or festival (Chinese UI) | Adds this month | The whole month with lunar dates, festivals and make-up workday marks | Local date and [`ChinaCalendar.js`](../../config/macshell/calendar/ChinaCalendar.js) |
| System | CPU, memory and disk bars (4-tier load colors) | Three rings with usage (4-tier load colors) | Adds a 5-minute CPU chart, uptime and load | `/proc`, `statvfs("/")` |
| AI usage | One row each for Claude, Codex and Antigravity: icon on the left, name on top, and paired `5h` / `7d` remaining percentages with mini quota bars below (each using 4-tier remaining-quota colors; when the weekly quota is `0%`, the `5h` figure and bar are muted in neutral gray) | Three columns with the same structure: icon and name, main figure, caption, two detail lines | Adds tokens per hour (Claude and Codex stacked) and Codex 5-hour / weekly quota bars with reset times | See "AI usage" below |

Notifications and widgets each have their own glass surface. The panel opens directly to its content. Clear All appears centered below the notifications and above the widgets, and scrolls with the list. Do Not Disturb is available in Control Center under Focus. Cards use the Control Center blur, refraction, and thin rim, bringing their translucency closer to the Wi-Fi panel. A light text-contrast veil adds 10% tint in dark mode and 16% in light mode. The weather card adds a subtle sky tint and puts the condition, high, and low on one line at medium and large sizes.

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

### Notifications stacked by app, scrolling with the widgets

With many notifications, the notification area and the widgets used to be two separate scroll areas with hard-cut edges, which felt disjointed. Now:

- **Stacked by app** (as on macOS): one app's notifications fold into a stack that shows only the newest, with one or two "paper" edges peeking out below (without a separate lower-right expand arrow button). Clicking a folded stack expands it first; an app header with "Show less" and "✕" (clear that app’s notifications) appears above. Clicking a single notification or an expanded notification’s body gives a brief press effect, then runs its default action and removes the notification. The card’s close button, the app’s clear button, and Clear All feather out the affected cards. If the notification has no default action, MacShell focuses a matching window or launches the app from its matching desktop entry. With Reduced Motion, opening and clearing take effect immediately.
- **Only the 3 newest apps**: older apps fold into "N more apps", which expands and collapses again. Closing the panel folds everything back.
- **One scroll**: notifications and widgets scroll together and stop above the Dock on that screen. The bottom fades while more content remains. At the end, the last widget and Edit Widgets can be seen in full. The empty-state label hides as widgets scroll up.

Implementation: the list groups notifications with `notifPop.silkyPlan` and animates positions computed by `silkyY()`. The cards and `SilkyWidgetDeck` share a `Flickable`, whose height accounts for the Dock height and bottom margin. The scroll resets to the top each time Notification Center opens. In Normal Blur, silky-dock-glass 0.5.2 and later clip the glass to the scroll viewport and fade it along with the contents at the bottom. Partly visible cards retain blur and refraction. Older versions and MacShell’s built-in Liquid Glass fade cards by their visible share.

Expanding and collapsing no longer ghost. In the first version, folded cards sat at the newest card's position and faded at the same pace as they moved, and each card's target position came from its neighbours' animating heights, so the targets kept moving, the animations kept restarting, and several translucent cards piled up. Now the layout uses each card's final height only (`silkyFinalH`, including the final app header and paper edges), so every card glides once to a fixed target; a folded card's opacity is the transition progress cubed, so it appears only after sliding out from under the newest card and is gone before it slides back; each app's newest card always draws above its folded cards; and the app header, the paper edges, the "N more apps" button and the widget area all move on the same 420 ms curve. Clearing applies a feather mask only to the affected cards in the viewport. The remaining cards and widgets slide into place when the animation ends.

Check with sample notifications (nothing is sent; they are only added to the list, and `undemo` removes only entries tagged `[Silky demo]`):

```bash
qs -c MacShell ipc call silkynotif demo      # WeChat ×3, Mail ×2, Slack, Calendar
qs -c MacShell ipc call notifications open
qs -c MacShell ipc call silkystack toggle wechat   # expand / collapse one app's stack without clicking
qs -c MacShell ipc call silkynotif undemo
```

Verified on the machine: the samples show as a WeChat stack and a Mail stack (with paper edges), a single Slack card and "1 more app", followed by the widgets, with the bottom card fading. Expanding and collapsing were checked frame by frame with `silkystack toggle`: folded cards stay invisible under the newest one and collapsing leaves no ghosts. Clearing an app and expanding "N more apps" still need to be clicked through in the panel. Over a light window the whole glass panel looks lighter; that is the glass being translucent, not a fault.

### Notification Center scroll speed

Each wheel notch moves 160 logical pixels, with successive steps accumulating and easing on display frames. The touchpad keeps the system scroll direction and scales fine pixel input by 2.2, with quicker easing than the wheel. Touchscreen drags keep the native `Flickable` and catch up to the full finger displacement when dragging starts, then decelerate more gradually on release. The list stops at its bounds and returns to the top when reopened. With Reduced Motion enabled, wheel and touchpad movement goes directly to the target. [Qt Flickable](https://doc.qt.io/qt-6/qml-qtquick-flickable.html)

Install with `python3 scripts/macshell_notification_center.py --install`, shared with the WeChat and banner fixes below. The same user service restores it after updates. With sample notifications, scroll from cards into widgets using each input, check the top and bottom bounds, and reopen the center. Wayland can report wheel notches and touchpad scroll under the same device, so the handler uses whole-notch angles and recent fine scroll events to tell them apart.

### WeChat activation and notification banners

Clicking a WeChat card invokes its default action when available (guarding against stale notifications without `actions` so a `TypeError` does not abort activation). If WeChat is in the tray and the default action leaves its window hidden, MacShell restores it through the tray; once the main window is found, Hyprland both focuses and raises it (`alter_zorder` `top`) so floating windows do not obscure it. A notification without a conversation action opens the main window. The previous window lookup could not see WeChat in the tray, and the existing focus-stealing rule could block ordinary activation requests. Tray restoration uses the [Quickshell tray activation API](https://quickshell.org/docs/v0.3.2/types/Quickshell.Services.SystemTray/SystemTrayItem/).

Opening Notification Center hides existing banners immediately and keeps their cards in the list. New notifications, including urgent ones, appear directly in the list while the center is open. Once it closes, new banners follow the usual settings. Notification Center state is shared across displays, so operating menus on another display does not resume banners early. Notification cards (both banners and Notification Center items) vertically center the left app icon inside the card (`anchors.verticalCenter: parent.verticalCenter` instead of a fixed `y: 15` in `NotifBody`) so multi-line notifications no longer leave the icon pinned near the top.

Run `python3 scripts/macshell_notification_center.py --install` from the repository root. The installer backs up and updates `~/.config/quickshell/MacShell/MacBar.qml` and reloads MacShell. It installs the repair script at `~/.local/libexec/silky-macshell-notifications` and enables the matching systemd user path unit and service. The path unit reapplies the fixes when a system or MacShell update replaces the file. The service also checks it at startup. Use `--check` to check a new version's compatibility. The installer reports unrecognized layouts and keeps the original file.

On MacShell 0.5.3, close WeChat to the tray and click a WeChat notification. Send a sample notification before opening Notification Center and an urgent one while it is open. Both should appear once in the list. Close the center and send another notification to check that banners resume. See automatic repair messages with `journalctl --user -u silky-macshell-notifications.service`.

To roll back, first run `systemctl --user disable --now silky-macshell-notifications.path silky-macshell-notifications.service`. If there have been no other MacBar edits since installation, restore the `~/.local/state/macshell/MacBar.qml.bak.notifications-*` backup printed by the first install, then run `qs -c MacShell ipc call macshell reload`. If there have been later edits, compare the live file with the backup and revert the desired Notification Center changes selectively.

### Sharp notification banner entrances

MacShell 0.5.3 applied Gaussian blur to the banner's text and icon during its roughly 770 ms entrance. The banner now draws its foreground directly and skips the launch-time screen capture for contrast sampling. Text and icons are sharp as soon as they appear, and the background keeps its glass effect.

Banners slide in over 350 ms and fade out over 230 ms. Each card's height and spacing animate together so the stack glides into place when notifications arrive in quick succession or an app withdraws one. Reduced Motion skips these animations.

Run `python3 scripts/macshell_notification_center.py --install` from the repository root. The installer backs up `~/.config/quickshell/MacShell/MacBar.qml` and reloads MacShell. See the [Notification Center fixes](#wechat-activation-and-notification-banners) for update recovery and rollback. On MacShell 0.5.3 under Hyprland Wayland, use `notify-send` to send a banner with Chinese and English text, then send three in succession and withdraw the middle one. Check the text on entry, the glass background, and how the remaining cards move. Single and stacked banners were recorded on the 90 Hz internal display at 2× scaling. The median recorded frame interval in the final sample was 11 ms.

### Feathering dismissed notifications

The old Clear All button called `flatMap()`, which the Qt QML runtime did not support. Clear All now reads directly from notification history, including folded stacks and apps hidden by the list limit. Notifications received after the animation starts stay in the list. Dismissing one card, an app group, or the entire list uses the same 280 ms animation. Visible cards drift up and right as a soft edge sweeps across their content. During dismissal, only cards in the viewport use a temporary GPU texture with one sample per pixel. Reduced Motion clears immediately.

Reinstall and reload MacShell using the steps below. With sample notifications, click one card’s × and then Clear All. The first click removes the selected card. Clear All leaves the No Notifications message. To roll back, restore the installer’s `MacBar.qml.bak.silky-widgets-*` backup to `MacBar.qml` and reload.

### Install

Requires MacShell 0.5.1–0.5.3 with the [menu bar system monitors](#menu-bar-system-monitors) (for the wallpaper accent) and the lunar calendar (`ChinaCalendar.js`) installed.

```bash
python3 scripts/install-macshell-widgets.py --check
python3 scripts/install-macshell-widgets.py
qs -c MacShell ipc call macshell reload
```

The installer copies the [widget files](../../config/macshell/widgets/) to `~/.config/quickshell/MacShell/`. It updates `MacBar.qml`, passes the Dock to the menu bar in `shell.qml`, and updates `SilkyGlassMarker.qml` where the glass plugin is installed. It saves the previous files as `*.bak.silky-widgets-*`. For live blur at the scroll edge, run `bash scripts/install-dock-glass-plugin.sh` from the repository root to update to 0.5.2 or later. After reloading, scroll until Screen Time is partially visible and check the blur and clearance above the Dock. Close and reopen the panel to verify that it starts at the top. Use a sample notification to check the press feedback and single-card clear. To roll back this update, restore the previous `MacBar.qml` and `SilkyGlassMarker.qml` from their backups. If you updated the plugin, restore and reload the previous plugin as well.

### Use

- Right-click any widget for a menu: switch Small / Medium / Large or remove the widget. The weather menu takes a city (any language; empty = locate by IP), saved with Enter or by clicking elsewhere, and shows the city currently shown. The stocks menu lists the followed entries with their resolved names; click "−" to drop one, type a code or name and press Enter to add one, and switch the up/down colors. The menu itself is frosted glass (the same liquid-glass material under a translucent veil). While the menu is open the panel accepts keyboard input; `Esc` closes it.
- Click "Edit Widgets" at the bottom of the panel. The widgets wiggle; click one to cycle Small → Medium → Large, drag to reorder, and click the "−" at the top-left to remove it.
- Below them, "Add Widget" lets you pick a kind and a size. The preview is the real widget; click it or "＋ Add Widget" to add it. The city and stock symbols are set from the right-click menu.
- Layout and settings live in `~/.config/silky/widgets.json`; you can edit it directly and MacShell picks it up.

### How Screen Time is counted

Every 5 s the data process reads the focused window's `class` over the Hyprland socket and adds that time to the app and the current hour. Not counted: 2 minutes without keyboard or mouse input (Quickshell `IdleMonitor`; idle inhibitors from video players count as use), a locked screen (`hyprlock` / `swaylock` / `gtklock` running), and suspend. Days are stored in `~/.local/state/silky/screen-time/YYYY-MM-DD.json`, written once a minute and kept for 30 days. App names and icons come from desktop entries matched by `class` (`DesktopEntries.heuristicLookup`), falling back to the `class`. Counting starts at install and only runs while MacShell runs.

### AI usage

The AI usage widget shows remaining quotas for Claude, Codex, and the Gemini model group in Antigravity. Claude Code token totals are available as a fallback.

- **Claude** reads the latest sample from Claude Desktop’s `~/.config/Claude/plan-usage-history.json`. The sample stores percentages used, which the widget converts to percentages remaining. If the weekly limit is exhausted, the card shows the weekly window and an empty bar at 0%. With no sample from the last 30 minutes, it falls back to Claude Code’s active limit-rejection records (seeding from the tail of session logs modified in the past 7 days on startup and day rollover so multi-day weekly limits survive) or today’s local token count. See [Claude’s usage limits](https://support.claude.com/en/articles/11647753-how-do-usage-and-length-limits-work).
- **Codex**: reads the sessions changed today under `~/.codex/sessions` and `~/.codex/archived_sessions`. Tokens are each session's `total_token_usage` increase today; the 5-hour and weekly quotas come from `rate_limits` in the latest `token_count` event whose `limit_id` is `codex` (or omitted) and that includes a window object (ignoring follow-up `limit_id: "premium"` events with null `primary`/`secondary`, which otherwise overwrite the exhausted quota with `—`), and are shown as "left", like the Codex app (100 − `used_percent`). Codex only writes them after a reply, so when the recorded reset time (`resets_at`) has passed, that window counts as reset: 100% left, "Fresh window". Before this, the widget showed the stale record, for example "5h 12% · resets in 0 min" while the Codex app showed 100% left. Reset times are shown as a clock time (today) or a date and time.
- **Antigravity** reads the signed-in desktop app’s Gemini model-group quota from its local language server every 15 seconds. The small card shows the five-hour percentage and progress bar. Medium and large cards also display the weekly percentage and the five-hour reset time. If the desktop service or quota is unavailable, the widget shows an em dash. The model groups and windows are described in [Google Antigravity’s quota documentation](https://antigravity.google/docs/cli/commands/usage).

Claude Code and Codex logs are read incrementally every 15 seconds. These reads and local Antigravity quota requests run while the AI usage widget is on the panel; opening the notification centre also sends `refresh-ai` and pushes any updated AI figures immediately instead of waiting for the next polling interval.

The logos come from [LobeHub Icons](https://github.com/lobehub/lobe-icons), npm package `@lobehub/icons-static-svg` (MIT, pinned at 1.104.0): `claude-color.svg`, `codex-color.svg`, `antigravity-color.svg`. The logos themselves are their companies' trademarks, so they are not kept in this repository: the installer downloads them from jsDelivr into `~/.config/quickshell/MacShell/assets/ai-logos/` on first install and only accepts plain SVG without scripts or external links. If the download fails the widget shows brand-colored letter tiles; re-running the installer fetches them later.

### Offscreen preview

[`scripts/preview-macshell-widgets.sh`](../../scripts/preview-macshell-widgets.sh) renders widgets into a PNG under `QT_QPA_PLATFORM=offscreen`, with a snapshot of real data (weather from the cache). Nothing appears on screen and the panel layout is untouched. The script prints QML errors (`TypeError`, `ReferenceError`, property clashes and so on).

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

Verified on the machine (Yoga Slim 7x, MacShell 0.5.3, Quickshell 0.3.2): widgets appear under the notifications with the Monterey wallpaper's violet accent; edit mode shows the wiggle, "−" badges, hint and add panel; the user has reordered and resized widgets in the panel. The stocks and weather right-click menus (opened directly by temporary code) render correctly, and symbol resolution was tested in the data process: `600519`, `00700`, `AAPL`, `^N225`, `7203.T`, `SAP.DE`, `BTC-USD`, `GC=F`, `茅台`, `英伟达` and `toyota` all return a price and an intraday line. A panel screenshot confirms the cards now use the liquid glass with a thin border, and weather shows 南京 after the city was set. AI usage data was tested in the data process (that day: Claude Code about 31.7M tokens over 217 requests; Codex about 6.27M tokens, 12% of the 5-hour limit and 37% of the week). The AI usage widget's small, medium and large layouts were checked in Chinese and English with the offscreen preview, and the Codex quotas match the Codex app (5 hours 100% left, week 63% left). Dragging stock rows and typing in the menu still need to be confirmed in the panel.

```bash
# AI usage (run from the repository root)
python3 -I -c 'import importlib.util as u; s=u.spec_from_file_location("w", "config/macshell/widgets/widgets.py"); m=u.module_from_spec(s); s.loader.exec_module(m); r=m.AiUsage().summary(); print(r["claude"] and r["claude"]["tokens"], r["codex"] and (r["codex"]["tokens"], r["codex"]["primary"]))'
# symbol resolution and quotes (run from the repository root)
python3 -I -c 'import importlib.util as u; s=u.spec_from_file_location("w", "config/macshell/widgets/widgets.py"); m=u.module_from_spec(s); s.loader.exec_module(m); [print(q["entry"], q.get("symbol"), q["name"], q.get("price")) for q in m.stocks(["600519", "^N225", "SAP.DE", "茅台"])]'
```

### Roll back

To uninstall, restore the backups of `MacBar.qml`, `shell.qml`, and any existing `SilkyGlassMarker.qml` from before the initial install. Remove `SilkyWidget*.qml`, `SilkyW*.qml`, `SilkyWidgetsFormat.js`, and `assets/silky-widgets.py` under `~/.config/quickshell/MacShell/`, then reload MacShell. Keep `~/.config/silky/widgets.json` to reuse the layout on reinstall.

## Applications panel interaction

[`tune-apps-panel.py`](../../scripts/tune-apps-panel.py) and [`tune-apps-dock-passthrough.py`](../../scripts/tune-apps-dock-passthrough.py): the mouse wheel moves the Applications panel 320 px per notch; two-finger touchpad scrolling tracks tightly (smoothing rate raised to 65) and hands off immediately with 0 ms delay into exponential glide as soon as Wayland delivers a zero-delta `axis_stop` event on finger lift, removing the old 50 ms release-timer hesitation; touchscreen dragging stays smooth inside the grid, braking cleanly on touch without accidental launches and rebounding past top/bottom bounds (`DragOverBounds`). Turning off `appsFlick.synchronousDrag` and handling icon taps on release with an 18 px drift tolerance prevents `Flickable` from stealing rapid taps after fast cursor travel.

### Open / close animation and Dock integration

Earlier revisions stacked an underdamped spring (`z = 0.97` with hard clamping at 1.0), a `114% → 100%` panel zoom multiplied by an independent 180 ms `zoomMix` animation, per-icon staggered `112%` outer-first scaling, and a per-frame 32 px `MultiEffect` full-panel blur, which produced visible bounce/overshoot on rapid reversals or flick releases.

The panel now uses a **restrained macOS Tahoe transition**:

- **Unified critically-damped spring (`ζ = 1.0`, zero bounce)**: opening (`ω = 28`) and closing (`ω = 33`) share one frame-time analytic critically-damped solver with monotonic velocity clamping, guaranteeing zero overshoot and smooth velocity continuity across mid-way reversals and pinch releases.
- **Single subtle zoom and lighter rendering**: `appsStage` scales cleanly from `1.06× → 1.00×` while glass (`t^0.85`) and content (`t`) fade together; per-icon staggered scaling, the per-frame 32 px `MultiEffect` offscreen blur, and the hidden duplicate `Repeater` of all `128×128` app icons are removed so `silky-dock-glass` (or single-pass glass) handles the backdrop directly.
- **Progressive idle tile warmup**: during the 3-second post-login silent warmup and whenever the panel is idle, offscreen tiles instantiate incrementally in 20 ms row batches (`appCols` per tick), eliminating the post-open instantiation spike.
- **Direct Dock interaction**: while Applications is open, `spotWin` carves the Dock capsule out of its overlay input mask. Clicking the Dock's Applications icon closes or reverses the panel directly, clicking any other Dock icon activates that app and dismisses Applications, and clicking empty desktop space outside both closes Applications immediately.

| Symptom | Cause | Fix |
| --- | --- | --- |
| Visible bounce or jelly feel on open/close or reversal | Underdamped spring clamping + non-monotonic `zoomMix × (1 - t)` product + per-icon staggered zoom | Replaced with one critically-damped spring (`ζ = 1.0`) and uniform `1.06× → 1.00×` scaling; removed `zoomMix`, `tileReveal`, and dynamic `MultiEffect` blur |
| ~200 ms first-open stall or ~650 ms post-open hitch | Shaders compiled on frame 1, followed by instantiating all offscreen tiles at once | Pre-render once at 0.4% opacity 3 s after startup and warm offscreen tiles in 20 ms row batches |
| Missed rapid taps on panel icons or repeated Dock clicks | `synchronousDrag` stole slight-motion taps; full-screen `Overlay` mask covered the Dock and bounced focus across layers | Disabled `synchronousDrag`, added 18 px release-tap tolerance, and carved the Dock capsule out of `spotWin`'s mask (see [03 · Rapid repeated clicks and Dock pass-through](03-silky-gestures.md#rapid-repeated-clicks-and-dock-pass-through)) |

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
- The fade behind a clear menu bar (`barFeather`) used to peak at 30%; it now peaks at 4.5%. It sits on the `macbar` layer, and anything above that layer's `ignore_alpha` gets blurred by Hyprland into a dark band. Kept below 0.05, the menu bar is almost fully clear, with only a very faint layer. The [menu bar contrast tuner](#wallpaper-adaptive-menu-bar-contrast) replaces this fade with `SilkyBarContrast`; after that the script skips this edit, so a missing `barFeather` no longer fails the full installer's preflight.
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

Hyprland can hide the Dock layer in fullscreen while keeping it mapped. Plugin 0.2.2 follows the compositor's visibility check so a glass-only Dock outline cannot linger over the fullscreen window. Update with `./scripts/install-dock-glass-plugin.sh`, enter fullscreen to verify the Dock disappears, and exit to verify its glass returns. The installer backs up the previous plugin for the same Hyprland version.

**Effect**: the Dock, MacShell menu bar popovers (Apple/app dropdown menus, Wi-Fi, Bluetooth, Volume, Battery/Status, Control Center, Notification Center and notification toasts), and other MacShell overlays (Spotlight / Applications `macspot`, Window Switcher `macswitch`, Wallpaper Picker `macwall`, OSD `macosd`) all use the Hyprland plugin to draw Liquid Glass bevel refraction, dispersion and edge light in the same composited frame, with zero lag and without MacShell capturing windows. The thin top menu bar strip itself (`macbarbg`) stays on native blur. Requires MacShell in the Normal Blur style (`barStyle` / `dockStyle` set to `"blur"`).

Edge refraction and dark-mode bottom rim fix in plugin 0.5.4:
- **No artificial white/warm bottom highlight or blur seam over dark backdrops**: previously, when opening panels such as Power & Battery over dark windows with white text, the shader kept a `0.45` base thickness factor and a `10.0` lip slope right at the outer edge (`t -> 0`), dropped the edge blur radius to `0.55×`, and applied `±9%` chromatic dispersion. That pulled bright text 12–16 logical px inside the panel down onto the 1–2 px dark bottom lip as a sharp warm-yellow/white fringe, amplified by symmetric bottom specular rim terms (`abs(g.y)` and `dOpp`). [`plugins/silky-dock-glass/main.cpp`](../../plugins/silky-dock-glass/main.cpp) now fades the refraction path length smoothly to `0` at the outer lip (`h * smoothstep(0.0, 0.28, u)` with slope capped at `1 / 0.24`), keeps edge blur continuous at `0.86×`–`1.0×`, tones down lip dispersion by `0.45 * lipFade`, and restrains the dark-mode bottom rim highlight while preserving the top-left key light and crisp 1-px silhouette. Built and hot-reloaded on Hyprland 0.57.2 at 2× scale (`hyprctl configerrors` empty, Dock verified by screenshot; check the Battery popover over dark text directly by clicking the menu-bar battery icon). To roll back, restore `~/.local/lib/silky-omarchy/silky-dock-glass-<version>.so.bak.<timestamp>` and reload the plugin via `hyprctl plugin unload` / `load`.

Large-panel performance optimizations in plugin 0.5.3:
- **Automatic 8-tap downsampling for large panels**: [`plugins/silky-dock-glass/main.cpp`](../../plugins/silky-dock-glass/main.cpp) switches glass slabs larger than `160000` logical px² (about `400×400`, such as the Applications panel, Wallpaper Picker, and expanded Spotlight) to 8-tap golden-angle mipmap sampling without 3× chromatic dispersion while keeping the same Convex Squircle refraction and 360° specular rim, cutting fragment texture fetches by 60%–86.7%. The Dock, Control Center bubbles, and regular menus keep full 20-tap + dispersion sampling.
- **No empty offscreen FBO**: [`tune-dock-glass-plugin.py`](../../scripts/tune-dock-glass-plugin.py) binds `appsGlassLayer.layer.enabled` to `!appsGlass.silkyOwned`, avoiding a ~2K offscreen texture while the plugin owns the Applications panel backdrop.
- **Idle-sleep marker polling**: [`SilkyGlassMarker.qml`](../../config/macshell/SilkyGlassMarker.qml) runs its per-frame `FrameAnimation` only while glass geometry or opacity is changing, backing off to the 120 ms fallback timer after 12 identical frames and waking immediately on `poke`, `onPopChanged` / `onLpChanged` / `onVisibleChanged`, or watched viewport `contentY` changes. On real hardware (2944×1840 @ 90 Hz, scale 2), 3 s idle open MacShell CPU dropped from ~11.6% to 5.3%–6.0%, idle Hyprland GPU time dropped from 1538 ms to 259 ms with a static backdrop, and 8× open/close Hyprland GPU time dropped from 2844 ms to 1950 ms.

Key changes in plugin 0.4.0 (macOS 26/27 optical Liquid Glass upgrade & floating Control Center bubbles):
- Adds a third material preset `kind = 2` (`cc_*` Control Center floating bubbles) and raises [`SilkyGlassMarker.qml`](../../config/macshell/SilkyGlassMarker.qml) `maxRects` from 16 to 24 to support frameless multi-tile Control Center layouts.
- Upgrades the Liquid Glass fragment shader across all layers (Dock, menus, Notification Center, Spotlight, and Control Center) to a physical **Convex Squircle height profile $h(u)=(1-(1-u)^4)^{1/4}$ with true Snell's Law inward refraction (IOR 1.50)**. The flat interior has strictly zero offset so window edges crossing the glass stay pixel-aligned with the background outside, while the convex bevel bends view rays inward to naturally reflect/refract interior elements (such as window traffic-light buttons) onto the curved rim without pulling outside wallpaper inward, paired with rim-adaptive blur, subtle dispersion, and an ultra-crisp 360° hairline specular rim.
- [`dock-glass.conf`](../../config/silky-omarchy/dock-glass.conf) supports three live-tunable prefixes: plain keys (Dock, `kind = 0`), `menu_` (menus/notifications/Spotlight, `kind = 1`), and `cc_` (Control Center floating bubbles, `kind = 2`).

Base capabilities from plugin 0.3.0:
- Covers `macdock`, `macbar`, `macspot`, `macosd`, `macswitch`, and `macwall` (excluding `macbarbg`). When loaded, [`config/hypr/silky-dock-glass.lua`](../../config/hypr/silky-dock-glass.lua) disables Hyprland native blur on these layers so nested translucent platters (such as grouped Control Center tiles and Notification Center widgets) do not double-blur; when the plugin is absent, native blur stays active as a fallback.
- Performs per-rectangle `requiresFullDamage` checks and `glBlitFramebuffer` copies instead of merging distant popovers into one full-screen bounding box.
- [`SilkyGlassMarker.qml`](../../config/macshell/SilkyGlassMarker.qml) adds an immediate `poke` trigger so opening popovers report their marker in the same frame instead of waiting for the 120 ms timer, and places marker pixels inside a dedicated child container to eliminate Qt `stackAfter` warnings. Nested platters inside a larger panel keep their own Qt tint.

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

The script builds the plugin against the installed Hyprland headers and installs it to `~/.local/lib/silky-omarchy/silky-dock-glass-<version>.so`. It installs [`config/hypr/silky-dock-glass.lua`](../../config/hypr/silky-dock-glass.lua), `require`s it from `hyprland.lua` (loaded at login), and loads the plugin right away. It also runs [`tune-dock-glass-plugin.py`](../../scripts/tune-dock-glass-plugin.py), so MacDock writes the hidden marker and stops drawing its own tint, and adds `export SILKY_DOCK_GLASS_PLUGIN=1` to `~/.config/macshell/env`. The changed `MacDock.qml`, `DockGlassPanel.qml`, and `env` are backed up to `~/.local/state/macshell/silky-backup-dock-glass-<timestamp>/`. Then restart MacShell from Settings > Tools > Restart. Re-run the script after every Hyprland update. Requires `g++`, `make`, `pkg-config` and the Hyprland headers.

**Tuning**: when `~/.config/silky-omarchy/dock-glass.conf` does not exist, the installer puts a commented [default config](../../config/silky-omarchy/dock-glass.conf) there and never overwrites it afterwards. One `key = value` per line: plain keys (`blur`, `tint`, `tint_dark`, `bezel`, `thickness`, `dispersion`, `magnify`, `saturation`, `lift`, `rim`) tune the Dock, `menu_`-prefixed keys tune menus and overlays, and `cc_`-prefixed keys tune standalone Control Center tiles and Notification Center cards. The plugin re-reads the file within a second of saving, with no Hyprland reload. Delete a line to get its default back.

### Liquid Glass on Dock context menus

When the Hyprland plugin handles the Dock, its app context menus share the same live refraction, blur, light and dark tint, and edge highlights. Both read the unprefixed settings in `dock-glass.conf`. The compositor draws the menu as a rounded panel. Disabling the plugin restores the original bubble with a pointer.

Run `./scripts/install-dock-glass-plugin.sh` from the repository root and reload MacShell. Right-click a Dock app where the menu crosses a window edge and the wallpaper to check the backdrop blur and refraction. Click outside the menu to confirm it closes. To roll back the menu change, restore `MacDock.qml` and `DockGlassPanel.qml` from the installer backup and reload MacShell.

### Control Center glass on menus and panels

Menus and panels share the Control Center tiles' refraction, dispersion, and edge highlights by default. Their interiors use a little more blur and tint for legibility over busy backgrounds. When the compositor draws menus, Wi-Fi, Bluetooth, volume, and Notification Center, it supplies their only outer rim. Dropdown menus also hide their extra dark veil in that mode. With widgets installed, Notification Center uses standalone cards with the Control Center material.

From the repository root, rerun the plugin installer above. If you already have a tuning file, back it up and copy the new `menu_*` lines from the default config or remove the old overrides. If notification widgets are installed, rerun `python3 scripts/install-macshell-widgets.py`, then reload MacShell. Open a menu, Wi-Fi, and Notification Center over the same wallpaper to compare color transitions behind the text and the thin highlight around each panel. To roll back this appearance change, restore your previous `dock-glass.conf`, `MacBar.qml`, and `SilkyWidget.qml`, then reload MacShell.

**Limitations**:

- The thin top menu bar strip (`macbarbg`) and Dock hover labels keep their existing materials.
- The glass parameters do not follow MacShell's glass sliders; tune them in `~/.config/silky-omarchy/dock-glass.conf` instead (see Tuning above).
- It relies on Hyprland 0.57's internal render interfaces (render-stage event, render elements, `requiresFullDamage`), so a Hyprland upgrade may need code changes.
- With `SILKY_DOCK_GLASS_PLUGIN=1` set but the plugin not loaded, plugin-owned layers have no glass backdrop (re-run the installer or unset the variable).
- Verified only on a single, unrotated built-in display at scale 2.

**Verify**: real-hardware check (Hyprland 0.57.2, MacShell 0.5.3, plugin 0.4.0): `hyprctl configerrors` is empty, `hyprctl plugin list` reports `silky-dock-glass` 0.4.0, and `MacShell.log` shows no QML errors or `stackAfter` warnings after reload. Screenshots of the floating Control Center bubbles and Dock confirm convex bevel refraction, subtle dispersion, 360° specular rim glints, solid-white active circles, and an untouched `macbarbg` top strip.

**Roll back**: delete `require("hypr.silky-dock-glass")` from `hyprland.lua`, run `hyprctl plugin unload ~/.local/lib/silky-omarchy/silky-dock-glass-<version>.so`, and run `hyprctl reload`. Restore `MacDock.qml`, `MacBar.qml`, and `~/.config/macshell/env` from `~/.local/state/macshell/silky-backup-dock-glass-<timestamp>/` (or delete the `SILKY_DOCK_GLASS_PLUGIN=1` line), then restart MacShell; all overlays go back to Normal Blur.

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

## Window dragging at 90 Hz

On a Snapdragon X Elite (Adreno X1-85) with Hyprland 0.57.2 and a 2944×1840 @ 90 Hz panel, live backdrop blur caused a floating foot window dragged across overlapping windows to update every other refresh. With simulated mouse input and Wayland `wp_presentation` timestamps, foot went from about 45 to 89.6 FPS, and the 95th-percentile frame interval fell from 22.25 to 11.13 ms. After reloading the installed config, GTK (Zenity) and XWayland (XTerm) test windows measured 89.9 and 89.4 FPS respectively, both with a 95th-percentile interval of 11.13 ms.

The opt-in in [`silky-native-blur.lua`](../../config/hypr/silky-native-blur.lua) blends blur in a shader, reduces the pass count from three to two, and disables compositor blur on ordinary windows by default (`no_blur = true`), keeping live backdrop blur only for an allowlist of windows with translucent glass surfaces (Folio, Obsidian, Nautilus, About Omarchy Linux, and macshell Settings). Alongside this, [`silky-macos.lua`](../../config/hypr/silky-macos.lua) disables live blur on `hyprbars` titlebars (`bar_blur = false`) with solid backgrounds to cut compositing overhead across stacked windows. MacShell panels and menus still use the live scene for their backdrop, and the Dock refraction plugin and window animations continue to run. [Hyprland blur options](https://wiki.hypr.land/0.57.0/configuring/core/config-options/#blur)

Update the module from the repository root. Back up the installed module first when present.

```bash
hypr_dir="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
if [ -f "$hypr_dir/silky-native-blur.lua" ]; then
  cp -a "$hypr_dir/silky-native-blur.lua" "$hypr_dir/silky-native-blur.lua.bak.$(date +%Y%m%d-%H%M%S)"
fi
install -m 644 config/hypr/silky-native-blur.lua "$hypr_dir/silky-native-blur.lua"
```

Add `silky_cached_window_blur = true` before `require("hypr.silky-native-blur")` in `hyprland.lua` and run `hyprctl reload`. `hyprctl configerrors` should be empty and `hyprctl getoption render:use_shader_blur_blend` should report `true`. Drag a floating window across other windows to check motion and the frosted backdrop. Check the display mode with `hyprctl monitors`. Remove the opt-in line and reload to restore the theme's blur settings. Apps and the session can stay open.

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

## Redaction levels and right-click cancellation

Press `PrtSc` to open the Omasnap capture picker. Right-click to exit. During an area drag, the first right-click cancels the drag and the next exits.

Press `D` to start drawing a redaction. Click the shield or press `Shift+D` to show the options in the existing toolbar row. Choosing an option or clicking the image restores the normal tools. Blur uses a Gaussian approximation with mirrored edges, gently softens saturation, and lifts shadows, following the pre-blur and tint used in MacShell. Mosaic turns them into blocks. Both effects have Light, Medium, and Strong levels, available by button or wheel. Each effect remembers its level when you switch modes, and the editor starts with Medium blur. Press `V` to select an existing redaction and adjust it with the same controls. Changes can be undone. Use Solid to fully obscure sensitive content.

The [right-click and legacy frost patch](../../patches/omasnap-1.26.2-zh-frost.patch), the [redaction levels patch](../../patches/omasnap-1.26.2-zh-redaction-levels.patch), the [inline toolbar patch](../../patches/omasnap-1.26.2-zh-inline-redaction.patch), and the [glass blur patch](../../patches/omasnap-1.26.2-zh-glass-blur.patch) target the Chinese Omasnap 1.26.2 checkout based on upstream commit `6150151` with `i18n/omasnap_zh_CN.ts`. Existing frosted redactions reopen with their original appearance and can be changed to the new styles. Building requires Qt 6, LayerShellQt, Wayland, libdeflate, and Qt Linguist's `lrelease`. Run from the Silky Omarchy repository root.

```bash
src="$HOME/.local/src/omasnap-zh"
(
  set -e
  frost="$PWD/patches/omasnap-1.26.2-zh-frost.patch"
  levels="$PWD/patches/omasnap-1.26.2-zh-redaction-levels.patch"
  inline="$PWD/patches/omasnap-1.26.2-zh-inline-redaction.patch"
  glass="$PWD/patches/omasnap-1.26.2-zh-glass-blur.patch"
  if ! git -C "$src" apply --reverse --check "$glass" 2>/dev/null; then
    if ! git -C "$src" apply --reverse --check "$inline" 2>/dev/null; then
      if ! git -C "$src" apply --reverse --check "$levels" 2>/dev/null; then
        git -C "$src" apply --reverse --check "$frost" 2>/dev/null ||
          git -C "$src" apply "$frost"
        git -C "$src" apply "$levels"
      fi
      git -C "$src" apply "$inline"
    fi
    git -C "$src" apply "$glass"
  fi
  "$src/bin/test"
)
```

After the tests pass, back up and replace the local binary. The update takes effect on the next launch.

```bash
cp -an "$HOME/.local/bin/omasnap" "$HOME/.local/bin/omasnap.pre-glass-blur"
install -m 755 "$src/build/omasnap" "$HOME/.local/bin/omasnap"
```

Offscreen tests cover the render levels, editing an existing redaction, undo, reopening, and closing the inline options. All three levels were compared on a synthetic dark list to check the edges and color transitions. The picker closed on right-click in a live Hyprland session. To roll back this update, restore `~/.local/bin/omasnap.pre-glass-blur` and reverse the glass blur patch with `git apply -R`.

## Scroll capture without accidental clicks

The scroll capture button used to appear below every selection. On some selections it covered the toolbar and took precedence on mouse press. After drawing a region, the copy, save, and annotation tools are directly accessible. To take a scrolling screenshot, press `S` before drawing, or press `Shift+S` after drawing to use the current region. Press `?` in the capture overlay to see its shortcuts.

The [scroll capture shortcut patch](../../patches/omasnap-1.26.2-zh-scroll-shortcut.patch) targets the configured Chinese Omasnap 1.26.2 checkout (`6150151`) with the build dependencies above. Run from the Silky Omarchy repository root. The change takes effect on the next screenshot.

```bash
src="$HOME/.local/src/omasnap-zh"
patch="$PWD/patches/omasnap-1.26.2-zh-scroll-shortcut.patch"
(
  set -e
  if ! git -C "$src" apply -R --check "$patch" 2>/dev/null; then
    git -C "$src" apply "$patch"
  fi
  "$src/bin/test"
  cp -an "$HOME/.local/bin/omasnap" "$HOME/.local/bin/omasnap.pre-scroll-shortcut"
  install -m 755 "$src/build/omasnap" "$HOME/.local/bin/omasnap"
)
```

Press `PrtSc` and draw a region to see the regular toolbar. Offscreen tests cover clicking the former button position and opening the scroll panel for the current region with `Shift+S`. Simulated keyboard input also verified the installed version on Hyprland 0.57.2 at 2× scale. To roll back, restore `~/.local/bin/omasnap.pre-scroll-shortcut` to `~/.local/bin/omasnap` and run `git -C "$src" apply -R "$patch"` to reverse the source patch.

## Standalone screenshot pins

Press `P` or `Ctrl+P` in the annotator, click the tack on a temporary preview, or use this desktop's `Shift+PrtSc` clipboard shortcut to add a pin to the lower-right stack. Each monitor has its own stack, visible across workspaces. Click a folded card to spread the stack upward. Click an expanded card to open the full image in the center of the work area. Drag any visible card to pull it out directly, or drag a detached image to reposition it.

Drag a detached image's lower-right grip to resize it at the original aspect ratio. Right-click to return it to the stack or delete it, or press `Esc` while it has focus to delete it. Wheel zoom, `Alt`+wheel for 1% steps, `Ctrl`+wheel for opacity, middle-click reset, double-click close, and `Shift`+drag for PNG export are still available. Large images fit the work area.

The context menu and opacity submenu use rounded glass panels, a fine rim, and high-contrast text. The palette follows the system `color-scheme` used by MacShell, even while the menu is open. The backdrop blur comes from Hyprland's popup blur.

The [standalone pin patch](../../patches/omasnap-1.26.2-zh-standalone-pin.patch), [glass menu patch](../../patches/omasnap-1.26.2-zh-pin-glass-menu.patch), and [card stack patch](../../patches/omasnap-1.26.2-zh-pin-stack.patch) target the Chinese Omasnap 1.26.2 checkout. The C++ UI handles thumbnails and input. Hyprland handles window animation and native window dragging. Each stack interaction submits window targets and stacking order in one batch, with no per-frame updates while idle. Use the build dependencies above and run from the Silky Omarchy repository root.

```bash
src="$HOME/.local/src/omasnap-zh"
patch="$PWD/patches/omasnap-1.26.2-zh-standalone-pin.patch"
(
  set -e
  glass="$PWD/patches/omasnap-1.26.2-zh-pin-glass-menu.patch"
  if ! git -C "$src" apply --reverse --check "$glass" 2>/dev/null; then
    git -C "$src" apply --reverse --check "$patch" 2>/dev/null ||
      git -C "$src" apply "$patch"
    git -C "$src" apply "$glass"
  fi
  stack="$PWD/patches/omasnap-1.26.2-zh-pin-stack.patch"
  git -C "$src" apply --reverse --check "$stack" 2>/dev/null ||
    git -C "$src" apply "$stack"
  "$src/bin/test"
  cp -an "$HOME/.local/bin/omasnap" "$HOME/.local/bin/omasnap.pre-pin-stack"
  install -m 755 "$src/build/omasnap" "$HOME/.local/bin/omasnap"
)
```

The change takes effect when opening new pins. Add three images of different sizes to check stacking, expanding, opening at the center, dragging out, and resizing. Use the context menu and `Esc` to check returning and deleting a pin. The offscreen suite covers proportional grip resizing. An isolated Hyprland 0.57.2 session verified the full interaction, clipboard pinning, and promotion from a temporary preview. Frame samples confirmed intermediate positions during expansion. To roll back, restore `~/.local/bin/omasnap.pre-pin-stack` to `~/.local/bin/omasnap` and run `git -C "$src" apply -R "$PWD/patches/omasnap-1.26.2-zh-pin-stack.patch"`.

## Battery icon

The menu-bar battery uses the macOS 26 style: a narrower pill (24 px battery body, 32 px button) with only the number inside, no `%`. The number is usually two digits, so it does not need to be longer. Right-click the battery to turn the number on or off (see "Menu bar system monitors" above). The outer shell and terminal cap stay monochrome with the menu bar text (`bpal.fg`, white on a dark bar and dark on a light bar); only the inner charge fill takes the state color.

The menu-bar battery stays monochrome like macOS: the fill is green while charging, amber on battery at 35% or below, red below 20%, and otherwise (including plugged in but not charging, or plenty of charge) it uses the menu bar ink. The number inverts when it sits on the fill. The shell and terminal cap use the ink at 45% opacity, so a nearly full battery is no longer the darkest block in the bar. The number grew from 9 to 10 px; the button widened from 32 to 37 px for 5 px on each side; the cap sits 0.5 px from the body (one device pixel at 2×), so the two read as one shape. Only states that need attention bring color into the bar.

The power panel and Notification Center battery widget keep this four-tier semantic palette (green = healthiest), shared with the thermal panel, load gauges and AI quota bars:

| State | Color (dark / light) | Condition |
| --- | --- | --- |
| Charging / external passthrough / abundant | Green `#30d158` / `#1c8241` | Charging, plugged-in passthrough (panel badge reads "Power passthrough"), or on battery with `> 65%` charge |
| On battery · normal | Cyan `#64d2ff` / `#0071a4` | On battery with `36%–65%` charge |
| On battery · getting low | Amber `#ff9f0a` / `#b85d00` | On battery with `20%–35%` charge |
| Low battery | Red `#ff453a` / `#c92a22` | Below `20%` (macOS's threshold) and not charging |

Charging wins over low battery: a low battery that is charging shows green. `wallpaperAccent` in `status.py` is still kept for Notification Center widgets such as Screen Time.

(The following describes an earlier design; the menu-bar battery no longer uses the wallpaper accent.) The external-power color used to come from the current wallpaper and follow it when the wallpaper changed. The menu-bar sampler (`wallpaper_accent` in [`status.py`](../../config/macshell/status/status.py)) resolves Omarchy's wallpaper link `~/.local/state/omarchy/current/background`, has ImageMagick (`magick`) shrink it to 96×96 and quantize it to 16 colors, and picks the most vivid dominant color by area × chroma². It keeps that hue and makes two tones, 72% lightness for a dark menu bar and 38% for a light one (saturation clamped to 50%–85%), and sends them as `wallpaperAccent` with each sample to the menu-bar battery and the battery panel. The result is cached by wallpaper path and modification time, so it updates within about 1.5 s of a wallpaper change and is only recomputed when the image changes (about 0.3 s for a 6K PNG). A near-grey wallpaper (dominant chroma below 0.12), a video wallpaper, or a missing `magick` falls back to the old blue. Limitation: green wallpapers (such as Bliss) give a color close to the charging green. To verify: while plugged in and not charging, run `omarchy-theme-bg-set ~/Pictures/Wallpapers/<another>.jpg`; within a few seconds the battery icon and the panel accent change. macOS Monterey gives violet and Sierra a warm orange. To see the picked color directly:

```bash
python3 -c 'import importlib.util as u; s=u.spec_from_file_location("s", "config/macshell/status/status.py"); m=u.module_from_spec(s); s.loader.exec_module(m); print(m.wallpaper_accent())'
```

To deploy, re-run `python3 scripts/install-macshell-status.py`; it replaces the old blue `indicatorColor` with one that reads `wallpaperAccent`. Then restart MacShell so the new sampler runs. To roll back, restore the `MacBar.qml.bak.silky-status-*` backup the installer prints, put the previous `SilkyStatusPanel.qml` and `assets/silky-status.py` back, and restart MacShell.

 The panel's "System power" chart is data, not state, so it always uses violet. [`scripts/install-macshell-status.py`](../../scripts/install-macshell-status.py) writes the colors into `MacBar.qml` (`indicatorColor`); the panel's colors come from `powerState` in [`SilkyStatusPanel.qml`](../../config/macshell/status/SilkyStatusPanel.qml). Re-running the installer replaces the old three-color version; restart MacShell afterwards so the background sampler is replaced by the new script. To verify: plugged in with the battery at its charge limit, the menu-bar icon uses the menu bar ink; unplugged and below 35% it turns amber, and green while charging. When only QML changed, `qs ipc -c MacShell call macshell reload` is enough to reload. To roll back, restore the `MacBar.qml.bak.silky-status-*` backup the installer prints and restart MacShell.

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

## Window opening flashes

The [window configuration](../../config/hypr/silky-macshell-windows.lua) disables Hyprland's `windowsIn` and `fadeIn`, so new windows appear at their final size and opacity, and disables compositor blur (`no_blur`) for Firefox-based browsers (`firefox-based-browser` tag) as well as per-app About dialogs (`AppAbout`, titles starting with `About ` / `关于 `), matching their `18 px` card radius so transparent outer corners never show a blurred light halo. The companion [GTK3 CSD stylesheet](../../config/gtk-3.0/silky-csd.css) (imported from `~/.config/gtk-3.0/gtk.css`) drops `window.csd decoration` transparent shadow margins so Firefox and other GTK3 CSD windows align cleanly from the first frame without flashing an offset frame or blurred halo. Window closing, workspace transitions and Dock minimization keep their own animations.

Run `./scripts/install-macshell-optimizations.sh` from the repository root, then run `hyprctl reload`. On Hyprland 0.57.2 under Wayland, compare opening overlapping test windows and Firefox frame by frame to check that the background does not show through and Firefox aligns cleanly on frame 0. To roll back, restore `silky-macshell-windows.lua` and `gtk3.css` from the installer's `~/.local/state/macshell/silky-backup-*/settings/` backup (or remove `@import url("silky-csd.css");` from `~/.config/gtk-3.0/gtk.css`) and reload Hyprland.

### About window outline

About Omarchy Linux uses the [Omarchy system menu's](11-menu-glass.md) glass tint at 61% opacity in dark mode and 74% in light mode (the System Settings sidebar uses a darker tint at 80% dark / 82% light so it stays subdued over bright windows). When `silky-dock-glass` 0.5.1 is loaded, [`silky-dock-glass.lua`](../../config/hypr/silky-dock-glass.lua) disables Hyprland's multi-pass native blur on About and hands it to the plugin at `RENDER_PRE_WINDOW`, using a **half-resolution backdrop copy + hardware mipmap + single-pass 8-tap golden-angle Vogel disk shader** (live-tunable via `win_blur`, `win_saturation`, `win_contrast`, and `win_brightness` in `~/.config/silky-omarchy/dock-glass.conf`) with bidirectional damage propagation against the Dock glass layer to avoid partial-damage flicker when overlapping. This preserves the live backdrop and borderless 18 px superellipse corners with far lower compositor CPU cost, falling back automatically to Hyprland native live blur if the plugin is not loaded.

The installer deploys the [window rules](../../config/hypr/silky-macshell-windows.lua) and applies the [Normal Blur tuner](../../scripts/tune-native-blur.py). For a manual update, back up `~/.config/hypr/silky-macshell-windows.lua` and the MacShell files `AboutApp.qml`, `MacBar.qml`, and `MacDock.qml`, then run these commands from the repository root. Open About from the top-left menu to inspect the backdrop and corners over text and saturated wallpaper. To roll back, restore the backups and reload Hyprland and MacShell.

```bash
python3 scripts/tune-native-blur.py "${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/MacShell"
install -m 644 config/hypr/silky-macshell-windows.lua ~/.config/hypr/
hyprctl reload
hyprctl configerrors
qs -c MacShell ipc call macshell reload
```

### About window blur during workspace swipes

`silky-dock-glass` 0.5.6 fixes the blurred patch that stayed behind the About window during a four-finger workspace swipe. The [C++ renderer](../../plugins/silky-dock-glass/main.cpp) previously used the window's static position. It now samples the compositor's workspace offset, floating offset, and opacity for the frame being drawn. The animated position determines where it copies the backdrop and expands damage. The plugin skips blur drawing when the window leaves the screen and reuses the same half-resolution texture as the window crosses the edge.

The compositor's swipe interface was used to verify held, canceled, committed, and reverse swipes on ARM64 with Hyprland 0.57.2 and a 90 Hz display. With the window fully off-screen, blur draws dropped from 19 to zero across 19 compositor frames. To check with a touchpad, open About from the top-left menu, hold a four-finger horizontal swipe partway through, then reverse or finish it. The blur should follow the window and disappear from its former position.

With the plugin already enabled, run these commands from the repository root. The installer saves the previous binary alongside the new one with a `.so.bak.<timestamp>` suffix. To roll back, unload the plugin, restore that backup to the original path, then load the plugin and reload Hyprland.

```bash
bash scripts/install-dock-glass-plugin.sh --build-only
plugin="$HOME/.local/lib/silky-omarchy/silky-dock-glass-$(pkg-config --modversion hyprland).so"
hyprctl plugin unload "$plugin"
hyprctl plugin load "$plugin"
hyprctl reload
hyprctl configerrors
```

## Edge version looking like a downgrade in "About This Mac"

Switching to the Edge channel replaces the `omarchy` package (for example `4.5.0-3`) with `omarchy-dev`. That package is versioned by `git describe` on master, for example `4.0.0.r8103.ge4635a4`. `4.0.0` is only the latest tag reachable from master, `r8103` is the number of commits since that tag, and `ge4635a4` is the commit hash. The release tags are not on master, so when About showed this version as-is, a build newer than 4.5.0 looked like a downgrade.

Now, whenever `omarchy-dev` is installed, the row shows the channel and short commit instead, for example `Edge · e4635a4`, followed by the package build date `11-20 build` in the same small, faint auxiliary text as "12 cores" and "8448 MT/s". The channel comes from `omarchy-channel-current`: `dev` shows as `Dev`, and anything else shows as `Edge`. The build date is `%BUILDDATE%` from `/var/lib/pacman/local/omarchy-dev-*/desc`, formatted as `MM-DD` in the local time zone. Stable and RC keep the regular version. The Chinese UI shows `11-20 构建`.

**Implementation**: [`scripts/tune-about-version.py`](../../scripts/tune-about-version.py) edits three files: `assets/about-info.sh` also prints `osver` and `osbuilddate`, `AboutApp.qml` puts the date into the auxiliary text, and `lang/zh-CN.js` gets a translation for `"%1 build"`. It is safe to run again, and `install-macshell-optimizations.sh` runs it every time.

**Install**: run `scripts/install-macshell-optimizations.sh` from the repository root. It backs up these three files and runs on any MacShell version (see [Versions](#versions)). To apply only this change, back up the three files yourself, then run the tuner directly:

```bash
python3 scripts/tune-about-version.py ~/.config/quickshell/MacShell
qs -c MacShell ipc call macshell reload
```

**Verify** (checked on this machine with MacShell 0.5.3, `omarchy-dev 4.0.0.r8103.ge4635a4-1`, Edge channel):

```bash
sh ~/.config/quickshell/MacShell/assets/about-info.sh | grep -E '^os(ver|build)'
qs -c MacShell ipc call about open
```

The last `osver=` line from `about-info.sh` should read `Edge · e4635a4`, and the output should also include `osbuilddate=11-20`. The About window's Omarchy row should read `Edge · e4635a4`, followed by a small, faint `11-20 构建` in Chinese. The Stable / RC display has not been tested on this machine. By the script's logic, the original version shows whenever `omarchy-dev` is not installed.

**Roll back**: restore `AboutApp.qml`, `assets/about-info.sh` and `lang/zh-CN.js` from the backup (the installer's `~/.local/state/macshell/silky-backup-*/MacShell/` or your manual copy), then run `qs -c MacShell ipc call macshell reload`.

## Two menu bars and two Docks after a crash

When MacShell crashed, two mechanisms brought it back at the same time: Quickshell's own crash handler showed a report window and **started a copy by itself** (process name `/usr/bin/quickshell` without arguments, with `__QUICKSHELL_CRASH_*` in its environment), and `macshell-start` started another one. Each drew its own menu bar and Dock.

- `QS_DISABLE_CRASH_HANDLER=1` in `~/.config/macshell/env`: no crash window and no self-restart; only `macshell-start` restarts it quietly. Crash details are still in `~/.local/state/macshell/MacShell.log` and the system core dumps

## The Dock and menu bar stop responding together

The MacShell process can stay alive while the Dock and menu bar stop responding. Even `qs -c MacShell kill` can time out. The [launcher watchdog](../../config/macshell/watchdog.py) arms after MacShell first answers IPC. Each probe waits up to 3 seconds. After three consecutive failures it stops that instance so the existing launcher can restart it. MacLock and other applications run in separate processes. Recovery is logged to `~/.local/state/macshell/MacShell.log`.

From the repository root, run `scripts/install-macshell-optimizations.sh`. The watchdog uses system Python 3 and Linux pidfds to identify the process launched for this session. It takes effect when you next log in or restart the launcher. To remove it, restore `settings/macshell-start` from the installation backup to `~/.local/bin/macshell-start` and log in again. Run `qs -c MacShell ipc show` to check if the current instance responds. Automatic recovery adds a `macshell-watchdog` entry to the log.
- `macshell-start` uses `qs -n -c MacShell`: if MacShell is already running the new one exits right away (exit code 0, and the guard script then ends quietly), so there is always exactly one

## "system.lock" showing in the Omarchy menu

Overriding a menu item with only `action` drops its original `icon` and `label`, so the menu shows the raw id. Write all three when overriding: `"system.lock": {"icon":"󰌾","label":"锁屏","action":"silky-lock"}`. The icon is a Nerd Font private-use character (here Material Design's lock U+F033E, the same set as the other menu icons), which is easily swallowed into an empty string when copied in a terminal or script, leaving only the text; writing it with an escape (such as Python's `"\U000F033E"`) is safer, and `od -c` confirms it afterwards.

## Misaligned glass panel edges

Panels popping out of the menu bar (calendar, Control Center and so on) showed a dark band at the edge that did not line up with the background, as if the background were shifted. The Liquid Glass shader's edge refraction was too strong: popup panels multiplied the refraction to 1.6× the base (and `liquidglass.frag` multiplied again by 1.35) with a 26 px bevel, so the edge "folded in" the background from 50–60 px outside the panel; with a window edge right next to the panel, that was the misaligned dark band.

The patch lowers the multiplier for the two popup glass instances in `MacBar.qml` from 1.6 to 0.6 and the bevel cap from 26 px to 18 px: the edges keep their glass thickness and highlight but bend only about 18 px, close to the restraint of Apple's Liquid Glass. The Dock's glass is unaffected.

The calendar needed its own fix: it scales from its top-right corner, but the old code sampled the background from the unscaled top-left, so after a menu-bar size or display scale change the wallpaper inside the panel was shifted sideways. The calendar now samples the real screen rectangle, its fixed 42 px blur becomes at most 18 px, tint and refraction are lowered, and saturation goes back to 1.05. It keeps a light glass feel, but its backdrop is continuous with the wallpaper outside the panel instead of looking like a separately pasted, recoloured blurred image.

## Control Center

[`tune-control-center-glass.py`](../../scripts/tune-control-center-glass.py): defaults to macOS 26/27-style frameless floating Liquid Glass bubbles (`ccStyle: "tiles"`), giving Wi-Fi, Bluetooth, Focus, Display, Sound, and circular toggles full-capsule/circular shapes rendered through `silky-dock-glass` `kind = 2` (`cc_*`) with vivid edge refraction and a 360° specular rim. Active 1×1 buttons switch cleanly to solid white without duplicate borders; you can still switch back to the grouped frosted slab (`ccStyle: "macos"`) in MacShell Settings or `~/.config/macbar/settings.json`. Appearance follows system light/dark mode.

[`tune-display-controls.py`](../../scripts/tune-display-controls.py): the Control Center gets a new "Display" page, entered like "Sound" (click the name on the left to open the page, drag the slider on the right directly). The page has a brightness slider plus "Night Shift" and "Appearance" (dark / light) switches.

## Dock icons and the Settings window

When System Settings is open, it has its own gear icon in the Dock. It uses the active icon theme's `preferences-system` icon, supplied by MacTahoe on this desktop. Other MacShell windows can still use the [violet M icon](../../config/icons/macshell-logo.png). Settings uses a borderless outline and 18 px rounding scaled with the UI. Its sidebar uses a darker frosted tint (80% dark `#cc1c1c1e`, 82% light `#d1f7f7f9`, matching Folio's sidebar translucency so it does not wash out over bright windows), while the content pane stays opaque. Place Settings over a bright or text-heavy window to check that the blur stays confined to the sidebar and labels remain crisp.

Run `./scripts/install-macshell-optimizations.sh` from the repository root. To apply only this change, back up `~/.config/quickshell/MacShell/MacDock.qml` and run the [Settings tuner](../../scripts/tune-macshell-settings.py) against it with Python 3. Run `hyprctl reload`, `hyprctl configerrors`, and `qs -c MacShell ipc call macshell reload`, then press `Super+Z` to open Settings. The Dock gear and rounded edge over purple wallpaper were checked on MacShell 0.5.3 with Hyprland 0.57.2 in dark mode at 2× scale. To roll back, restore `MacDock.qml` from your backup (or `MacShell/MacDock.qml` in the directory printed by the full installer) and reload Hyprland and MacShell.

- [`tune-dock-hover-label.py`](../../scripts/tune-dock-hover-label.py): after a Dock icon is clicked its hover label stays hidden until the pointer moves more than 4 px. The script recognizes the applied edit by markers such as `muteX`, `muteY` and `cell.tipMuted`, so adding other properties or a `Timer` next to the press handler no longer breaks the full installer's preflight on a rerun.
- [`tune-wallpaper-picker.py`](../../scripts/tune-wallpaper-picker.py): the Wallpaper grid in Settings snaps to whole rows (`GridView.SnapToRow`), so the bottom row's names are never cut in half. Names drop underscores and a trailing resolution (`solid_black_2560x1440` reads `solid black`) and elide at the end; the current wallpaper title follows the same rule. The favorite button is a 24 px light disc with a hairline and a dark star (a gold filled star when set), readable on black and white thumbnails alike. Search still matches the file name. To verify, run `qs -c MacShell ipc call settings pane wallpaper`; after scrolling the grid it should rest on whole rows with readable names. The hover look of the favorite button has not yet been checked with a real pointer. To roll back, restore the backed-up `MacDock.qml` and reload MacShell.
- [`tune-dock-icons.py`](../../scripts/tune-dock-icons.py): optical scaling of Dock icons is centred on the icon, so icons do not drift to one side when magnified on hover; the pivot for rotation (the wiggle) is unchanged.
- [`tune-settings-scroll.py`](../../scripts/tune-settings-scroll.py): the Settings window's left navigation list used to move only a few pixels per wheel notch. It now moves 140 px per notch, adding up several notches and easing there frame by frame; pixel-precise touchpad scrolling is still left to the list itself, keeping native inertia.

### Files fails to open from the Dock

When Omarchy removes Nautilus and switches the default directory handler to Folio, an existing Dock pin can still point to Nautilus. A leftover desktop entry can display the Files icon, and the Dock bounces it while waiting for a window.

From the repository root, run `./scripts/install-macshell-optimizations.sh`. If Nautilus is absent and Folio is installed as the default directory handler, the [migration](../../scripts/migrate-macshell-files.py) replaces the Nautilus pin in `~/.config/macdock/pinned.json` with Folio and preserves the order of other icons. It also removes the old Silky Nautilus localization bindings to restore Omarchy's file shortcuts and archives the old Silky desktop entry so it disappears from the applications panel.

To update these settings on their own, run `python3 scripts/migrate-macshell-files.py`. Then run `hyprctl reload` and `qs -c MacShell ipc call macshell reload`. The Files icon should open Folio and activate its existing window on the next click. Press `Super+Shift+F` to verify the shortcut. If you reinstall Nautilus and want your previous settings back, copy the `.bak.folio.*` files printed by the migration back to their original locations, then reload Hyprland and MacShell.

## Glass refreshes when focus changes

[`tune-glass-stacking.py`](../../scripts/tune-glass-stacking.py): the "fingerprint" of the windows behind the glass used to cover only position and size, so clicking to change which floating window is in front left the glass showing the old stacking order. The focus order (`focusHistoryID`) is now part of it, so the glass refreshes immediately on focus changes; windows changing their titles (terminals, browser tabs, players) still do not wake the 60 Hz refresh.

### Common folders in the Files context menu

With the Folio customization installed, right-click Files in the Dock to open Home, Desktop, Documents, Downloads, or Pictures. The menu uses the system’s user directory settings. If a shortcut resolves to Home, it uses the existing conventional folder when available to avoid a duplicate Home entry. Run the Folio or MacShell optimization installer and reload MacShell to verify the menu. To roll back, restore the installer’s backups of `MacDock.qml` and `lang/zh-CN.js`, then reload MacShell.

#### Long menus are no longer cut off

When Files has several windows open, its context menu lists each window title before the folders and app actions, and can be taller than the 300 px the Dock’s layer surface reserves above the icons. The overflow used to be clipped at the surface edge, hiding the top window titles. The reserved room is now computed once for the tallest menu the Dock can build (8 window titles, the Files folder shortcuts and app actions: 17 rows and 5 separators) and scales with the icon size. With 52 px icons it reserves about 394 px, so the Dock layer grows from 447 to 541 px. The surface keeps that height when a menu opens. Growing the surface only while a menu was open was tried first, but each resize set off the Dock’s position animation and made it jump on every right-click, so the room is now fixed; the script undoes that earlier version. The extra area is transparent and the input region is unchanged, so the desktop does not lose any clicks. The menu stays at least 8 px below the top of the screen.

See [tune-dock-menu-room.py](../../scripts/tune-dock-menu-room.py), called by `scripts/install-macshell-optimizations.sh`. To update only this, back up `~/.config/quickshell/MacShell/MacDock.qml` and run the following from the repository root. The script can be rerun.

```bash
python3 scripts/tune-dock-menu-room.py ~/.config/quickshell/MacShell/MacDock.qml
qs ipc -c MacShell call macshell reload
```

To verify, open seven or more Folio windows and right-click Files in the Dock. The first window title should be fully visible with space above the menu, and the Dock must not move when the menu opens or closes; the `macdock` layer in `hyprctl layers` keeps the same height either way. Verified by a real right-click on MacShell 0.5.2 at 2× scale on eDP-1: with seven Folio windows open the menu shows in full and the Dock stays still. To roll back, restore the backed-up `MacDock.qml` and reload MacShell.

### Empty Trash with one click

Right-click the Trash in the MacShell Dock and select Empty Trash to run it immediately. The item is disabled when the Trash is empty.

The standard optimization installer applies this change. To update only the menu, back up `~/.config/quickshell/MacShell/MacDock.qml` and run these commands from the repository root. A stubbed callback can verify that the first click closes the menu and requests the operation. To roll back, restore the backup and reload MacShell.

```bash
python3 scripts/tune-dock-trash.py ~/.config/quickshell/MacShell/MacDock.qml
qs ipc -c MacShell call macshell reload
```

## Window minimizing

Click the yellow button on Folio, Foot, or any other Silky titlebar window ([silky-macos.lua](../../config/hypr/silky-macos.lua)), the Obsidian yellow button, WeChat's minimize button ([touch-scroll.c](../../plugins/wechat-wayland/touch-scroll.c)), or press `Super+M` ([silky-shortcuts.lua](../../config/hypr/silky-shortcuts.lua)) to fold the window into an individual thumbnail with an app icon badge between the Dock separator and the Trash using a Genie-style curve. Click the thumbnail (or its Dock app icon) to bring back the same window from the same slot. The animation is configured for 300 ms.

Folio captures one bounded frame asynchronously to the Wayland session runtime directory and removes it when the window closes; all other windows capture one bounded in-memory snapshot via `ScreencopyView` + `grabToImage` inside the [scale effect](../../config/macshell/FolioMinimizeFx.qml) right before minimizing (zero disk I/O, capture source released immediately, works even with `windowCapture: false` and zero idle capture overhead), and release it on restore or close. MacShell animates the mesh on the render thread and limits the overlay to the area between the window and its thumbnail. The overlay is ready before the real window moves to the hidden workspace, and Hyprland's window animation is suppressed for that move. The Dock slot and its gap expand linearly over 180 ms and retract when the window returns. When MacShell is unavailable, all entry points fall back to `omarchy-hyprland-window-minimize`.

The old curve started the upper and lower edges in separate phases, reached the final width too early at the bottom, and dimmed the window near the end. The new curve keeps each mesh row moving throughout the animation, with the lower edge leading. It preserves the snapshot brightness and briefly holds the overlay during the handoff to the thumbnail or restored window. Sampling the shader trajectory at 90 Hz with the same endpoints reduced the upper edge’s largest single-frame move from about 45 to 13 logical pixels.

On minimize, MacShell submits the full-size snapshot in place, waits for it to be queued for presentation (calling `window.update()` while waiting for `frameSwapped` so the static overlay does not stall at one swap and hit the 320 ms deadline), and then moves the real window to the hidden workspace. Deformation begins once the move is confirmed. The [Folio Hyprland rule](../../config/hypr/silky-folio.lua) disables the minimize overlay’s own fade to prevent the desktop or a dimmed frame from showing during the handoff.

From the repository root, run `python3 scripts/tune-folio-macshell.py ~/.config/quickshell/MacShell --backup` (or `./scripts/install-folio-macos.sh`), and `./scripts/install-wechat-touch-scroll.sh` for WeChat, then run `hyprctl reload` and `qs -c MacShell ipc call macshell reload` (reopen WeChat for the adapter update). To keep this setup across system updates, install [post-update-silky-minimize](../../hooks/post-update-silky-minimize) to `~/.config/omarchy/hooks/post-update.d/silky-minimize.hook`: after each Omarchy update it verifies and restores the MacShell and Hyprland minimize hooks, and notifies you if `/usr/bin/folio` or its runtime libraries changed. Minimize and restore Folio, Foot, and other floating windows via the yellow button or `Super+M` to verify both the genie animation and the Dock window thumbnail + badge. To roll back, restore any minimized windows, remove the post-update hook, recover the previous MacShell, Hyprland, and WeChat adapter backups, and reload Hyprland and MacShell.

[`disable-minimize.py`](../../scripts/disable-minimize.py) manages the shared minimize entry points for other apps.

## Compositor glass and background collector C++ optimizations

- **`silky-dock-glass` (`0.5.5`) render & readback optimization** ([`plugins/silky-dock-glass/main.cpp`](../../plugins/silky-dock-glass/main.cpp)): tracks `CWLSurfaceResource::m_events.commit` and texture/geometry changes so PBO marker readbacks run only when a glass layer actually updates; skips GL state queries and redraws entirely on frames whose damage does not touch any glass area; shrinks backdrop textures and mipmaps to the tight glass bounding box (64 px bucketed, with `REACH = 48` and `CPU_MARGIN = 24`), caches all uniform locations once in `ensureGL()`, unbinds `g_gl.fbo`'s color attachment after blits, and exposes `hyprctl silkyglass` for live frame/skip/readback counters. On dual high-refresh displays (90 Hz + 110 Hz), ~81.7%–85.8% of frames are skipped, readbacks drop by 99.7%, and idle heap growth drops by ~90%.
- **Native C++ status collector** ([`plugins/silky-status/main.cpp`](../../plugins/silky-status/main.cpp)): [`scripts/install-macshell-status.py`](../../scripts/install-macshell-status.py) builds and installs `assets/silky-status` (falling back to a wrapper calling `silky-status.py` if `g++` is absent). The always-on `bar` mode and `/proc`-heavy `thermal` mode run natively in C++ (reducing resident RSS from ~17 MB to 3.7 MB), while infrequent on-demand modes (`network`, `power`, `profiles`, `set-charge-limit`) `execv` the sibling `silky-status.py`.
- **Multi-monitor widget backend deduplication** ([`SilkyWidgetsFormat.js`](../../config/macshell/widgets/SilkyWidgetsFormat.js), [`SilkyWidgetDeck.qml`](../../config/macshell/widgets/SilkyWidgetDeck.qml)): coordinates all screen instances through the `.pragma library` module so only one `silky-widgets.py` backend runs across all monitors (with automatic handoff on hot-unplug), saving ~105 MB RSS and half of the periodic polling on dual-display setups.
