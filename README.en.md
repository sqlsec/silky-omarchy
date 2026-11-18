# Silky Omarchy

[简体中文](README.md) | English

A set of macOS-inspired refinements for [Omarchy](https://omarchy.org/) Linux. Every item documents its design, configuration, how to verify it and how to roll it back, and comes with a one-step install script.

> Want an AI coding assistant to reproduce it? Hand it [docs/en/00-ai-reproduction.md](docs/en/00-ai-reproduction.md): it lists, module by module, the effect, key files, search keywords, pitfalls and verification commands.

## What's included

To see every interface and interaction change grouped by where you feel it (menu bar, Control Center, Dock, glass, gestures, shortcuts, input method, light/dark sync…), read [12 · UI interaction overview](docs/en/12-ui-interactions.md).

| # | Module | Status | What it does |
| --- | --- | --- | --- |
| 01 | Touchpad | ✅ | Natural scrolling (touchpad and mouse), three-finger drag, four-finger swipe between workspaces (four fingers up / down: see 13) |
| 02 | MacShell | ✅ | Simplified Chinese, compact "About This Mac", Vulkan live glass, stutter fixes, network / temperature / battery panels, monochrome tray icons, battery pill with a percentage switch, Control Center "Display" page, Dock and Applications panel animations, screenshots without duplicates or notifications, lock-screen wallpaper, autostart fixes |
| 03 | Touchscreen gestures | ✅ | Rubber-band at the ends, three-finger and edge swipes on the touchscreen, touch drag / pinch-resize of floating windows (Hyprland plugin) |
| 04 | macOS Tahoe theme | ✅ | Dark / light themes, Apple system colors, rounded shadowed glass, MacTahoe blue folder icons, Finder-style Nautilus, theme sync, round traffic lights on floating windows |
| 05 | Voice overlay | ✅ | Frosted waveform pill for WowType voice input; fixes the Right Alt clash with Superwhisper |
| 06 | Terminal | ✅ | zsh + Oh My Zsh (ys), history suggestions, syntax highlighting, richer completion, still fast to start |
| 07 | Lock and boot screens | ✅ | Shortcuts, menus, idle and lid close all use MacLock; the boot disk-unlock screen looks like macOS FileVault |
| 08 | File manager context menu | ✅ | Nautilus right-click "Copy Path", "Open in Terminal", "Extract Here / Extract to…" |
| 09 | Frosted candidate window | ✅ | Rounded frosted WowType candidate skin that follows dark/light mode; fixes the ghosting candidate bar in WeChat |
| 10 | Shortcuts | ✅ | Keys MacShell and Omarchy both use go to MacShell only, Omarchy's actions move to free keys; Super+K becomes a searchable macOS 27-style shortcut panel that runs what you pick. `Super+T` splits windows on the current workspace, and `Super+Alt+T` toggles single-window tiling with window restoration |
| 11 | Menu glass | ✅ | Omarchy's own menus (Super+Esc, Super+Ctrl+M, clipboard, emoji) become macOS 27 frosted glass that switches light / dark live |
| 13 | Window overview | ✅ | Four fingers up on the touchpad or touch screen shows every window of the workspace, four fingers down every window of the current app; linear, follows the fingers, interruptible and reversible (plugin + MacShell component) |
| 14 | [Logitech mouse](docs/en/14-omalogi.md) | ✅ | Standalone Omalogi window with a Chinese UI, G604 button diagrams, onboard profiles, a manual key picker, Super+K system shortcuts, and an ARM source build |
| 15 | [Obsidian](docs/en/15-obsidian.md) | ✅ | macOS 27 theme: glass menus and floating sidebars, follows light / dark, Finder blue folders and per-extension file icons, gliding caret and typing fade-in (input methods included), Terminal-window code blocks |

## Quick start

Requirements: Omarchy 4.x (Hyprland 0.57, Lua config) and MacShell.

| Component | Version currently tested | Notes |
| --- | --- | --- |
| Omarchy | 4.5.0 | Any 4.x with the Lua config |
| Hyprland | 0.57.2 | The plugin must be built for the running version; re-run `install-silky-gestures.sh` after updates |
| MacShell | 0.5.2 | Module 02 supports fresh and already patched **0.5.2** installations (see [02 · Versions](docs/en/02-macshell.md#versions)) |
| Quickshell / Qt | 0.3.2 / 6.12 | |
| libinput | 1.32.0 | The 03 pinch patch targets 1.32.0 |

Run what you need:

```bash
./scripts/install-macshell-optimizations.sh
./scripts/install-silky-gestures.sh
python3 scripts/install-macshell-overview.py
./scripts/install-macos-theme.sh && omarchy theme set macos-tahoe-dark
./scripts/install-voice-overlay.sh
./scripts/install-zsh.sh
./scripts/install-maclock.sh
./scripts/install-boot-screen.sh
./scripts/install-nautilus-actions.sh
./scripts/install-wowtype-glass.sh
./scripts/install-shortcuts.sh
./scripts/install-menu-glass.sh
./scripts/install-omalogi.sh
./scripts/install-obsidian-theme.sh
```

Every script backs up the files it changes first. After installing or upgrading, run the self-check: it confirms item by item that the menu bar, Dock, plugins, lock screen, voice overlay and so on are in the expected state, and prints the fix for anything that is not:

```bash
./scripts/silky-doctor.sh
```

01 Touchpad is a config snippet you merge by hand; see its document.

## Repository layout

```text
config/hypr/      Hyprland Lua snippets (touchpad, animations, monitors, screenshot key, plugin loading, voice overlay, shortcuts)
config/macshell/  MacShell glass settings, GPU environment variables, window overview component
config/zsh/       ~/.zshrc
config/obsidian/  Obsidian theme Silky macOS, typing-fade plugin silky-typing, icon generator
patches/          Patches for MacShell 0.5.1 / 0.5.2, MacLock and the Omalogi translation
plugins/          Hyprland C++ plugin silky-gestures
themes/           Omarchy themes macos-tahoe-dark / macos-tahoe-light
hooks/            Omarchy theme-set hook
bin/              silky-lock, silky-sleep-lock (MacLock entry points), silky-menu-glass
config/omarchy/   Omarchy shell plugin silky.idle and menu overrides
config/systemd/   User services silky-sleep-lock, silky-ime-theme, silky-menu-glass
plymouth/         Boot unlock theme and preview image
voice-overlay/    WowType voice overlay (Quickshell + D-Bus bridge)
keys-panel/       Super+K shortcut panel Silky Keys (Quickshell)
omalogi-app/      Logitech mouse window (the Omalogi plugin with its own app id)
nautilus/         Nautilus context-menu extension (nautilus-python)
wowtype-glass/    WowType Silky Glass candidate skin generator and light/dark switcher
scripts/          Install scripts
docs/             One document per module (English in docs/en/)
```

## Principles

- Only user configuration is changed (`~/.config`, `~/.local`), never `/usr/share/omarchy/` directly
- Every item ships with configuration, verification steps and rollback notes, and backs files up before changing them
- Third-party dependencies are pinned to specific commits, so results are reproducible
- Prefer what Omarchy and Hyprland already provide; keep extra daemons to a minimum

## Documentation

- [00 · Reproduction index for AI coding assistants](docs/en/00-ai-reproduction.md)
- [01 · Touchpad gestures](docs/en/01-touchpad-gestures.md)
- [02 · MacShell: localization, live glass and GPU tuning](docs/en/02-macshell.md)
- [03 · Touchscreen workspace gestures and rubber-band](docs/en/03-silky-gestures.md)
- [04 · macOS Tahoe theme (dark / light)](docs/en/04-macos-theme.md)
- [05 · Waveform overlay for WowType voice input](docs/en/05-voice-overlay.md)
- [06 · Terminal: zsh + Oh My Zsh](docs/en/06-terminal.md)
- [07 · MacLock everywhere and a macOS-style boot screen](docs/en/07-lock-and-boot.md)
- [08 · File manager context menu](docs/en/08-nautilus-actions.md)
- [09 · WowType candidate window: rounded frosted glass and the WeChat ghosting fix](docs/en/09-wowtype-glass.md)
- [10 · Shortcuts: MacShell first, searchable Super+K panel](docs/en/10-shortcuts.md)
- [11 · Omarchy's own menus: macOS 27 glass, light / dark](docs/en/11-menu-glass.md)
- [12 · UI interaction overview](docs/en/12-ui-interactions.md)
- [13 · Four fingers up / down: window overview](docs/en/13-window-overview.md)
- [14 · Omalogi: G604 buttons, onboard profiles, and system shortcuts](docs/en/14-omalogi.md)
- [15 · Obsidian: macOS 27 theme, file icons and smooth typing](docs/en/15-obsidian.md)
