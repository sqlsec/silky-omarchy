#!/usr/bin/env python3
"""Run the MacShell Dock's Empty Trash action on the first click."""

import sys
from pathlib import Path

OLD = 'label: I18n.tr("Empty Trash"), confirm: true, disabled: !trashFull'
NEW = 'label: I18n.tr("Empty Trash"), disabled: !trashFull'


def tune(text):
    if text.count(NEW) == 1 and OLD not in text:
        return text
    if text.count(OLD) != 1 or NEW in text:
        raise ValueError("expected one Empty Trash menu item")
    return text.replace(OLD, NEW, 1).replace(" (e.g. Empty Trash)", "", 1)


if __name__ == "__main__":
    try:
        path = Path(sys.argv[1])
        original = path.read_text()
        updated = tune(original)
        if updated != original:
            path.write_text(updated)
    except (OSError, ValueError) as error:
        sys.exit(f"MacShell Dock Trash: {error}")
