# 04 · macOS Tahoe theme (dark / light)

[简体中文](../04-macos-theme.md) | English

## Goals

- Two Omarchy themes, `macos-tahoe-dark` and `macos-tahoe-light`, with colours from Apple's system palette
- Windows use continuous-curvature corners and soft shadows, with backdrop blur on translucent surfaces
- MacTahoe icons: blue folders, macOS-style app icons
- The file manager (Nautilus) looks like Finder: translucent sidebar, traffic lights at the top left, Space for Quick Look (sushi)
- Floating windows get a macOS traffic-light title bar: close, full screen
- Switching theme also switches the GTK look, the pointer and MacShell's light/dark appearance

## Parts

| Part | File | Notes |
| --- | --- | --- |
| Colours | `themes/macos-tahoe-*/colors.toml` | Apple system colours. The light variant uses high-contrast terminal colours, otherwise yellow and green are unreadable on white |
| Window look | `themes/macos-tahoe-*/hyprland.lua` | No compositor border, 14 px corners (`rounding_power = 2.6`), shadow, 3 blur passes and blur brightness `1.0` in both appearances |
| Icons | `themes/macos-tahoe-*/icons.theme` | `Silky-MacTahoe-dark` / `Silky-MacTahoe-light` (inherit MacTahoe, unify the sidebar symbolic icons) |
| GTK / Finder | MacTahoe GTK theme | The upstream prebuilt release, no sassc needed |
| Sync | `hooks/theme-set-silky-macos` | Omarchy theme-set hook |
| Traffic lights | `config/hypr/silky-titlebar-guard.lua` + `config/hypr/silky-macos.lua` | Turns Omarchy's floating-window title bar into round traffic lights |

### Window edges

Both Tahoe variants set the Hyprland window border to zero. To keep this behavior across other themes, add `hl.config({ general = { border_size = 0 } })` to `~/.config/hypr/looknfeel.lua`. Run `hyprctl reload` and `hyprctl configerrors`, then check `hyprctl getoption general:border_size`. The current session was checked with open Chromium, Foot, Folio, Firefox and WeChat windows. Application title bars, control borders and window shadows are retained.

The [MacShell tuner](../../scripts/tune-macshell-window-edges.py) also removes the QML window strokes from Clock, the dependency dialog and the standalone installer. The [Nautilus GTK style](../../config/gtk-4.0/nautilus-glass.css) removes the decorative sidebar highlight and keeps the blur. Reload MacShell and reopen the window to inspect the result. To roll back, restore the corresponding `looknfeel.lua`, Tahoe theme, MacShell or GTK backup and reload the affected program.

### Third-party components

The installer pins third-party components to commits listed in `scripts/install-macos-theme.sh`.

