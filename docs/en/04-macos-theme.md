# 04 · macOS Tahoe theme (dark / light)

[简体中文](../04-macos-theme.md) | English

## Goals

- Two Omarchy themes, `macos-tahoe-dark` and `macos-tahoe-light`, with colours from Apple's system palette
- Windows that feel like macOS: hairline borders, continuous-curvature rounded corners, a soft deep shadow under the focused window, glass blur behind translucent surfaces
- MacTahoe icons: blue folders, macOS-style app icons
- The file manager (Nautilus) looks like Finder: translucent sidebar, traffic lights at the top left, Space for Quick Look (sushi)
- Floating windows get a macOS traffic-light title bar: close, full screen
- Switching theme also switches the GTK look, the pointer and MacShell's light/dark appearance

## Parts

| Part | File | Notes |
| --- | --- | --- |
| Colours | `themes/macos-tahoe-*/colors.toml` | Apple system colours. The light variant uses high-contrast terminal colours, otherwise yellow and green are unreadable on white |
| Window look | `themes/macos-tahoe-*/hyprland.lua` | 1 px translucent border, 14 px corners (`rounding_power = 2.6` is close to Apple's continuous curvature), shadow, 3 blur passes |
| Icons | `themes/macos-tahoe-*/icons.theme` | `Silky-MacTahoe-dark` / `Silky-MacTahoe-light` (inherit MacTahoe, unify the sidebar symbolic icons) |
| GTK / Finder | MacTahoe GTK theme | The upstream prebuilt release, no sassc needed |
| Sync | `hooks/theme-set-silky-macos` | Omarchy theme-set hook |
| Traffic lights | `config/hypr/silky-titlebar-guard.lua` + `config/hypr/silky-macos.lua` | Turns Omarchy's floating-window title bar into round traffic lights |

All third-party parts are pinned to specific commits (see the top of `scripts/install-macos-theme.sh`), so every install gives the same result:

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

Nautilus softens windows and wallpaper behind it into broad patches of color. The sidebar lets more color through and has a thin highlight along its edge. The file area uses a denser tint to keep names and icons readable.

The theme installer writes the [GTK 4 overlay](../../config/gtk-4.0/nautilus-glass.css) into `~/.local/share/themes/Silky-MacTahoe-{Dark,Light}/gtk-4.0/`. If the base MacTahoe GTK theme is installed, run `./scripts/install-macos-theme.sh --no-icons --no-gtk --no-bars` from the repository root to update it. With either macOS Tahoe theme active, save your work, quit the Nautilus process, and reopen Files. Background blur requires GTK's Wayland background effects support and Hyprland with blur enabled. Tested with Nautilus 51.1, GTK 4.24.1, and Hyprland 0.57.2.

To check the effect, overlap Files with another window containing text. The sidebar should pick up the colors while softening the text behind it, and filenames should stay crisp. To revert the glass styling, restore the corresponding `gtk.css.bak.*` and `gtk-dark.css.bak.*` backup files printed by the installer, then quit and reopen Nautilus.

Icon tweaks made earlier with ChatGPT are folded into the installer:

- Icon aliases for Omarchy's bundled apps: `omacalc → calc`, `omawrite → text-editor`, `omarchy-discord → discord`
- MacTahoe redraws the ChatGPT and Claude icons. The script renames those two aliases to `*.mactahoe-backup` so the vendors' official icons are used
- ChatGPT's official icon has different transparent padding from MacTahoe's, so `dockIconScale()` in the MacShell patch draws it 4% smaller in the Dock; Claude is now redrawn on the standard tile, so its factor is 1.0
- `scripts/tune-app-icons.py` brings every other launcher app into the MacTahoe style. Its output goes straight into `MacTahoe/apps/scalable`, so the Applications panel, Dock and Spotlight all use it:
  - Utilities and Omarchy's own apps link to the matching macOS icon, e.g. `imv → accessories-image-viewer`, `omacut → VideoTrimmer`, `hype → Keynote`, `gliff → remote-desktop`, `signed → PDF`, `monologue → Photo Booth`, `LimineSnapperSync → timeshift`, `wemeetapp → meeting`, `zoom → Zoom`
  - Branded apps (Claude, HEY, Superwhisper, WorkBuddy, xiezuo, Basecamp, Netcatty, Clippy, WowType, Google Messages, …) keep their logo, redrawn on MacTahoe's exact tile: 442 px on a 512 canvas, corner radius 100, with the shadow taken from the set's own Zoom icon. Round logos and bare glyphs sit on a light tile
  - Local `.desktop` files that pointed at hand-made PNGs now use the theme icon name
  - After installing a new app, run `python3 scripts/tune-app-icons.py` again. An app with no mapping yet needs an entry in the script's `ALIASES` or `BRANDS` first
- MacShell's Dock and Spotlight read the icon theme from `QS_ICON_THEME` in `~/.config/macshell/env`

<a id="foot-glass"></a>

## Frosted glass in Foot

Dark mode uses a smoky violet background and light mode uses frosted white. Foot applies transparency to the default background and keeps text crisp. When MacShell Appearance switches to Light, Dark, or Auto, Foot windows that have loaded the glass palettes follow the system appearance. Floating windows retain the existing traffic-light title bar.

From the repository root, run:

```bash
./scripts/install-foot-glass.sh
foot --check-config
systemctl --user is-active silky-foot-glass.service
```

The installer backs up `~/.config/foot/foot.ini` and adds the [glass palettes](../../config/foot/silky-glass.ini) and startup appearance settings. This requires Foot with dual palettes and background blur support (verified on 1.28.0) and Hyprland with blur enabled, as in the macOS Tahoe themes. The user service watches `org.gnome.desktop.interface color-scheme`, sets the appearance for new windows, and tells running Foot processes to switch palettes.

Open a fresh Foot window in front of a colorful wallpaper or window, then switch between Light and Dark in MacShell and observe the background and text in the same window. Windows opened before installation need reopening to load the palettes. If you use `foot --server`, restart its process after the existing sessions finish so new clients can load the glass palettes.

To roll back, run `systemctl --user disable --now silky-foot-glass.service`, restore the contents of the backup printed by the installer to `~/.config/foot/foot.ini`, and open a new Foot window.

<a id="remmina"></a>

## Remmina in Simplified Chinese with a macOS look

Remmina 1.4.44 ships a Simplified Chinese translation, but the system language is `en_US`, so the interface stayed in English. After installation, Remmina shows Simplified Chinese menus, column headers and dialogs whether you open it from the launcher, the Dock, an `rdp://` link or the tray applet. Under the macOS Tahoe theme you also get:

- **MacShell glass**: the main window and remote connection windows have translucent backgrounds that Hyprland blurs. Dark is smoky `#1c1c1e`, light is frosted `#f6f6f8`, a little more opaque than the menus so text stays crisp. The remote desktop picture itself stays opaque.
- **Live light / dark**: switching appearance in MacShell or with `omarchy theme set` restyles open Remmina windows immediately, without a restart.
- **Main window**: borderless title bar buttons with a rounded plate on hover. The connection list has no grid lines, and the selected row is a rounded pill inset from the edges, in MacShell's accent colour, turning light grey when the window loses focus. The quick-connect bar, column headers and footer use small secondary text.
- **Remote connection window**: the toolbar moves from the left edge to the top, forming a unified title bar. Traffic lights and the connection name sit on the left. Dragging the name or any empty toolbar space moves a floating window directly, without holding `Super`; double-clicking maximizes it. The tools on the right use a thin 16 px line icon set, and tooltips say what each tool does in plain words, such as "Resize remote screen with window" or "Send key combination", keeping Remmina's shortcut hint. Active toggles (full screen, scaling, keyboard capture…) show in the accent colour.
- **Trimmed toolbar**: connection list, fit window, full screen, dynamic resolution, scaling, keyboard capture, screenshot and disconnect stay visible. Duplicate connection, view only, invert scrolling, edit connection settings, minimize and reconnect move into a `⋯` menu. Plugin menus the current protocol does not offer (quality options, remote actions, send key combination) hide themselves, and separators are gone.
- **Tabs**: hidden for a single session and shown as rounded segments from two sessions on. Empty space in the tab row also drags the window.

From the repository root, run:

```bash
./scripts/install-remmina-mac.sh
```

The installer only edits `~/.config/remmina/remmina.pref` while Remmina is not running, because Remmina rewrites that file when it quits. If Remmina was running, end your remote sessions, run `remmina --quit`, run the installer again, then open Remmina from the app menu. Remmina runs as a single instance, so any process started before installation (including the tray applet) must quit before the new language and look apply. Requires `remmina`, the `zh_CN.UTF-8` locale, and `gcc`, `pkgconf`, `gtk3` and `librsvg` to build the module. The look also needs the [macOS Tahoe theme](#install-and-switch) and Hyprland window blur (enabled by the macOS Tahoe theme).

### Implementation

| File | Role |
| --- | --- |
| [`plugins/silky-remmina/silky-remmina.c`](../../plugins/silky-remmina/silky-remmina.c) | GTK3 module loaded only into Remmina. Under a MacTahoe theme it layers the stylesheet below over the current GTK theme and follows `gtk-theme-name` live. Tags the main and connection windows with `.silky-glass` and `.silky-dark` / `.silky-light` and gives them an RGBA visual so the background can be translucent. Reads MacShell's accent from `~/.config/macbar/settings.json` as `@silky_accent`. Paints the main list's selection pill. Identifies connection toolbar buttons by icon name, swaps icons and tooltips, hides or moves them into `⋯`, and adds the traffic lights and title to a horizontal toolbar. Removes itself from `GTK_MODULES` at startup so programs Remmina launches do not load it |
| [`config/remmina/silky-remmina.css`](../../config/remmina/silky-remmina.css) | Glass colours, main window, unified toolbar, traffic lights and tabs. The module reloads it when it changes |
| [`config/remmina/icons/`](../../config/remmina/icons/) | Toolbar line icons: 16×16, 1.25 px round strokes; `currentColor` is replaced with the button's current text colour when drawn |
| [`bin/silky-remmina`](../../bin/silky-remmina) | Installed as `~/.local/bin/silky-remmina`. Sets `LANGUAGE=zh_CN:en` and `LC_MESSAGES=zh_CN.UTF-8`, adds `GTK_PATH` and `GTK_MODULES=silky-remmina` when the module is installed, then hands off to `remmina-file-wrapper` |
| [`scripts/install-remmina-mac.sh`](../../scripts/install-remmina-mac.sh) | Builds the module in a temporary directory and installs it to `~/.local/share/silky-remmina/gtk-3.0/modules/`, with the stylesheet and icons in `~/.local/share/silky-remmina/`. Copies `org.remmina.Remmina*.desktop` to `~/.local/share/applications/` with every `Exec` rewritten, and rewrites `~/.config/autostart/remmina-applet.desktop`. While Remmina is not running it sets `toolbar_placement=0` (top) and `always_show_tab=false`. Writes only on change and backs up originals as `*.bak.<timestamp>` |

Most Remmina widgets have no CSS names, and rules in the global `~/.config/gtk-3.0/gtk.css` would hit every GTK3 app. The previous version loaded a separate theme through `GTK_THEME`, which froze the appearance at launch: after a light/dark switch Remmina had to restart to follow. The GTK3 module does not pin the theme and only layers styles on top, so it follows live. GTK3 only loads modules by name from a `modules/` directory under `GTK_PATH`, not from an absolute path. GTK3 symbolic icons only refill elements such as `path`, so stroke-based icons cannot use them; the module draws the toolbar icons with librsvg in the current colour instead.

The traffic lights and title appear only on a horizontal toolbar (`toolbar_placement=0` or `2`). If you move the toolbar back to the left or right in Remmina's preferences, the trimmed buttons and new icons still apply. Full screen uses Remmina's own floating toolbar, without traffic lights. Verified only with Remmina 1.4.44 / GTK 3.24. If Remmina renames a toolbar icon, that button keeps its stock look. Remmina runs natively on Wayland, so XWayland plays no part.

### Verify

```bash
grep -h '^Exec' ~/.local/share/applications/org.remmina.Remmina.desktop
grep -c libsilky-remmina /proc/"$(pgrep -xn remmina)"/maps
grep -E '^(toolbar_placement|always_show_tab)=' ~/.config/remmina/remmina.pref
```

Expected: every `Exec` points to `~/.local/bin/silky-remmina`, the module appears in the process maps (count above 0), and the preferences read `toolbar_placement=0` and `always_show_tab=false`. After opening a connection, the top of the window shows traffic lights, the connection name and thin line icons, and `⋯` lists the moved actions. Switching light/dark in MacShell restyles the main and connection windows immediately, with the wallpaper blurred behind them.

Verified in an isolated instance (separate D-Bus and config directory, a WWW-protocol test connection): module loading, top toolbar, trimmed buttons and `⋯` menu, line icons, main-window glass and selection pill, and a live switch from dark to light. A real RDP session and the Hyprland blur on hardware are still to be verified.

### Rollback

```bash
remmina --quit
rm ~/.local/share/applications/org.remmina.Remmina.desktop ~/.local/share/applications/org.remmina.Remmina-file.desktop
rm -r ~/.local/share/silky-remmina ~/.local/bin/silky-remmina
```

Then restore the `~/.config/autostart/remmina-applet.desktop.bak.*` reported by the installer as `remmina-applet.desktop`. To get the left toolbar and always-visible tabs back, copy the `~/.config/remmina/remmina.pref.bak.*` backup over `remmina.pref`, or change them under Remmina Preferences → Appearance. `~/.local/share/themes/Silky-Remmina-{Dark,Light}` from the previous version is no longer used and can be deleted. Reopen Remmina.

## Traffic-light title bar

Omarchy already adds title bars to windows on floating workspaces: `default/hypr/workspace-modes.lua` loads its own plugin `omarchy-hyprland-titlebars` (`/usr/lib/omarchy-hyprland-titlebars/titlebars.so`, based on hyprbars) with three square buttons × □ − on the right (`button_rounding = 0`). Under the macOS Tahoe themes it becomes:

- The 30 px bar keeps the title centred and lets some of the wallpaper or the window behind show through in both appearances. The background is about 80% opaque when focused and 84% when unfocused. The bar also blurs its backdrop when Hyprland has global blur enabled.
- Two **round** buttons at the top left: 12 px, `button_rounding = 6`, 8 px apart, `#ff5f57` / `#28c840`
- The × − + symbols appear only when the pointer is over the lights; the lights turn grey when the window loses focus
- Close → close the window; green → maximize / restore; double-clicking the title bar also maximizes
- Only added to windows that draw no buttons of their own, currently terminals (foot, kitty, Alacritty, Ghostty, WezTerm); Claude, Chrome, Electron apps, GTK / libadwaita apps and MacShell windows keep their own. To add another app, add its class to `with_bar` in `silky-macos.lua`

### Implementation

| File | Role |
| --- | --- |
| `config/hypr/silky-titlebar-guard.lua` | Comes **before** `require("default.hypr.omarchy")` in `hyprland.lua`. hyprbars buttons can only be added, never removed, so under the macOS theme `hl.plugin.hyprbars.add_button` is replaced with a no-op and Omarchy's three square buttons never get added; the original function is kept as `silky_add_button` |
| `config/hypr/silky-macos.lua` | Comes after Omarchy's defaults: overrides the title-bar style, adds the two round buttons with the original function, and sets `hyprbars:no_bar` rules from an allow list |

These settings apply only once Omarchy has loaded the title-bar plugin (some workspace is in floating mode); otherwise they are skipped, so there is no `unknown field 'hyprbars:no_bar'` config error. hyprbars is no longer built here, so nothing needs rebuilding after a Hyprland update.

The theme installer above updates the [title bar configuration](../../config/hypr/silky-macos.lua) and reloads Hyprland. To verify the effect, overlap two Foot windows in a floating workspace and switch focus to see the lower window’s colour through the bar. To revert just this effect, restore the `~/.config/hypr/silky-macos.lua.bak.*` reported by the installer, or restore opaque bar colours and set `bar_blur` to `false`, then run `hyprctl reload`.

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
