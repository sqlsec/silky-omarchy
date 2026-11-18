# 08 · File manager context menu

[简体中文](../08-nautilus-actions.md) | English

Run `./scripts/install-nautilus-actions.sh`, close every file window, run `nautilus -q` and open the file manager again. The script installs the extension into `~/.local/share/nautilus-python/extensions/` and backs up an existing different version when updating; it needs `nautilus-python` and `xdg-terminal-exec`.

- Right-click a local file or folder and choose "Copy Path"; with several selected, one path per line.
- Right-click a local folder, or the empty space of a file list, and choose "Open in Terminal". The terminal is the system default.
- Right-click files or folders and use Nautilus's own "Compress…"; right-click a supported archive and choose "Extract Here" or "Extract to…". Which formats work depends on the system's archive support.
- Remote locations have no local path, so the two extension menus do not appear there.

To uninstall, delete `~/.local/share/nautilus-python/extensions/silky_actions.py`, then quit and reopen Nautilus.

## Simplified Chinese interface

Run these commands from the repository root. You need Python 3, Nautilus with its Simplified Chinese translations, and a generated `zh_CN.UTF-8` locale (check with `locale -a`). The setup uses Nautilus’s translations for menus and dates and translates common sidebar bookmarks and the installed LocalSend and Transcode menu items. Bookmarks keep their original targets. Folder names, script filenames and volume labels display their original names.

```bash
./scripts/install-nautilus-zh-cn.py
nautilus --quit
```

Reopen from the application menu entry labeled 文件 or use `Super+Shift+F`, then check the sidebar and context menu. Press `Super+Alt+Shift+F` in a terminal to check the current-directory shortcut. The localized launcher sets the locale for Nautilus. Starting a new process by calling `nautilus` directly in a terminal uses that terminal’s locale.

The [installer](../scripts/install-nautilus-zh-cn.py) writes user-level `applications/org.gnome.Nautilus.desktop` and `dbus-1/services/org.gnome.Nautilus.service` overrides and updates `~/.config/hypr/bindings.lua` and existing GTK bookmarks. If the running D-Bus session has yet to pick up the service override, refresh it with `gdbus call --session --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus --method org.freedesktop.DBus.ReloadConfig`.

To roll back, restore the originals from the `.bak.*` paths printed during installation. Remove the generated user-level `.desktop` and `.service` overrides if you had no originals. Run `hyprctl reload`, refresh D-Bus, then quit and reopen Nautilus.
