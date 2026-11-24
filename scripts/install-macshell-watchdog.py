#!/usr/bin/env python3
"""Install the process watchdog into an existing MacShell launcher."""

import argparse
import os
import shutil
import tempfile
from pathlib import Path

WATCHDOG = Path(__file__).resolve().parents[1] / "config/macshell/watchdog.py"
BLOCK = """    if [ "$NAME" = MacShell ] && [ -f "$CONF/macshell/watchdog.py" ]; then
        /usr/bin/python3 "$CONF/macshell/watchdog.py" "$pid" >>"$LOG" 2>&1 &
    fi
"""
ANCHOR = '    pid=$!\n'


def install(source: Path, target: Path) -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("backup", type=Path)
    args = parser.parse_args()
    launcher = Path.home() / ".local/bin/macshell-start"
    original = launcher.read_text()
    if BLOCK not in original and original.count(ANCHOR) != 1:
        raise SystemExit(f"Cannot find the MacShell child process in {launcher}")

    args.backup.mkdir(parents=True, exist_ok=True)
    target.parent.mkdir(parents=True, exist_ok=True)
    if not target.exists() or target.read_bytes() != source.read_bytes():
        if target.exists():
            shutil.copy2(target, args.backup / "macshell-watchdog.py")
        shutil.copyfile(source, target)

    if BLOCK not in original:
        backup = args.backup / launcher.name
        if not backup.exists():
            shutil.copy2(launcher, backup)
        with tempfile.NamedTemporaryFile(mode="w", dir=launcher.parent, delete=False) as new_launcher:
            new_launcher.write(original.replace(ANCHOR, ANCHOR + BLOCK, 1))
        shutil.copymode(launcher, new_launcher.name)
        os.replace(new_launcher.name, launcher)


if __name__ == "__main__":
    config = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
    install(WATCHDOG, config / "macshell/watchdog.py")
