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

## Set the desktop background

Right-click one local image in Nautilus, choose Set as Background, then confirm in the preview. Omarchy updates the wallpaper immediately and records the image path. Keep the original image accessible so the desktop can load it again.

The default Hyprland and GTK portal backends lack a Wallpaper interface, so Nautilus’s built-in action previously could not apply the image. The [installer](../scripts/install-nautilus-wallpaper.py) registers a user-session [Wallpaper backend](../nautilus/wallpaper_portal.py) that applies the picture with `omarchy theme bg set`. It was tested on Omarchy 4.5, Nautilus 51 and xdg-desktop-portal 1.22.1. It requires Python GObject, GTK 4 and a systemd user session. The image must be a local file that GdkPixbuf can decode. The action sets the desktop wallpaper.

Run this from the repository root. Installation reloads the user D-Bus configuration and restarts the desktop portal. Existing Nautilus windows can then use the action.

```bash
./scripts/install-nautilus-wallpaper.py
```

To verify, preview an image with spaces in its filename and cancel to confirm the wallpaper stays the same. Open the preview again and apply it, then check that the desktop changes and that `owe status` reports the new `source_path`. Use the same menu action on the original image to switch back.

To roll back, restore your original `~/.config/xdg-desktop-portal/hyprland-portals.conf` from backup or remove the added `org.freedesktop.impl.portal.Wallpaper=silky-wallpaper` line. Stop `silky-wallpaper-portal.service`, then remove the backend Python file, `.portal` descriptor, D-Bus service and systemd user unit listed by the installer. Restore backups for any files that existed before installation. Run `systemctl --user daemon-reload` and `systemctl --user restart xdg-desktop-portal.service`.
