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

<a id="remmina"></a>

## Remmina in Simplified Chinese with a macOS look

Remmina 1.4.44 ships a Simplified Chinese translation, but the system language is `en_US`, so the interface stayed in English. After installation, Remmina shows Simplified Chinese menus, column headers and dialogs whether you open it from the launcher, the Dock, an `rdp://` link or the tray applet. Under the macOS Tahoe theme the main window also changes:

- Title bar buttons lose their grey circles and become borderless icons. A rounded plate appears only on hover or press. The title uses 10pt semibold.
- The quick-connect bar is slimmer. The protocol drop-down and the address field use 7 px corners and show a soft accent halo when focused.
- The connection list drops its grid lines and gets more row spacing. Column headers use small, regular-weight secondary text. The footer status text is also smaller and dimmer and no longer sits on its own coloured strip.

From the repository root, run:

```bash
./scripts/install-remmina-mac.sh
remmina --quit
```

Then reopen Remmina from the app menu. Remmina runs as a single instance, so any process started before installation (including the tray applet) must quit before the new language and style apply. Requires `remmina` and the `zh_CN.UTF-8` locale. The styling part also needs the [macOS Tahoe theme](#install-and-switch).

### Implementation

| File | Role |
| --- | --- |
| [`bin/silky-remmina`](../../bin/silky-remmina) | Installed as `~/.local/bin/silky-remmina`. Sets `LANGUAGE=zh_CN:en` and `LC_MESSAGES=zh_CN.UTF-8`, picks `GTK_THEME=Silky-Remmina-Dark` or `Silky-Remmina-Light` from the current `gtk-theme`, then hands off to `remmina-file-wrapper`. With any other GTK theme only the language changes |
| [`config/remmina/silky-remmina.css`](../../config/remmina/silky-remmina.css) | Main-window styling. Colours come from MacTahoe's named colours, so both variants share one file |
| [`scripts/install-remmina-mac.sh`](../../scripts/install-remmina-mac.sh) | Builds `~/.local/share/themes/Silky-Remmina-{Dark,Light}/gtk-3.0/` (imports MacTahoe, then the stylesheet above). Copies `org.remmina.Remmina*.desktop` to `~/.local/share/applications/` with every `Exec` rewritten, and rewrites `~/.config/autostart/remmina-applet.desktop`. Writes only on change and backs up originals as `*.bak.<timestamp>` |

Remmina's main-window widgets have no CSS names, and rules in the global `~/.config/gtk-3.0/gtk.css` would hit every GTK3 app. A separate theme loaded only by the Remmina process avoids that. The appearance is fixed at launch: switching light/dark while Remmina runs takes effect on its next start. `GTK_THEME` and the language variables also pass to external tools Remmina starts. Remmina runs natively on Wayland, so XWayland plays no part; verified on native Wayland.

### Verify

```bash
grep -h '^Exec' ~/.local/share/applications/org.remmina.Remmina.desktop
tr '\0' '\n' < /proc/"$(pgrep -xn remmina)"/environ | grep -E '^(GTK_THEME|LANGUAGE)='
hyprctl clients -j | jq -r '.[] | select(.class == "org.remmina.Remmina") | .title'
```

Expected: every `Exec` points to `~/.local/bin/silky-remmina`, the process environment has `GTK_THEME=Silky-Remmina-Dark` (or `-Light`) and `LANGUAGE=zh_CN:en`, and the window title is `Remmina 远程桌面客户端`. Confirmed on real hardware in dark mode: Chinese interface, grid-free list, flat title bar buttons and status bar. Light mode and remote-session windows are still to be verified.

### Rollback

```bash
remmina --quit
rm ~/.local/share/applications/org.remmina.Remmina.desktop ~/.local/share/applications/org.remmina.Remmina-file.desktop
rm -r ~/.local/share/themes/Silky-Remmina-Dark ~/.local/share/themes/Silky-Remmina-Light ~/.local/bin/silky-remmina
```

Then restore the `~/.config/autostart/remmina-applet.desktop.bak.*` reported by the installer as `remmina-applet.desktop` and reopen Remmina.

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
