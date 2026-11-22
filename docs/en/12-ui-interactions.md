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

The Dock's glass tint used to be pinned to dark: only the right-click menu and hover labels followed the switch. Now the whole Dock glass (tint, edge highlights, launch preview bar) switches with light / dark too; see [02](02-macshell.md).

## Menu bar

- The menu bar follows the foreground app, with History and Bookmarks in supported browsers and Go in Nautilus. [02 · Per-application menu bar](02-macshell.md#per-application-menu-bar)
- Fully in Simplified Chinese; a more compact "About This Mac" ([02](02-macshell.md)), with Edge builds shown as `Edge · commit` plus a faint `MM-DD build` instead of looking like a downgrade ([02](02-macshell.md#edge-version-looking-like-a-downgrade-in-about-this-mac))
- Three monitor buttons, network speed, CPU temperature and battery, with upload above download in the bar, each opening a glass panel: network shows per-app traffic and your IPs (click to copy), temperature shows top processes and a hardware overview, battery shows a system power chart (measurable on battery only) and battery health and lets you set a charge limit ([02 · Menu bar system monitors](02-macshell.md#menu-bar-system-monitors))
- The battery is a narrow macOS 26 pill with only the number inside, no `%`, colored by state: charging green, running on external power the current wallpaper's accent (it follows wallpaper changes), on battery neutral, low (below 20%) red; left-click for battery details, right-click to switch power mode (power saver / balanced / performance), and the right-click panel also has a "Show battery percentage" switch ([02 · Battery icon](02-macshell.md#battery-icon))
- Tray icons are unified as monochrome line icons: Chrome, ChatGPT, Clippy, Netcatty, Remmina, Clash Verge, WeChat; they follow light/dark ([02](02-macshell.md#menu-bar-system-monitors))
- In the notification panel from the bell, notifications stack by app (click to expand; the 3 newest apps show) and scroll together with the widgets below, fading at the edges. The widgets are: weather, stocks, screen time, batteries, calendar, system and AI usage (Claude, Codex, DeepSeek), on the same liquid glass as the Control Center tiles, each small / medium / large, with an accent that follows the wallpaper; the weather card is translucent glass too. Right-click a widget to change its size, set the weather city, add, remove and drag-reorder stock symbols from any market (names work too), or paste a DeepSeek API key. In "Edit Widgets", click to change size, drag to reorder, "−" to remove, and add new ones from the gallery below ([02 · Notification Center widgets](02-macshell.md#notification-center-widgets))
- Auto contrast is event-driven: brightness is measured again only when windows appear, close or move, and when only the wallpaper is behind the bar it reads the wallpaper file instead of taking a screenshot; the pause when opening the Control Center went from about 76 ms to about 19 ms ([02](02-macshell.md#stutter-when-opening-menus-and-the-control-center))
- Floating windows cannot be dragged under the menu bar ([03](03-silky-gestures.md#floating-windows-cannot-be-dragged-under-the-menu-bar))

## Control Center

- Control Center defaults to macOS 26/27-style frameless floating Liquid Glass bubbles (full-capsule tiles, circular toggles, crisp edge refraction, and 360° specular rim glints) following system light/dark appearance, while still letting you switch back to a grouped frosted slab in Settings ([02 · Control Center](02-macshell.md#control-center))
- A new "Display" page: brightness slider, Night Shift switch and light/dark Appearance switch, working like the "Sound" page ([02 · Control Center](02-macshell.md#control-center))
- Dragging a volume slider (Control Center, the menu-bar volume popover, scrolling on the menu bar) plays a tap at the level being set, and one more where you let go. Turning off UI sounds silences it
- The Sound page shows a live microphone level under the input slider: a few segments in a quiet room, jumping when you speak, red when close to clipping. It listens only while that page is open and the mic is not muted

## Dock and Applications panel

- After Omarchy switches to Folio, the MacShell update migrates the old Nautilus pin to Folio. [02 · Files fails to open from the Dock](02-macshell.md#files-fails-to-open-from-the-dock)

- MacShell has a violet glass Dock icon with a silver-lavender M ([02 · Dock](02-macshell.md#dock-icons-and-the-settings-window))
- The menu bar, Control Center, Notification Center, Applications panel and Dock use Hyprland blur: the glass follows dragged windows in the same frame, with a light Liquid-Glass-like tint and top sheen in both light and dark mode, and the menu bar is almost fully clear; About This Mac's "More Info…" button is quieter ([02](02-macshell.md#hyprland-blur-instead-of-liquid-glass-normal-blur))
- (Optional) A Hyprland plugin draws macOS 26/27 optical Liquid Glass (convex bevel refraction, subtle dispersion, and 360° dual-diagonal specular rims, following dragged windows in the same frame) for the Dock, all menu bar popovers (Apple/app menus, Wi-Fi, Bluetooth, Volume, Battery/Status, floating Control Center bubbles, Notification Center and toasts), and other MacShell overlays (Spotlight, Applications, Switcher, Wallpaper Picker, OSD); the thin top menu bar strip (`macbarbg`) stays on native blur ([02](02-macshell.md#liquid-glass-dock-plugin-prototype))
- Only MacShell's Dock; Omarchy's own Dock is turned off for good ([02](02-macshell.md#only-macshells-dock))
- Optical icon scaling is centred, so icons no longer drift to one side when magnified ([02 · Dock](02-macshell.md#dock-icons-and-the-settings-window))
- After you click a Dock icon, its name label waits until the pointer moves 4 px before showing again (as on macOS), so repeated clicks no longer stall for 60–70 ms ([02](02-macshell.md#applications-panel-interaction))
- Applications panel (Launchpad): 320 px per wheel notch, smooth deceleration after a touchpad / touchscreen flick; on open the whole panel scales from 114% to 100% and goes from blurred to sharp; it is warmed up beforehand so the first open no longer stalls for about 200 ms; repeated clicks on the Applications icon reverse the spring directly ([02](02-macshell.md#applications-panel-interaction))
- Right-click Files in the Dock for shortcuts to Home, Desktop, Documents, Downloads, and Pictures. [02 · Common folders in the Files context menu](02-macshell.md#common-folders-in-the-files-context-menu)
- Folio's yellow button folds the window into a thumbnail between the Dock separator and Trash with a GPU-driven animation that takes over in place and preserves window brightness. Click the thumbnail to restore it. The Dock smoothly makes room and closes the gap ([02](02-macshell.md#window-minimizing))
- "罗技鼠标" (Omalogi) is in the Applications panel and Spotlight with a bright blue tile matching MacTahoe; while running, the Dock shows its own icon ([14](14-omalogi.md#launcher-entry-and-icon))

## Glass and smoothness

- Vulkan live glass; menus and the Control Center capture only while visible and only windows that intersect the glass, and slow down when windows are still ([02](02-macshell.md#default-glass-settings))
- When window focus changes (the stacking order of floating windows changes), the glass backdrop refreshes; title changes do not wake the refresh ([02 · Glass](02-macshell.md#glass-refreshes-when-focus-changes))
- Fixed the misaligned dark band at the edges of popup panels (weaker refraction, narrower bevel) ([02](02-macshell.md#misaligned-glass-panel-edges))
- Removed the periodic pointer stutter; 90 Hz built-in screen ([02](02-macshell.md#periodic-pointer-stutter))
- Floating windows can reuse a blurred desktop backdrop to keep up with the 90 Hz panel while being dragged over other windows ([02](02-macshell.md#window-dragging-at-90-hz))
- No more two menu bars / two Docks after a crash; the menu bar, Dock and wheel direction survive a reboot ([02](02-macshell.md))
- Window animations, the menu bar, the Dock and the pointer stay smooth while background programs max out the CPU: Hyprland, MacShell and the input method are scheduled first, and on AC the GPU no longer starts from its lowest clock ([16](16-desktop-priority.md))

## Windows

- Calculator, Omacut, Write, and Media Viewer use the shared traffic lights and size-aware half-screen and corner layouts. WeChat and the PuTTY console render working content at full opacity. [System app window updates](04-macos-theme.md#system-app-audit)
- Silk-drawn title bars on floating windows have round traffic lights and translucent backgrounds ([04](04-macos-theme.md#traffic-light-title-bar))
- MacShell's own windows (Settings, About This Mac) keep their size, are centred, and open without a white flash at the edges ([02](02-macshell.md))
- New windows open directly, Firefox and other GTK3 CSD windows align cleanly from frame 0 without flashing a blurred halo or offset border, and the About panel blurs the actual windows behind it. See [Window opening and live blur](02-macshell.md#window-opening-flashes-and-live-about-blur).
- The Settings window's navigation list: 140 px smooth scrolling per wheel notch, native inertia on the touchpad ([02 · Settings window](02-macshell.md#dock-icons-and-the-settings-window))
- Use `Super+T` for split tiling on the current workspace. Use `Super+Alt+T` for single-window tiling and press it again to return to floating and bring back the displaced windows. ([10 · Super+T](10-shortcuts.md#supert))
- Switching back to floating with either shortcut keeps the window’s top edge below the menu bar. ([10 · Super+T](10-shortcuts.md#supert))
- Pictures and videos opened in WeChat always appear in a centred floating viewer at a moderate 900×620 size instead of reaching into the menu bar; the chat-history window is narrowed and centred too (height stays at WeChat's own 720 minimum). ([10](10-shortcuts.md#wechats-image-viewer-and-chat-history-window-sizes))
- WeChat no longer steals focus or pops above other floating windows in the background on incoming messages. ([10](10-shortcuts.md#stop-wechat-from-stealing-focus-in-the-background))
- The Logitech mouse editor (Omalogi) is a normal window: centred floating 1280×700 (clear of the Dock), tiles / goes full screen, shows in Alt+Tab, and no longer stays on top across workspaces; opening it again only focuses it; with wired and wireless mice both connected, switch between them at the top right ([14 · A real window](14-omalogi.md#a-real-window))
- Remmina remote desktop shows Simplified Chinese, and its solid connection list and frosted header follow light / dark live. The connection toolbar moves to the top with traffic lights and the connection name, drags the window from empty title space, thin line icons and plain tooltips, rarely used actions in `⋯`, and no tab bar for a single session. The main list selects rows with a rounded accent pill. The remote Windows screen shows 1:1 and sharp on HiDPI at 150% by default, instead of an oversized, blurry 200% ([HiDPI scaling](04-macos-theme.md#remmina-hidpi)). See [Remmina in Simplified Chinese with a macOS look](04-macos-theme.md#remmina).
- Omalogi uses a solid editor background and shared window controls. [Omalogi window](14-omalogi.md#a-real-window)

## Gestures (touchpad / touchscreen)

- WeChat’s main window lets less wallpaper show through, and dragging the conversation list on the touchscreen produces continuous scrolling ([01](01-touchpad-gestures.md#touchscreen-scrolling-in-wechats-conversation-list))

- Touchpad: natural scrolling (mouse too), three-finger drag, four-finger horizontal swipe between workspaces with smoother transitions ([01](01-touchpad-gestures.md))
- Touchscreen: three-finger and single-finger edge swipes between workspaces with rubber-band at the ends; touch drag and two-finger resize of floating windows; dragging terminal title bars ([03](03-silky-gestures.md))
- Four- / five-finger pinch recognition; rapid repeated clicks are not lost ([03](03-silky-gestures.md))
- Touchpad or touch screen four fingers up: every window of the workspace; four fingers down: every window of the current app. Linear and follows the fingers, finishes at a constant speed after release, can be grabbed again mid-way to interrupt or reverse; click or tap a window to switch to it ([13](13-window-overview.md))
- The four-finger swipe-up overview shows clickable workspace previews over the undimmed wallpaper. Clicking a preview slides the windows sideways, and a four-finger horizontal swipe moves the windows with your fingers ([13](13-window-overview.md#workspace-previews-and-navigation)).

## Keyboard and shortcuts

- Keys MacShell and Omarchy both used go to MacShell only (Super+Space Spotlight, Super+V clipboard history, Alt+Tab app switcher, Alt+Shift+Tab backwards, Super+L lock), and Omarchy's actions move to free keys ([10](10-shortcuts.md#keys-after-the-change))
- Super+K: a searchable macOS 27-style shortcut panel with groups and ⌘⌥⌃⇧ keycaps; Return runs the shortcut ([10](10-shortcuts.md))
- Screenshots (PrtSc) capture once and post no notification; a floating preview at the bottom right can be dragged out or annotated ([02](02-macshell.md#no-more-screenshot-notifications))
- Right-click exits the capture picker. The redaction controls open inside the toolbar and close after a choice. Blur uses smooth frosted transitions ([02](02-macshell.md#redaction-levels-and-right-click-cancellation))
- Standalone screenshot pins preserve the full image and support dragging, zoom, opacity, and a glass context menu that follows system appearance ([02](02-macshell.md#standalone-screenshot-pins))

## Menus and popups

- Omarchy's own menus become translucent blurred cards: no screen dimming, accent-filled selection, Inter font, live light/dark switching ([11](11-menu-glass.md))

## Input method

- WowType candidate window: rounded frosted skin, Inter 12, an edge-to-edge highlight that shares the panel's 8 px corner, a translucent panel the blur shows through, and the two corners coincide when the first candidate is selected; fixed the ghosting candidate bar in WeChat; in WeChat the pinyin now sits on the bar's first line, so the bar no longer blinks while you type ([09](09-wowtype-glass.md#wechats-candidate-bar-blinks-while-typing))
- WowType and vinput voice input: vinput's live transcript and sound-reactive waveform share one frosted pill ([05](05-voice-overlay.md))

## Lock and boot

- Shortcuts, menus, idle and lid close all lock with MacLock ([07](07-lock-and-boot.md))
- The boot disk-unlock screen looks like macOS FileVault ([07](07-lock-and-boot.md#boot-screen))

## File manager and terminal

- Folio uses the Finder icon and a compact toolbar. Dock launches continue to use the installed customization after a reboot and packaged Folio updates. Its sidebar is frosted and the file area and path bar are solid. The green button uses a plus to enter full screen and inward diagonal marks to exit, like `Super+F`. Right-click or hold it for half-screen and quarter-screen layouts. The yellow button is disabled in full screen. Drag to either screen edge to preview and snap to a half or quarter. In column view, selecting and expanding a subfolder updates the top path bar, path editor, and copy button to include that subfolder. Click or tap the path area to edit it and click or tap empty file space to cancel. Drag the path area to move the window. Use the adjacent copy button to copy the full path. Swipe with one finger to scroll the file area. In column view, tap with one finger to left-click, or touch and hold or tap with two fingers to open the context menu. Right-click Trash in the sidebar for the centered Empty action. See [04 · Finder-style Folio](04-macos-theme.md#finder-style-folio).

- Floating Folio windows appear immediately on the first frame without flashing an empty blurred box, and keep clean frosted sidebar corners over high-contrast backgrounds. See [Finder-style Folio](04-macos-theme.md#finder-style-folio).
- Files and Foot match the size of their traffic lights, the paths and stroke width of their hover symbols, and their inward-diagonal exit mark. See [Tahoe appearance for Foot](04-macos-theme.md#foot-glass).
- Foot has a solid reading surface and light/dark palettes. Its floating windows use the Files-style green-button layout menu and edge previews for halves and corners. See [Tahoe appearance for Foot](04-macos-theme.md#foot-glass).
- With a macOS Tahoe theme active, the Nautilus sidebar picks up blurred background colors while the file area keeps text and icons crisp. See [Frosted glass in Files](04-macos-theme.md#frosted-glass-in-files).
- Nautilus looks like Finder, with Space for Quick Look ([04](04-macos-theme.md)); its context menu has "Copy Path", "Open in Terminal" and "Extract Here" ([08](08-nautilus-actions.md))
- The optional Simplified Chinese setup localizes menus, dates and common sidebar bookmarks. See [Simplified Chinese interface](08-nautilus-actions.md#simplified-chinese-interface).
- Right-click a single image in Nautilus and choose Set as Background to preview and apply it to the Omarchy desktop. See [Set the desktop background](08-nautilus-actions.md#set-the-desktop-background).
- The terminal runs zsh + Oh My Zsh: history suggestions, syntax highlighting, richer completion ([06](06-terminal.md))

## Obsidian notes

- Obsidian gets a macOS 27 look: menus, the command palette and modals are glass, and the sidebars are floating rounded glass panels. Folders are Finder blue folders, each extension has its own icon, and code blocks are Terminal windows with red / yellow / green dots. The caret glides and new characters fade in, including Pinyin commits. See [15 · Obsidian](15-obsidian.md).
- Obsidian's window buttons sit in the top-left corner like the title bars of Sublime and other apps: red closes, the middle one is grey (there is no minimise), and green toggles Full width, the same as `Super+Alt+F`; click again to restore. See [15 · Obsidian](15-obsidian.md#what-it-does).
- Clicking Obsidian in the Dock switches to the window that is already open, with a running dot under the icon, instead of bouncing forever. See [15 · Obsidian](15-obsidian.md#implementation).

## Check that everything is still in place

After upgrading Omarchy or MacShell, run the self-check; it reports on each of the modules above (shortcut clashes, menu glass, the Super+K panel, lock screen, voice overlay, gesture plugin and more):

```bash
./scripts/silky-doctor.sh
```
