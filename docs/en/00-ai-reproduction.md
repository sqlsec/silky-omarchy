# 00 · Reproduction index for AI coding assistants

[简体中文](../00-ai-reproduction.md) | English

> For an overview of every interface and interaction change, see [12 · UI interaction overview](12-ui-interactions.md).

Hand this file and the repository URL to an AI coding assistant such as Claude Code, Codex or Cursor, and it can reproduce these refinements module by module without you explaining each step. Each module lists: the intended effect, key files, search keywords, likely pitfalls and verification commands. Details are in the numbered documents.

## Prerequisites

- Distribution: Omarchy 4.x (Arch Linux + Hyprland 0.57.x, **Lua config**: `~/.config/hypr/*.lua`, `hl.config` / `hl.bind` / `hl.window_rule` / `hl.layer_rule`)
- Test machine: Lenovo Yoga Slim 7 14Q8X9, Snapdragon X Elite, Adreno X1-85, aarch64, 2944×1840@90Hz, scale 2
- Desktop shell: MacShell 0.5.1 (Quickshell / QML), lock screen MacLock
- Input method: fcitx5 + WowType (pinyin + offline voice)
- Rules: never change `/usr/share/omarchy/`, only `~/.config` and `~/.local`; run `hyprctl configerrors` after changing the Hyprland config

A general prompt for the AI:

> This is an Omarchy system (Hyprland Lua config). Reproduce module N of `docs/en/00-ai-reproduction.md`, change only the user directories, confirm each step with the verification commands given, and back up original files before changing them.

## Install order

```bash
./scripts/install-macshell-optimizations.sh   # 02: MacShell patch (MacShell 0.5.1 must be installed first)
./scripts/install-silky-gestures.sh           # 03: workspace gesture plugin
./scripts/install-macos-theme.sh              # 04: macOS Tahoe theme
omarchy theme set macos-tahoe-dark
./scripts/install-voice-overlay.sh            # 05: voice overlay
./scripts/install-zsh.sh                      # 06: terminal
./scripts/install-maclock.sh                  # 07: MacLock for every lock
./scripts/install-boot-screen.sh              # 07: macOS-style boot unlock screen
./scripts/install-nautilus-actions.sh         # 08: Nautilus context menu
./scripts/install-wowtype-glass.sh            # 09: WowType candidate skin
./scripts/install-shortcuts.sh                # 10: shortcut clashes + Super+K panel
./scripts/install-menu-glass.sh               # 11: Omarchy menu glass + light/dark
```

01 is a config snippet merged by hand; it has no script.

---

## 01 Touchpad gestures

- **Effect**: natural scrolling; three-finger drag; four-finger horizontal swipe between workspaces, tracking 1:1
- **Files**: `config/hypr/input-touchpad.lua` → `~/.config/hypr/input.lua`; `config/hypr/looknfeel-workspaces.lua` → `looknfeel.lua`
- **Keywords**: `input.touchpad.natural_scroll`, `input.natural_scroll` (mouse), `drag_3fg = 1`, `hl.gesture({ fingers = 4, direction = "horizontal", action = "workspace" })`, `workspace_swipe_create_new = false`, `hl.animation({ leaf = "workspaces", style = "slide" })`
- **Pitfalls**: Omarchy turns the workspaces animation off by default; it must be turned back on for a finger-tracking slide. Three-finger drag and a three-finger switch would fight, so switching uses four fingers
- **Verify**: `hyprctl getoption input:touchpad:natural_scroll`, `hyprctl getoption input:natural_scroll`

## 02 MacShell refinements

- **Effect**: Simplified Chinese; a compact "About This Mac" (correctly identifying Snapdragon / Adreno); dragging windows by touch; live glass on Vulkan; no periodic pointer stutter; wallpaper on the lock screen; battery icon without `%`; no desktop icons; only one screenshot tool
- **Files**: `patches/macshell-0.5.1-silky.patch` (a unified diff against `~/.config/quickshell/{MacShell,MacLock}`), `scripts/install-macshell-optimizations.sh`
- **Keywords**:
  - Rendering: `QSG_RHI_BACKEND=vulkan`, `QSG_RENDER_LOOP=threaded` (in `~/.config/macshell/env`)
  - Stutter: MacShell's "auto contrast" took timed screenshots with `grim`, each stalling Hyprland's main thread for 60–110 ms; made event-driven, with `assets/tone-wall.sh` computing the brightness straight from the wallpaper
  - Touch window drag: Hyprland 0.57 drops `xdg_toplevel.move` without a mouse-button serial; new `TouchWindowMove.qml` moves the window by the finger's offset through Hyprland IPC
  - Lost settings: MacShell writes mouse/touchpad settings temporarily with `hyprctl eval`; they must be re-applied after `configreloaded`
  - Lock wallpaper: MacLock reads `~/.local/state/omarchy/current/background`
  - Theme sync: new IPC `qs -c MacShell ipc call appearance set dark|light`
  - Screenshot clash: Omarchy and MacShell both bound `PRINT` → remove the bind from `macshell.lua`
