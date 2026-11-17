#!/usr/bin/env python3
"""Keep a Dock icon's hover label away after the icon was clicked, until the pointer really moves.

The label is a whole glass bubble; building one takes 60-70 ms on the shell's only GUI thread. Clicking the
Applications icon repeatedly moves the pointer focus between the Dock and the full-screen Applications panel, and
every return to the Dock built the bubble again in the middle of the panel's animation. macOS does the same thing
this script does: after a click the label stays hidden until the pointer moves.
"""
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
original = text


def replace(old, new):
    global text
    if new in text:
        return
    if text.count(old) != 1:
        raise SystemExit(f"Dock hover label tuning: expected text missing or repeated: {old[:70]!r}")
    text = text.replace(old, new)


replace(
    "                                readonly property bool tipOn: root.showLabels && !cell.isSep && cell.hoverSettled && ma.containsMouse && !ma.pressed && !ui.menuOpen && !ui.dragging\n",
    "                                // set by a press on the icon, cleared once the pointer has moved a few pixels (see ma)\n"
    "                                property bool tipMuted: false\n"
    "                                readonly property bool tipOn: root.showLabels && !cell.isSep && cell.hoverSettled && !cell.tipMuted && ma.containsMouse && !ma.pressed && !ui.menuOpen && !ui.dragging\n",
)
replace(
    "                                    property real pressX: 0\n"
    "\n"
    "                                    property real pressY: 0\n"
    "                                    onPressed: mouse => {\n",
    "                                    property real pressX: 0\n"
    "\n"
    "                                    property real pressY: 0\n"
    "                                    property real muteX: 0\n"
    "                                    property real muteY: 0\n"
    "                                    onPressed: mouse => {\n"
    "                                        var mp = ma.mapToItem(ui, mouse.x, mouse.y);\n"
    "                                        muteX = mp.x; muteY = mp.y; cell.tipMuted = true;\n",
)
replace(
    "                                    onPositionChanged: mouse => {\n"
    "                                        if (!(pressedButtons & Qt.LeftButton) || cell.isSep) return;\n",
    "                                    onPositionChanged: mouse => {\n"
    "                                        if (cell.tipMuted) {\n"
    "                                            var mq = ma.mapToItem(ui, mouse.x, mouse.y);\n"
    "                                            if (Math.abs(mq.x - muteX) > 4 || Math.abs(mq.y - muteY) > 4) cell.tipMuted = false;\n"
    "                                        }\n"
    "                                        if (!(pressedButtons & Qt.LeftButton) || cell.isSep) return;\n",
)

if text != original:
    path.write_text(text)
