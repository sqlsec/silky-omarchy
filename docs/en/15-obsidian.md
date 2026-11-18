# 15 · Obsidian: macOS 27 theme, file icons and smooth typing

[简体中文](../15-obsidian.md) | English

## What it does

Obsidian gets a macOS 27 look and follows the desktop's light / dark mode:

- **Light / dark follows the system.** The theme is set to "Adapt to system". When Omarchy switches between `macos-tahoe-light/dark`, or you switch the appearance in MacShell, Obsidian follows immediately without a restart.
- **Glass.** Context menus, the command palette and quick switcher (Spotlight-style, with a large input), Settings and other modals, hover previews, tooltips, notices, the sidebars and the status bar are frosted glass (blur plus saturation). The left and right sidebars are rounded glass panels floating inside the window, and the editor is a rounded sheet.
- **Finder-style file tree.** Folders are macOS blue folders and switch to an open folder when expanded. Each extension has its own icon: notes, plain text, Canvas, Base, PDF, Word / WPS, spreadsheets, presentations, images, SVG, audio, video, archives, web links, and code files such as JS / TS / Python / Shell / JSON / CSS / HTML / Lua / YAML / Rust / Go / C. Code files show a small dark terminal with red / yellow / green dots. The selected row is filled with the accent colour, as in Finder's sidebar.
- **Smooth typing.** The caret glides between positions instead of jumping, and fades in and out instead of blinking hard. The companion plugin Silky Typing fades each new character in with a slight blur and an accent glow. Text committed from an input method such as Pinyin fades in as a whole.
- **Code blocks look like a macOS Terminal window**: dark glass, red / yellow / green dots in the top left, the language name centred in the title bar, and Xcode Default (Dark) syntax colours. Code blocks stay dark in both modes. Inline code is a light pill that follows the appearance.
- Other details: Apple system colours and font stack (`-apple-system`, Inter, Noto Sans CJK SC; SF Mono / JetBrainsMono Nerd Font for code). Window buttons are traffic lights whose glyphs appear on hover. Switches are iOS-style, task checkboxes are round like Reminders, scrollbars only appear on hover, and menus and modals pop in with a short animation. Turning on the system's reduced-motion setting disables all animations.

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
| Copies the plugin | `<vault>/.obsidian/plugins/silky-typing/` (from [`config/obsidian/plugins/silky-typing/`](../../config/obsidian/plugins/silky-typing/)) |
| Enables the theme and follows the system | `<vault>/.obsidian/appearance.json`: `"cssTheme": "Silky macOS"`, `"theme": "system"`; other keys are kept |
| Registers the plugin | adds `silky-typing` to `<vault>/.obsidian/community-plugins.json` |
| Backs up on the first run | the original `appearance.json` and `community-plugins.json` go to `~/.local/state/silky-omarchy/obsidian/<vault-path-hash>/` |

It is safe to run again. Later runs only update the theme and plugin files and keep the first backup.

A running Obsidian loads the theme without a restart. The typing fade has to be switched on once per vault: **Settings → Community plugins → turn off Restricted mode, then make sure "Silky Typing" is on**. Obsidian keeps that switch in its own localStorage and treats it as a security setting, so the script leaves it to you. Without the plugin, the caret glide and soft blink still work, because they come from the theme CSS alone.

Optional settings:

- To see docx, xlsx, zip and similar files in the file tree with their icons, turn on **Settings → Files and links → Detect all file extensions**. By default Obsidian only lists types it can open.
- The default accent is Apple blue. If you pick another colour under **Settings → Appearance → Accent color**, selected rows, the caret, switches and the typing glow all follow it.

## Implementation

| File | Role |
| --- | --- |
| [`theme.css`](../../config/obsidian/themes/Silky%20macOS/theme.css) | The whole theme: light / dark variables, glass, floating sidebars, traffic-light window buttons, file tree, caret and terminal code blocks |
| [`build-icons.py`](../../config/obsidian/build-icons.py) | Draws every file and folder icon in Python (SVG, no third-party artwork) and writes them into `theme.css` as data URIs between `@silky-icons-start` and `@silky-icons-end`. After changing an icon or adding an extension, run `python3 config/obsidian/build-icons.py` |
| [`silky-typing/main.js`](../../config/obsidian/plugins/silky-typing/main.js) | CodeMirror 6 extension that adds a `silky-typed` mark to newly typed characters and removes it after 260 ms |
| [`silky-typing/styles.css`](../../config/obsidian/plugins/silky-typing/styles.css) | Fallback fade animation for when the Silky macOS theme is not active |
| [`install-obsidian-theme.sh`](../../scripts/install-obsidian-theme.sh) | Install, backup and `--remove` |

Key points:

