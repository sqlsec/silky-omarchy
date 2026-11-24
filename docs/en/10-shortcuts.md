# 10 · Shortcuts: MacShell first, Super+K becomes a searchable macOS panel

[简体中文](../10-shortcuts.md) | English

## Goals

1. When MacShell and Omarchy want the same key, keep only the MacShell function; move Omarchy's action to a key nobody uses, so nothing is lost.
2. Super+K no longer opens Omarchy's monospace text menu but a frosted panel in MacShell's macOS 27 look: groups, keycaps (⌘ ⌥ ⌃ ⇧), instant search, and Return runs the selected shortcut.

## Where the clashes came from

Hyprland lets one key carry several binds, and **a press runs all of them**. MacShell's `macshell.lua` calls `hl.bind` directly without unbinding Omarchy's binds on the same keys, so:

| Key | What one press did |
| --- | --- |
| Super+Space | MacShell Spotlight + the Omarchy menu |
| Super+V | MacShell clipboard history + Omarchy "Universal paste" (sends Ctrl+V to the focused window) |
| Alt+Tab | MacShell app switcher + Omarchy "Focus on next window" and "Reveal active window on top" |
| Super+L | MacLock + Omarchy "Cycle workspace layout" |

On top of that, Alt+Shift+Tab is "Focus on previous window" in Omarchy, while MacShell has a backwards switcher (`switcher prev`) with no key; following macOS habits it now goes to MacShell too.

How to find them: group `hyprctl binds` by `modmask + key` and look for keys that appear more than once (Lua binds show only an id in `arg`; the registry below provides the descriptions).

## Keys after the change

MacShell (kept, now with descriptions so they show up in the Super+K panel):

| Key | Function |
| --- | --- |
| Super+Space | Spotlight |
| Super+V | Clipboard history |
| Super+. | Emoji & symbols |
| Super+Z | System Settings |
| Alt+Tab / Alt+Shift+Tab | Switch apps / switch backwards |
| Ctrl+Alt+W | Wallpapers |
| Super+L | Lock (MacLock) |

Omarchy actions that moved:

| Action | Before | Now |
| --- | --- | --- |
| Omarchy menu | Super+Space | **Super+Ctrl+M** |
| Universal paste (Ctrl+Shift+V in terminals) | Super+V | **Super+Alt+V** |
| Cycle workspace layout | Super+L | **Super+Shift+L** (backwards is still Super+Alt+L) |
| Focus next window and raise it | Alt+Tab | **Alt+`** (the key left of 1) |
| Focus previous window | Alt+Shift+Tab | **Alt+Shift+`** |

Every new key was checked to be free in the current configuration first. Super+C / Super+X (universal copy / cut) do not clash and stay as they are.

### Super+T

Use `Super+T` on each of two windows to tile them on the same workspace. On a fullscreen or maximized tiled window, the first press returns it to the split layout. An app can retain its fullscreen presentation within its tile. The floating and tiling actions in MacShell’s View and Window menus use the same action.

Hyprland restores a window's floating size and position when switching back to floating. This could put WeChat or terminals with server-side `hyprbars` title bars under the menu bar. If the restored position is too close to the menu bar, the shortcut accounts for the window's top decoration inset (`silky_gestures.window_top_inset`, falling back to `o.silky_titlebar_height`), places the outer frame 4 logical pixels below the monitor's reserved top edge, and reduces its height if needed. Press `Super+T` on WeChat or Foot to float it, check that its outer top edge clears the menu bar, then press it again to return to tiling.

If the workspace uses the floating layout, use `Super+Shift+L` to select Tiling so new windows automatically join the split. In the tiling layout, `Super+J` switches between horizontal and vertical splits.

Use `Super+Alt+T` to tile a window on its own. Silky moves the other windows to the next workspace on the same display, wrapping from the last workspace to the first. Focus the same window on the original workspace and press `Super+Alt+T` again to float it and return the windows that are still on the destination workspace.

Silky skips windows that have since been closed, moved to another workspace, pinned, or grouped with unrelated windows. It records the moves when you tile the window and clears that history when Hyprland reloads its configuration or restarts.

### Workspace layout switching: centered Liquid Glass OSD, top-bar icon, and in-process toggle

Previously `Super+Shift+L` spawned `omarchy-hyprland-workspace-layout-toggle`, chaining `bash`, `hyprctl`, `jq`, `omarchy-i18n`, and `omarchy-notification-send` — adding noticeable lag, cluttering the notification center with a generic `omarchy-action` bell toast, and leaving no persistent indicator of which layout a workspace uses.

