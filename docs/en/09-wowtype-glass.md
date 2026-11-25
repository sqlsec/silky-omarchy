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

## WeChat's candidate bar blinks while typing

With fades off the ghosting is gone, but while you keep typing the candidate bar still blinks and feels less responsive than in other apps.

Cause: the fcitx5-qt bundled with WeChat 4.1.13 (Qt 6.6) is old. Its `updatePosition()` does not use `xdg_popup.reposition`; whenever the anchor changes it calls `hide()` and then `show()`, so the bar is destroyed and recreated with an empty frame in between. The anchor is the text cursor. With the pinyin shown inline in the input box (preedit), the cursor moves one step right on every letter, so the bar is recreated on every keystroke. Newer upstream fcitx5-qt repositions instead, but WeChat links its copy statically, so it cannot be swapped.

Fix: Silky ships a tiny fcitx5 addon, [`plugins/silky-wechat-preedit`](../../plugins/silky-wechat-preedit/silky-wechat-preedit.cpp), that turns preedit off only for WeChat's D-Bus input context (`program:wechat frontend:dbus`). The pinyin moves to the first line of the candidate bar, the cursor stays put while you compose, and the bar is only redrawn and resized in place instead of being recreated. Other apps and WeChat's `wayland_v2` context are untouched. The cost: in WeChat the pinyin is no longer shown inline in the input box; it sits at the top of the candidate bar.

