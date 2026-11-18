#!/usr/bin/env python3
"""Give the Dock's right-click menu the same see-through glass as the Dock itself.

DockGlassPanel draws the menu as blurred backdrop + a fixed tint of 0.50-0.58 alpha (dark) / 0.36-0.44 (light).
The Dock tints its glass with only glassOpacity * 0.55 (~0.21 at the Silky default of 0.38), so the menu read as a
flat grey slab next to the Dock. This adds a `tintScale` to DockGlassPanel (1 = unchanged, used by the hover label)
and lets the menu follow the Dock's glass settings: tint scaled by the Glass Opacity slider, blur by the Blur slider.

Usage: tune-dock-menu-glass.py <MacShell dir>
"""
from pathlib import Path
import sys

shell = Path(sys.argv[1])


def tune(path, edits):
    text = path.read_text()
    original = text
    for old, new in edits:
        if new in text:
            continue
        if text.count(old) != 1:
            raise SystemExit(f"Dock menu glass tuning ({path.name}): expected text missing or repeated: {old[:70]!r}")
        text = text.replace(old, new)
    if text != original:
        path.write_text(text)


tune(shell / "DockGlassPanel.qml", [
    (
        '    property real blurAmount: 0.85       // 0..1 of the 64 px blur kernel: "very blurred"\n',
        '    property real blurAmount: 0.85       // 0..1 of the 64 px blur kernel: "very blurred"\n'
        '    property real tintScale: 1.0         // multiplies the live tint\'s alpha (lower = more see-through glass)\n',
    ),
    (
        '    readonly property string shapeKey: [width, bodyH, tailW, tailH, tailTipR, tailX, radius, dark, live, k].join("|")\n',
        '    readonly property string shapeKey: [width, bodyH, tailW, tailH, tailTipR, tailX, radius, dark, live, k, tintScale].join("|")\n',
    ),
    (
        '            if (gp.dark) {\n'
        '                g.addColorStop(0, gp.live ? "rgba(56,56,62,0.50)" : "rgb(54,54,59)");\n'
        '                g.addColorStop(1, gp.live ? "rgba(30,30,34,0.58)" : "rgb(34,34,38)");\n'
        '            } else {\n'
        '                g.addColorStop(0, gp.live ? "rgba(255,255,255,0.44)" : "rgb(246,246,249)");\n'
        '                g.addColorStop(1, gp.live ? "rgba(255,255,255,0.36)" : "rgb(236,236,241)");\n'
        '            }\n',
        '            var ts = Math.max(0, Math.min(1, gp.tintScale));\n'
        '            if (gp.dark) {\n'
        '                g.addColorStop(0, gp.live ? "rgba(56,56,62," + (0.50 * ts).toFixed(3) + ")" : "rgb(54,54,59)");\n'
        '                g.addColorStop(1, gp.live ? "rgba(30,30,34," + (0.58 * ts).toFixed(3) + ")" : "rgb(34,34,38)");\n'
        '            } else {\n'
        '                g.addColorStop(0, gp.live ? "rgba(255,255,255," + (0.44 * ts).toFixed(3) + ")" : "rgb(246,246,249)");\n'
        '                g.addColorStop(1, gp.live ? "rgba(255,255,255," + (0.36 * ts).toFixed(3) + ")" : "rgb(236,236,241)");\n'
        '            }\n',
    ),
])

tune(shell / "MacDock.qml", [
    # Windows under the open menu are captured live too. Before, only windows within ~48 px of the Dock were captured
    # and every capture paused while the menu was open, so a window above the Dock showed a stale kept frame (a white
    # page behind a black terminal). Only windows the menu (+ its blur reach) covers stream; the rest stay paused.
    (
        '                                readonly property real dockTop: dock.y + bd.height - ui.height\n',
        '                                readonly property real dockTop: dock.y + bd.height - ui.height\n'
        '                                // Silky: the open right-click menu (+ its blur reach) covers this window\n'
        '                                readonly property real menuTop: menu.y + bd.height - ui.height\n'
        '                                readonly property bool underMenu: ui.menuOpen\n'
        '                                    && x < menu.x + menu.width + 64 && x + width > menu.x - 64\n'
        '                                    && y < menuTop + menu.height + 64 && y + height > menuTop - 64\n',
    ),
    (
        '                                readonly property bool nearNow: !ui.tucked\n',
        '                                readonly property bool nearNow: underMenu || !ui.tucked\n',
    ),
    (
        'readonly property bool canRun: !quiet && !ui.tucked && !ui.menuOpen && (root.glassRT',
        'readonly property bool canRun: !quiet && !ui.tucked && (!ui.menuOpen || gw.underMenu) && (root.glassRT',
    ),
    (
        'wantLive: root.glassRT && canRun && gw.overlap && !ui.tucked\n',
        'wantLive: root.glassRT && canRun && (gw.overlap || gw.underMenu) && !ui.tucked\n',
    ),
    (
        '                    frozen: ui.menuOpen      // the menu\'s glass stops updating while it is open\n'
        '                    dark: root.darkMode\n',
        '                    frozen: false            // Silky: real-time glass while the menu is open (GPU blur of a menu-sized region)\n'
        '                    // Silky: same glass as the Dock: tint follows Glass Opacity, blur follows the Dock\'s blur (glassBlur + dockBlurBoost)\n'
        '                    tintScale: Math.max(0.35, Math.min(1, root.glassOpacity * 1.5))\n'
        '                    blurAmount: Math.max(0.35, Math.min(0.85, (root.glassBlur + root.dockBlurBoost) / 48))\n'
        '                    dark: root.darkMode\n',
    ),
])