- **In-process toggle, balanced tiling & floating restore**: [`config/hypr/silky-shortcuts.lua`](../../config/hypr/silky-shortcuts.lua) rebinds `Super+Shift+L` to `o.silky_workspace_layout_cycle` inside Hyprland's Lua runtime (keeping the `floating → dwindle → scrolling` cycle, calling `o.workspace_mode` directly, and atomically updating `~/.local/state/omarchy/workspace-layouts/<id>.lua`) with no shell forks or D-Bus notifications. When entering `dwindle` with 3 or more tiled windows, `balance_dwindle_workspace` splits the largest tile at each step instead of forming a deep Fibonacci spiral — preventing stamp-sized windows (tested with 10 windows on workspace 1: minimum tile `358 × 190`, max/min area ratio `~2:1`) while temporarily enabling `cursor.no_warps` so the pointer stays put. Before leaving `floating`, it snapshots every floating window's position, size, and z-order on that workspace; returning to `floating` (even after `dwindle` → `scrolling` or **Reset All to Floating**) restores the exact prior floating layout without warping the cursor. The green-light layout menu in [`silky-folio.lua`](../../config/hypr/silky-folio.lua) routes through the same helper.
- **Top-right Liquid Glass OSD**: [`SilkyWorkspaceLayoutOSD.qml`](../../config/macshell/SilkyWorkspaceLayoutOSD.qml) listens to `silky-ws-layout` Hyprland custom events and matches the volume/brightness OSD's exact top-right placement (`x = width - 256 - 22`, `y = barH + 14`), dimensions (`256 × 67` full pill), and `SilkyGlassMarker` (`kind: 1`) Liquid Glass look. Switching animates the monochrome icon with a subtle spring scale, glides the label in, and slides a 3-segment indicator thumb across the track, fading out after 1.2 s without touching the notification center.
- **Top-bar workspace layout icon**: [`scripts/install-workspace-layout-ui.py`](../../scripts/install-workspace-layout-ui.py) adds a compact layout button ([`SilkyWorkspaceLayoutIcon.qml`](../../config/macshell/SilkyWorkspaceLayoutIcon.qml)) right beside the workspace numbers in MacShell's top bar. Non-floating workspaces show a highlighted pill; left-clicking cycles the screen's active workspace layout, and right-clicking opens a Liquid Glass menu to pick any of the three modes or **Reset All to Floating**.
- **Install, verification & rollback**:

```bash
python3 ./scripts/install-workspace-layout-ui.py
python3 ./scripts/install-workspace-layout-ui.py --check
```

Verified on this machine on 2026-11-23 (Hyprland 0.57.2, dual-monitor `eDP-1` + `DP-1`): `o.silky_workspace_layout_set(8, "dwindle", true)` and returning to `floating` completed in 6–8 ms end-to-end (including `hyprctl`), creating and removing `8.lua` cleanly with empty `hyprctl configerrors` and healthy `macbar` / `macosd` layers. To roll back, restore `~/.config/quickshell/MacShell/{shell,MacBar}.qml.bak.ws-layout.*` and `~/.config/hypr/silky-shortcuts.lua.bak.*`, then reload Hyprland and MacShell.

### Windows adopt the destination workspace layout

When you move a window to another regular workspace by dragging it across displays, dropping it in the overview, or using a shortcut, it adopts the destination layout. It floats in a floating workspace and joins the layout in a tiling or scrolling workspace. Fullscreen windows adapt when they leave fullscreen. Pinned windows stay pinned.

Hyprland 0.57.2 temporarily floats tiled windows during a native drag and tiles them again on release. The [shortcut configuration](../../config/hypr/silky-shortcuts.lua) checks [Silky Gestures](../../plugins/silky-gestures/main.cpp) for the end of the drag before applying the current destination layout.

From the repository root, run `bash scripts/install-silky-gestures.sh` and `bash scripts/install-shortcuts.sh`, then check `hyprctl configerrors`.

On 2026-11-24, simulated pointer input in the live dual-display session confirmed that a temporary Foot window floated on release from workspace 6 to 1 and tiled from 1 to 6. The overview move action also confirmed that a manually floated window joined the scrolling layout in workspace 5. A fullscreen window moved from 6 to 1 stayed fullscreen and floated when it exited fullscreen.

To roll back, restore the installer backups of `~/.config/hypr/silky-shortcuts.lua` and `~/.local/lib/silky-omarchy/silky-gestures-<Hyprland-version>.so`, unload and reload that plugin, then run `hyprctl reload`.

### WeChat's image viewer and chat-history window sizes

