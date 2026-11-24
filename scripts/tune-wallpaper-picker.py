#!/usr/bin/env python3
"""Tidy the wallpaper grid in MacShell Settings.

- The grid stops on whole rows, so the bottom row's names are never cut in half.
- Names drop underscores and a trailing resolution such as `_2560x1440`.
- The favourite badge is a light disc with a dark outline star, readable on black and white thumbnails.
"""

import sys
from pathlib import Path

EDITS = [
    (
        "                    boundsBehavior: Flickable.StopAtBounds\n"
        "                    model: wpPane.shown\n",
        "                    boundsBehavior: Flickable.StopAtBounds\n"
        "                    // Stop on whole rows so the bottom row's names are never cut through.\n"
        "                    snapMode: GridView.SnapToRow\n"
        "                    model: wpPane.shown\n",
    ),
    (
        '                function nameOf(p) { var n = p.substring(p.lastIndexOf("/") + 1); var k = n.lastIndexOf("."); return k > 0 ? n.substring(0, k) : n; }\n',
        '                function nameOf(p) { var n = p.substring(p.lastIndexOf("/") + 1); var k = n.lastIndexOf("."); return displayName(k > 0 ? n.substring(0, k) : n); }\n'
        "                // File names read as titles: no underscores and no trailing pixel size.\n"
        "                function displayName(n) {\n"
        '                    var s = String(n).replace(/[ _-]*\\d{3,5}\\s*[x×]\\s*\\d{3,5}$/i, "").replace(/_+/g, " ").replace(/\\s+/g, " ").trim();\n'
        "                    return s !== \"\" ? s : String(n);\n"
        "                }\n",
    ),
    (
        "                                elide: Text.ElideMiddle\n"
        "                                text: wt.modelData.name\n",
        "                                elide: Text.ElideRight\n"
        "                                text: wpPane.displayName(wt.modelData.name)\n",
    ),
    (
        "                                        width: 26; height: 26; radius: 13\n"
        "                                        visible: wt.modelData.fav || wtMa.containsMouse || wtFavMa.containsMouse\n"
        "                                        color: Qt.rgba(0, 0, 0, wtFavMa.containsMouse ? 0.72 : 0.52)\n"
        "                                        Text {\n"
        "                                            anchors.centerIn: parent\n"
        '                                            text: wt.modelData.fav ? "★" : "☆"\n'
        '                                            color: wt.modelData.fav ? "#ffd60a" : "white"\n',
        "                                        width: 24; height: 24; radius: 12\n"
        "                                        visible: wt.modelData.fav || wtMa.containsMouse || wtFavMa.containsMouse\n"
        "                                        // A light disc with a hairline reads the same on black and white thumbnails.\n"
        "                                        color: Qt.rgba(1, 1, 1, wtFavMa.containsMouse ? 0.96 : 0.84)\n"
        "                                        border.width: 1\n"
        "                                        border.color: Qt.rgba(0, 0, 0, 0.14)\n"
        "                                        Text {\n"
        "                                            anchors.centerIn: parent\n"
        '                                            text: wt.modelData.fav ? "★" : "☆"\n'
        '                                            color: wt.modelData.fav ? "#e0a100" : "#3a3a3c"\n',
    ),
]


def tune(text: str) -> str:
    for old, new in EDITS:
        if new in text:
            continue
        if text.count(old) != 1:
            raise ValueError(f"expected one match for {old.strip().splitlines()[0][:80]!r}")
        text = text.replace(old, new, 1)
    return text


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(f"usage: {sys.argv[0]} <MacDock.qml>")
    path = Path(sys.argv[1])
    original = path.read_text()
    try:
        updated = tune(original)
    except ValueError as error:
        sys.exit(f"MacShell wallpaper picker: {error}")
    if updated != original:
        path.write_text(updated)