- **Pitfalls**: MacShell autostarts through `~/.config/hypr/macshell.lua` plus the `-- >>> MacShell (added by install.sh) >>>` block in `hyprland.lua`; losing them means no menu bar or Dock after a reboot and a reversed wheel direction. Regenerate the patch only against pristine 0.5.1 sources
- **Verify**: `./scripts/install-macshell-optimizations.sh --check` shows `patch state: applied`; `pgrep -af '^qs -c MacShell'`; `qs -c MacShell ipc show`

## 03 Workspace gesture plugin

- **Effect**: resistance and rubber-band at the ends of the workspace list; three-finger and single-finger edge swipes between workspaces on the touchscreen; on the touchscreen, drag a floating window's title area to move it, drag edges/corners to resize, or long-press 0.4 s anywhere and drag
- **Files**: `plugins/silky-gestures/main.cpp`, `config/hypr/silky-gestures.lua`, `scripts/install-silky-gestures.sh`
- **Keywords**: Hyprland C++ plugin, `HyprlandAPI`, `pkg-config hyprland`, version-named `~/.local/lib/silky-omarchy/silky-gestures-<version>.so`, `gestures.workspace_swipe_touch = false`; window drags: `Desktop::viewState()->hitTest().windowAt(pos, RESERVED_EXTENTS | INPUT_EXTENTS | ALLOW_FLOATING)`, `g_layoutManager->beginDragTarget(target, MBIND_MOVE / MBIND_RESIZE, corner)`, `moveMouse`, `endDragTarget`, with `Pointer::pointerController()->warpTo` before starting; touches go to the app as usual and are taken over with `g_pSeatManager->sendTouchCancel()` only once it is clearly a window operation (do not hold the down event and replay it: a replayed down and the up in the same `wl_touch.frame` make Electron drop the click)
- **Pitfalls**: for a finger whose down event was held back, its later motion/up must also be held back until it lifts (tracked per finger ID, not via gesture state), otherwise Qt apps crash on unpaired touch points; the plugin must be built against the running Hyprland version, so run the script again after every Hyprland update
- **Verify**: `hyprctl plugin list`

## 04 macOS Tahoe theme

