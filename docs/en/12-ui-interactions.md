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

Dock app context menus share the Dock’s Liquid Glass, including its refraction, blur, and edge highlights. [02 · Liquid Glass on Dock context menus](02-macshell.md#liquid-glass-on-dock-context-menus)

## Menu bar

- Repeated clicks on the system menu reverse its opening or closing animation, with text and glass moving together. [02 · Rapidly toggling the system menu](02-macshell.md#rapidly-toggling-the-system-menu)
- Restart, Shut Down, and Log Out in the top-left system menu take effect on the first click. [02 · System menu](02-macshell.md#rapidly-toggling-the-system-menu)
- The launcher restarts MacShell after three consecutive missed response checks. [02 · The Dock and menu bar stop responding together](02-macshell.md#the-dock-and-menu-bar-stop-responding-together)
- The menu bar follows the foreground app, with History and Bookmarks in supported browsers and Go in Nautilus. [02 · Per-application menu bar](02-macshell.md#per-application-menu-bar)
- Occupied inactive workspaces in the menu bar show a 3 px dot underneath and a brighter digit; the active workspace is marked by its pill alone, without a dot. The layout icon beside the numbers is now as clear as the digits. [02 · Occupied workspace indicators in the menu bar](02-macshell.md#occupied-workspace-indicators-in-the-menu-bar)
- About Omarchy Linux uses the system menu's frosted backdrop and keeps its borderless outline. [02 · About window outline](02-macshell.md#about-window-outline)
- The About Omarchy Linux blur follows the window during four-finger workspace swipes. [02 · About window blur during workspace swipes](02-macshell.md#about-window-blur-during-workspace-swipes)
- Fully in Simplified Chinese; a more compact "About This Mac" ([02](02-macshell.md)), with Edge builds shown as `Edge · commit` plus a faint `MM-DD build` instead of looking like a downgrade ([02](02-macshell.md#edge-version-looking-like-a-downgrade-in-about-this-mac))
- Three monitor buttons, network speed, CPU temperature and battery, with upload above download in the bar, each opening a glass panel: network shows per-app traffic and your IPs (click to copy), temperature shows top processes and a hardware overview, battery shows a system power chart (measurable on battery only) and battery health and lets you set a charge limit ([02 · Menu bar system monitors](02-macshell.md#menu-bar-system-monitors))
- The battery is a narrow macOS 26 pill with only the number inside, no `%`, in the menu bar ink, colored only while charging (green), at 35% or below (amber) and below 20% (red); the thermometer only takes a color from 65 °C, the network speed is a single monochrome line showing the busier direction (the panel still has both); the thermometer is heavier, the battery outline lighter with a larger number, and the network, temperature and battery buttons are evenly spaced; left-click for battery details, where the power mode can also be switched in place, or right-click to switch power mode (power saver / balanced / performance), and the right-click panel also has a "Show battery percentage" switch ([02 · Battery icon](02-macshell.md#battery-icon))
- Tray icons are unified as monochrome line icons: Chrome, ChatGPT, Clippy, Netcatty, Remmina, Clash Verge, WeChat. Menu titles, workspace numbers and tray icons each pick their ink from the wallpaper under them, so each side of a split wallpaper gets suitable ink with no grey scrim; only an icon that the edge runs through gets a hover-sized rounded plate. The Settings wallpaper grid snaps to whole rows, names drop underscores and resolutions, and the favorite button reads on black and white thumbnails ([02 · Dock icons and the Settings window](02-macshell.md#dock-icons-and-the-settings-window)). [02 · Wallpaper-adaptive menu bar contrast](02-macshell.md#wallpaper-adaptive-menu-bar-contrast)
- Clear All appears centered between the notifications and widgets. Notifications stack by app (no lower-right dropdown arrow; clicking a folded stack expands it first; the 3 newest apps show). Click a single or expanded notification’s body for a brief press effect before it opens the app and is removed. Closing one notification or using Clear All makes the affected cards in view drift and feather out. The panel opens at the top each time. Notifications and widgets keep their glass blur as they fade at the scroll edge. The widgets are: weather, stocks, screen time, batteries, calendar, system and AI usage (Claude, Codex, and Antigravity’s Gemini quota; the small card shows both `5h` and `7d` quota bars side by side), on the same liquid glass as the Control Center tiles, each small / medium / large, with an accent that follows the wallpaper; the weather card is translucent glass too. Right-click a widget to change its size, set the weather city, add, remove and drag-reorder stock symbols from any market (names work too). In "Edit Widgets", click to change size, drag to reorder, "−" to remove, and add new ones from the gallery below ([02 · Notification Center widgets](02-macshell.md#notification-center-widgets))
- Notification Center hides existing banners and adds new notifications directly to the list while open; notification cards (banners and list items) vertically center the left app icon inside the card. A WeChat card restores and focuses the main window even if WeChat is in the tray. [02 · WeChat activation and notification banners](02-macshell.md#wechat-activation-and-notification-banners)
- Notification banner text and icons stay sharp as they slide in, and stacked banners glide into place when new ones arrive or an app withdraws one. [02 · Sharp notification banner entrances](02-macshell.md#sharp-notification-banner-entrances)
- Notification Center moves 160 logical pixels per wheel notch, responds faster to touchpad input, and tracks touchscreen drags more closely. [02 · Notification Center scroll speed](02-macshell.md#notification-center-scroll-speed)
- Auto contrast is event-driven: brightness is measured again only when windows appear, close or move, and when only the wallpaper is behind the bar it reads the wallpaper file instead of taking a screenshot; the pause when opening the Control Center went from about 76 ms to about 19 ms ([02](02-macshell.md#stutter-when-opening-menus-and-the-control-center))
- Floating windows (including `hyprbars`-decorated terminals and apps, during drags, multi-monitor layout changes, or returning to floating) cannot cross the menu bar ([03](03-silky-gestures.md#floating-windows-cannot-cross-the-menu-bar))

## Control Center

- Control Center defaults to macOS 26/27-style frameless floating Liquid Glass bubbles (full-capsule tiles, circular toggles, crisp edge refraction, and 360° specular rim glints) following system light/dark appearance, while still letting you switch back to a grouped frosted slab in Settings ([02 · Control Center](02-macshell.md#control-center))
- A new "Display" page: brightness slider, Night Shift switch and light/dark Appearance switch, working like the "Sound" page ([02 · Control Center](02-macshell.md#control-center))
- Dragging a volume slider (Control Center, the menu-bar volume popover, scrolling on the menu bar) plays a tap at the level being set, and one more where you let go. Turning off UI sounds silences it
- The Sound page shows a live microphone level under the input slider: a few segments in a quiet room, jumping when you speak, red when close to clipping. It listens only while that page is open and the mic is not muted

## Dock and Applications panel

- Empty Trash in the Dock’s Trash context menu takes effect on the first click. [02 · Empty Trash with one click](02-macshell.md#empty-trash-with-one-click)

- WPS components share the red WPS Office Dock icon. Selecting text and opening the mini toolbar keeps a single icon. Press `Super+I` in the WPS editor to switch to WowType. [09 · WPS candidate bar, mini toolbar, and document fonts](09-wowtype-glass.md#wps-candidate-bar-mini-toolbar-and-document-fonts)

- After Omarchy switches to Folio, the MacShell update migrates the old Nautilus pin to Folio. [02 · Files fails to open from the Dock](02-macshell.md#files-fails-to-open-from-the-dock)

- System Settings uses the MacTahoe gear in the Dock. Its sidebar uses a darker frosted backdrop (80% dark / 82% light) so it stays readable over bright windows, while the content pane stays opaque. [02 · Dock icons and the Settings window](02-macshell.md#dock-icons-and-the-settings-window)
- The menu bar, Control Center, Notification Center, Applications panel and Dock use Hyprland blur: the glass follows dragged windows in the same frame, with a light Liquid-Glass-like tint and top sheen in both light and dark mode, and the menu bar is almost fully clear; About This Mac's "More Info…" button is quieter ([02](02-macshell.md#hyprland-blur-instead-of-liquid-glass-normal-blur))
- (Optional) A Hyprland plugin draws macOS 26/27 optical Liquid Glass (convex bevel refraction, subtle dispersion, and 360° dual-diagonal specular rims, following dragged windows in the same frame) for the Dock, all menu bar popovers (Apple/app menus, Wi-Fi, Bluetooth, Volume, Battery/Status, floating Control Center bubbles, Notification Center and toasts), and other MacShell overlays (Spotlight, Applications, Switcher, Wallpaper Picker, OSD); the thin top menu bar strip (`macbarbg`) stays on native blur ([02](02-macshell.md#liquid-glass-dock-plugin-prototype))
- Menus, Wi-Fi, and Notification Center share the clearer glass and thin rim of Control Center. Notifications and widgets use lightly tinted independent glass cards that fade above the Dock as they scroll. [02 · Control Center glass on menus and panels](02-macshell.md#control-center-glass-on-menus-and-panels)
- The Wi-Fi popover and System Settings wait for scan completion and show timeout, retry, and connection feedback. [02 · Wi-Fi scanning and recovery](02-macshell.md#wi-fi-scanning-and-recovery)
- Only MacShell's Dock; Omarchy's own Dock is turned off for good ([02](02-macshell.md#only-macshells-dock))
- Optical icon scaling is centred, so icons no longer drift to one side when magnified ([02 · Dock](02-macshell.md#dock-icons-and-the-settings-window))
- After you click a Dock icon, its name label waits until the pointer moves 4 px before showing again (as on macOS), so repeated clicks no longer stall for 60–70 ms ([02](02-macshell.md#applications-panel-interaction))
- Applications panel (Launchpad): critically-damped (`ζ = 1.0`) zero-bounce transition with restrained `1.06× → 1.00×` scaling, symmetric open/close, and instant velocity-continuous reversal; the Dock remains directly clickable while Applications is open (click Applications to close, click another Dock icon to switch apps, click empty desktop space to dismiss); rapid icon taps respond immediately, touchpad scrolling glides with 0 ms release delay, and offscreen tiles warm up progressively ([02](02-macshell.md#applications-panel-interaction))
- Four- and five-finger pinches support 350 ms staggered landing, bottom-button/palm-sized thumb exemption, opposing-span geometry, and dynamic `3 → 4 → 5` promotion without false three-finger swipes; post-pinch rapid taps unlock immediately, and outside taps close Applications under a stationary pointer ([03](03-silky-gestures.md#four---five-finger-pinch-recognition-on-the-touchpad)).
- Right-click Files in the Dock for shortcuts to Home, Desktop, Documents, Downloads, and Pictures. [02 · Common folders in the Files context menu](02-macshell.md#common-folders-in-the-files-context-menu)
- Folio's yellow button folds the window into a thumbnail between the Dock separator and Trash with a GPU-driven animation that takes over in place and preserves window brightness. Click the thumbnail to restore it. The Dock smoothly makes room and closes the gap ([02](02-macshell.md#window-minimizing))
- "罗技鼠标" (Omalogi) is in the Applications panel and Spotlight with a bright blue tile matching MacTahoe; while running, the Dock shows its own icon ([14](14-omalogi.md#launcher-entry-and-icon))

## Glass and smoothness

- Vulkan live glass; menus and the Control Center capture only while visible and only windows that intersect the glass, and slow down when windows are still ([02](02-macshell.md#default-glass-settings))
- When window focus changes (the stacking order of floating windows changes), the glass backdrop refreshes; title changes do not wake the refresh ([02 · Glass](02-macshell.md#glass-refreshes-when-focus-changes))
- Fixed the misaligned dark band at the edges of popup panels (weaker refraction, narrower bevel) ([02](02-macshell.md#misaligned-glass-panel-edges))
- Removed the periodic pointer stutter; 90 Hz built-in screen ([02](02-macshell.md#periodic-pointer-stutter))
- Floating windows can reuse a blurred desktop backdrop to keep up with the 90 Hz panel while being dragged over other windows ([02](02-macshell.md#window-dragging-at-90-hz))
- Only the focused Folio keeps the glass sidebar; unfocused Folio windows show a solid sidebar, so dragging other windows over many Folio windows no longer re-blurs each of them ([04](04-macos-theme.md#finder-style-folio))
- No more two menu bars / two Docks after a crash; the menu bar, Dock and wheel direction survive a reboot ([02](02-macshell.md))
- Window animations, the menu bar, the Dock and the pointer stay smooth while background programs max out the CPU: Hyprland, MacShell and the input method are scheduled first, and on AC the GPU no longer starts from its lowest clock ([16](16-desktop-priority.md))
- Windows completely covered by other windows stop redrawing (one frame a second remains) and update live again as soon as any part shows; windows under glass or translucent windows keep updating ([16](16-desktop-priority.md#completely-covered-windows-stop-redrawing))

## Windows

- The Tahoe themes, MacShell Clock and installer drop their decorative window strokes. [04 · Window edges](04-macos-theme.md#window-edges)
- Calculator, Omacut, Write, and Media Viewer use the shared traffic lights and size-aware half-screen and corner layouts. WeChat and the PuTTY console render working content at full opacity. [System app window updates](04-macos-theme.md#system-app-audit)
- Silk-drawn title bars on floating windows have round traffic lights and translucent backgrounds ([04](04-macos-theme.md#traffic-light-title-bar))
- MacShell's own windows (Settings, About This Mac) keep their size, are centred, and open without a white flash at the edges ([02](02-macshell.md))
- New windows open directly, Firefox and other GTK3 CSD windows align cleanly from frame 0 without flashing a blurred halo or offset border, per-app About dialogs (such as "About Obsidian") drop outer blur and match their 18 px corners. See [Window opening flashes](02-macshell.md#window-opening-flashes).
- The Settings window's navigation list: 140 px smooth scrolling per wheel notch, native inertia on the touchpad ([02 · Settings window](02-macshell.md#dock-icons-and-the-settings-window))
- `Super+Shift+L` (or clicking the layout icon next to the top-bar workspace numbers) switches the active workspace between floating, tiling, and scrolling in-process with a centered Liquid Glass OSD (skipping the notification center); non-floating workspaces highlight the top-bar icon, and right-clicking lets you pick any mode or reset all workspaces to floating. ([10 · Workspace layout switching](10-shortcuts.md#workspace-layout-switching-centered-liquid-glass-osd-top-bar-icon-and-in-process-toggle))
- Windows dropped into another workspace adopt its floating, tiling, or scrolling layout. [10 · Destination workspace layout](10-shortcuts.md#windows-adopt-the-destination-workspace-layout)
- Use `Super+T` for split tiling on the current workspace. Use `Super+Alt+T` for single-window tiling and press it again to return to floating and bring back the displaced windows. ([10 · Super+T](10-shortcuts.md#supert))
- Switching back to floating with either shortcut keeps the window’s top edge below the menu bar. ([10 · Super+T](10-shortcuts.md#supert))
- Pictures and videos opened in WeChat always appear in a centred floating viewer at a moderate 900×620 size instead of reaching into the menu bar; the chat-history window is narrowed and centred too (height stays at WeChat's own 720 minimum). ([10](10-shortcuts.md#wechats-image-viewer-and-chat-history-window-sizes))
- WeChat no longer steals focus or pops above other floating windows in the background on incoming messages. ([10](10-shortcuts.md#stop-wechat-from-stealing-focus-in-the-background))
- Reopening the main WeChat window from the tray or launcher restores the previous windowed/maximized state and floating geometry instead of auto-maximizing. ([10](10-shortcuts.md#preserve-the-main-wechat-window-state-across-hide-and-reopen))
- The Logitech mouse editor (Omalogi) is a normal window: centred floating 1280×700 (clear of the Dock), tiles / goes full screen, shows in Alt+Tab, and no longer stays on top across workspaces; opening it again only focuses it; with wired and wireless mice both connected, switch between them at the top right ([14 · A real window](14-omalogi.md#a-real-window))
- Remmina remote desktop shows Simplified Chinese, and its solid connection list and frosted header follow light / dark live. The connection toolbar moves to the top with traffic lights and the connection name, drags the window from empty title space, thin line icons and plain tooltips, rarely used actions in `⋯`, and no tab bar for a single session. The main list selects rows with a rounded accent pill. The remote Windows screen shows 1:1 and sharp on HiDPI at 150% by default, instead of an oversized, blurry 200% ([HiDPI scaling](04-macos-theme.md#remmina-hidpi)). See [Remmina in Simplified Chinese with a macOS look](04-macos-theme.md#remmina).
- Omalogi uses a solid editor background and shared window controls. [Omalogi window](14-omalogi.md#a-real-window)
- Unplugging an external monitor automatically moves its workspaces (such as 6–9) and floating windows back into the internal display's usable work area instead of leaving them detached or off-screen. ([10 · Return on unplug](10-shortcuts.md#return-external-display-workspaces-and-windows-to-the-internal-screen-on-unplug))

## Gestures (touchpad / touchscreen)

- WeChat runs in native Wayland without version-pinned binary patches: the top bar drags directly with the mouse, single-finger touchscreen drags scroll continuously in both the conversation list and chat pane, and the built-in minimize/maximize buttons minimize to the Dock and toggle maximized state ([01](01-touchpad-gestures.md#touchscreen-scrolling-in-wechats-conversation-list))

- Touchpad: natural scrolling (mouse too), three-finger drag, four-finger horizontal swipe between workspaces with smoother transitions ([01](01-touchpad-gestures.md))
- Touchscreen: three-finger and single-finger edge swipes between workspaces with rubber-band at the ends; touch drag and two-finger resize of floating windows; dragging terminal title bars ([03](03-silky-gestures.md))
- Four- / five-finger pinch recognition; rapid repeated clicks are not lost ([03](03-silky-gestures.md))
- Touchpad or touch screen four fingers up: every window of the workspace; four fingers down: every window of the current app. Linear and follows the fingers, finishes at a constant speed after release, can be grabbed again mid-way to interrupt or reverse; click or tap a window to switch to it ([13](13-window-overview.md))
- The four-finger overview cancels a gesture if its release event is lost. `Esc` also closes it. [13 · Verify](13-window-overview.md#verify)
- The four-finger swipe-up overview shows clickable workspace previews over a full-screen undimmed wallpaper with no bottom bleed-through. Clicking a preview slides the windows sideways, a four-finger horizontal swipe moves the windows with your fingers, dragging a window thumbnail onto another workspace preview moves it there silently, and clicking the Dock, Menu Bar, or empty space beside the workspace strip dismisses the overview ([13](13-window-overview.md#workspace-previews-and-navigation)).

## Keyboard and shortcuts

- Keys MacShell and Omarchy both used go to MacShell only (Super+Space Spotlight, Super+V clipboard history, Alt+Tab app switcher, Alt+Shift+Tab backwards, Super+L lock), and Omarchy's actions move to free keys ([10](10-shortcuts.md#keys-after-the-change))
- Super+K: a searchable macOS 27-style shortcut panel with groups and ⌘⌥⌃⇧ keycaps; Return runs the shortcut ([10](10-shortcuts.md))
- Screenshots (PrtSc) capture once and post no notification; a floating preview at the bottom right can be dragged out or annotated ([02](02-macshell.md#no-more-screenshot-notifications))
- Right-click exits the capture picker. The redaction controls open inside the toolbar and close after a choice. Blur uses smooth frosted transitions ([02](02-macshell.md#redaction-levels-and-right-click-cancellation))
- After drawing a screenshot region, use `Shift+S` for scrolling capture. The floating button no longer covers the toolbar ([02](02-macshell.md#scroll-capture-without-accidental-clicks))
- New screenshot pins stack in the lower-right corner. Expand to open a card in the center, or drag a card out, resize it, and return or delete it from the context menu ([02](02-macshell.md#standalone-screenshot-pins))

## Menus and popups

- Omarchy's own menus become translucent blurred cards: no screen dimming, accent-filled selection, Inter font, live light/dark switching ([11](11-menu-glass.md))
- Context menus and floating mini toolbars across WPS Writer, Spreadsheets, Presentation, PDF, and the All-in-One shell open at their compact native size without oversized white margins or stealing initial focus (so back-to-back text selections start cleanly), and floating WPS main windows drop the dark outer frame margin so content runs edge to edge ([09](09-wowtype-glass.md#wps-candidate-bar-mini-toolbar-and-document-fonts))

## Input method

- WowType candidate window: rounded frosted skin, Inter 12, an edge-to-edge highlight that shares the panel's 8 px corner, a translucent panel the blur shows through, and the two corners coincide when the first candidate is selected; fixed the ghosting candidate bar in WeChat; in WeChat the pinyin now sits on the bar's first line, so the bar no longer blinks while you type ([09](09-wowtype-glass.md#wechats-candidate-bar-blinks-while-typing))
- With MacShell replacing `omarchy-shell`, `Super+I` / `Super+Shift+I` cycle Fcitx5 input methods directly over D-Bus instead of failing in ChatGPT and other windows when `omarchy-shell` is not running, surviving system updates ([09](09-wowtype-glass.md#superi-input-method-switching-under-macshell))
- WowType and vinput voice input: vinput's live transcript and sound-reactive waveform share one frosted pill ([05](05-voice-overlay.md))

## Lock and boot

- Lock screen notifications sync with the current list when MacShell starts or reloads. [07 · Stale lock screen notifications](07-lock-and-boot.md#stale-lock-screen-notifications)
- Account pictures in MacShell Settings have smoother circular edges. Changing the picture updates the sidebar immediately, and the next lock screen reads the same picture. [07 · Lock screen avatar](07-lock-and-boot.md#lock-screen-avatar)

- Shortcuts, menus, idle and lid close all lock with MacLock ([07](07-lock-and-boot.md))
- The boot disk-unlock screen looks like macOS FileVault ([07](07-lock-and-boot.md#boot-screen))
- Boot starts a single Hyprland session locked immediately by MacLock with `session_lock_xray`, fading directly into the same wallpaper and desktop with zero black screen while keeping the greeter on logout. [07 · Login wallpaper transition](07-lock-and-boot.md#login-wallpaper-transition)

## File manager and terminal

- Folio uses the Finder icon and a compact toolbar. Dock launches continue to use the installed customization after a reboot and packaged Folio updates. Its sidebar is frosted and the file area and path bar are solid. The green button uses a plus to enter full screen and inward diagonal marks to exit, like `Super+F`. Right-click or hold it for half-screen and quarter-screen layouts. The yellow button is disabled in full screen. Drag to either screen edge to preview and snap to a half or quarter. In column view, selecting and expanding a subfolder updates the top path bar, path editor, and copy button to include that subfolder. The breadcrumb has a distinct background and uses semibold text for the current folder. Select an ancestor to navigate or select the current folder or press `Ctrl+L` to edit the path. Tap empty file space to cancel editing. Drag the blank space beside the breadcrumb to move the window. Use the adjacent copy button to copy the full path. Swipe with one finger to scroll the file area. In column view, tap with one finger to left-click, or touch and hold or tap with two fingers to open the context menu. Right-click Trash in the sidebar for the centered Empty action. See [04 · Finder-style Folio](04-macos-theme.md#finder-style-folio).

- Floating Folio windows appear immediately on the first frame without flashing an empty blurred box, and keep clean frosted sidebar corners over high-contrast backgrounds. The Devices sidebar lists unmounted local data partitions (such as a Windows NTFS drive, even when launched via "Show in Folder" from another app) for one-click mounting and appends a single "Network" entry that scans LAN SMB/SFTP/WebDAV/NFS devices on demand in the main pane, with SMB share-list browsing and a "Remember password" keyring option in the sign-in dialog. In the system file chooser's column view, selecting and expanding a subfolder (including an empty folder) confirms or saves directly to that subfolder instead of its parent. Right-click extraction auto-detects legacy non-UTF-8 (e.g., Windows GBK) ZIP filename encodings and extracts valid UTF-8 paths instead of reporting nothing to extract. Both Spacebar Quick Look and the column-view right-hand preview pane render `.xlsx`/`.ods`/`.csv` and `.docx`/`.odt`/`.pptx` natively in C++ within milliseconds (spreadsheets offer multi-sheet virtualized grids, cell copy, and `Shift+wheel` horizontal scrolling; mouse-wheel scrolling is smoothly accelerated while preserving native touchpad scrolling), with cached background conversion for legacy `.doc`/`.xls`/`.ppt`. Creating a new folder (`Ctrl+Shift+N` or context menu) and renaming (`F2` or context menu) edit the name inline across list, column, and grid views without a modal dialog; renaming an expanded folder in list view no longer triggers a false "This folder no longer exists." banner, and right-click actions (Rename, Cut, Copy, Delete, etc.) in list and grid views accurately target the item directly under the pointer even with top margins or scrolling. See [Finder-style Folio](04-macos-theme.md#finder-style-folio).

- Name and save a new folder in its original column while the breadcrumb and column positions stay steady. Browsers, WeChat, and other apps open a new window when opening a folder or revealing a file, preserving the location in existing windows. Revealing a file also scrolls the selected item into view. See [Finder-style Folio](04-macos-theme.md#finder-style-folio).
- Files and Foot match the size of their traffic lights, the paths and stroke width of their hover symbols, and their inward-diagonal exit mark. See [Tahoe appearance for Foot](04-macos-theme.md#foot-glass).
- Foot has a solid reading surface and light/dark palettes. Its floating windows use the Files-style green-button layout menu and edge previews for halves and corners. See [Tahoe appearance for Foot](04-macos-theme.md#foot-glass).
- With a macOS Tahoe theme active, the Nautilus sidebar picks up blurred background colors while the file area keeps text and icons crisp. See [Frosted glass in Files](04-macos-theme.md#frosted-glass-in-files).
- Nautilus looks like Finder, with Space for Quick Look ([04](04-macos-theme.md)); its context menu has "Copy Path", "Open in Terminal" and "Extract Here" ([08](08-nautilus-actions.md))
- The optional Simplified Chinese setup localizes menus, dates and common sidebar bookmarks. See [Simplified Chinese interface](08-nautilus-actions.md#simplified-chinese-interface).
- Right-click a single image in Nautilus and choose Set as Background to preview and apply it to the Omarchy desktop. See [Set the desktop background](08-nautilus-actions.md#set-the-desktop-background).
- The terminal runs zsh + Oh My Zsh: history suggestions, syntax highlighting, richer completion ([06](06-terminal.md))

## Obsidian notes

- Obsidian follows the macOS design of Files (Folio) and Foot: sidebars run edge-to-edge with live Hyprland frosted blur while the editor pane and tab bar stay fully solid; folders use Finder blue icons, extensions have dedicated icons, code blocks look like Terminal windows, and the caret glides with per-character fade-in. See [15 · Obsidian](15-obsidian.md).
- Obsidian's top-left traffic lights match the 12 px solid-circle baseline with unfocused dimming: red closes, yellow minimises to the Dock and restores the same window, green single-click toggles true fullscreen (with the shared top-left exit hover bar), right-click or hold opens the 2-row 8-slot layout menu, and empty titlebar space supports double-click maximise and edge-drag snap. See [15 · Obsidian](15-obsidian.md#what-it-does).
- Clicking Obsidian in the Dock switches to the window that is already open, with a running dot under the icon, instead of bouncing forever. See [15 · Obsidian](15-obsidian.md#implementation).

## Check that everything is still in place

After upgrading Omarchy or MacShell, run the self-check; it reports on each of the modules above (shortcut clashes, menu glass, the Super+K panel, lock screen, voice overlay, gesture plugin and more):

```bash
./scripts/silky-doctor.sh
```
