#!/usr/bin/env python3
"""Remove the outer strokes on MacShell's clock and installer windows."""
from pathlib import Path
import sys


def tune(path, edits):
    original = path.read_text()
    text = original
    for before, after in edits:
        if after in text:
            continue
        if text.count(before) != 1:
            raise SystemExit(f"Window edge tuning ({path}): expected one match for {before[:80]!r}")
        text = text.replace(before, after)
    if text != original:
        path.write_text(text)


shell = Path(sys.argv[1])
for filename in ("ClockApp.qml", "Installer.qml"):
    tune(shell / filename, [
        (
            "            readonly property color ctrlSel: dark ? \"#636366\" : \"#FFFFFF\"\n"
            "            readonly property color border: dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.2)\n"
            "            function lightBorder",
            "            readonly property color ctrlSel: dark ? \"#636366\" : \"#FFFFFF\"\n"
            "            function lightBorder",
        ) if filename == "ClockApp.qml" else (
            "            property color pill: dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.07)\n"
            "            property color border: dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.2)\n"
            "            property color lightOff",
            "            property color pill: dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.07)\n"
            "            property color lightOff",
        ),
        (
            "            color: pal.bg\n"
            "            border.width: 1; border.color: pal.border\n"
            "            clip: true\n",
            "            color: pal.bg\n"
            "            clip: true\n",
        ),
    ])

installer = shell.parent / "MacInstaller/shell.qml"
if installer.is_file():
    tune(installer, [
        (
            "        readonly property color cardBorder: dark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.12)\n"
            "        readonly property color edgeOuter: Qt.rgba(1, 1, 1, 0.50)\n"
            "        readonly property color edgeInner: dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.65)\n"
            "        readonly property color sep:",
            "        readonly property color cardBorder: dark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.12)\n"
            "        readonly property color sep:",
        ),
        (
            """            color: "transparent"
            border.width: 1
            border.color: root.pal.edgeOuter

            // inner highlight: with the outer line this is the two-tone edge macOS windows have
            Rectangle {
                anchors.fill: parent; anchors.margins: 1
                radius: frame.radius - 1
                color: "transparent"
                border.width: 1; border.color: root.pal.edgeInner
                z: 900
            }

            // Backdrop""",
            """            color: "transparent"

            // Backdrop""",
        ),
        (
            """                x: sidebar.x + sidebar.width; y: 1
                width: parent.width - x - 1; height: parent.height - 2
                radius: 11
                color: root.pal.contentSolid
                Rectangle { anchors.left: parent.left; width: 12; height: parent.height; color: parent.color }""",
            """                x: sidebar.x + sidebar.width
                width: parent.width - x; height: parent.height
                color: root.pal.contentSolid""",
        ),
        (
            """                x: 1; y: 1
                width: 232
                height: parent.height - 2
                radius: 11
                color: "transparent"
                // translucent fill drawn as ONE layer so the rounded body and the square right edge don't add up to a darker band
                Item {
                    anchors.fill: parent
                    z: -1
                    layer.enabled: true
                    opacity: root.pal.sidebarGlass.a
                    Rectangle { anchors.fill: parent; radius: sidebar.radius; color: Qt.rgba(root.pal.sidebarGlass.r, root.pal.sidebarGlass.g, root.pal.sidebarGlass.b, 1) }
                    Rectangle { anchors.right: parent.right; width: 14; height: parent.height; color: Qt.rgba(root.pal.sidebarGlass.r, root.pal.sidebarGlass.g, root.pal.sidebarGlass.b, 1) }
                }""",
            """                width: 233
                height: parent.height
                color: root.pal.sidebarGlass""",
        ),
    ])