- **Effect**: dark and light Omarchy themes; Apple system colours; 14 px continuous-curvature corners, hairline borders, deep shadows, glass blur; MacTahoe icons (blue folders); Finder-style Nautilus; traffic lights on floating windows; GTK, pointer and MacShell light/dark switch along with the theme
- **Files**: `themes/macos-tahoe-{dark,light}/{colors.toml,hyprland.lua,icons.theme}`, `hooks/theme-set-silky-macos`, `config/hypr/silky-titlebar-guard.lua`, `config/hypr/silky-macos.lua`, `scripts/install-macos-theme.sh`
- **Keywords**:
  - Third party (pinned commits): `vinceliuice/MacTahoe-icon-theme`, `vinceliuice/MacTahoe-gtk-theme` (uses the prebuilt `release/*.tar.xz`, no sassc)
  - libadwaita theme: link `~/.config/gtk-4.0/{gtk.css,gtk-dark.css,assets}` to the theme
  - Traffic lights on the left: `gsettings set org.gnome.desktop.wm.preferences button-layout 'close,maximize:'`
  - Corner curvature: `decoration.rounding = 14`, `rounding_power = 2.6`
  - Theme hook: `~/.config/omarchy/hooks/theme-set.d/`, called with the theme slug
  - Title bars: Omarchy's own `omarchy-hyprland-titlebars` (a hyprbars build, loaded by `workspace-modes.lua` for floating workspaces), options include `button_rounding`, `bar_color_inactive`; buttons can only be added with `add_button`, never removed → before Omarchy's defaults, replace `hl.plugin.hyprbars.add_button` with a no-op to block the square buttons, then add round traffic lights with the original function; allow-list rules `["hyprbars:no_bar"] = true/false`
  - Icons: ChatGPT / Claude use their official icons (MacTahoe's aliases renamed to `*.mactahoe-backup`), corrected optically in the Dock by `dockIconScale()`
- **Pitfalls**: do not build and load upstream hyprbars yourself again; it stacks with Omarchy's (two rows of buttons, square buttons). Unloading a duplicate instance at runtime unregisters the `hyprbars:no_bar` rule name, and only logging in again helps. Write hyprbars rules only when the plugin is loaded, otherwise you get `unknown field`
- **Verify**: `omarchy theme current`, `gsettings get org.gnome.desktop.interface gtk-theme`, `hyprctl plugin list | grep -c hyprbars` should be 1

## 05 WowType voice overlay

- **Effect**: during WowType voice input, a frosted pill at the bottom of the screen: gradient microphone + three coloured waveforms following the voice level + status text
- **Files**: `voice-overlay/bridge.py`, `voice-overlay/shell.qml` → `~/.config/quickshell/SilkyVoice/`; `config/hypr/silky-voice.lua`
- **Keywords**: D-Bus name `io.github.gloridust.WowType.VoiceOverlay`, object `/io/github/gloridust/WowType`, interface `io.github.gloridust.WowType.Voice1`, signal `State(u state, s label, level, x, y, w, h, b relative, d scale)` (every 50 ms), acknowledgement signal `Ack(u)`, level 0–100 maps to -60…-10 dB; Quickshell `PanelWindow` + `WlrLayershell.namespace: "silky-voice"` + `mask: Region {}` (click-through) + `FrameAnimation` + `Canvas` (`globalCompositeOperation = "lighter"`)
- **Pitfalls**: every state shown must be answered with `Ack`, or WowType falls back to the text hint; Omarchy binds Right Alt to "system dictation" (Superwhisper) by default, which fires together with WowType's Right Alt → empty `~/.config/omarchy/defaults/dictation`
- **Verify**: `busctl --user list | grep VoiceOverlay`; preview with `SILKY_VOICE_DEMO=1 qs -c SilkyVoice`; simulate by hand with `gdbus emit --session --object-path /io/github/gloridust/WowType --signal io.github.gloridust.WowType.Voice1.State 1 '' 70.0 0 0 0 0 false 1.0`

## 06 Terminal

- **Effect**: zsh + Oh My Zsh with the ys theme, grey history suggestions, live right/wrong colouring, more completions, still fast to start
- **Files**: `config/zsh/zshrc` → `~/.zshrc`; `scripts/install-zsh.sh`
- **Keywords**: `zsh-users/zsh-autosuggestions`, `zsh-users/zsh-syntax-highlighting` (must be the last plugin), `zsh-users/zsh-completions` (added to `fpath` only, not as a plugin), `zstyle ':omz:update' mode disabled`, `DISABLE_MAGIC_FUNCTIONS`, `ZSH_DISABLE_COMPFIX`, `ZSH_COMPDUMP` in `~/.cache`; ported from Omarchy's bash config: `mise activate zsh`, `zoxide init zsh`, `/usr/share/fzf/key-bindings.zsh`, eza aliases
- **Verify**: `time zsh -i -c exit`

## 07 Lock and boot screens

- **Effect**: every lock uses MacLock; the boot disk-unlock screen matches MacLock's layout (sharp wallpaper, round avatar near the bottom, user name, frosted password field, unit u = screen height / 1200)
- **Files**: `bin/silky-lock`, `bin/silky-sleep-lock`, `config/systemd/silky-sleep-lock.service`, `config/omarchy/plugins/silky.idle/`, `config/hypr/bindings-lock.lua`, `config/omarchy/omarchy-menu-lock.jsonc`, `plymouth/silky-maclock.script`, `scripts/install-maclock.sh`, `scripts/install-boot-screen.sh`
- **Keywords**:
  - Omarchy's four lock entry points: `omarchy-system-lock` (Super+Ctrl+L, menu `system.lock`), the `omarchy.idle` service, `omarchy-sleep-lock.service` (`systemd-inhibit --mode=delay` + `dbus-monitor` watching `PrepareForSleep`)
  - MacLock IPC: `qs -c MacLock ipc call lockscreen lock|state` (`ready` / `busy` / `stopping`), entry script `~/.config/quickshell/MacLock/lock-via-ipc.sh`
  - `omarchy plugin clone omarchy.idle` → change the id to `silky.idle` (the `omarchy.` prefix is reserved for first-party plugins), keep `clonedFrom` so it still reads the `idle` settings in `shell.json`
  - Boot: LUKS + Plymouth (script module: `Plymouth.SetDisplayPasswordFunction`, `Image.Scale`, `Sprite.SetPosition`) + SDDM autologin; `plymouth-set-default-theme`, `limine-mkinitcpio` rebuilds the initramfs
- **Pitfalls**: the sleep-lock service must exit right after locking to release the delay inhibitor, otherwise logind waits for the timeout before sleeping; Plymouth has no Chinese fonts in the initramfs, so text must be pre-rendered as images; on high-DPI screens set `DeviceScale=1` in `plymouthd.conf` and render at native resolution, otherwise Plymouth scales the whole frame 2× and it looks soft; `omarchy-plymouth-set-by-theme` sets the theme back to `omarchy`
- **Verify**: `omarchy plugin list | grep idle`, `systemctl --user is-active silky-sleep-lock`, `plymouth-set-default-theme`
- **Status**: lock screen and boot screen both confirmed on real hardware

## 08 Nautilus context menu

- **Effect**: right-click local files / folders for "Copy Path" (one per line with several selected) and "Open in Terminal", and archives for "Extract Here / Extract to…"
- **Files**: `nautilus/silky_actions.py` → `~/.local/share/nautilus-python/extensions/`
- **Keywords**: `nautilus-python`, `Nautilus.MenuProvider`, `xdg-terminal-exec`
- **Verify**: `nautilus -q`, reopen it, and check the context menu

## 09 WowType candidate window

- **Effect**: rounded frosted candidate window, dark and light skins switching with `color-scheme`; Inter 12; edge-to-edge highlight sharing the panel's 8 px corner; translucent panel (40% / 50%) so the blur shows; no more ghosting in WeChat's candidate bar
- **Files**: `wowtype-glass/build-themes.py` (generates the fcitx5 theme PNGs + theme.conf), `wowtype-glass/silky-ime-theme` + `config/systemd/silky-ime-theme.service`, `config/hypr/silky-ime.lua`
- **Keywords**: fcitx5 classicui `Theme=`, `Font=`, `[InputPanel/ContentMargin]`, `[InputPanel/TextMargin]`, `[InputPanel/Highlight/Margin]` (9-slice border and highlight extent at once); WeChat's bundled fcitx5-qt only understands images / plain colours / margins; Hyprland `decoration.blur.input_methods`, `fadePopups` off against ghosting
- **Pitfalls**: the highlight margin must equal the text margin and the corner radius must fit inside it (`HR <= TM_Y`), or the highlight overflows and its corners are clipped square; the panel corner must be highlight corner + padding (`R = HR + PAD`); WeChat must be restarted to pick up a new skin
- **Verify**: `grep -E '^(Theme|Font)=' ~/.config/fcitx5/conf/classicui.conf`

## 10 Shortcuts

- **Effect**: keys shared by MacShell and Omarchy (Super+Space, Super+V, Alt+Tab, Alt+Shift+Tab, Super+L) trigger only MacShell; Omarchy's actions move to Super+Ctrl+M (menu), Super+Alt+V (universal paste), Super+Shift+L (layout), Alt+` / Alt+Shift+` (window cycling). Super+K is a frosted shortcut panel: groups, ⌘⌥⌃⇧ keycaps, multi-word search, Return to run
- **Files**: `config/hypr/silky-keys-registry.lua` (first in hyprland.lua), `config/hypr/silky-shortcuts.lua` and `config/hypr/silky-keys.lua` (last); `keys-panel/shell.qml` → `~/.config/quickshell/SilkyKeys/`
- **Keywords**: Hyprland runs every bind on a key; wrap `hl.bind` / `hl.unbind` to record dispatchers; `hyprctl dispatch 'function() silky_keys.run(n) end'` (same Lua state as the config); Omarchy's catalog `default/i18n/<lang>/keybindings.json`; `IpcHandler { target: "keys" }`; blur on layer `silky-keys`
- **Pitfalls**: on Hyprland 0.57 Omarchy's keybindings cache holds only ids and cannot run anything; keys injected with `wtype` do not trigger Hyprland binds; `hl.unbind` clears every bind on the key, so silky-shortcuts must come after hypr.macshell; `pkill -f 'qs -c SilkyKeys'` kills the shell running it
- **Verify**: `./scripts/silky-doctor.sh` (clash check + panel running); `qs -c SilkyKeys ipc call keys search 截图`

## 11 Omarchy menu glass

- **Effect**: Omarchy menus such as Super+Esc / Super+Ctrl+M (plus clipboard and emoji) become translucent blurred cards, no dimming behind, accent-filled selection, Inter font; live switching between dark smoky and light frosted glass with `color-scheme`
- **Files**: `bin/silky-menu-glass` (writes a marked block in `~/.config/omarchy/shell.toml`), `config/systemd/silky-menu-glass.service`, `config/hypr/silky-menu-glass.lua` (layer blur + `OMARCHY_MENU_FONT`)
- **Keywords**: the `menu.*` keys of Omarchy's `Commons/Color.qml` (`background-alpha`, `scrim-alpha`, `selected-background`…); the user-level `shell.toml` wins over the theme and has `watchChanges: true`; layers `omarchy-menu` / `omarchy-clipboard` / `omarchy-emojis`; `gsettings monitor org.gnome.desktop.interface color-scheme`
- **Pitfalls**: write the file in place (a rename loses the watch); `ignore_alpha` keeps the transparent full-screen click layer unblurred; the font variable needs `hl.env` and then `omarchy-restart-shell`
- **Verify**: `./scripts/silky-doctor.sh`; `omarchy-menu toggle system`; switch `color-scheme` and watch the menu change

## Miscellaneous

| Need | How |
| --- | --- |
| No screenshot notifications | `o.rebind("PRINT", "Screenshot", "omasnap")` (Omarchy's default passes `--notify`), MacShell setting `screenshotNotify = false` |
| MacShell windows stretched, white edge flash on open | Omarchy's floating-workspace mode enlarges new windows except apps with their own float rule; MacShell windows turned off the Hyprland border with a timer only after creation → `o.window("^(org\\.quickshell)$", { float = true, center = true, border_size = 0 })` (`config/hypr/silky-macshell-windows.lua`), then restart MacShell |
| Two menu bars / two Docks after a crash | Quickshell's crash handler restarts a copy itself + `macshell-start` starts another → `QS_DISABLE_CRASH_HANDLER=1`, `qs -n -c MacShell` |
| Touch-dragging a terminal title bar does nothing / makes it tiled | Omarchy's title-bar plugin only takes touches when the mouse pointer is over that window, and on release after taking over calls `floatWindow(DISABLE)`; silky-gestures handles title-bar drags itself and, after release, restores floating, position and unpins it in `doLater` |
| Debugging touch | Temporarily log `g_pInputManager->m_touchData` (touchFocusWindow / touchFocusLS / consumedTouches) in the plugin, then unload it for an A/B comparison |
| Floating windows dragged under the menu bar | The reserved area only constrains tiled windows; silky-gestures clamps the window top (title bar included) below `m_reservedArea.top()` in `dragController()->m_events.motion/ended` |
| Overall check after any change | `./scripts/silky-doctor.sh` |
| Glass panel edges misaligned with the background | Popup refraction too strong (`thickness × 1.6`, 26 px bevel, edge sampling 50–60 px outside) → `× 0.6` and an 18 px bevel at two places in `MacBar.qml` |
| The built-in Dock shows up | `omarchy plugin disable omarchy.dock` (it comes back after the Omarchy shell restarts) |
| No desktop icons | `desktopIcons = false` in `~/.config/macdock/settings.json` |
| Superwhisper should not autostart | `superwhisper general set launchAtLogin false`, `systemctl --user stop superwhisper` |
| Claude desktop says "Hardware acceleration disabled" | At shutdown/reboot the GPU child process fails to restart (`launch-failed`, `exitCode 1002`, while the Network Service gets SIGTERM), which Claude counts as 3 GPU crashes and turns hardware acceleration off; the kernel log shows no GPU errors. Turn it back on from Claude's Help menu (setting `isHardwareAccelerationDisabled` in `~/.config/Claude/claude_desktop_config.json`) |
| 90 Hz built-in screen | `hl.monitor({ output = "eDP-1", mode = "2944x1840@90", scale = 2 })` |
