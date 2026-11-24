#!/usr/bin/env python3
"""Make occupied non-active workspaces stand out in MacShell's top bar."""

import sys
from pathlib import Path

OLD_BLOCK = '''                                Rectangle {
                                    anchors.centerIn: parent
                                    width: parent.width - 2
                                    height: parent.height - 6
                                    radius: 6
                                    color: wsi.cur ? bpal.hover : "transparent"
                                    opacity: wsi.cur || wsMa.containsMouse ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 140 } }
                                }
                                Text {
                                    anchors.centerIn: parent
                                    text: "" + wsi.modelData
                                    color: wsi.cur ? bpal.fg : (wsi.busy ? bpal.fg2 : bpal.fg3)
                                    font.family: root.fontForWeight((wsi.cur ? Font.DemiBold : Font.Normal), bpal.fam)
                                    font.pixelSize: 13
                                    font.weight: wsi.cur ? Font.DemiBold : Font.Normal
                                    Behavior on color { ColorAnimation { duration: 140 } }
                                }'''

NEW_BLOCK = '''                                Rectangle {
                                    anchors.centerIn: parent
                                    width: parent.width - 2
                                    height: parent.height - 6
                                    radius: 6
                                    color: bpal.hover
                                    opacity: wsi.cur ? 1 : (wsMa.containsMouse ? 0.65 : 0)
                                    Behavior on opacity { NumberAnimation { duration: 140 } }
                                }
                                Text {
                                    anchors.centerIn: parent
                                    text: "" + wsi.modelData
                                    color: wsi.cur
                                        ? bpal.fg
                                        : (wsi.busy ? Qt.rgba(bpal.fg.r, bpal.fg.g, bpal.fg.b, 0.90) : (wsMa.containsMouse ? bpal.fg2 : bpal.fg3))
                                    font.family: root.fontForWeight((wsi.cur ? Font.DemiBold : (wsi.busy ? Font.Medium : Font.Normal)), bpal.fam)
                                    font.pixelSize: 13
                                    font.weight: wsi.cur ? Font.DemiBold : (wsi.busy ? Font.Medium : Font.Normal)
                                    Behavior on color { ColorAnimation { duration: 140 } }
                                }
                                Rectangle {
                                    id: wsBusyDot
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: 2
                                    width: 3
                                    height: 3
                                    radius: 1.5
                                    color: bpal.fg
                                    opacity: !wsi.cur && wsi.busy ? 0.85 : 0
                                    Behavior on opacity { NumberAnimation { duration: 140 } }
                                }'''

# The current workspace already has its pill; the dot only marks other workspaces with windows.
PREV_DOT_OPACITY = "                                    opacity: wsi.busy ? (wsi.cur ? 1 : 0.85) : 0"
NEXT_DOT_OPACITY = "                                    opacity: !wsi.cur && wsi.busy ? 0.85 : 0"


def tune(text: str) -> str:
    palette = "barWorkspacePalette." if "id: barContrast" in text else "bpal."
    new_block = NEW_BLOCK.replace("bpal.", palette)
    old_block = OLD_BLOCK.replace("bpal.", palette)
    if new_block in text:
        return text
    if PREV_DOT_OPACITY in text:
        updated = text.replace(PREV_DOT_OPACITY, NEXT_DOT_OPACITY, 1)
        if new_block in updated:
            return updated
    if text.count(old_block) != 1:
        raise ValueError("expected one workspace delegate block in MacBar.qml")
    return text.replace(old_block, new_block, 1)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(f"usage: {sys.argv[0]} <MacBar.qml>")
    path = Path(sys.argv[1])
    original = path.read_text()
    try:
        updated = tune(original)
    except ValueError as error:
        sys.exit(f"MacShell workspace indicators: {error}")
    if updated != original:
        path.write_text(updated)
