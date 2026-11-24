#!/usr/bin/env python3
"""Allow MacDock clicks while the Applications panel is open, like macOS Launchpad."""
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
s = path.read_text()
original = s

# 1. Expose each screen's quantized Dock input rectangle so MacBar's spotWin mask
#    can carve out just the Dock capsule while keeping surrounding desktop space
#    click-to-dismiss.
prop_marker = "    property var silkyDockRects: ({})\n"
if prop_marker not in s:
    anchor = "    property string hideMode:"
    if anchor not in s:
        raise SystemExit("Dock passthrough tuning: property anchor missing in MacDock.qml")
    s = s.replace(anchor, prop_marker + anchor, 1)

sync_fn = (
    "                    function syncSilkyDockRect() {\n"
    "                        var name = win.modelData ? win.modelData.name : \"\";\n"
    "                        if (!name) return;\n"
    "                        var prev = root.silkyDockRects || ({});\n"
    "                        var next = ({});\n"
    "                        for (var k in prev) next[k] = prev[k];\n"
    "                        if (win.visible && root.dockEnabled && maskItem.width > 0 && maskItem.height > 0) {\n"
    "                            next[name] = Qt.rect(maskItem.x, win.modelData.height - win.implicitHeight + maskItem.y,\n"
    "                                                 maskItem.width, maskItem.height);\n"
    "                        } else {\n"
    "                            delete next[name];\n"
    "                        }\n"
    "                        root.silkyDockRects = next;\n"
    "                    }\n"
    "                    onXChanged: Qt.callLater(syncSilkyDockRect)\n"
    "                    onYChanged: Qt.callLater(syncSilkyDockRect)\n"
    "                    onWidthChanged: Qt.callLater(syncSilkyDockRect)\n"
    "                    onHeightChanged: Qt.callLater(syncSilkyDockRect)\n"
    "                    Component.onCompleted: Qt.callLater(syncSilkyDockRect)\n"
    "                    Connections {\n"
    "                        target: win\n"
    "                        function onVisibleChanged() { Qt.callLater(maskItem.syncSilkyDockRect); }\n"
    "                        function onImplicitHeightChanged() { Qt.callLater(maskItem.syncSilkyDockRect); }\n"
    "                    }\n"
    "                    Connections {\n"
    "                        target: root\n"
    "                        function onDockEnabledChanged() { Qt.callLater(maskItem.syncSilkyDockRect); }\n"
    "                    }\n"
)

if "function syncSilkyDockRect()" not in s:
    mask_anchor = (
        "                Item {\n"
        "                    id: maskItem\n"
    )
    if s.count(mask_anchor) != 1:
        raise SystemExit("Dock passthrough tuning: maskItem anchor missing in MacDock.qml")
    s = s.replace(mask_anchor, mask_anchor + sync_fn, 1)

# 2. Clicking any other Dock item (minimized window, Trash, running/pinned app)
#    dismisses the Applications panel smoothly and activates that item immediately.
old_activate = (
    '    function activate(item, forceNew) {\n'
    '        if (item.kind === "win") { restoreWindow(item); return; }\n'
    '        if (item.special === "apps") { if (bar) bar.spotOpen("apps"); return; }\n'
)
new_activate = (
    '    function activate(item, forceNew) {\n'
    '        if (item.special === "apps") { if (bar) bar.spotOpen("apps"); return; }\n'
    '        if (bar) bar.spotOpen("apps-close");\n'
    '        if (item.kind === "win") { restoreWindow(item); return; }\n'
)
if new_activate not in s:
    if old_activate not in s:
        raise SystemExit("Dock passthrough tuning: activate() anchor missing in MacDock.qml")
    s = s.replace(old_activate, new_activate, 1)

if s != original:
    path.write_text(s)