Even with the main WeChat window floating, the `图片和视频` ("Images and Videos") window that opens when you click a picture or video was tiled next to other windows on a tiling workspace — and WeChat's own size runs tall: a long phone screenshot opened 874 logical px high, straight into the menu bar (screen here: 1472×920 @ scale 2). The chat-history window (titled `"群名"的聊天记录(条数)`) opens oversized too, with large empty margins on both sides. [`config/hypr/silky-app-windows.lua`](../../config/hypr/silky-app-windows.lua) matches both by `class` `wechat` and title with `hl.window_rule`, floats them, centres them and pins a moderate default size as they open: 900×620 for the viewer, 820×720 for the chat history. Only the two popup title patterns are added to `o.floating_apps.title` (without adding `^wechat$` to `o.floating_apps.class`), so the popups remain self-floating while the main WeChat window still opens floating on its first frame on floating workspaces. `Super+T` still tiles them on demand, the windows stay freely resizable, and WeChat's in-viewer zoom is unaffected.

WeChat does not destroy the viewer when you close it; the next picture reuses the same window (same address, no `openwindow` event), so the open-time rule only reaches viewers created after it was loaded. The same file also hooks `config.reloaded`: every `hyprctl reload` floats any of the two windows that is still tiled, shrinks it back to the default size if either dimension grew past it, and centres it. Windows within the default size are left alone, so manually shrunk sizes survive.

The chat-history window's minimum height is WeChat's own: on 2026-11-20 (WeChat 4.1.13) programmatic resize requests for 600/640/660/700 all snapped back to 720, while growing works freely, so 820×720 is as small as this window gets — the win here is the narrower width and the smaller side margins.

The titles come from WeChat 4.1.13 with the Chinese UI (a native Wayland window, not XWayland). With the English UI, or if a later version renames the windows, the rules will not match; look up the new titles with the command below and adjust the patterns.

### Stop WeChat from stealing focus in the background

On a floating workspace, WeChat (XWayland, `class` `wechat`) sends X11 `_NET_ACTIVE_WINDOW` requests on incoming messages or background state updates. Because Omarchy enables global `misc.focus_on_activate = true` in `/usr/share/omarchy/default/hypr/looknfeel.lua`, Hyprland focuses WeChat and raises it above every other floating window (`pinned` is still `false`, even though it looks unexpectedly pinned on top). Upstream Omarchy already disables this for Telegram (`org.telegram.desktop`), but not for WeChat.

[`config/hypr/silky-app-windows.lua`](../../config/hypr/silky-app-windows.lua) adds `focus_on_activate = false` (`silky-wechat-no-focus-steal`) for `^wechat$`, blocking unsolicited background raises without affecting clicking the window, the Dock, or `Alt+Tab`.

### Preserve the main WeChat window state across hide and reopen

