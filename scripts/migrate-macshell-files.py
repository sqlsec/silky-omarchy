#!/usr/bin/env python3
"""Migrate stale Nautilus launchers after Omarchy switches to Folio."""

import argparse
import json
import os
import re
import shutil
import subprocess
from datetime import datetime
from pathlib import Path
from tempfile import NamedTemporaryFile


NAUTILUS = "org.gnome.nautilus"
LOCALE_LAUNCH = (
    "/usr/bin/env -u LC_ALL LC_MESSAGES=zh_CN.UTF-8 "
    "LC_TIME=zh_CN.UTF-8 LANGUAGE=zh_CN /usr/bin/nautilus"
)
OLD_BINDINGS = (
    "-- >>> Silky Nautilus zh_CN >>>\n"
    f'o.rebind("SUPER + SHIFT + F", "文件管理器", [[setsid uwsm-app -- {LOCALE_LAUNCH} --new-window]])\n'
    'o.rebind("SUPER + ALT + SHIFT + F", "在当前目录打开文件管理器", '
    f'[[setsid uwsm-app -- {LOCALE_LAUNCH} --new-window "$(omarchy-cmd-terminal-cwd)"]])\n'
    "-- <<< Silky Nautilus zh_CN <<<\n"
)


def desktop_id(pin):
    return str(pin).removesuffix(".desktop").casefold()


def migrate_pins(pins):
    if not any(desktop_id(pin) == NAUTILUS for pin in pins):
        return pins
    migrated = []
    for pin in pins:
        if desktop_id(pin) in (NAUTILUS, "folio"):
            if "folio" not in migrated:
                migrated.append("folio")
        else:
            migrated.append(pin)
    return migrated


def write_with_backup(path, content, stamp):
    path = path.resolve()
    backup = path.with_name(f"{path.name}.bak.folio.{stamp}")
    shutil.copy2(path, backup)
    with NamedTemporaryFile(
        mode="w", encoding="utf-8", dir=path.parent, prefix=f".{path.name}.", delete=False
    ) as stream:
        temporary = Path(stream.name)
        try:
            stream.write(content)
            stream.close()
            shutil.copymode(path, temporary)
            temporary.replace(path)
        finally:
            temporary.unlink(missing_ok=True)
    print(f"Updated {path} (backup: {backup})")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Check without writing files.")
    args = parser.parse_args()
    if shutil.which("nautilus") or not shutil.which("folio"):
        return
    if subprocess.check_output(["xdg-mime", "query", "default", "inode/directory"], text=True).strip() != "folio.desktop":
        return

    home = Path.home()
    config = Path(os.environ.get("XDG_CONFIG_HOME") or home / ".config")
    data = Path(os.environ.get("XDG_DATA_HOME") or home / ".local/share")
    updates = {}

    pins_path = config / "macdock/pinned.json"
    if pins_path.is_file():
        pins = json.loads(pins_path.read_text())
        if not isinstance(pins, list):
            raise SystemExit(f"Expected a list of Dock pins in {pins_path}")
        migrated = migrate_pins(pins)
        if migrated != pins:
            updates[pins_path] = json.dumps(migrated, indent=2, ensure_ascii=False) + "\n"

    bindings_path = config / "hypr/bindings.lua"
    if bindings_path.is_file() and shutil.which("omarchy-launch-files") and shutil.which("omarchy-launch-files-cwd"):
        bindings = bindings_path.read_text()
        if OLD_BINDINGS in bindings:
            updates[bindings_path] = bindings.replace(OLD_BINDINGS, "", 1)

    desktop_path = data / "applications/org.gnome.Nautilus.desktop"
    archive_desktop = False
    if desktop_path.is_file():
        entry = desktop_path.read_text().split("\n[Desktop Action ", 1)[0]
        archive_desktop = bool(re.search(rf"(?m)^Exec={re.escape(LOCALE_LAUNCH)}(?: |$)", entry))

    if args.check:
        return
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    for path, content in updates.items():
        write_with_backup(path, content, stamp)
    if archive_desktop:
        backup = desktop_path.with_name(f"{desktop_path.name}.bak.folio.{stamp}")
        desktop_path.rename(backup)
        print(f"Archived {desktop_path} (backup: {backup})")


if __name__ == "__main__":
    main()