- **Why the glass only blurs the app itself.** Obsidian's "Translucent window" setting only works on macOS (the source checks `process.platform === "darwin"`). On Linux the Electron window is opaque, and Hyprland cannot blur one region inside a window. So the glass here is CSS `backdrop-filter` over Obsidian's own content. A faint accent gradient on the window background gives the glass panels something to refract.
- **Light / dark signal chain.** Omarchy's `omarchy-theme-set-gnome` and MacShell both write `org.gnome.desktop.interface color-scheme`. `xdg-desktop-portal-gtk` passes it to Electron as `prefers-color-scheme`, and in "Adapt to system" mode Obsidian switches between `body.theme-light` and `body.theme-dark`. This is the same signal used by [11 · Menu glass](11-menu-glass.md) and [09 · Candidate window](09-wowtype-glass.md).
- **File icons.** Obsidian writes `data-path` on every row of the file tree. The theme matches extensions with selectors such as `.nav-file-title[data-path$=".pdf" i]` and draws the icon in `.nav-file-title-content::before`, so renaming a file never edits the icon into its name.
- **Caret glide.** Obsidian 1.15 draws its own caret with CodeMirror's `drawSelection`. When the caret moves, CodeMirror reuses the same `.cm-cursor` element and only changes its `left` / `top`, so a 90 ms transition on those properties makes it glide. The blink animation was a hard `steps(1)` switch and now uses an easing curve.
- **Typing fade and input methods.** The plugin only handles `input.type` events and only marks insertions of 8 characters or fewer, so pastes and snippet completions are left alone. Each mark carries a unique attribute so CodeMirror does not merge neighbouring marks, which would replay the animation on earlier characters. While an input method is composing (preedit), the plugin does not touch the DOM at all, because doing so breaks Chromium's IME handling. Text inserted during composition is tracked and faded in after `compositionend`. If a mark expires while a composition is active, its removal waits until the composition ends.

Known limitations:

- Code blocks in Reading view don't expose the language name, so their title bar only shows the dots. The Live Preview title bar shows the language.
- On this machine, `~/.config/obsidian/user-flags.conf` contains `-disable-gpu`, so Obsidian composites in software. Blur is only used on menus, the command palette, the sidebars and similar areas, and its CPU cost has not been measured. Without that flag the GPU handles the blur, which uses less CPU.
- In Live Preview, the first and last lines of a code block are the ```` ``` ```` fence lines. They appear below the terminal title bar when the cursor is inside the block.

## Verify

Verified on Obsidian 1.15.1 (aarch64, native Wayland window, Electron's bundled Chromium):

- **Isolated test**: a separate Obsidian instance started with `--user-data-dir` on a temporary test vault, inspected over the DevTools protocol. `cssTheme` was `Silky macOS` and screenshots in both modes looked right. `.cm-cursor` had a `transition` covering `left` / `top`, and `.cm-cursorLayer` used `cubic-bezier(0.45, 0, 0.55, 1)`. Simulated typing produced one `.silky-typed` mark per character. During a simulated Pinyin composition (`ni` → `nihao`) no new marks were added, and the committed 「你好」 was marked afterwards. All marks were gone after about 0.7 s and the text was unchanged.
- **On this machine**: after the install script ran on the two local vaults, the running Obsidian switched to the floating glass sidebar without a restart. The typing fade only works once Restricted mode is off, and still needs to be confirmed on the real vaults.

To check it yourself:

```bash
grep -h '"cssTheme"\|"theme"' ~/path/to/vault/.obsidian/appearance.json   # "Silky macOS" and "system"
gsettings set org.gnome.desktop.interface color-scheme prefer-light       # Obsidian turns light at once; set prefer-dark again after
```

In Obsidian:

1. Press `Ctrl+P`. The command palette should be a rounded glass card, with the content behind it blurred.
2. Type a few characters in a note, then type a word with Pinyin. The caret should glide, new characters should fade in, and the input method's candidates and commit should work normally.
3. Add a ```` ```bash ```` code block. It should look like a dark terminal window with red / yellow / green dots and `bash` in the title bar.

Not yet verified: blur cost across monitors with different scales (2× and 2.5×), and Obsidian's popout windows.

## Roll back

```bash
./scripts/install-obsidian-theme.sh --remove           # every registered vault
./scripts/install-obsidian-theme.sh --remove ~/Notes   # the given vaults
```

The script deletes `themes/Silky macOS/` and `plugins/silky-typing/`, then restores `appearance.json` and `community-plugins.json` from the backup in `~/.local/state/silky-omarchy/obsidian/<hash>/`. If those files didn't exist before, it deletes them. Obsidian switches back to the previous theme on its own. To return to the default look but keep the files, pick "Default" under **Settings → Appearance → Themes**.

Note: `--remove` restores those two files to how they were before the first install, so any other appearance changes made since then (font size, for example) are undone too.