Closing WeChat 4.x (`×`) to the system tray destroys its `xdg_toplevel` and reopening from the tray or launcher creates a new one. Paired with [touch-scroll.c](../../plugins/wechat-wayland/touch-scroll.c) ignoring unsolicited `set_maximized` requests that do not follow an in-window click, [`config/hypr/silky-app-windows.lua`](../../config/hypr/silky-app-windows.lua) hooks `window.destroy`, `window.fullscreen`, and `window.open` for the main WeChat window (`class` `wechat`, title `微信` or `WeChat`), saving the last state (normal floating geometry, maximized, or fullscreen) to `~/.local/state/silky-omarchy/wechat-main-window.state` and restoring it (clamped to the current monitor's usable area) on reopen. Delete that state file and reload Hyprland to clear saved state.

### Return external-display workspaces and windows to the internal screen on unplug

In multi-monitor setups, [`config/hypr/silky-workspaces.lua`](../../config/hypr/silky-workspaces.lua) (installed to `~/.config/hypr/silky-workspaces.lua` and loaded via `require("hypr.silky-workspaces")` before Omarchy's defaults in `hyprland.lua`) assigns workspaces 1–5 to the internal panel `eDP-1` and 6–9 to the external display (preferring `desc:BOE 0x0A52` and falling back to any other connected non-mirror external monitor).

- **Confirmed cause**: When the external display is unplugged, Hyprland tears down that output and leaves non-empty workspaces from it (such as workspace 6) detached (`monitor: "?"`, `monitorID: null`, i.e. `workspace.monitor == nil` in Lua), with their floating windows stuck at `monitor: -1` and off-screen coordinates from the former external monitor. Both `workspaces.reconcile()` and `workspaces.focus()` previously guarded moves with `if workspace and workspace.monitor and ...`, skipping orphaned workspaces with `workspace.monitor == nil` so they never moved back to `eDP-1` and could not be reached even with `Super+6`; `reconcile()` also ignored the `gone` monitor name passed from `monitor.removed`.
- **Fix**: `reconcile(added, gone)` and `focus(id)` now move any workspace whose `workspace.monitor` is `nil`, differs from its target monitor, or matches `gone` back onto the internal panel, and also rescue orphaned regular workspaces with id > 9. When clamping floating windows to the target monitor's logical work area (scale, transform, and `reserved` insets for the menu bar and Dock), `clamp_floating_windows` also accounts for each window's `hyprbars` server-side title-bar height (via `silky_gestures.window_top_inset`, falling back to `o.silky_titlebar_height`) so decorated windows such as Foot never place their title bar over the menu bar. A 150 ms one-shot follow-up `reconcile()` runs after `monitor.removed` to cover teardown timing. Paired with the compositor-level non-drag menu-bar guard and `post-update` rebuild hook in [`silky-gestures`](03-silky-gestures.md#floating-windows-cannot-cross-the-menu-bar) (0.8.4+), windows stay below the menu bar across multi-monitor switches and system updates.
- **Verification & rollback**: Verified on this machine on 2026-11-23 (Hyprland 0.57.2, dual-monitor `eDP-1` + `DP-1` at `1472x-319`): a `foot` window previously clamped to `at.y = -296` (leaving its 30 px `hyprbars` title bar covering the `-319..-296` menu bar) automatically settled at `at.y = -266` (outer top `-296`, flush below the menu bar) after reload; pushing `foot` to `y = -310` and reloading immediately pulled it back, with 0 violations across all 15 floating windows on both displays and empty `hyprctl configerrors`. To roll back, restore `~/.config/hypr/silky-workspaces.lua.bak.*`, `silky-shortcuts.lua.bak.*`, and `silky-macos.lua.bak.*`, then run `hyprctl reload`.

## How it works

| File | Role |
| --- | --- |
| `config/hypr/silky-keys-registry.lua` | Loaded **first** in `hyprland.lua`. Wraps `hl.bind` / `hl.unbind` and records every bind's keys, description, source file and dispatcher; provides `silky_keys.dump(path)` and `silky_keys.run(n)` |
| `config/hypr/silky-shortcuts.lua` | Loaded **last** in `hyprland.lua` (after `hypr.macshell`). Unbinds the clashing keys, binds only MacShell's functions on them, and binds Omarchy's actions to the new keys |
| `config/hypr/silky-keys.lua` | Starts the panel at login; `o.rebind("SUPER + K", …)`; adds background blur to the `silky-keys` layer |
| `keys-panel/shell.qml` → `~/.config/quickshell/SilkyKeys/` | The panel itself (a resident Quickshell process, IPC target `keys`) |
| `config/hypr/silky-app-windows.lua` | Per-app window rules: stop WeChat from stealing focus in the background; WeChat's `图片和视频` viewer and chat-history window always float, centred, at a moderate default size |

Why a registry:

- Omarchy's own Super+K menu learns what each key does from `hyprctl binds` plus a cached Lua scan. On Hyprland 0.57 that cache is broken: `arg` holds only an id and the dispatcher reads `HL.Dispatcher(exec_cmd)` or `function: 0x…`, so selecting an entry actually does nothing.
- Hyprland's Lua API has no function that lists binds (`hl.get_binds` does not exist), and keys sent by a virtual keyboard such as `wtype` **do not** trigger Hyprland binds, so a key press cannot be simulated.
- `hyprctl dispatch 'function() … end'` runs in the same Lua state as the config, so once the dispatchers are recorded while the config loads, the panel can run any of them with `hyprctl dispatch 'function() silky_keys.run(42) end'`. All binds on the same key run together, exactly like a real key press.
- Descriptions use Omarchy's own translation catalog (`/usr/share/omarchy/default/i18n/<language>/keybindings.json`); descriptions with a number in them ("Switch to workspace 3") match their `%1` pattern.

The panel:

- Calls `silky_keys.dump` once each time it opens to get the current binds, so after changing the config `hyprctl reload` is enough; the panel does not need restarting.
- Follows MacShell's settings (`darkMode`, `accent`, `fontFamily` in `~/.config/macbar/settings.json`) live; when the font is Open Runde it loads the font files bundled with MacShell.
- A 28 px-radius glass slab: Hyprland background blur + translucent tint + a top highlight + inner and outer hairlines; a pill-shaped search field; the selected row is an accent-coloured rounded bar with translucent white keycaps. Opens with a 220 ms fade and a slight overshoot, closes in 150 ms.
- Groups: MacShell, Common, Apps, Windows, Workspaces, Screenshots & recording, System & tools, Media & hardware, Input, My shortcuts (by the bind's source file and description).
- Search: several words in any order, all must match; matches the Chinese description, the English original, key names (`super k`, `ctrl shift`, `⌘K`, aliases `win` / `cmd` / `option`) and group names. Results keep the group order.
- Keyboard: ↑↓ / Ctrl+N / Ctrl+P / Tab to select, PgUp/PgDn jump 10 rows, ↩ runs, Esc first clears the search, then closes; clicking outside closes. The mouse changes the selection only when it really moves, so rows scrolling under a resting pointer never steal the keyboard selection.
- To run a shortcut it closes the panel first and waits 140 ms for focus to return to the original window, so shortcuts aimed at the focused window, such as universal copy, still work. Mouse-drag binds (Super+left button to move a window, etc.) are listed but not run.

## Install

```bash
./scripts/install-shortcuts.sh
```

The script backs up `hyprland.lua`, inserts the registry right after Omarchy's bootstrap line, moves `silky-shortcuts` / `silky-keys` to the end of the file, adds a `require` for `silky-app-windows` if missing, then runs `hyprctl reload` and restarts the panel.

## Verify

```bash
./scripts/silky-doctor.sh                                  # "no shortcut shared between MacShell and Omarchy", "Super+K shortcut panel is running"
qs -c SilkyKeys ipc call keys search 截图                   # open the panel with a search already typed
hyprctl dispatch 'function() silky_keys.dump("/tmp/k.json") end' && jq length /tmp/k.json
```

WeChat image viewer and chat history: click a picture in WeChat and open a chat-history window, then run

```bash
hyprctl clients -j | jq -c '.[] | select(.class=="wechat") | {title, size, floating}'
```

The `图片和视频` line should read `"size":[900,620]` with `"floating":true`, the chat history `"size":[820,720]`; both centred and clear of the menu bar. Confirmed on this machine on 2026-11-20: `hyprctl configerrors` is empty; a viewer created after the rules were loaded opened at 900×620 centred; the chat-history window narrowed and centred after `hyprctl reload`. Programmatically resizing the chat history below 720 height snaps back to WeChat's own minimum, not a rule problem; whether a reused old viewer is pulled back to the default size on reload is still to be checked.

WeChat focus-stealing guard: verified on this machine on 2026-11-22 (Hyprland 0.57.2, WeChat 4.1.29 on XWayland): `hyprctl configerrors` is empty; sending `_NET_ACTIVE_WINDOW` to WeChat's X11 window raised and focused WeChat before the rule, and left the current active window untouched after reloading.

The doctor's clash check exports every bind from the registry, groups them by "modifiers + key", and reports any key that has a MacShell/MacLock description plus some other description. If an Omarchy or MacShell update adds a new clash, it shows up here; move it in `silky-shortcuts.lua` the same way.

## Pitfalls

- `silky-shortcuts.lua` must load **after** `hypr.macshell`: its `hl.unbind` clears every bind on the key (MacShell's included) and then binds only MacShell's again. Loaded earlier, MacShell would add a duplicate bind back.
- The registry must load **before** Omarchy's defaults, otherwise it misses Omarchy's binds. The `hl` table survives `hyprctl reload`, so the original `hl.bind` is kept in `_G.silky_keys_real` to avoid wrapping a wrapper.
- Do not use `pkill -f 'qs -c SilkyKeys'`: the command line of the shell running it contains that string too, so it kills itself. The installer uses `pkill -x -f 'qs -c SilkyKeys( -d)?'`.

## Rollback

To undo the floating-window placement fix alone, restore the previous `~/.config/hypr/silky-shortcuts.lua.bak.*` and run `hyprctl reload`. The installer creates a backup when it replaces a shortcut Lua file whose contents differ.

```bash
rm ~/.config/hypr/silky-keys-registry.lua ~/.config/hypr/silky-shortcuts.lua ~/.config/hypr/silky-keys.lua
# remove the three lines require("hypr.silky-keys-registry"), require("hypr.silky-shortcuts"), require("hypr.silky-keys") from hyprland.lua
pkill -x -f 'qs -c SilkyKeys( -d)?'; rm -r ~/.config/quickshell/SilkyKeys
hyprctl reload
```

To undo only the WeChat viewer and chat-history window rules, delete `~/.config/hypr/silky-app-windows.lua` and the `require("hypr.silky-app-windows")` line in `hyprland.lua`, and run `hyprctl reload`. Windows that are already floating stay floating; press `Super+T` or restart WeChat to tile them again.

Super+K goes back to Omarchy's own menu, and the clashing keys trigger both sides again.
