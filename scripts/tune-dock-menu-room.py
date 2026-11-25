#!/usr/bin/env python3
"""Give tall MacShell Dock menus enough room above the Dock.

The Dock's layer surface kept a fixed 300 px (menuRoom) above the magnified
icons. A Files menu with several open windows plus the folder shortcuts is
taller, so its top rows were clipped by the surface edge. menuRoom is now sized
once for the tallest menu the Dock can build (8 window rows, the Files folder
shortcuts and the app actions), scaled with the icon size. The surface never
resizes when a menu opens, so the Dock does not jump. The input mask is
unchanged.

An earlier version of this script grew the surface while a menu was open, which
made the Dock slide on every right-click; it is undone here.

Usage: tune-dock-menu-room.py <MacDock.qml>
"""

import sys
from pathlib import Path

ROOM_OLD = "    readonly property int menuRoom: 300\n"
ROOM_NEW = """\
    // Silky: room for the tallest Dock menu (8 windows + Files folders + actions: 17 rows, 5 separators), fixed so the
    // surface never resizes when a menu opens. Matches the menu metrics: 22 / 11 pt rows, 5 pt padding, 9 pt tail, 10 pt gap.
    readonly property int menuRoom: Math.max(300, 17 * Math.round(22 * labelK) + 5 * Math.round(11 * labelK)
                                                  + 2 * Math.round(5 * labelK) + Math.ceil(9 * labelK) + Math.round(10 * labelK) + 8 - 72)
"""

# Undo the earlier dynamic-resize variant.
DYN_HEIGHT_OLD = "            implicitHeight: root.windowHeight + ui.silkyMenuExtra\n"
DYN_HEIGHT_NEW = "            implicitHeight: root.windowHeight\n"
DYN_PROP = """\
                // Silky: extra surface height for menus taller than root.menuRoom (no ui.height dependency, so no binding loop)
                readonly property int silkyMenuExtra: (menuOpen || menu.visible)
                    ? Math.max(0, Math.ceil(root.margin + root.bgHeight + root.iconSize * (root.effMag - 1)
                                            + Math.round(10 * root.labelK) + menu.height + 8) - root.windowHeight)
                    : 0
"""

Y_OLD = """\
                    y: ui.menuIconTop >= 0 ? ui.menuIconTop - Math.round(10 * k) - height
                                           : ui.height - root.margin - root.bgHeight - root.iconSize * (root.effMag - 1) - Math.round(10 * k) - height
"""
Y_NEW = """\
                    y: Math.max(8, ui.menuIconTop >= 0 ? ui.menuIconTop - Math.round(10 * k) - height
                                           : ui.height - root.margin - root.bgHeight - root.iconSize * (root.effMag - 1) - Math.round(10 * k) - height)
"""


def tune(text):
    text = text.replace(DYN_HEIGHT_OLD, DYN_HEIGHT_NEW, 1).replace(DYN_PROP, "", 1)
    if "silkyMenuExtra" in text:
        raise ValueError("could not remove the earlier menu resize")
    if ROOM_NEW not in text:
        if text.count(ROOM_OLD) != 1:
            raise ValueError("expected one menuRoom property")
        text = text.replace(ROOM_OLD, ROOM_NEW, 1)
    if Y_NEW not in text:
        if text.count(Y_OLD) != 1:
            raise ValueError("expected one menu position")
        text = text.replace(Y_OLD, Y_NEW, 1)
    return text


if __name__ == "__main__":
    try:
        path = Path(sys.argv[1])
        original = path.read_text()
        updated = tune(original)
        if updated != original:
            path.write_text(updated)
    except (IndexError, OSError, ValueError) as error:
        sys.exit(f"MacShell Dock menu room: {error}")
