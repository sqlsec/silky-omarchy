# 15 · Obsidian: macOS 27 theme, file icons and smooth typing

[简体中文](../15-obsidian.md) | English

## What it does

Obsidian gets a macOS 27 look and follows the desktop's light / dark mode:

- **Light / dark follows the system.** The theme is set to "Adapt to system". When Omarchy switches between `macos-tahoe-light/dark`, or you switch the appearance in MacShell, Obsidian follows immediately without a restart.
- **Native compositor-blurred sidebar & solid editor.** Matching Files (Folio) and Foot, the sidebars and ribbon run edge-to-edge as live Hyprland frosted glass (`rgba(38, 38, 42, 0.77)` dark / `rgba(242, 242, 245, 0.83)` light) that blurs the actual desktop and windows behind Obsidian, while the main editor pane and tab bar stay fully opaque (`#1c1c1e` dark / `#ffffff` light) for crisp reading and writing. Context menus, the command palette, modals, hover previews, tooltips and the status bar remain frosted glass. In fullscreen the sidebar switches to a solid surface.
- **Finder-style file tree.** Folders are macOS blue folders and switch to an open folder when expanded. Each extension has its own icon: notes, plain text, Canvas, Base, PDF, Word / WPS, spreadsheets, presentations, images, SVG, audio, video, archives, web links, and code files such as JS / TS / Python / Shell / JSON / CSS / HTML / Lua / YAML / Rust / Go / C. Code files show a small dark terminal with red / yellow / green dots. The selected row is filled with the accent colour, as in Finder's sidebar.
- **Smooth typing.** The caret glides between positions instead of jumping, and fades in and out instead of blinking hard. The companion plugin Silky Typing fades each new character in with a slight blur and an accent glow. Text committed from an input method such as Pinyin fades in as a whole.
- **Code blocks look like a macOS Terminal window**: dark glass, red / yellow / green dots in the top left, the language name centred in the title bar, and Xcode Default (Dark) syntax colours. Code blocks stay dark in both modes. Inline code is a light pill that follows the appearance.
- **Window buttons & layout (matching Folio and Foot).** Top-left traffic lights use 12 px solid circles, 8 px gap, an 8 × 8 px symbol canvas and 1.1 px round-cap strokes, dim to grey when unfocused, and restore colour with glyphs on hover. No empty space is reserved on the right.
  - Red closes the current window (preserving Obsidian's native close handling).
  - Yellow minimises to the MacShell Dock and restores the same window, workspace, position and size from its Dock thumbnail (falls back to `omarchy-hyprland-window-minimize` when MacShell is not running).
  - Green single-click toggles true fullscreen like `Super+F`, revealing the shared top-left hover control strip (greyed yellow light, inward-chevron green light) to exit fullscreen. Right-click or press-and-hold (≥ 350 ms) opens the shared MacShell 2-row window layout menu (four halves and four corners) with live blue snap preview and menu bar / Dock clearance.
  - Double-clicking empty titlebar space toggles maximised state; dragging empty titlebar space to the left or right screen edge triggers the shared blue half/corner snap preview and drops into place on release.
  - Window background alpha and traffic-light actions require the Silky Window Controls plugin.
- Other details: Apple system colours and font stack (`-apple-system`, Inter, Noto Sans CJK SC; SF Mono / JetBrainsMono Nerd Font for code). Switches are iOS-style, task checkboxes are round like Reminders, scrollbars only appear on hover, and menus and modals pop in with a short animation. Turning on the system's reduced-motion setting disables all animations.

## Install

```bash
./scripts/install-obsidian-theme.sh                  # every vault listed in ~/.config/obsidian/obsidian.json
./scripts/install-obsidian-theme.sh ~/Notes          # only the given vaults
./scripts/install-obsidian-theme.sh --no-plugin      # theme only, no typing fade
```

Run it from the repository root. It needs `python3`. For each vault the script:

| Action | Location |
| --- | --- |
| Copies the theme | `<vault>/.obsidian/themes/Silky macOS/` (from [`config/obsidian/themes/Silky macOS/`](../../config/obsidian/themes/Silky%20macOS/)) |
| Copies the plugins | `<vault>/.obsidian/plugins/silky-typing/` and `<vault>/.obsidian/plugins/silky-window-controls/` (from [`config/obsidian/plugins/`](../../config/obsidian/plugins/)) |
| Enables the theme and follows the system | `<vault>/.obsidian/appearance.json`: `"cssTheme": "Silky macOS"`, `"theme": "system"`; other keys are kept |
| Registers the plugins | adds `silky-typing` and `silky-window-controls` to `<vault>/.obsidian/community-plugins.json` |
| Fixes the launcher entry | `~/.local/share/applications/obsidian.desktop`: a copy of the system `obsidian.desktop` with only `StartupWMClass` changed to `md.obsidian.Obsidian`. An existing user-level entry is first backed up to `~/.local/state/silky-omarchy/obsidian/obsidian.desktop.backup` |
| Hyprland live blur rule | `~/.config/hypr/silky-obsidian.lua` (from [`config/hypr/silky-obsidian.lua`](../../config/hypr/silky-obsidian.lua)) and appends `require("hypr.silky-obsidian")` to `~/.config/hypr/hyprland.lua` |
| Backs up on the first run | the original `appearance.json` and `community-plugins.json` go to `~/.local/state/silky-omarchy/obsidian/<vault-path-hash>/` |

It is safe to run again. Later runs only update the theme, plugins and Hyprland rule while keeping the first backup. To also wire Dock minimisation, the fullscreen exit strip and the 8-slot layout menu, copy [`config/hypr/silky-folio.lua`](../../config/hypr/silky-folio.lua) into `~/.config/hypr/` and run:

```bash
python3 scripts/tune-folio-macshell.py ~/.config/quickshell/MacShell --backup
hyprctl reload
qs -c MacShell ipc call macshell reload
```

A running Obsidian picks up theme changes without a restart; restart Obsidian (or toggle the plugin off and on) after updating plugins. Both plugins must be enabled once per vault: **Settings → Community plugins → turn off Restricted mode, then make sure "Silky Typing" and "Silky Window Controls" are on**. Obsidian keeps that switch in its own localStorage and treats it as a security setting, so the script leaves it to you. Without the plugins, the caret glide, soft blink and button look still work, but window alpha and Hyprland button actions are inactive. `--no-plugin` installs the theme without either plugin.

Optional settings:

- To see docx, xlsx, zip and similar files in the file tree with their icons, turn on **Settings → Files and links → Detect all file extensions**. By default Obsidian only lists types it can open.
- The default accent is Apple blue. If you pick another colour under **Settings → Appearance → Accent color**, selected rows, the caret, switches and the typing glow all follow it.

## Implementation

| File | Role |
| --- | --- |
| [`theme.css`](../../config/obsidian/themes/Silky%20macOS/theme.css) | The whole theme: light / dark variables, edge-to-edge glass sidebars, solid editor, 12 px traffic lights (with unfocused dimming), file tree, caret and terminal code blocks |
| [`build-icons.py`](../../config/obsidian/build-icons.py) | Draws every file and folder icon in Python (SVG, no third-party artwork) and writes them into `theme.css` as data URIs between `@silky-icons-start` and `@silky-icons-end`. After changing an icon or adding an extension, run `python3 config/obsidian/build-icons.py` |
| [`silky-typing/main.js`](../../config/obsidian/plugins/silky-typing/main.js) | CodeMirror 6 extension that adds a `silky-typed` mark to newly typed characters and removes it after 260 ms |
| [`silky-typing/styles.css`](../../config/obsidian/plugins/silky-typing/styles.css) | Fallback fade animation for when the Silky macOS theme is not active |
| [`silky-window-controls/main.js`](../../config/obsidian/plugins/silky-window-controls/main.js) | Sets the Electron window background to `#00000000`, syncs unfocused dimming, and handles yellow Dock minimisation, green fullscreen + right-click/hold layout menu, titlebar double-click maximise, and edge-drag snap |
| [`silky-obsidian.lua`](../../config/hypr/silky-obsidian.lua) | Hyprland window rule enabling live compositor blur for `md.obsidian.Obsidian` (`opacity = "0.995 override 0.995 override 1.0 override"`, `xray = false`, `border_size = 0`) |
| [`silky-folio.lua`](../../config/hypr/silky-folio.lua) & [`FootWindowLayout.qml`](../../config/macshell/FootWindowLayout.qml) | Connects `md.obsidian.Obsidian` to the shared MacShell Dock minimisation, fullscreen exit hover bar, 2-row layout menu and blue snap preview |
| [`install-obsidian-theme.sh`](../../scripts/install-obsidian-theme.sh) | Install, backup and `--remove` |

Key points:

- **Live compositor sidebar blur with a solid editor.** Obsidian's built-in "Translucent window" switch is macOS-only, but on native Wayland Electron still exposes per-pixel alpha once `BrowserWindow.setBackgroundColor("#00000000")` is called via `@electron/remote`. Because Chromium marks `wl_surface.opaque_region` full-window, Hyprland skips its blur pass at exact `1.0` opacity; [`silky-obsidian.lua`](../../config/hypr/silky-obsidian.lua) sets `0.995 override` with `xray = false` and `border_size = 0` so Hyprland blurs the translucent sidebar in real time with clean corners while the solid editor pane remains visually opaque. Fullscreen stays `1.0 override`.
- **Light / dark signal chain.** Omarchy's `omarchy-theme-set-gnome` and MacShell both write `org.gnome.desktop.interface color-scheme`. `xdg-desktop-portal-gtk` passes it to Electron as `prefers-color-scheme`, and in "Adapt to system" mode Obsidian switches between `body.theme-light` and `body.theme-dark`. This is the same signal used by [11 · Menu glass](11-menu-glass.md) and [09 · Candidate window](09-wowtype-glass.md).
- **File icons.** Obsidian writes `data-path` on every row of the file tree. The theme matches extensions with selectors such as `.nav-file-title[data-path$=".pdf" i]` and draws the icon in `.nav-file-title-content::before`, so renaming a file never edits the icon into its name.
- **Caret glide.** Obsidian 1.15 draws its own caret with CodeMirror's `drawSelection`. When the caret moves, CodeMirror reuses the same `.cm-cursor` element and only changes its `left` / `top`, so a 90 ms transition on those properties makes it glide. The blink animation was a hard `steps(1)` switch and now uses an easing curve.
- **Typing fade and input methods.** The plugin only handles `input.type` events and only marks insertions of 8 characters or fewer, so pastes and snippet completions are left alone. Each mark carries a unique attribute so CodeMirror does not merge neighbouring marks, which would replay the animation on earlier characters. While an input method is composing (preedit), the plugin does not touch the DOM at all, because doing so breaks Chromium's IME handling. Text inserted during composition is tracked and faded in after `compositionend`. If a mark expires while a composition is active, its removal waits until the composition ends.

Known limitations:

- Code blocks in Reading view don't expose the language name, so their title bar only shows the dots. The Live Preview title bar shows the language.
- **Window button and layout takeover.** Obsidian's native maximise request is dropped by Omarchy's default `suppress_event = "maximize"` rule, and Electron's internal state drifts from Hyprland's. The plugin intercepts clicks in the capture phase and routes them through `hyprctl` and MacShell IPC for Dock minimisation, true fullscreen toggling, the 2-row 8-slot layout menu (right-click or ≥ 350 ms hold on green), titlebar double-click maximise, and edge-drag snap. Target windows are matched by main PID and title using `address:`, so other focused windows are never touched. Outside Hyprland the plugin does nothing.
- **Window button placement.** Obsidian reserves room for window buttons with `--frame-right-space` on Linux / Windows and `--frame-left-space` on macOS. The theme swaps them (78 px left, 0 right), moves `.titlebar-button-container.mod-right` to the top-left corner (12 px solid circles, 8 px gap, no dark inner shadow), and renders centred ×, − and + glyphs on an 8 × 8 px canvas with 1.1 px round-cap strokes. In fullscreen, the built-in lights hide and the shared MacShell `FootWindowLayout` top-left hover bar provides exit controls. Right-to-left (RTL) systems are left unchanged.
- **The Dock icon keeps bouncing and the window doesn't open.** Obsidian 1.15's native Wayland window has the app id `md.obsidian.Obsidian`, but the packaged `obsidian.desktop` says `StartupWMClass=obsidian`. MacShell's Dock therefore doesn't recognise the open window and shows no running dot under the icon. Clicking the icon starts another process, which hands the request to the running Obsidian and exits, while the Dock keeps waiting for a new window, so the icon keeps bouncing. If the existing window is hidden behind other windows, it looks as if Obsidian won't open. The user-level entry written by the install script corrects `StartupWMClass`, so Quickshell's `DesktopEntries.heuristicLookup` can match the window to the icon. The entry carries an `X-Silky-Omarchy=obsidian-wmclass` line, and rollback only deletes a file with that marker.
- On this machine, `~/.config/obsidian/user-flags.conf` contains `-disable-gpu`, so Obsidian composites in software. Blur is only used on menus, the command palette, the sidebars and similar areas, and its CPU cost has not been measured. Without that flag the GPU handles the blur, which uses less CPU.
- In Live Preview, the first and last lines of a code block are the ```` ``` ```` fence lines. They appear below the terminal title bar when the cursor is inside the block.

## Verify

Verified on Obsidian 1.15.1 (aarch64, native Wayland window, Electron's bundled Chromium):

- **Isolated test**: a separate Obsidian instance started with `--user-data-dir` on a temporary test vault, inspected over the DevTools protocol. `cssTheme` was `Silky macOS` and screenshots in both modes looked right. `.cm-cursor` had a `transition` covering `left` / `top`, and `.cm-cursorLayer` used `cubic-bezier(0.45, 0, 0.55, 1)`. Simulated typing produced one `.silky-typed` mark per character. During a simulated Pinyin composition (`ni` → `nihao`) no new marks were added, and the committed 「你好」 was marked afterwards. All marks were gone after about 0.7 s and the text was unchanged.
- **On this machine**: after the install script ran on the two local vaults, the running Obsidian switched to the floating glass sidebar without a restart. The typing fade only works once Restricted mode is off, and still needs to be confirmed on the real vaults.

The macOS redesign was also verified in an isolated instance (Hyprland 0.57.2, MacShell 0.5.3, Obsidian 1.15.1, 2× scale internal display):

- **Visuals & blur**: with the theme and Silky Window Controls enabled, the left sidebar and vault footer run edge-to-edge with live Hyprland frosted blur, while the editor pane and tab bar stay fully solid (`#1c1c1e`). The top-left traffic lights are 12 px solid circles with 8 px spacing and dim to grey when the window loses focus (e.g. when a menu opens).
- **Window state & layout**: `o.silky_foot_fullscreen` toggled between `fullscreen = 2` and `0`; right-clicking green opened the 2-row 8-slot layout menu right below the button; placing left-half snapped cleanly to `[0, 23] 736×822` (clearing the 23 px menu bar and Dock); `qs -c MacShell ipc call window minimizeFoot <address>` returned `true` and `restore` returned the same window to its original workspace and geometry `[0, 23] 736×822`.

Not yet verified: light mode on-device pass, physical touchscreen hold on the green light, mixed-DPI multi-monitor placement, and Obsidian popout windows.

## Roll back

```bash
./scripts/install-obsidian-theme.sh --remove           # every registered vault
./scripts/install-obsidian-theme.sh --remove ~/Notes   # the given vaults
```

The script deletes `themes/Silky macOS/`, `plugins/silky-typing/` and `plugins/silky-window-controls/`, deletes the marked `~/.local/share/applications/obsidian.desktop` (restoring the backup if there was a user-level entry before), removes `~/.config/hypr/silky-obsidian.lua` and its `require("hypr.silky-obsidian")` line in `~/.config/hypr/hyprland.lua`, then restores `appearance.json` and `community-plugins.json` from the backup in `~/.local/state/silky-omarchy/obsidian/<hash>/`. If you also updated `silky-folio.lua` and MacShell's `FootWindowLayout.qml`, restore their `.bak.*` backups and run `hyprctl reload` plus `qs -c MacShell ipc call macshell reload`. If the two JSON files didn't exist before, they are deleted and Obsidian switches back to the previous theme on its own. To return to the default look but keep the files, pick "Default" under **Settings → Appearance → Themes**.

Note: `--remove` restores those two files to how they were before the first install, so any other appearance changes made since then (font size, for example) are undone too.
