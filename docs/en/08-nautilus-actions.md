# 08 · File manager context menu

[简体中文](../08-nautilus-actions.md) | English

Run `./scripts/install-nautilus-actions.sh`, close every file window, run `nautilus -q` and open the file manager again. The script installs the extension into `~/.local/share/nautilus-python/extensions/` and backs up an existing different version when updating; it needs `nautilus-python` and `xdg-terminal-exec`.

- Right-click a local file or folder and choose "Copy Path"; with several selected, one path per line.
- Right-click a local folder, or the empty space of a file list, and choose "Open in Terminal". The terminal is the system default.
- Right-click files or folders and use Nautilus's own "Compress…"; right-click a supported archive and choose "Extract Here" or "Extract to…". Which formats work depends on the system's archive support.
- Remote locations have no local path, so the two extension menus do not appear there.

To uninstall, delete `~/.local/share/nautilus-python/extensions/silky_actions.py`, then quit and reopen Nautilus.