- [vinceliuice/MacTahoe-icon-theme](https://github.com/vinceliuice/MacTahoe-icon-theme)
- [vinceliuice/MacTahoe-gtk-theme](https://github.com/vinceliuice/MacTahoe-gtk-theme)

The themes ship no wallpapers (Apple's wallpapers are copyrighted). The installer copies your current wallpaper into `~/.config/omarchy/backgrounds/macos-tahoe-*/`; add more wallpapers to those two folders as you like.

## Install and switch

```bash
./scripts/install-macos-theme.sh
```

```bash
omarchy theme set macos-tahoe-dark
```

```bash
omarchy theme set macos-tahoe-light
```

Optional flags: `--no-icons`, `--no-gtk`, `--no-bars` (leave the title bars alone). GTK apps that are already open (Files, Settings) pick up the new look when reopened.

## What switches along with the theme

Omarchy's own theme mechanism only sets Adwaita and the icon theme. Under the `macos-tahoe-*` themes the hook also:

- Sets the GTK 3 theme to `MacTahoe-Dark` / `MacTahoe-Light`; libadwaita (GTK 4) picks it up through links from `~/.config/gtk-4.0/gtk.css` and friends to the theme files
- Sets the window button layout to `close,maximize:`, so the traffic lights are on the left
- Switches the pointer to MacTahoe (the black macOS arrow in both appearances)
- Switches the light/dark appearance of MacShell's menu bar, Dock and Control Center with `qs -c MacShell ipc call appearance set dark|light`, and updates the icon theme the Dock uses

When you switch to any other theme, the hook removes the GTK 4 links it made (a `gtk.css` you wrote yourself is backed up and restored, never deleted) and restores the previous button layout and pointer. The original values are kept in `~/.local/state/silky-omarchy/macos-theme.previous`.

## Icons

The Nautilus sidebar uses MacTahoe's own symbolic icons, shown in blue; the Projects folder reuses the theme's code-folder symbolic icon.

### Frosted glass in Files

Nautilus softens windows and wallpaper behind it into broad patches of color. The sidebar lets more color through and has a thin highlight along its edge. The file area uses the theme’s solid view color so names and icons stay readable at any overlap.

The theme installer writes the [GTK 4 overlay](../../config/gtk-4.0/nautilus-glass.css) into `~/.local/share/themes/Silky-MacTahoe-{Dark,Light}/gtk-4.0/`. If the base MacTahoe GTK theme is installed, run `./scripts/install-macos-theme.sh --no-icons --no-gtk --no-bars` from the repository root to update it. With either macOS Tahoe theme active, save your work, quit the Nautilus process, and reopen Files. Background blur requires GTK's Wayland background effects support and Hyprland with blur enabled. Tested with Nautilus 51.1, GTK 4.24.1, and Hyprland 0.57.2.

To check the effect, overlap Files with another window containing text. The sidebar should pick up the blurred colors, and details behind the file area should be obscured. To revert the glass styling, restore the corresponding `gtk.css.bak.*` and `gtk-dark.css.bak.*` backup files printed by the installer, then quit and reopen Nautilus.

Icon tweaks made earlier with ChatGPT are folded into the installer:

- Icon aliases for Omarchy's bundled apps: `omacalc → calc`, `omawrite → text-editor`, `omarchy-discord → discord`
- MacTahoe redraws the ChatGPT and Claude icons. The script renames those two aliases to `*.mactahoe-backup` so the vendors' official icons are used
- ChatGPT's official icon has different transparent padding from MacTahoe's, so `dockIconScale()` in the MacShell patch draws it 4% smaller in the Dock; Claude is now redrawn on the standard tile, so its factor is 1.0
- `scripts/tune-app-icons.py` brings every other launcher app into the MacTahoe style. Its output goes straight into `MacTahoe/apps/scalable`, so the Applications panel, Dock and Spotlight all use it:
  - Utilities and Omarchy's own apps link to the matching macOS icon, e.g. `imv → accessories-image-viewer`, `omacut → VideoTrimmer`, `hype → Keynote`, `gliff → remote-desktop`, `signed → PDF`, `monologue → Photo Booth`, `LimineSnapperSync → timeshift`, `wemeetapp → meeting`, `zoom → Zoom`
  - Branded and custom-logo apps (Claude, Kimi Code, HEY, Superwhisper, WorkBuddy, xiezuo, Basecamp, Netcatty, Clippy, WowType, Google Messages, Fantasi, Flowtunes, and Omarchy's Browser / Terminal / Media Viewer / Game Vibes / Agent launchers) keep their logo, redrawn on MacTahoe's exact tile: 442 px on a 512 canvas, corner radius 100, with the shadow taken from the set's own Zoom icon. Bordered solid cards with hard drop shadows are trimmed clean and centered on their own background colour; round logos and bare glyphs sit on a light tile
  - `.desktop` entries that pointed at absolute-path PNGs or wide device icons (such as `antigravity.desktop`, `kimi-code.desktop`, and `kbd-layout-viewer5.desktop`) are switched in `~/.local/share/applications/` to the matching MacTahoe theme icon name
  - After installing a new app, run `python3 scripts/tune-app-icons.py` again. An app with no mapping yet needs an entry in the script's `ALIASES` or `BRANDS` first
- MacShell's Dock and Spotlight read the icon theme from `QS_ICON_THEME` in `~/.config/macshell/env`

## Finder-style Folio

Folio uses the Finder icon already in MacTahoe. The Dock and the MacShell applications panel share the same `folio` app ID. The navigation sidebar keeps its frosted glass. The path bar, file area, and preview use the theme's fully opaque background. Blue folders keep their rounded selection outlines. The red button closes the window, and yellow minimizes it. The green button uses a plus for entering full screen and inward diagonal marks for exiting it. Click it to toggle full screen, just like `Super+F`. The yellow button is disabled in full screen. Right-click or hold the green button to open a layout menu with two rows of icons for the four halves and four corners of the display. Hover over an icon to see its label. In full screen, the menu offers an exit action and disables the layout icons. Drag the space next to the buttons to move a floating window, or drag the path bar with a mouse or touchscreen, or double-click it to maximize or restore. At either display edge, the middle zone previews a half-screen layout and the top and bottom zones preview their respective quarters. The blue preview moves and resizes linearly and fades out when the pointer leaves the edge. Releasing the pointer submits the placement right away and fades the preview out in 45 ms. The preview and window both respect space reserved by the bar and Dock.

The toolbar is 44 px tall. Its traffic lights use solid 12 px circles with 8 px gaps, optically matching Foot. Files uses its existing path strokes for hover symbols. The sidebar background runs continuously from the top of the window, and the divider in the file area sits over the background. Columns avoid leaving a sliver of a folder icon at the leading edge when automatically scrolling.

Under the Tahoe themes, the floating Folio sidebar blurs the scene behind the window and Hyprland clips it to the window's rounded shape. The [Folio window rule](../../config/hypr/silky-folio.lua) uses live blur and removes the translucent outer border to clear the colored fringe at the sidebar corners. Regular Folio windows paint at full opacity on the first frame instead of waiting through the upstream 150 ms settle timer and 100 ms fade-in, so opening Folio no longer flashes an empty blurred glass box (file choosers keep the upstream behavior). Update the user config and run `hyprctl reload` to apply it to open windows. Check the top-left and bottom-left corners over a high-contrast window. To roll back, remove the `silky-folio-rounded-glass-edge` rule and reload.

Only the focused Folio window keeps the glass sidebar. An unfocused Folio paints an opaque sidebar in the same tint, and the `silky-folio-unfocused-no-blur` rule in the [Folio window rule](../../config/hypr/silky-folio.lua) stops Hyprland from blurring behind it. With a dozen Folio windows open, dragging another window across them used to recompute the live blur of every Folio window on every frame and drop frames; now only the one in front pays for it. `focus = false` is a dynamic match, so Hyprland re-evaluates the rule on every focus change. The sidebar color comes from `sidebarTint` in `Main.qml` in the [patch](../../patches/folio-0.6.1-silky.patch), which switches on `active`. On the frame focus leaves, Hyprland may drop the blur one frame before Folio paints the solid color, so the unblurred backdrop can briefly show through the sidebar. Install with `./scripts/install-folio-macos.sh` and reopen Folio. The installer also updates `~/.config/hypr/silky-folio.lua`; run `hyprctl reload` afterwards. To verify, open Folio, move focus to another window, and run `hyprctl getprop address:<address> no_blur` on the Folio window: it should print `true` while unfocused and `false` while focused. Verified on Hyprland 0.57.2 on real hardware: the rule toggles with focus and the focused sidebar keeps its glass. The solid sidebar of an unfocused window still needs a visual check on real hardware, and drag frame times have not been measured yet. To roll back, delete the `silky-folio-unfocused-no-blur` rule from `silky-folio.lua` and run `hyprctl reload`. To bring back the translucent sidebar on unfocused windows, also remove `!active ? 1 :` from the patch and rerun the installer, or restore the previous build from `~/.local/share/silky-omarchy/folio/folio.bak.folio.*`.

The breadcrumb sits on a rounded surface with a subtle border that follows the light or dark theme. Semibold text marks the current folder. Each segment has a 30 px high hit area and its own hover highlight. Click or tap an ancestor to navigate, or select the current folder to edit and select the full path. Long paths scroll horizontally and keep the current folder visible by default. Drag the blank space beside the breadcrumb to move the window, or double-click it to toggle maximization. The path bar was checked in light and dark Tahoe themes in temporary Wayland windows. Offscreen Qt tests cover clicks on segment padding, touch dragging, dismissal by touch, and long paths in narrow windows. Click or tap empty space in the file area to cancel editing. Swiping still scrolls the files. `Ctrl+L` also starts editing. Enter opens the path and Escape leaves the editor. The copy icon copies the full path of the current folder. In column view, when a subfolder is selected and expanded in the next column, the top path bar, window title, path editor, and copy-path button include that subfolder; selecting a file or switching to list/grid view returns the bar to the containing folder.

Swipe with one finger to scroll the file area in column, list, or icon view. Mouse drag and drop remains available. In column view, a single-finger touchscreen tap acts like a left click. Touch and hold with one finger or tap with two fingers to open the context menu at the first contact. Moving past the system drag threshold cancels the context gesture. If Silky Gestures is enabled, rebuild it with its installer so Folio receives holds in the file area. See [Moving and resizing floating windows on the touchscreen](03-silky-gestures.md#moving-and-resizing-floating-windows-on-the-touchscreen).

Trash gives the toolbar space back to the file view. Right-click Trash in the sidebar and choose the centered Empty action, or use the same action in the Trash file area. The action asks for confirmation, and the sidebar menu disables it when Trash is empty.

The sidebar's Devices section also lists **unmounted local data partitions** reported by GIO/UDisks2 (such as a dual-boot Windows NTFS volume) labeled "Not mounted". Clicking or activating one mounts it asynchronously via UDisks2 and opens it right away; its context menu offers Mount (or Open and Unmount/Eject once mounted) while still filtering out system, EFI, and recovery partitions. When another app opens Folio through `xdg-desktop-portal` `OpenURI` (for example, "Show in Folder" in a browser), the child inherits `GIO_USE_VFS=local` from the portal daemon, which disables GVfs / `GProxyVolumeMonitorUDisks2` and hides unmounted partitions and remote mounts; both the [launcher](../../bin/silky-folio) and `main.cpp` clear `GIO_USE_VFS=local` at startup so unmounted local partitions remain visible from every entry point. When no graphical polkit agent is running, mounting an internal disk (`org.freedesktop.udisks2.filesystem-mount-system`) fails with `Not authorized to perform operation`; install [50-silky-udisks2-mount.rules](../../config/polkit/50-silky-udisks2-mount.rules) into `/etc/polkit-1/rules.d/` to let active local `wheel` users mount internal volumes directly.

In the system file chooser (`org.freedesktop.impl.portal.FileChooser`), selecting and expanding a subfolder in column view (including an empty folder) updates the top path bar to include that subfolder; confirming with Choose/Save (or `Ctrl+Enter`) now returns or saves into that subfolder instead of its parent directory (multi-selected folders, cleared selection, and list/grid views keep their existing behavior). Verified with `folio_tests` (`chooserWindowAnswersFromTheKeyboard`, including an empty-subfolder column regression test, and `chooserAnswersForEachMode`).

A single "Network" entry is appended under Devices via the [Folio network plugin](../../config/folio/plugins/network/) installed to `~/.local/share/folio/plugins/network/`. It does not expand in the sidebar or poll in the background on startup; opening "Network" (or refreshing with `F5`) scans on demand with `avahi-browse` for LAN devices advertising SMB, SFTP, WebDAV, or NFS services, merges optional static entries from `~/.config/folio/network-servers.json` (an array of `{"name": "NAS", "url": "smb://10.1.1.5/"}` objects), and includes active remote mounts under `/run/user/$UID/gvfs/`. Opening an SMB host (from the Network view or by typing `smb://host` in the path bar) authenticates through GVfs and lists its shared folders (skipping administrative `$` shares); opening a share mounts it locally and enters the folder. The sign-in dialog includes a "Remember password" checkbox (checked by default) that passes `G_PASSWORD_SAVE_PERMANENTLY` to GVfs so credentials are stored in the system keyring (`gnome-keyring-daemon` / Secret Service) for automatic reconnects, or kept for the current session only when unchecked. Requires `avahi-daemon`, `gvfs`, `gvfs-smb` (plus optional `gvfs-nfs`), `gnome-keyring`, and `python3`.

Right-click "Extract" now handles legacy Windows ZIP archives with non-UTF-8 filenames (such as GB18030/GBK, Big5, Shift_JIS, or EUC-KR). Because those archives omit the ZIP UTF-8 flag (bit 11), `bsdtar` otherwise writes raw legacy bytes that Qt's `QDir::entryList()` skips on a UTF-8 system, causing Folio to fail with "There's nothing in … to extract." Before launching `bsdtar`, the patch inspects the ZIP central directory and, only when non-UTF-8 legacy entry names are present, probes candidate encodings via glibc `iconv` (ordered by system locale) and passes `--options hdrcharset=<charset>` to `bsdtar` so extracted paths are written in valid UTF-8. Standard UTF-8 and ASCII archives are untouched. Verified with `folio_tests` (`extractLegacyGbkZip` and the extraction suite) and against a real 229 MB GBK-encoded ZIP archive.

Creating a new folder (context menu "New Folder" or `Ctrl+Shift+N`) and renaming (`F2` or context menu "Rename") now use **Finder-style in-place inline editing** across list, column, and grid views instead of opening a modal dialog: a newly created folder immediately enters an inline editor with its name selected so you can type right away, press Enter or click away to commit, or press `Esc` to cancel; renaming a file selects only the stem before the extension. Sidebar folder renames keep the existing dialog. Verified with `folio_tests` (`newFolderEmitsFolderCreatedForInlineRename`) and offscreen window load tests.

Fixed two context-menu and rename bugs in list and grid views:
- **No stale "This folder no longer exists." banner after renaming an expanded folder**: previously, renaming (or deleting/moving) an expanded folder in list view left the old path in `FolderModel::m_expanded`, so the next `reload()` tried to list the old path and surfaced a red error banner. The patch adds `FolderModel::renamed()` wired to `fileOps.onRenamed` to remap expanded folder paths (and nested children) plus their watchers in place, and silently drops expanded folders that vanished on disk during `reload()` (explicit expand failures and permission errors still report as before).
- **Accurate right-click hit-testing under the pointer in list and grid views**: `TapHandler` declared directly inside a `ListView` or `GridView` is reparented by Qt Quick to `contentItem`, so `Selecting.menuAt()` was adding `contentX`/`contentY` a second time—shifting right-clicks onto the row above when `topMargin` is set, and farther off once scrolled, causing Rename, Cut, Copy, Delete, and other context actions to target the wrong item. `Selecting.menuAt()` now maps `point.scenePosition` directly into `view.contentItem` space via `view.contentItem.mapFromItem(null, point.scenePosition)`. Verified with offscreen `folio_tests` (`renamingOrRemovingExpandedFolderEmitsNoError`, `listRightClickHitsItemUnderCursorWhenScrolledOrMargined`, and `gridRightClickHitsItemUnderCursorWhenScrolled`); live verification requires running `./scripts/install-folio-macos.sh` and reopening Folio.

In column view, new folders are named inline in the current column or an already expanded child column. Creation and confirmation preserve the breadcrumb, column positions, and current selection. Previously, auto-selecting the new folder added a column, and clicking empty space removed it and shifted the other columns. Create a folder with `Ctrl+Shift+N` or the context menu, then press Enter or click empty space to check that it appears in the same column. Select the new folder to expand its contents.

Multi-selection now accepts **`Ctrl+click`** (alongside `Alt+click`) to toggle individual items, **`Shift+click`** for ranges, **`Ctrl+Shift+click`** to add ranges, and adds rubber-band drag selection (`Band`, with `Ctrl`/`Alt` additive drag) to the active column in column view.

Spacebar Quick Look (`folio preview`) and the column-view right-hand `PreviewPane` add **fast native Office and spreadsheet previews**, parsing modern formats in milliseconds on a C++ worker thread with zero LibreOffice subprocess overhead:
- **Spreadsheets (`.xlsx`, `.xlsm`, `.ods`, `.csv`, `.tsv`)**: Parsed in milliseconds via `libarchive` and `QXmlStreamReader` (handling shared strings, Excel serial dates, and UTF-8/GB18030 CSV auto-detection) and displayed in a virtualized grid (`SpreadsheetPreview.qml`) with multi-sheet tabs, smooth bidirectional scrolling (including `Shift+wheel` horizontal scrolling), CJK-aware column sizing, and a selected-cell inspector with one-click copy.
- **Modern documents & decks (`.docx`, `.odt`, `.pptx`)**: Parsed natively in C++ (headings, paragraphs, bold/italic/underline, lists, and tables) and shown immediately in `OfficeDocPreview.qml` (< 20 ms) without launching LibreOffice.
- **Column-view `PreviewPane` snippets**: Selecting a `.docx`/`.odt`/`.pptx`/`.xlsx`/`.ods`/`.csv` file in column view asynchronously renders a compact document or table preview card directly in the right-hand pane instead of a generic file icon.
- **Global 90 Hz smooth mouse-wheel scrolling (`SmoothMouseWheelFilter`)**: On Wayland, discrete mouse wheels arrive with a tiny `pixelDelta` (~15 px) and `Qt::NoScrollPhase`, causing Qt Quick `Flickable`/`ListView`/`GridView` views to crawl. An application-level event filter in `main.cpp` intercepts `Qt::NoScrollPhase` wheel events (excluding `Ctrl` zoom) and eases **210 px per detent** across 90 Hz (11 ms) frames (with `Shift+wheel` mapped to horizontal scroll), covering list/column/grid views, sidebar, Quick Look previews, and the file chooser in one place while passing phased touchpad gestures (`ScrollBegin`/`ScrollUpdate`/`ScrollEnd`) through untouched.
- **Legacy binary formats (`.xls`, `.doc`, `.ppt`, `.rtf`, `.odp`, `.wps`, `.et`, `.dps`)**: `.xls` converts in the background to a cached `.xlsx` for the native spreadsheet grid; the rest convert to cached PDFs under `~/.cache/folio/office-preview/` (pruned at 256 MB) for Qt PDF. Switching files kills the conversion process group immediately, and cached files reopen instantaneously.
- Dependencies: `libarchive` (required for build and native parsing), `qt6-webengine` (Qt PDF), and optional `libreoffice-fresh` / `libreoffice-still` (legacy binary formats only). Verified with `folio_tests` (`officePreviewClassifiesFormats`, `officePreviewParsesDocxXlsxCsvAndPptx`) and offscreen `folio preview` smoke tests.

Install the MacTahoe icon pack through the theme installer and select `macos-tahoe-dark` or `macos-tahoe-light`. From the repository root, run:

```bash
./scripts/install-folio-macos.sh
hyprctl reload
qs -c MacShell ipc call macshell reload
```

The installer builds the [window patch](../../patches/folio-0.6.1-silky.patch) against a pinned Folio 0.6.1 revision. It requires Git, CMake, a C++ compiler, pkg-config, Qt 6, GLib/GIO, `libarchive`, and zlib. The build goes into `~/.local/share/silky-omarchy/folio/`. The user desktop entry, `~/.local/bin/folio`, and the user-level D-Bus services (`~/.local/share/dbus-1/services/org.freedesktop.impl.portal.desktop.folio.service` and `org.freedesktop.FileManager1.service`) route regular Folio windows, "Show in Folder" calls from browsers/WeChat, spacebar previews (`folio preview`), and the system file chooser (`folio chooser`) through the custom build while retaining the Folio app ID. Under Tahoe themes, the launcher checks the shared libraries and symbols that the user build needs. Kernel and packaged Folio updates leave the Dock, default folder handler, system file chooser, and both file manager shortcuts on the same user build and view settings. The user build stays on 0.6.1 independently of packaged Folio updates. Other themes use the package. The launcher also uses it when the user build is missing or its runtime libraries are incompatible. After an update, run `gtk-launch folio.desktop /tmp` and check that `/proc/<Folio PID>/exe` points to the build in your home directory, or run `busctl --user call org.freedesktop.impl.portal.desktop.folio /org/freedesktop/portal/desktop org.freedesktop.DBus.Peer Ping` to verify the chooser portal service runs the user build. The desktop entry and chooser D-Bus activation were verified with packaged Folio 0.7.1 on kernel 7.3.0-75-omarchy. The [Folio window rules](../../config/hypr/silky-folio.lua) leave Folio at full window opacity so its own sidebar translucency controls the glass.

Browsers, WeChat, and other apps using `org.freedesktop.FileManager1` open a new window for each "Open Folder" or "Show in Folder" request. When asked to reveal a file, Folio opens its containing folder, selects it, and scrolls it near the center in column, list, and grid views. Column view also brings the file’s column into view. Existing Folio windows keep their paths, selections, and navigation history. D-Bus activation opens only the requested window when Folio is closed. In addition, Linux WeChat (e.g. `wechat-bin` 4.1.13.29) falls back to `dbus-send ... org.freedesktop.FileManager1.ShowItems array:string:<path>` when neither `dde-file-manager` nor `nautilus` is installed, passing a bare filesystem path instead of a `file://` URI (and `dbus-send` splits filenames containing `,` across array elements); `src/filemanager1.cpp` in the patch accepts both `file://` URIs and bare absolute `/` paths (normalizing extra slashes), and falls back to rejoining comma-split elements when the first item does not exist on disk, fixing silent no-ops on WeChat's "Show in Folder". Run the installer above, close any running Folio processes (including a resident `folio --file-manager-service`), reopen Folio with a test folder, then reveal a file from your browser or test a bare-path call with `dbus-send --session --print-reply --dest=org.freedesktop.FileManager1 --type=method_call /org/freedesktop/FileManager1 org.freedesktop.FileManager1.ShowItems array:string:"/tmp/test.txt" string:""` (plus comma-containing filenames and `file://` URIs). Expect each request to open a new window at the target folder with the file selected. To roll back, restore the installer backups for the Folio binary, launcher, and `org.freedesktop.FileManager1.service`, then reload the user D-Bus configuration and reopen Folio.

The [MacShell integration](../../scripts/tune-folio-macshell.py) lets the yellow button scale the window into a thumbnail between the Dock separator and Trash. Click the window thumbnail to restore it. See [Window minimizing](02-macshell.md#window-minimizing). Without MacShell, Omarchy supports minimize on floating workspaces. Verified on native Wayland with Hyprland 0.57.2, MacShell 0.5.3, and Folio 0.6.1. Reopen Folio, then click green twice, yellow, the Dock thumbnail, and red to verify entering full screen, exiting full screen, minimizing, restoring the same window, and closing. Right-click and hold should both open the layout menu. Each half should respect the display space reserved for the bar and Dock. The corner icons should match the previews shown when dragging to the corners. In full screen, the yellow button and layout icons should be disabled. Over a high-contrast wallpaper, the empty file area should stay solid in floating and fullscreen windows while the sidebar picks up blurred colors. If a fullscreen window shows an empty Dock outline, see the [Liquid Glass Dock plugin](02-macshell.md#liquid-glass-dock-plugin-prototype).

To roll back, restore the `.bak.folio.*` files printed by the installer. If there was no user launcher, desktop entry, or D-Bus service override, remove `~/.local/bin/folio`, `~/.local/share/applications/folio.desktop`, `~/.local/share/dbus-1/services/org.freedesktop.impl.portal.desktop.folio.service`, and `~/.local/share/folio/plugins/network/`, then reload the session D-Bus config (`dbus-send --session --dest=org.freedesktop.DBus --type=method_call /org/freedesktop/DBus org.freedesktop.DBus.ReloadConfig`). Restore the `MacDock.qml` and `shell.qml` backups, reload MacShell, and reopen Folio. Restore any minimized Folio windows from the Dock first. To remove the Folio opacity, minimize overlay, and half-screen layout configuration, remove `require("hypr.silky-folio")` from `~/.config/hypr/hyprland.lua` and reload Hyprland.

<a id="foot-glass"></a>

## Tahoe appearance for Foot

Foot follows Folio’s layout. The output sits on solid graphite or warm white, with frosting on the 30 px floating title bar. The terminal uses 11 pt Monaco with fallbacks for Chinese text, terminal icons, and emoji. It has 20 px horizontal and 16 px vertical padding, a thin beam cursor, and separate ANSI palettes with blue selections. Foot windows with both palettes loaded follow MacShell’s Light, Dark, and Auto appearances.

On floating workspaces, red closes the window and yellow minimizes it through MacShell, where the Dock restores it. Click green to enter fullscreen as in Files. Right-click or hold green to choose from two rows containing the four halves and four corners. In fullscreen, moving the pointer to the top-left edge reveals the exit control. Drag free space on the title bar to move the window, or double-click to toggle maximize. During a side-edge drag, the middle band previews a half and the upper and lower bands preview their respective corners. Releasing places only the dragged window and respects the menu bar and Dock reserves.

The colored faces in Foot and Files are both 12 px. On hover, Silky Gestures draws the cross, dash, and plus for the shared Tahoe title bars using the same paths and 1.1 px round-cap strokes as Files. It rasterizes the strokes at the output scale and aligns them to the pixel grid. Foot’s fullscreen overlay uses Files’ inward diagonals for exit and greys out yellow. Run `./scripts/install-silky-gestures.sh`, install the matching `silky-macos.lua`, and reload Hyprland to update the hover marks. The title bar uses the configured font glyphs when the updated plugin is unavailable. To roll back, restore the previous `silky-macos.lua` and plugin build and sign in again. The fullscreen overlay comes from `FootWindowLayout.qml` and updates when MacShell reloads.

From the repository root, run:

```bash
./scripts/install-foot-glass.sh
foot --check-config
systemctl --user is-active silky-foot-glass.service
```

The [theme installer](#install-and-switch) provides the floating title bar. The Foot installer backs up any changed copies of `~/.config/foot/foot.ini` and `~/.config/foot/silky-glass.ini`. The first migration writes the font to `foot.ini` so Omarchy’s font and text-size commands can adjust it. The [appearance profile](../../config/foot/silky-glass.ini) needs dual-palette support, verified on Foot 1.28.0. Fontconfig uses installed Monaco, JetBrainsMono Nerd Font, Sarasa Mono SC, and Noto Color Emoji fonts or available fallbacks. The user service watches `org.gnome.desktop.interface color-scheme` to set the startup appearance and switch the palettes of running Foot windows.

Window layouts use the existing Files/MacShell integration. From the repository root, back up and update `config/hypr/silky-folio.lua` and `config/hypr/silky-macos.lua` in `~/.config/hypr/`. Back up the installed Silky Gestures plugin in `~/.local/lib/silky-omarchy/`. Run `./scripts/install-silky-gestures.sh` to rebuild the input plugin and `python3 scripts/tune-folio-macshell.py ~/.config/quickshell/MacShell --backup` to update the menu. Apply with `hyprctl reload` and `qs -c MacShell ipc call macshell reload`. To roll back layouts, restore the two Lua backups, the MacShell `shell.qml` backup, and the previous plugin build, then sign in again to load that build.

Open a fresh window through the default terminal launcher and check Chinese text, ANSI colors, selections, and the title-bar controls. Reopen older windows after their sessions finish. With `foot --server`, wait for active sessions to finish before restarting the server process.

On Hyprland 0.57.2, the live session verified both palettes and MacShell minimize and restore of the same session. An isolated Wayland session used simulated input to check right-click, press-and-hold, entering and exiting fullscreen, the snap preview, and the top-right drop. All eight placements kept clear of the menu bar and Dock reserves. Simulated title-bar dragging on the built-in panel measured 89.6 FPS using Wayland presentation timestamps after the update. Physical touchscreen checks are pending.

To return to the previous look, restore the Foot backups printed by the installer and open a fresh window. To remove appearance synchronization entirely, run `systemctl --user disable --now silky-foot-glass.service` and restore the pre-installation `foot.ini` or remove its two Silky includes. To roll back the title bar separately, restore the `~/.config/hypr/silky-macos.lua` backup and run `hyprctl reload`.

<a id="remmina"></a>

## Remmina in Simplified Chinese with a macOS look

Remmina 1.4.44 ships a Simplified Chinese translation, but the system language is `en_US`, so the interface stayed in English. After installation, Remmina shows Simplified Chinese menus, column headers and dialogs whether you open it from the launcher, the Dock, an `rdp://` link or the tray applet. Under the macOS Tahoe theme you also get:

- **MacShell glass**: the header and session toolbar use glass. The main connection list, quick connect area and footer sit over a solid base (`#1c1c1e` dark, `#f6f6f8` light). The remote desktop picture is opaque.
- **Live light / dark**: switching appearance in MacShell or with `omarchy theme set` restyles open Remmina windows immediately, without a restart.
- **Main window**: borderless title bar buttons with a rounded plate on hover. The connection list has no grid lines, and the selected row is a rounded pill inset from the edges, in MacShell's accent colour, turning light grey when the window loses focus. The quick-connect bar, column headers and footer use small secondary text.
- **Remote connection window**: the toolbar moves from the left edge to the top, forming a unified title bar. Traffic lights and the connection name sit on the left. Dragging the name or the empty middle of the toolbar moves a floating window directly, without holding `Super`; double-clicking maximizes it. The tools on the right use a thin 16 px line icon set, and tooltips say what each tool does in plain words, such as "Resize remote screen with window" or "Send key combination", keeping Remmina's shortcut hint. Active toggles (full screen, scaling, keyboard capture…) show in the accent colour.
- **Trimmed toolbar**: connection list, fit window, full screen, dynamic resolution, scaling, keyboard capture, screenshot and disconnect stay visible. Duplicate connection, view only, invert scrolling, edit connection settings, minimize and reconnect move into a `⋯` menu. Plugin menus the current protocol does not offer (quality options, remote actions, send key combination) hide themselves, and separators are gone.
- **Sharp, right-sized remote screen**: on a scale-2 display, stock Remmina asks Windows for the window's logical size (about 1159×630) and draws every remote pixel as 2×2, so Windows looks like 200% and slightly blurry. The patched RDP plugin asks for the real pixel size (about 2318×1260) and shows it 1:1, with Windows at 150%: the UI is about 3/4 of its previous size and text is crisp. Resizing the window still resizes the remote desktop, and the remote pointer is shown at HiDPI size. See [HiDPI scaling of the remote screen](#remmina-hidpi).
- **Tabs**: hidden for a single session and shown as rounded segments from two sessions on. Empty space in the tab row also drags the window.

From the repository root, run:

```bash
./scripts/install-remmina-mac.sh
```

The module itself puts the toolbar on top and hides the tab row for a single session, independent of Remmina's preferences. Remmina reads `~/.config/remmina/remmina.pref` only at startup and rewrites it on quit, so a `toolbar_placement` written by the installer can be overwritten. The installer still writes both keys while Remmina is closed, as a fallback when the module is not loaded. After installing, end your remote sessions, run `remmina --quit`, and open Remmina from the app menu. Remmina runs as a single instance, so any process started before installation (including the tray applet) must quit before the new language and look apply. Requires `remmina`, the `zh_CN.UTF-8` locale, and `gcc`, `pkgconf`, `gtk3` and `librsvg` to build the module. The HiDPI RDP plugin also needs `cmake`, `make`, `curl`, `patch` and `freerdp` (already a Remmina dependency); the first install downloads about 4 MB of Remmina source. The look also needs the [macOS Tahoe theme](#install-and-switch) and Hyprland window blur (enabled by the macOS Tahoe theme).

### Implementation

| File | Role |
| --- | --- |
| [`plugins/silky-remmina/silky-remmina.c`](../../plugins/silky-remmina/silky-remmina.c) | GTK3 module loaded only into Remmina. Under a MacTahoe theme it layers the stylesheet below over the current GTK theme and follows `gtk-theme-name` live. Tags the main and connection windows with `.silky-glass` and `.silky-dark` / `.silky-light` and gives them an RGBA visual so the background can be translucent. Reads MacShell's accent from `~/.config/macbar/settings.json` as `@silky_accent`. Paints the main list's selection pill. Identifies connection toolbar buttons by icon name, swaps icons and tooltips, hides or moves them into `⋯`, and adds the traffic lights and title to a horizontal toolbar. Removes itself from `GTK_MODULES` at startup so programs Remmina launches do not load it |
| [`config/remmina/silky-remmina.css`](../../config/remmina/silky-remmina.css) | Glass colours, main window, unified toolbar, traffic lights and tabs. The module reloads it when it changes |
| [`config/remmina/icons/`](../../config/remmina/icons/) | Toolbar line icons: 16×16, 1.25 px round strokes; `currentColor` is replaced with the button's current text colour when drawn |
| [`patches/remmina-1.4.44-rdp-hidpi.patch`](../../patches/remmina-1.4.44-rdp-hidpi.patch) | Touches only the RDP plugin's `plugins/rdp/rdp_event.c`; see [HiDPI scaling](#remmina-hidpi) below |
| [`bin/silky-remmina`](../../bin/silky-remmina) | Installed as `~/.local/bin/silky-remmina`. Sets `LANGUAGE=zh_CN:en` and `LC_MESSAGES=zh_CN.UTF-8`, adds `GTK_PATH` and `GTK_MODULES=silky-remmina` when the module is installed. If the HiDPI plugin was built for a different Remmina version than the installed one, renames it to `remmina-plugin-rdp.so.disabled-<version>` and sends a notification, so an old plugin never loads into a newer Remmina. Then hands off to `remmina-file-wrapper` |
| [`scripts/install-remmina-mac.sh`](../../scripts/install-remmina-mac.sh) | Builds the module in a temporary directory and installs it to `~/.local/share/silky-remmina/gtk-3.0/modules/`, with the stylesheet and icons in `~/.local/share/silky-remmina/`. Copies `org.remmina.Remmina*.desktop` to `~/.local/share/applications/` with every `Exec` rewritten, and rewrites `~/.config/autostart/remmina-applet.desktop`. While Remmina is not running it sets `toolbar_placement=0` (top) and `always_show_tab=false`. Writes only on change and backs up originals as `*.bak.<timestamp>` |

Most Remmina widgets have no CSS names, and rules in the global `~/.config/gtk-3.0/gtk.css` would hit every GTK3 app. The previous version loaded a separate theme through `GTK_THEME`, which froze the appearance at launch: after a light/dark switch Remmina had to restart to follow. The GTK3 module does not pin the theme and only layers styles on top, so it follows live. GTK3 only loads modules by name from a `modules/` directory under `GTK_PATH`, not from an absolute path. GTK3 symbolic icons only refill elements such as `path`, so stroke-based icons cannot use them; the module draws the toolbar icons with librsvg in the current colour instead. The icon widget has no GdkWindow of its own; otherwise it covers the middle of the button and only clicks on the edge respond. The `⋯` menu is destroyed only after it closes: GTK closes a menu before activating the chosen item, so destroying it immediately drops the click.

The module moves a windowed connection toolbar to the first row of Remmina's grid and the session area to the second, so the toolbar sits on top wherever the preferences place it. To keep Remmina's own placement and tab behaviour, set `SILKY_REMMINA_TOOLBAR=native` in `bin/silky-remmina`; then only a horizontal toolbar gets the traffic lights and title, while the trimmed buttons and new icons still apply. Dragging sends `xdg_toplevel.move` through GTK, which Hyprland follows for floating windows; tiled windows stay under Hyprland's tiling layout. GTK3 buttons let their press propagate to parent widgets, so the module starts a drag only from event boxes on the name and the empty space, and skips presses that began on a button or entry; otherwise the compositor takes the pointer, the button never gets its release, and the click is lost. Full screen uses Remmina's own floating toolbar, without traffic lights. Verified only with Remmina 1.4.44 / GTK 3.24. If Remmina renames a toolbar icon, that button keeps its stock look. Remmina runs natively on Wayland, so XWayland plays no part.

<a id="remmina-hidpi"></a>

### HiDPI scaling of the remote screen

In dynamic resolution mode, Remmina 1.4.44's RDP plugin uses the logical size from `gtk_widget_get_allocation()` as the remote resolution and draws it 1:1 in logical pixels. On a Hyprland output at scale 2, GTK then stretches every remote pixel to 2×2. The [patch](../../patches/remmina-1.4.44-rdp-hidpi.patch) only acts in dynamic resolution mode with a GTK scale above 1, and does four things:

- Multiplies the resolution sent to the server by the scale factor, and corrects it once right after connecting
- Reuses Remmina's existing "scaled" path for drawing, redraw regions and pointer coordinates, at exactly 1/2, so the picture is 1:1 and sharp
- Builds the remote pointer cursor at device scale instead of doubling it
- Leaves scale 1, fixed resolution and "scaled" mode unchanged

How large Windows content looks is set by Remmina's "Desktop scale factor %" (Preferences → RDP; `rdp_desktopScaleFactor` in `remmina.pref`, which only applies when `rdp_deviceScaleFactor` is also non-zero). The installer writes `150` and `100` when they are unset and keeps existing values. For smaller content use `125`, for larger `175`; it applies at the next connection without restarting Remmina. Valid values are 100–500, and the device factor only accepts 100, 140 or 180. Both are global and apply to every RDP connection. Windows Server 2012 R2 / Windows 8.1 or later re-lay out the UI for a new scale factor mid-session.

The installer downloads the pinned Remmina 1.4.44 source from GitLab (SHA-256 checked), applies the patch and builds only the `remmina-plugin-rdp` target with the same feature switches as Arch's package (including CUPS printing and libsecret), then installs it as `~/.config/remmina/plugins/remmina-plugin-rdp.so`. Remmina searches that directory first and skips a same-named plugin in `/usr/lib/remmina/plugins/`, so package-managed files stay untouched. The source is cached in `~/.cache/silky-omarchy/remmina-1.4.44/`, and nothing is rebuilt while the patch and version are unchanged. With a Remmina other than 1.4.44 the installer skips this step; `SILKY_REMMINA_HIDPI=0` skips it too, and `SILKY_REMMINA_SCALE=125` picks another factor on first install.

Verified: the patch passes a compiler check and builds without warnings; the new plugin links the same libraries and exports the same symbols as the packaged one; an isolated instance loaded only the plugin from the user directory. Sharpness in a real RDP session, resolution following on window resize and pointer placement are still to be verified.

### Verify

```bash
grep -h '^Exec' ~/.local/share/applications/org.remmina.Remmina.desktop
grep -c libsilky-remmina /proc/"$(pgrep -xn remmina)"/maps
grep -E '^(toolbar_placement|always_show_tab)=' ~/.config/remmina/remmina.pref
grep -o '/[^ ]*remmina-plugin-rdp.so' /proc/"$(pgrep -xn remmina)"/maps | sort -u
grep -E '^rdp_(desktop|device)ScaleFactor=' ~/.config/remmina/remmina.pref
```

Expected: every `Exec` points to `~/.local/bin/silky-remmina`, and the module appears in the process maps (count above 0). The two preferences are only a fallback: even with `toolbar_placement=3` the toolbar should be on top. After opening a connection, the top of the window shows traffic lights, the connection name and thin line icons, and `⋯` lists the moved actions. Switching light/dark in MacShell updates the solid profile-list background and the glass on the header and session toolbar. The RDP plugin path should be `~/.config/remmina/plugins/remmina-plugin-rdp.so`, and the scale preferences `rdp_desktopScaleFactor=150` and `rdp_deviceScaleFactor=100`. Once connected, right-click the remote desktop → Display settings: the resolution should be about the window's real pixel size (twice its logical size), scale 150%, with crisp text.

Verified in an isolated instance (separate D-Bus and config directory, a WWW-protocol test connection): module loading, top toolbar, trimmed buttons and `⋯` menu, line icons, main-window glass and selection pill, a live switch from dark to light, and a top toolbar despite a left-toolbar preference. A real RDP session and the Hyprland blur on hardware are still to be verified.

### Rollback

```bash
remmina --quit
rm ~/.local/share/applications/org.remmina.Remmina.desktop ~/.local/share/applications/org.remmina.Remmina-file.desktop
rm -r ~/.local/share/silky-remmina ~/.local/bin/silky-remmina
rm ~/.config/remmina/plugins/remmina-plugin-rdp.so ~/.config/remmina/plugins/.silky-hidpi
```

To roll back only the HiDPI plugin, run just the last command; Remmina loads the packaged plugin on its next start. Then set Desktop scale factor back to 0 under Preferences → RDP, or delete `rdp_desktopScaleFactor` and `rdp_deviceScaleFactor` from `remmina.pref`. The source cache in `~/.cache/silky-omarchy/remmina-1.4.44/` can be deleted. Then restore the `~/.config/autostart/remmina-applet.desktop.bak.*` reported by the installer as `remmina-applet.desktop`. To get the left toolbar and always-visible tabs back, copy the `~/.config/remmina/remmina.pref.bak.*` backup over `remmina.pref`, or change them under Remmina Preferences → Appearance. `~/.local/share/themes/Silky-Remmina-{Dark,Light}` from the previous version is no longer used and can be deleted. Reopen Remmina.

## Traffic-light title bar

Omarchy already adds title bars to windows on floating workspaces: `default/hypr/workspace-modes.lua` loads its own plugin `omarchy-hyprland-titlebars` (`/usr/lib/omarchy-hyprland-titlebars/titlebars.so`, based on hyprbars) with three square buttons × □ − on the right (`button_rounding = 0`). Under the macOS Tahoe themes it becomes:

- The 30 px bar keeps the title centred and lets some of the wallpaper or the window behind show through in both appearances. The background is about 80% opaque when focused and 84% when unfocused. The bar also blurs its backdrop when Hyprland has global blur enabled.
- Three **round** buttons at the top left, 12 px across and 8 px apart, in `#ff5f57`, `#febc2e`, and `#28c840`
- The × − + symbols appear only when the pointer is over the lights; the lights turn grey when the window loses focus
- Red closes the window and yellow minimizes it to the Dock. For Foot and the four system apps below, green toggles full screen and double-clicking empty title-bar space toggles maximize.
- The bar is used on windows that Hyprland decorates, including Foot, the other configured terminals, and the four system apps below. Apps with client-side controls keep their own decorations.

### Implementation

| File | Role |
| --- | --- |
| `config/hypr/silky-titlebar-guard.lua` | Comes **before** `require("default.hypr.omarchy")` in `hyprland.lua`. hyprbars buttons can only be added, never removed, so under the macOS theme `hl.plugin.hyprbars.add_button` is replaced with a no-op and Omarchy's three square buttons never get added; the original function is kept as `silky_add_button` |
| `config/hypr/silky-macos.lua` | Comes after Omarchy's defaults, overrides the title-bar style, adds the three round buttons with the original function, and sets `hyprbars:no_bar` rules from an allow list |

These settings apply only once Omarchy has loaded the title-bar plugin (some workspace is in floating mode); otherwise they are skipped, so there is no `unknown field 'hyprbars:no_bar'` config error. hyprbars is no longer built here, so nothing needs rebuilding after a Hyprland update.

The theme installer above updates the [title bar configuration](../../config/hypr/silky-macos.lua) and reloads Hyprland. To verify the effect, overlap two Foot windows in a floating workspace and switch focus to see the lower window’s colour through the bar. To revert just this effect, restore the `~/.config/hypr/silky-macos.lua.bak.*` reported by the installer, or restore opaque bar colours and set `bar_blur` to `false`, then run `hyprctl reload`.

<a id="system-app-audit"></a>

### System app window updates

| App | Change |
| --- | --- |
| Calculator, Omacut, Write, Media Viewer | Floating windows use the shared 30 px title bar. Yellow minimizes to the Dock through MacShell, green matches `Super+F`, and the top-left overlay exits full screen. Right-click or hold green to open the half-screen and corner layouts. The menu and drag preview honor the app’s size limits and the available space on the display. |
| Omalogi | The standalone mouse editor uses a solid background and the shared title bar. [Standalone window](14-omalogi.md#a-real-window) |
| WeChat | Chat and list content retain their original colors at full opacity. The compositor gradient outline was removed from the main window. Update the [WeChat configuration](01-touchpad-gestures.md#touchscreen-scrolling-in-wechats-conversation-list) and reload Hyprland. |
| AccessClient’s PuTTY | The XWayland console uses a solid background. Use the [shortcuts installer](10-shortcuts.md#install) to update `silky-app-windows.lua`, reload, and check a floating SSH console. |
| Nautilus, Remmina | [Nautilus](#frosted-glass-in-files) uses a solid file-area background with glass on auxiliary surfaces. [Remmina](#remmina) uses a solid connection list with glass on the header and session toolbar. Reopen Remmina from the launcher after updating its style. |

The four system apps keep their Omarchy app IDs and launchers. Use the Silky Gestures plugin built for Hyprland 0.57.2 and an existing Folio/MacShell integration. Update the theme’s title-bar configuration, back up and replace `~/.config/hypr/silky-folio.lua`, then run from the repository root:

```bash
./scripts/install-silky-gestures.sh
python3 scripts/tune-folio-macshell.py ~/.config/quickshell/MacShell --backup
hyprctl reload
hyprctl configerrors
qs -c MacShell ipc call macshell reload
```

[Silky Gestures](../../plugins/silky-gestures/foot-layout.hpp) reads the window size limits, and the [Hyprland configuration](../../config/hypr/silky-folio.lua) computes the preview and placement with space for the 30 px compositor title bar. With the layout plugin unavailable, the four new title-bar users still enter full screen via the compositor and can exit with `Super+F`.

Open each system app from its launcher and check green right-click, press and hold, `Esc`, click, and the exit overlay in the top left. Areas smaller than the window’s minimum are disabled and the drag preview skips them. Minimize and restore from the Dock, then compare the window and its position. For WeChat, PuTTY, Nautilus, and Remmina, overlap a window containing high-contrast text and check the chat, terminal, file, or connection area.

Checked on Hyprland 0.57.2 with a 2×, 90 Hz internal display and in an isolated 1472×920 Wayland session. Simulated input covered the shared menus and full-screen paths, all eight Foot placements, Media Viewer drag snapping, and disabled slots in Write. MacShell’s Dock IPC restored Calculator to the same window, workspace, and geometry. An isolated Remmina instance and a GTK4 Nautilus style fixture were checked against a saturated backdrop in both appearances. The WeChat and PuTTY rules were tested with windows using their class names. Physical touch, external displays, and a live RDP session remain to be checked.

To roll back, restore the title-bar, plugin, MacShell, and `silky-folio.lua` backups. Reload Hyprland and MacShell and sign back in to load the previous plugin. Restore WeChat, PuTTY, and GTK styles from the backups in their installation sections. To roll back only the Remmina style, restore `~/.local/share/silky-remmina/silky-remmina.css.bak.*` and reopen the app.

### Pitfalls

- An early version built and loaded a separate upstream hyprbars on top of Omarchy's: every window had two rows of buttons, the buttons were square, and it looked "loaded twice"
- Unloading one of them in a running session also unregisters rule names such as `hyprbars:no_bar`; the config then keeps erroring until you log in again

## Verify

```bash
omarchy theme current
gsettings get org.gnome.desktop.interface gtk-theme
gsettings get org.gnome.desktop.wm.preferences button-layout
qs -c MacShell ipc call appearance get
hyprctl plugin list | grep -c hyprbars
hyprctl configerrors
```

Expected: the theme is `Macos Tahoe Dark`, GTK theme `MacTahoe-Dark`, button layout `close,maximize:`, MacShell answers `dark`, `hyprctl -j plugin list` has exactly one hyprbars (Omarchy's), and there are no config errors.

Confirmed on real hardware: theme switching, Finder-style Nautilus (blue folders, glass sidebar, traffic lights), window corners and shadows, MacShell light/dark sync.

**Still to verify**: the traffic-light title bar on floating windows needs confirming in a clean session. Unloading a duplicate hyprbars instance in a running session unregisters its window-rule names, after which the config reports `unknown field 'hyprbars:no_bar'`, which the config cannot catch; only logging in again helps. To prevent loading it twice at boot, the load command runs under `flock` and only when `hyprctl plugin list` does not list hyprbars yet.

## Rollback

```bash
omarchy theme set tokyo-night
```

After switching to any other theme the hook restores GTK, the button layout and the pointer. To remove everything:

- Delete `~/.config/omarchy/themes/macos-tahoe-*` and `~/.config/omarchy/backgrounds/macos-tahoe-*`
- Delete `~/.config/omarchy/hooks/theme-set.d/silky-macos`
- Remove `require("hypr.silky-titlebar-guard")` and `require("hypr.silky-macos")` from `hyprland.lua`, and those two files
- Delete `~/.local/share/themes/MacTahoe-*`