- Install: `./scripts/install-wowtype-glass.sh` builds it with `make` against the local fcitx5 headers (`Fcitx5Core`, shipped in Arch's `fcitx5` package), installs it to `~/.local/lib/silky-omarchy/libsilkywechatpreedit.so`, writes `~/.local/share/fcitx5/addon/silky-wechat-preedit.conf` (an absolute `Library=` path, so nothing is written to `/usr/lib`), and restarts fcitx5 over D-Bus. Without `make`, `pkg-config` or the headers it is skipped with a message. WeChat does not need a restart; it reconnects to fcitx5 the next time its input box gets focus.
- Built and loaded on fcitx5 5.1.23. Re-run the installer after a major fcitx5 update.
- Preedit is turned off again when a context is created and on every focus-in, because a global fcitx5 config reload resets every context to the default. `Ctrl+Alt+P` in WeChat (fcitx5's "Toggle preedit") brings the inline pinyin back temporarily; it is turned off again after you switch away and back.

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

## WPS candidate bar, mini toolbar, and document fonts

- WPS ships a Fcitx plugin built for its own Qt. If the editor starts without `QT_IM_MODULE=fcitx`, Omarchy can switch to WowType while the WPS editor receives no candidates. The `wps-dark-border` wrapper selects XWayland and Fcitx for WPS launchers that use it. From the repository root, run `./scripts/install-wowtype-glass.sh` to update the wrapper. Save your work, quit WPS, and reopen it from the application launcher or file manager. In the document body, press `Super+I`, type `ninhao`, and select 你好. On the tested system, the desktop entry started WPS with its bundled Fcitx plugin loaded. An isolated X11 test also confirmed that a WowType candidate could be committed to the document. To roll back, restore `~/.local/bin/wps-dark-border.bak.*` and reopen WPS. [Fcitx Wayland documentation](https://fcitx-im.org/wiki/Using_Fcitx_5_on_Wayland)
- MacShell groups Writer, Spreadsheets, Presentation, PDF, and All-in-One windows under the red WPS Office Dock icon. The selection mini toolbar gets no Dock item. Existing WPS pins are grouped as well. Run `./scripts/install-macshell-optimizations.sh`, or apply the Dock change alone with `python3 scripts/tune-wps-dock.py ~/.config/quickshell/MacShell/MacDock.qml --backup`, then run `qs -c MacShell ipc call macshell reload`. Select document text and open a context menu to check that the Dock shows just one WPS icon and that clicking it returns to the document. To roll back, restore `MacDock.qml` from the reported backup and reload MacShell.
- WPS runs under XWayland. Fcitx5's X11 candidate window reads `Xft.dpi` from Xresources. When `xprop` is available (`xorg-xprop` on Arch), the installer and Hyprland startup set a missing value from the built-in display's scale, or from the first output on desktops without one. A 2× display yields 192 DPI. An existing value takes precedence, and other X11 applications that read Xresources can also use this setting. [Fcitx DPI documentation](https://fcitx-im.org/wiki/Theme_Customization#Classic_User_interface)
- Omarchy's floating workspace mode gives new application windows a default size and a cascading position, which stretched WPS context menus and floating mini toolbars into oversized panels with large white margins. The `o.window(..., { float = true })` rules let `Fcitx5 Input Window` and popups from all WPS components — Writer (`wps`), Spreadsheets (`et`), Presentation (`wpp`), PDF (`wpspdf`), and the All-in-One shell (`wpsoffice`), matched via `initial_class` and `title` against `^(wps|et|wpp|wpspdf|wpsoffice)$` under rule `silky-wps-popups` — supply their own geometry. The rules disable Hyprland blur and window animations on both popups, avoiding the large first-frame background, and disable compositor shadows on the WPS popups.
- When you drag the vertical scrollbar in WPS Writer, the page-number tip opens as an XWayland window titled `KToolTipWidget`. The previous rule matched component names, so the floating workspace applied its default window size when this tip appeared. The [window rule](../../config/hypr/silky-ime.lua) now also matches this title and preserves the size and position requested by WPS. Run `./scripts/install-wowtype-glass.sh`, or back up and sync `~/.config/hypr/silky-ime.lua` and run `hyprctl reload`. Drag the scrollbar thumb in a multi-page document to check that the tip stays beside it. Live testing on Hyprland 0.57.2 with WPS 12.1.2.29183 in All-in-One mode measured a change from 942 × 626 to about 82 × 37 logical pixels. To roll back, remove `|KToolTipWidget` from the title pattern and reload Hyprland.
- WPS's Find and Replace dialog (`查找和替换`) is modeless, so the floating workspace treated it as a new application window and stretched it to the default 942 × 626 logical pixels, leaving a large blank area under the search field. The `silky-wps-find-dialog` [window rule](../../config/hypr/silky-ime.lua) matches `initial_class` plus the title `^(查找和替换|Find and Replace)$` and marks the dialog as floating on its own account. Only that title joins the floating workspace exclusions, so WPS document windows keep the mode's default size. Run `./scripts/install-wowtype-glass.sh`, or back up and sync `~/.config/hypr/silky-ime.lua` and run `hyprctl reload`. The next `Ctrl+F` picks it up without restarting WPS. On Hyprland 0.57.2 with WPS 12.1.2.29183 in All-in-One mode on a 1472 × 920 logical screen, the dialog went from 942 × 626 back to WPS's own 548 × 308 and no longer carries the `omarchy-mode-opened` tag. Check the size of the window titled `查找和替换` with `hyprctl clients -j`. Dialog titles in other UI languages must be added to the match. To roll back, remove the `silky-wps-find-dialog` rule or restore `~/.config/hypr/silky-ime.lua.bak.*`, then run `hyprctl reload`.
- The Find and Replace dialog has no title bar and WPS ignores drags on its header. WPS is a self-framed app, so Hyprland adds no titlebar either, and the dialog could only be moved with `Super` + drag. [`config/hypr/silky-ime.lua`](../../config/hypr/silky-ime.lua) treats the empty header strip to the right of the 查找 / 替换 / 定位 tabs (from 200 logical pixels in from the dialog's left edge, within the top 40 logical pixels) as a title bar. A plain left press there that travels more than 3 logical pixels moves the dialog with the pointer until release. The binds are `non_consuming`, so WPS still receives every click and the tabs and controls below keep working; `Super` + drag still uses Hyprland's native move. An 8 ms Lua timer that only runs during the drag moves the window with absolute `hl.dsp.window.move` calls. Deploy as above; it applies after `hyprctl reload`. Verified live that the dialog accepts absolute moves and redraws correctly at the new position, and that `hyprctl binds -j` shows the two non-consuming `mouse:272` binds alongside Folio's drag binds. Mouse buttons could not be injected on this machine, so real mouse and touchpad drags still need hands-on confirmation. To roll back, delete the drag block below the `silky-wps-find-dialog` rule (the `WPS_FIND_*` constants, the timer and both `mouse:272` binds) and run `hyprctl reload`.
- **Keep WPS selection mini toolbars from breaking consecutive drag-selections:** under click-to-focus (`input:follow_mouse = 0` in floating workspace mode), letting the selection mini toolbar steal focus on map caused the next drag-selection elsewhere in the document to carry/paste the previous selection instead of starting a fresh selection. [`config/hypr/silky-ime.lua`](../../config/hypr/silky-ime.lua) sets `no_initial_focus = true` on `silky-wps-popups`, keeping focus on the WPS document window while toolbar buttons remain clickable. Run `./scripts/install-wowtype-glass.sh` (or update `~/.config/hypr/silky-ime.lua` and run `hyprctl reload`) to apply immediately without restarting WPS; verified live in WPS Writer with back-to-back text selections. To roll back, remove `no_initial_focus = true` from `silky-wps-popups` (or restore `~/.config/hypr/silky-ime.lua.bak.*`) and run `hyprctl reload`.
- **Remove the dark outer frame around floating WPS windows:** in All-in-One mode (`wps-office-cn 12.1.2.29183-1`), `KPromeMainWindow::_updateMargins()` / `onSkinChanged()` adds a window-frame layout margin whenever the window is not maximized (2 px, or 5 px on touch devices, multiplied by DPI scale — about 10 physical pixels on a 2× display). [`plugins/silky-wps-noborder/`](../../plugins/silky-wps-noborder/silky-wps-noborder.cpp) builds a small `LD_PRELOAD` library (`~/.local/lib/silky-omarchy/libsilkywpsnoborder.so`) that zeroes `QLayout::setContentsMargins` only on `KPromeMainWindow` and its `centralWidget()` root layout, leaving all other layouts untouched. [`wps-dark-border`](../../plugins/silky-wps-noborder/wps-dark-border) (installed to `~/.local/bin/wps-dark-border` and invoked by user `~/.local/share/applications/wps-office-*.desktop` overrides) uses `bwrap --ro-bind-data` to append the library to `LD_PRELOAD` inside `/usr/bin/{wps,et,wpp,wpspdf}` while keeping `/usr/lib/libfreetype.so` and the dark border fallback intact, without modifying packaged files. Fully quit and reopen WPS to apply; to roll back, remove `~/.local/lib/silky-omarchy/libsilkywpsnoborder.so` and restore `~/.local/bin/wps-dark-border.bak.*`.
- Place the caret in a WPS document and press `Super+I` to select WowType. Type pinyin at different heights on a page and check that the candidate bar follows the caret. In WPS Writer, Spreadsheets, and Presentation, drag across content or right-click to open context menus and mini toolbars and verify they open at their compact size without white margins; after fully restarting WPS, check that floating windows no longer show the thick dark frame along the left, right, and bottom edges (live UI check pending WPS restart). Run `xprop -root RESOURCE_MANAGER` to inspect the DPI.

If WPS reports missing fonts, copy the fonts Linux recognizes from your Windows `Windows/Fonts` directory into `~/.local/share/fonts/Windows/`, run `fc-cache -f`, save your documents, and fully quit and reopen WPS. Run `fc-match -f '%{family} %{file}\n' 'SimSun'` to check the actual family and file being used.

Modern Windows supplies `simfang.ttf` under the family name `FangSong`. Older files may explicitly request `仿宋_GB2312`. Install a font whose embedded family is `FangSong_GB2312,仿宋_GB2312`, then verify it with `fc-match -f '%{family} %{file}\n' '仿宋_GB2312'`. The document can keep its original font name. [Anyang University font downloads](https://www.ayxy.edu.cn/xxh/contents/127/2224.html)

## `Super+I` input-method switching under MacShell

Starting with Omarchy `4.0.0.r8205`, the default `Super+I` / `Super+Shift+I` bindings call `omarchy-input-method cycle [back]`, which forwards the request via `omarchy-shell shell cycleInput` to `indicator.py` inside Omarchy's built-in shell. When MacShell replaces `omarchy-shell`, that IPC fails with `omarchy-shell is not running`, so pressing `Super+I` in any window whose Fcitx5 context is on `keyboard-us` (such as the ChatGPT desktop app) cannot switch to WowType — and every `omarchy-dev` update keeps those `omarchy-shell`-dependent defaults.

Fix: [`wowtype-glass/silky-input-cycle`](../../wowtype-glass/silky-input-cycle) (installed to `~/.local/bin/silky-input-cycle`) talks directly to `org.fcitx.Fcitx5` `Controller1` over `busctl` (`CurrentInputMethodGroup`, `InputMethodGroupInfo`, `CurrentInputMethod`, `SetCurrentIM`) to cycle input methods forward or backward, cycles multi-layout keyboards via `hyprctl switchxkblayout` in the same order as Omarchy's `indicator.py`, and falls back to XKB layout switching if Fcitx5 is not running. [`config/hypr/silky-ime.lua`](../../config/hypr/silky-ime.lua) loads after `default.hypr.omarchy`, unbinds the stock `SUPER + I` / `SUPER + SHIFT + I`, and rebinds them to `~/.local/bin/silky-input-cycle` (and `back`) without touching packaged files under `/usr/share/omarchy/`, so system updates do not undo it.

- Install & apply: run `./scripts/install-wowtype-glass.sh` from the repository root (installs the script, updates `~/.config/hypr/silky-ime.lua`, and runs `hyprctl reload`); no app restart or relogin is needed.
- Verification: verified on this machine that `hyprctl reload` and `hyprctl configerrors` report no errors, `hyprctl binds -j` keeps a single binding for each of `SUPER + I` and `SUPER + SHIFT + I`, and running `~/.local/bin/silky-input-cycle` / `~/.local/bin/silky-input-cycle back` switches between `wowtype` and `keyboard-us` as observed via `fcitx5-remote -n`; physical `Super+I` switching inside ChatGPT is ready for live confirmation.
- Rollback: remove `~/.local/bin/silky-input-cycle`, drop the `SUPER + I` / `SUPER + SHIFT + I` override lines from `~/.config/hypr/silky-ime.lua`, and run `hyprctl reload`.

## Verify

```bash
systemctl --user is-active silky-ime-theme
grep '^Theme=' ~/.config/fcitx5/conf/classicui.conf
hyprctl animations | grep -A3 'name: fadePopups$'   # enabled: 0
grep -c libsilkywechatpreedit /proc/$(pgrep -x fcitx5)/maps   # greater than 0
```

Then type `nihao` in a WeChat input box: while you keep typing, the candidate bar should be a single layer with sharp edges, the pinyin should be on its first line, and the bar should stay in place without blinking. It should follow light/dark switches. The commands above were run on this machine; typing in WeChat with the addon loaded still needs a check on real hardware.

## Rollback

```bash
systemctl --user disable --now silky-ime-theme
mv ~/.config/fcitx5/conf/classicui.conf.silky-backup ~/.config/fcitx5/conf/classicui.conf
```

Then remove `require("hypr.silky-ime")` from `~/.config/hypr/hyprland.lua` and run `hyprctl reload`.

To bring back only the inline pinyin in WeChat, remove the addon and restart fcitx5:

```bash
rm ~/.local/share/fcitx5/addon/silky-wechat-preedit.conf ~/.local/lib/silky-omarchy/libsilkywechatpreedit.so
fcitx5 -rd
```
