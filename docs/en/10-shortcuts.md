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

## How it works

| File | Role |
| --- | --- |
| `config/hypr/silky-keys-registry.lua` | Loaded **first** in `hyprland.lua`. Wraps `hl.bind` / `hl.unbind` and records every bind's keys, description, source file and dispatcher; provides `silky_keys.dump(path)` and `silky_keys.run(n)` |
| `config/hypr/silky-shortcuts.lua` | Loaded **last** in `hyprland.lua` (after `hypr.macshell`). Unbinds the clashing keys, binds only MacShell's functions on them, and binds Omarchy's actions to the new keys |
| `config/hypr/silky-keys.lua` | Starts the panel at login; `o.rebind("SUPER + K", …)`; adds background blur to the `silky-keys` layer |
| `keys-panel/shell.qml` → `~/.config/quickshell/SilkyKeys/` | The panel itself (a resident Quickshell process, IPC target `keys`) |

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

The script backs up `hyprland.lua`, inserts the registry right after Omarchy's bootstrap line, moves `silky-shortcuts` / `silky-keys` to the end of the file, then runs `hyprctl reload` and restarts the panel.

## Verify

```bash
./scripts/silky-doctor.sh                                  # "no shortcut shared between MacShell and Omarchy", "Super+K shortcut panel is running"
qs -c SilkyKeys ipc call keys search 截图                   # open the panel with a search already typed
hyprctl dispatch 'function() silky_keys.dump("/tmp/k.json") end' && jq length /tmp/k.json
```

The doctor's clash check exports every bind from the registry, groups them by "modifiers + key", and reports any key that has a MacShell/MacLock description plus some other description. If an Omarchy or MacShell update adds a new clash, it shows up here; move it in `silky-shortcuts.lua` the same way.

## Pitfalls

- `silky-shortcuts.lua` must load **after** `hypr.macshell`: its `hl.unbind` clears every bind on the key (MacShell's included) and then binds only MacShell's again. Loaded earlier, MacShell would add a duplicate bind back.
- The registry must load **before** Omarchy's defaults, otherwise it misses Omarchy's binds. The `hl` table survives `hyprctl reload`, so the original `hl.bind` is kept in `_G.silky_keys_real` to avoid wrapping a wrapper.
- Do not use `pkill -f 'qs -c SilkyKeys'`: the command line of the shell running it contains that string too, so it kills itself. The installer uses `pkill -x -f 'qs -c SilkyKeys( -d)?'`.

## Rollback

```bash
rm ~/.config/hypr/silky-keys-registry.lua ~/.config/hypr/silky-shortcuts.lua ~/.config/hypr/silky-keys.lua
# remove the three lines require("hypr.silky-keys-registry"), require("hypr.silky-shortcuts"), require("hypr.silky-keys") from hyprland.lua
pkill -x -f 'qs -c SilkyKeys( -d)?'; rm -r ~/.config/quickshell/SilkyKeys
hyprctl reload
```

Super+K goes back to Omarchy's own menu, and the clashing keys trigger both sides again.
