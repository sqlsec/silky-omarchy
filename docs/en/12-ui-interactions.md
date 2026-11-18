# 12 · UI interaction overview

[简体中文](../12-ui-interactions.md) | English

The interface and interaction work done on this Omarchy + MacShell desktop, grouped by where you feel it. Each line only states the effect; details, how it works and how to roll it back are in the linked documents.

Overall principles: **look and behave like macOS** (glass materials, monochrome icons, synced light/dark, macOS shortcut habits), **no stutter** (capture on demand, event-driven, warm-up), **no conflicts** (one key, one function, one entry point).

## Dark / light: the whole desktop switches together

The signal is `org.gnome.desktop.interface color-scheme`. Both MacShell's Appearance setting (including Auto: light by day, dark at night) and `omarchy theme set macos-tahoe-light/dark` write it, and all of these follow:

| What follows | Document |
| --- | --- |
| MacShell menu bar, Dock, Spotlight, Control Center | [02](02-macshell.md) |
| GTK / libadwaita apps (Finder-style Nautilus), pointer, MacTahoe icons | [04](04-macos-theme.md) |
| Omarchy's own menus (Super+Esc, Super+Ctrl+M, clipboard, emoji) | [11](11-menu-glass.md) |
| WowType candidate skin (including WeChat's candidate bar) | [09](09-wowtype-glass.md) |
| The Super+K shortcut panel | [10](10-shortcuts.md) |
| Obsidian notes (theme set to "Adapt to system") | [15](15-obsidian.md) |

The Control Center's new "Display" page has an Appearance switch, so you can switch right there.

## Menu bar

- Fully in Simplified Chinese; a more compact "About This Mac" ([02](02-macshell.md))
- Three monitor buttons, network speed, CPU temperature and battery, each opening a glass panel: network shows per-app traffic and your IPs (click to copy), temperature shows top processes and a hardware overview, battery shows a system power chart (measurable on battery only) and battery health and lets you set a charge limit ([02 · Menu bar system monitors](02-macshell.md#menu-bar-system-monitors))
- The battery is a narrow macOS 26 pill with only the number inside, no `%`, colored by state: charging green, running on external power blue, on battery neutral, low (below 20%) red; left-click for battery details, right-click to switch power mode (power saver / balanced / performance), and the right-click panel also has a "Show battery percentage" switch ([02 · Battery icon](02-macshell.md#battery-icon))
- Tray icons are unified as monochrome line icons: Chrome, ChatGPT, Clippy, Netcatty, Remmina, Clash Verge, WeChat; they follow light/dark ([02](02-macshell.md#menu-bar-system-monitors))
- Auto contrast is event-driven: brightness is measured again only when windows appear, close or move, and when only the wallpaper is behind the bar it reads the wallpaper file instead of taking a screenshot; the pause when opening the Control Center went from about 76 ms to about 19 ms ([02](02-macshell.md#stutter-when-opening-menus-and-the-control-center))
- Floating windows cannot be dragged under the menu bar ([03](03-silky-gestures.md#floating-windows-cannot-be-dragged-under-the-menu-bar))

## Control Center

- The grouped Control Center uses the same glass material as the menu-bar dropdowns, and is light in the light appearance (MacShell 0.5.2 forced it dark) ([02 · Control Center](02-macshell.md#control-center))
- A new "Display" page: brightness slider, Night Shift switch and light/dark Appearance switch, working like the "Sound" page ([02 · Control Center](02-macshell.md#control-center))
- Dragging a volume slider (Control Center, the menu-bar volume popover, scrolling on the menu bar) plays a tap at the level being set, and one more where you let go. Turning off UI sounds silences it
- The Sound page shows a live microphone level under the input slider: a few segments in a quiet room, jumping when you speak, red when close to clipping. It listens only while that page is open and the mic is not muted

## Dock and Applications panel

- Only MacShell's Dock; Omarchy's own Dock is turned off for good ([02](02-macshell.md#only-macshells-dock))
- Optical icon scaling is centred, so icons no longer drift to one side when magnified ([02 · Dock](02-macshell.md#dock-icons-and-the-settings-window))
- After you click a Dock icon, its name label waits until the pointer moves 4 px before showing again (as on macOS), so repeated clicks no longer stall for 60–70 ms ([02](02-macshell.md#applications-panel-interaction))
- Applications panel (Launchpad): 320 px per wheel notch, smooth deceleration after a touchpad / touchscreen flick; on open the whole panel scales from 114% to 100% and goes from blurred to sharp; it is warmed up beforehand so the first open no longer stalls for about 200 ms; repeated clicks on the Applications icon reverse the spring directly ([02](02-macshell.md#applications-panel-interaction))
- No window-minimize entry points (title bars keep only close and maximize); windows that were already minimized can still be restored from the Dock ([02](02-macshell.md#window-minimizing))
- "罗技鼠标" (Omalogi) is in the Applications panel and Spotlight with a bright blue tile matching MacTahoe; while running, the Dock shows its own icon ([14](14-omalogi.md#launcher-entry-and-icon))

## Glass and smoothness

- Vulkan live glass; menus and the Control Center capture only while visible and only windows that intersect the glass, and slow down when windows are still ([02](02-macshell.md#default-glass-settings))
- When window focus changes (the stacking order of floating windows changes), the glass backdrop refreshes; title changes do not wake the refresh ([02 · Glass](02-macshell.md#glass-refreshes-when-focus-changes))
- Fixed the misaligned dark band at the edges of popup panels (weaker refraction, narrower bevel) ([02](02-macshell.md#misaligned-glass-panel-edges))
- Removed the periodic pointer stutter; 90 Hz built-in screen ([02](02-macshell.md#periodic-pointer-stutter))
- No more two menu bars / two Docks after a crash; the menu bar, Dock and wheel direction survive a reboot ([02](02-macshell.md))

## Windows

- Floating windows get a macOS round traffic-light title bar ([04](04-macos-theme.md#traffic-light-title-bar))
- MacShell's own windows (Settings, About This Mac) keep their size, are centred, and open without a white flash at the edges ([02](02-macshell.md))
- The Settings window's navigation list: 140 px smooth scrolling per wheel notch, native inertia on the touchpad ([02 · Settings window](02-macshell.md#dock-icons-and-the-settings-window))
- Use `Super+T` for split tiling on the current workspace. Use `Super+Alt+T` for single-window tiling and press it again to return to floating and bring back the displaced windows. ([10 · Super+T](10-shortcuts.md#supert))
- Switching back to floating with either shortcut keeps the window’s top edge below the menu bar. ([10 · Super+T](10-shortcuts.md#supert))
- The Logitech mouse editor (Omalogi) is a normal window: centred floating 1280×700 (clear of the Dock), tiles / goes full screen, shows in Alt+Tab, and no longer stays on top across workspaces; opening it again only focuses it; with wired and wireless mice both connected, switch between them at the top right ([14 · A real window](14-omalogi.md#a-real-window))

## Gestures (touchpad / touchscreen)

- Touchpad: natural scrolling (mouse too), three-finger drag, four-finger horizontal swipe between workspaces with smoother transitions ([01](01-touchpad-gestures.md))
- Touchscreen: three-finger and single-finger edge swipes between workspaces with rubber-band at the ends; touch drag and two-finger resize of floating windows; dragging terminal title bars ([03](03-silky-gestures.md))
- Four- / five-finger pinch recognition; rapid repeated clicks are not lost ([03](03-silky-gestures.md))
- Touchpad or touch screen four fingers up: every window of the workspace; four fingers down: every window of the current app. Linear and follows the fingers, finishes at a constant speed after release, can be grabbed again mid-way to interrupt or reverse; click or tap a window to switch to it ([13](13-window-overview.md))

## Keyboard and shortcuts

- Keys MacShell and Omarchy both used go to MacShell only (Super+Space Spotlight, Super+V clipboard history, Alt+Tab app switcher, Alt+Shift+Tab backwards, Super+L lock), and Omarchy's actions move to free keys ([10](10-shortcuts.md#keys-after-the-change))
- Super+K: a searchable macOS 27-style shortcut panel with groups and ⌘⌥⌃⇧ keycaps; Return runs the shortcut ([10](10-shortcuts.md))
- Screenshots (PrtSc) capture once and post no notification; a floating preview at the bottom right can be dragged out or annotated ([02](02-macshell.md#no-more-screenshot-notifications))

## Menus and popups

- Omarchy's own menus become translucent blurred cards: no screen dimming, accent-filled selection, Inter font, live light/dark switching ([11](11-menu-glass.md))

## Input method

- WowType candidate window: rounded frosted skin, Inter 12, an edge-to-edge highlight that shares the panel's 8 px corner, a translucent panel the blur shows through, and the two corners coincide when the first candidate is selected; fixed the ghosting candidate bar in WeChat; in WeChat the pinyin now sits on the bar's first line, so the bar no longer blinks while you type ([09](09-wowtype-glass.md#wechats-candidate-bar-blinks-while-typing))
- WowType voice input: a frosted waveform pill at the bottom of the screen that follows your voice level ([05](05-voice-overlay.md))

## Lock and boot

- Shortcuts, menus, idle and lid close all lock with MacLock ([07](07-lock-and-boot.md))
- The boot disk-unlock screen looks like macOS FileVault ([07](07-lock-and-boot.md#boot-screen))

## File manager and terminal

- Nautilus looks like Finder, with Space for Quick Look ([04](04-macos-theme.md)); its context menu has "Copy Path", "Open in Terminal" and "Extract Here" ([08](08-nautilus-actions.md))
- The optional Simplified Chinese setup localizes menus, dates and common sidebar bookmarks. See [Simplified Chinese interface](08-nautilus-actions.md#simplified-chinese-interface).
- Right-click a single image in Nautilus and choose Set as Background to preview and apply it to the Omarchy desktop. See [Set the desktop background](08-nautilus-actions.md#set-the-desktop-background).
- The terminal runs zsh + Oh My Zsh: history suggestions, syntax highlighting, richer completion ([06](06-terminal.md))

## Obsidian notes

- Obsidian gets a macOS 27 look: menus, the command palette and modals are glass, and the sidebars are floating rounded glass panels. Folders are Finder blue folders, each extension has its own icon, and code blocks are Terminal windows with red / yellow / green dots. The caret glides and new characters fade in, including Pinyin commits. See [15 · Obsidian](15-obsidian.md).
- Obsidian's close, minimise and zoom buttons sit in the top-left corner as traffic lights, as on macOS, with glyphs on hover. See [15 · Obsidian](15-obsidian.md#what-it-does).
- Clicking Obsidian in the Dock switches to the window that is already open, with a running dot under the icon, instead of bouncing forever. See [15 · Obsidian](15-obsidian.md#implementation).

## Check that everything is still in place

After upgrading Omarchy or MacShell, run the self-check; it reports on each of the modules above (shortcut clashes, menu glass, the Super+K panel, lock screen, voice overlay, gesture plugin and more):

```bash
./scripts/silky-doctor.sh
```
