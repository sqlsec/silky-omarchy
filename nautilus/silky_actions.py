"""Small, local-path actions for Nautilus 4."""
import subprocess

from gi import require_version

require_version("Nautilus", "4.1")
require_version("Gdk", "4.0")
from gi.repository import Gdk, GObject, Nautilus


class SilkyActions(GObject.GObject, Nautilus.MenuProvider):
    @staticmethod
    def _path(file):
        location = file.get_location()
        return location.get_path() if location else None

    @staticmethod
    def _copy_paths(_item, paths):
        display = Gdk.Display.get_default()
        if display:
            display.get_clipboard().set_content(
                Gdk.ContentProvider.new_for_value("\n".join(paths))
            )

    @staticmethod
    def _open_terminal(_item, path):
        subprocess.Popen(["xdg-terminal-exec", "--dir=" + path], start_new_session=True)

    def _terminal_item(self, path):
        item = Nautilus.MenuItem(name="SilkyActions::terminal", label="在终端打开")
        item.connect("activate", self._open_terminal, path)
        return item

    def get_file_items(self, files):
        paths = [self._path(file) for file in files]
        if not paths or not all(paths):
            return []
        item = Nautilus.MenuItem(name="SilkyActions::copy_paths", label="复制路径")
        item.connect("activate", self._copy_paths, paths)
        items = [item]
        if len(files) == 1 and files[0].is_directory():
            items.append(self._terminal_item(paths[0]))
        return items

    def get_background_items(self, current_folder):
        path = self._path(current_folder)
        return [self._terminal_item(path)] if path else []
