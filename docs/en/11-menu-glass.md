# 11 · Omarchy's own menus: macOS 27 glass that follows light / dark

[简体中文](../11-menu-glass.md) | English

## Goal

Omarchy's own menus (the Super+Esc system menu, the Super+Ctrl+M Omarchy menu, and the clipboard and emoji panels that inherit the same style) used to be opaque dark cards that dimmed the whole screen, set in the terminal's monospace font. They now match MacShell:

- A translucent glass card; the windows and wallpaper behind it are blurred by Hyprland
- The screen behind is no longer dimmed
- The selected row is filled with MacShell's accent colour, white text (like macOS menus)
- Hairline border: white in dark mode, a very faint dark line in light mode
- A proportional face, Inter (close to SF Pro), with automatic Chinese fallback
- Smoky glass in dark mode, frosted white glass in light mode; switching the appearance changes the menus live, even one that is open

## How it works

The Omarchy shell's interface colours come from `shell.toml`: one shipped with the theme, plus the user-level `~/.config/omarchy/shell.toml`. Keys in the user file **win** over the theme and are watched live (`omarchy display text size` writes the same file), so nothing under `/usr/share/omarchy` is touched and theme switches do not undo it.

| File | Role |
| --- | --- |
| `bin/silky-menu-glass` → `~/.local/bin/` | Reads `org.gnome.desktop.interface color-scheme` and MacShell's accent colour and writes `[menu]` and `[launcher]` sections into a marked block of `~/.config/omarchy/shell.toml` (the rest of the file is kept). `--watch` keeps following, `--remove` deletes the block |
| `config/systemd/silky-menu-glass.service` | User service running `silky-menu-glass --watch` |
| `config/hypr/silky-menu-glass.lua` | Adds background blur to the `omarchy-menu`, `omarchy-clipboard` and `omarchy-emojis` layers; sets `OMARCHY_MENU_FONT=Inter` |

Why follow `color-scheme`: MacShell writes it when its appearance changes (Settings → Appearance, including Auto), and `omarchy theme set macos-tahoe-light/dark` writes it too. The WowType candidate window (09) uses the same signal, so the menus, the candidate window and MacShell always agree.

The `shell.toml` keys used (`[menu]`; `[launcher]` is the same):

| Key | Dark | Light |
| --- | --- | --- |
| `background` / `background-alpha` | `#1c1c1e` / 0.55 | `#f7f7f9` / 0.68 |
| `text` | `#f5f5f7` | `#1d1d1f` |
| `border` / `border-alpha` / `border-width` | `#ffffff` / 0.14 / 1 | `#000000` / 0.09 / 1 |
| `scrim-alpha` | 0 (no dimming) | 0 |
| `selected-background` / `selected-text` | MacShell accent / white | Same |

The corner radius follows Hyprland's `decoration:rounding` (14 here) and is not changed separately.

## Install

```bash
./scripts/install-menu-glass.sh
```

It installs the three files above, enables the service, runs `hyprctl reload`, then `omarchy-restart-shell` once (the menu font is read only when the Omarchy shell starts).

## Verify

```bash
./scripts/silky-doctor.sh            # "Omarchy menus follow light / dark as glass", "menu glass matches the current appearance"
omarchy-menu toggle system           # same as Super+Esc
gsettings set org.gnome.desktop.interface color-scheme prefer-light   # the menu turns into light glass at once; set prefer-dark again afterwards
```

## Pitfalls

- `omarchy-launch-shell` starts the shell with `QS_DISABLE_FILE_WATCHER=1`, but in practice the watch on the user-level `shell.toml` still works and appearance switches apply live.
- Write the file in place, never through a temporary file and a rename: the rename breaks the watch.
- The transparent full-screen layer behind the card (it catches clicks outside to close the menu) has alpha 0; `ignore_alpha = 0.05` makes Hyprland blur only the card, not the whole screen.
- `OMARCHY_MENU_FONT` must be in Hyprland's environment (`hl.env`): `omarchy-restart-shell` starts the shell through Hyprland and it inherits Hyprland's environment.

## Rollback

```bash
systemctl --user disable --now silky-menu-glass
~/.local/bin/silky-menu-glass --remove
rm ~/.config/hypr/silky-menu-glass.lua ~/.config/systemd/user/silky-menu-glass.service ~/.local/bin/silky-menu-glass
# remove require("hypr.silky-menu-glass") from hyprland.lua
hyprctl reload && omarchy-restart-shell
```
