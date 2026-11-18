#!/usr/bin/env python3
"""Make MacShell's Smart Dock hide when a visible window overlaps it."""
from pathlib import Path
import sys

path = Path(sys.argv[1])
original = text = path.read_text()


def replace(old, new):
    global text
    if new and new in text:
        return
    if text.count(old) != 1:
        raise SystemExit(f"Dock smart hide: expected text missing or repeated: {old[:70]!r}")
    text = text.replace(old, new, 1)


marker = "    // Smart hide uses the shared geometry snapshot, including floating windows."
if marker not in text:
    replace(
        '// "smart"  = hide while a non-floating window is open on that monitor\'s workspace',
        '// "smart"  = hide while a visible window overlaps the Dock',
    )
    replace(
        'I18n.tr("Hides only while a tiled window needs the space")',
        'I18n.tr("Hides when a window overlaps the Dock")',
    )
    replace(
        '    Binding { target: root.hub; property: "dockWantsGeo"; value: root.liquidActive && root.glassLive && (root.dockEnabled || prefsWindow.visible) }',
        '    Binding {\n'
        '        target: root.hub; property: "dockWantsGeo"\n'
        '        value: (root.dockEnabled && root.hideMode === "smart")\n'
        '            || (root.liquidActive && root.glassLive && (root.dockEnabled || prefsWindow.visible))\n'
        '    }',
    )

    start = text.index("    // ── smart hide:")
    end = text.index("    Connections {\n        target: Hyprland\n", start)
    replace(text[start:end], marker + """
    readonly property var monData: hub ? hub.monData : []

    function overlapsDock(screen, dockWidth, dockHeight, bottomMargin) {
        var mon = monData.find(m => m.name === screen.name);
        if (!mon || dockWidth <= 0 || dockHeight <= 0) return false;

        // Use the resting footprint so sliding away or magnifying cannot change the answer.
        // Screen size is in logical pixels, like the client rectangles from Hyprland.
        var left = mon.x + (screen.width - dockWidth) / 2;
        var right = left + dockWidth;
        var bottom = mon.y + screen.height - bottomMargin;
        var top = bottom - dockHeight;
        var normal = mon.activeWorkspace && mon.activeWorkspace.id;
        var special = mon.specialWorkspace && mon.specialWorkspace.id;
        return glassClients.some(cl => {
            if (!cl.mapped || cl.hidden || cl.monitor !== mon.id || !cl.workspace || !cl.at || !cl.size) return false;
            var ws = cl.workspace.id;
            if (ws === undefined || (ws !== normal && (!special || ws !== special))) return false;
            var x = cl.at[0], y = cl.at[1], w = cl.size[0], h = cl.size[1];
            return w > 0 && h > 0 && x < right && x + w > left && y < bottom && y + h > top;
        });
    }

""")
    if "            busyDebounce.restart(); tickDebounce.restart();\n" in text:
        replace("            busyDebounce.restart(); tickDebounce.restart();\n", "            tickDebounce.restart();\n")
    else:
        replace("            busyDebounce.restart();\n", "")
    replace("    Timer { id: busyDebounce; interval: 120; onTriggered: root.refreshBusy() }\n", "")
    replace("        refreshBusy();                 // monitor geometry for the window compositor\n", "")
    replace("        refreshBusy();\n", "")
    replace(
        '                    || (root.hideMode === "smart" && root.busyMonitors[win.modelData.name] === true)',
        '                    || (root.hideMode === "smart" && root.overlapsDock(win.modelData,\n'
        '                        Math.min(ui.width, root.totalW0 + 2 * root.hPad), root.bgHeight, root.margin))',
    )

if text != original:
    path.write_text(text)

locale = path.parent / "lang" / "zh-CN.js"
if locale.is_file():
    original = text = locale.read_text()
    key = '    "Automatically hide and show the Dock": "自动隐藏和显示程序坞",\n'
    replace(key, key + '    "Hides when a window overlaps the Dock": "窗口与程序坞重叠时隐藏",\n')
    if text != original:
        locale.write_text(text)
