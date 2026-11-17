# 09 · WowType candidate window: rounded frosted glass and the WeChat ghosting fix

[简体中文](../09-wowtype-glass.md) | English

```bash
./scripts/install-wowtype-glass.sh
```

Restart WeChat once after installing.

## Why WeChat's candidate bar looked blurry and doubled

In other apps the candidate window is drawn by fcitx5 itself as a Wayland input-method-v2 popup, which stays one and the same surface, so it is smooth.

WeChat is different: it statically links the fcitx5-qt client into its binary and declares `ClientSideInputPanel` (in `busctl --user call org.fcitx.Fcitx5 /controller org.fcitx.Fcitx.Controller1 DebugInfo`, WeChat's `frontend:dbus` entry has bit 39 set in its capabilities). So the candidate bar is an xdg_popup drawn by WeChat's own Qt, **destroyed and recreated on every keystroke**. Hyprland fades popups in and out by default (`fadePopups` inherits `fade`), so the old bar was still fading out while the new one faded in; the two layers on top of each other are the ghosting, and `blur:popups` on top made it look even blurrier. At rest it was actually sharp.

The fix is one line: `config/hypr/silky-ime.lua` turns `fadePopups` off. The cost is that other popups, such as context menus, also appear instantly instead of fading in.

The `QT_IM_MODULE=wayland` / `ibus` interfaces tried earlier only allow English in this WeChat version; do not use them again. `Super+I` relies on the current fcitx (D-Bus) interface.

## Silky Glass skins

`wowtype-glass/build-themes.py` generates two fcitx5 themes into `~/.local/share/fcitx5/themes/`:

| Theme | Panel | Selection |
| --- | --- | --- |
| `silky-glass-dark` | 40% opaque dark grey + hairline light rim | macOS blue `#0A84FF` rounded pill |
| `silky-glass-light` | 50% opaque near-white + hairline dark rim | macOS blue `#007AFF` rounded pill |

- Edge-to-edge highlight: no gap between the panel and the highlight (`PAD = 0`), and the panel corner equals the highlight corner (both 8 px, `R = HR + PAD`). When the first candidate is selected, the blue highlight lies exactly over the panel's left rounded end, so the two are one curve.
- The highlight margin must equal the text margin: fcitx5's `[InputPanel/Highlight/Margin]` does two things, it is how far the highlight extends beyond the text and it is the 9-slice border of `highlight.png`. When it is larger than `[InputPanel/TextMargin]`, the highlight overflows the candidate window and gets clipped, which squares off the corners (a highlight margin of 11 with a 6 px vertical text margin did exactly that). Both are now 11 left/right and 8 top/bottom, and the corner radius is no larger than the vertical margin (`HR <= TM_Y`). The bundled default and wowtype themes also keep the two equal.
- Glass: the dark panel used to be 74% opaque, so the blur barely showed and over dark content it looked like a grey slab. It is now 40% (dark) and 50% (light), more transparent than the Omarchy menu glass (55% / 68%): the candidate bar is small, so it needs more transparency for the glass to read. The rounded corners and translucency are painted into 9-slice PNGs: WeChat's bundled fcitx5-qt understands only images, plain colours and margins, not blur, dark-theme or accent keys.
- The frosting comes from Hyprland: `decoration.blur.input_methods` (fcitx5's own candidate window) and `decoration.blur.popups` (WeChat's candidate bar); `ignorealpha = 0.1` keeps the transparent area outside the rounded corners unblurred.
- To change colours or corners: edit `R`, `HR` and `SKINS` at the top of `build-themes.py` and run the installer again.
- Proportions: fcitx5's default `Sans 10` font with the old 7 + 5 px vertical margins made the bar tall with small text. The font is now `Inter 12` (the same face as the Omarchy menus, with automatic Chinese fallback; `Sans 12` if Inter is not installed), with the edge-to-edge highlight and an 8 px vertical text margin the bar is more compact and the text larger. `silky-ime-theme` writes the font as `Font=` in `classicui.conf`, but only if you have not set `Font=` yourself; to change the size, edit that line and it will not be overwritten.

## Automatic dark / light switching

`silky-ime-theme.service` runs `silky-ime-theme --watch`, which watches `org.gnome.desktop.interface color-scheme` (changed both by Omarchy theme switches and by macOS Tahoe light/dark), sets `Theme=` in `classicui.conf` to the matching skin and makes fcitx5 reload classicui.

fcitx5's own "follow system dark mode" (`UseDarkTheme`) is not used: WeChat's copy of fcitx5-qt does not support it and only reads `Theme=`. Changing `Theme=` keeps WeChat and every other app on the same skin. The file is rewritten in place (same inode), so the client inside WeChat notices the change; if it ever misses one, restart WeChat.

## Verify

```bash
systemctl --user is-active silky-ime-theme
grep '^Theme=' ~/.config/fcitx5/conf/classicui.conf
hyprctl animations | grep -A3 'name: fadePopups$'   # enabled: 0
```

Then type `nihao` in a WeChat input box: while you keep typing, the candidate bar should be a single layer with sharp edges, and it should follow light/dark switches.

## Rollback

```bash
systemctl --user disable --now silky-ime-theme
mv ~/.config/fcitx5/conf/classicui.conf.silky-backup ~/.config/fcitx5/conf/classicui.conf
```

Then remove `require("hypr.silky-ime")` from `~/.config/hypr/hyprland.lua` and run `hyprctl reload`.
