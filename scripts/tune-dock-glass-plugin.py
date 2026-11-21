#!/usr/bin/env python3
"""Let MacShell hand its glass to the silky-dock-glass Hyprland plugin (prototype, see docs/02-macshell.md).

With `SILKY_DOCK_GLASS_PLUGIN=1` in MacShell's environment (~/.config/macshell/env) and the Normal Blur style:
  * the Dock gets a SilkyGlassMarker (installed next to the QML): its glass rectangle is written into invisible pixels
    on the bottom row of the layer, which the plugin decodes on the GPU from the same buffer Hyprland draws, so the
    glass follows the magnifying Dock in the same frame;
  * the Dock stops drawing its own translucent tint.
The menu bar stays on plain blur (tried in plugin 0.2 and reverted).

Without the variable nothing changes. Usage: tune-dock-glass-plugin.py <MacShell dir>
"""
from pathlib import Path
import re
import shutil
import sys

shell = Path(sys.argv[1])
repo = Path(__file__).resolve().parent.parent
shutil.copyfile(repo / "config/macshell/SilkyGlassMarker.qml", shell / "SilkyGlassMarker.qml")


def tune(path, edits):
    text = path.read_text()
    original = text
    for old, new in edits:
        if new in text:
            continue
        if text.count(old) != 1:
            raise SystemExit(f"Glass plugin tuning ({path.name}): expected text missing or repeated: {old[:70]!r}")
        text = text.replace(old, new)
    if text != original:
        path.write_text(text)


# ── Dock ──
dock = shell / "MacDock.qml"
text = dock.read_text()
# the first prototype wrote its own one-rect marker: replace it with the shared component
text = re.sub(r"                // Silky: hidden marker for the silky-dock-glass plugin.*?\n                }\n\n(?=                Item \{\n                    id: dock\n)",
              "", text, flags=re.S)
dock.write_text(text)
tune(dock, [
    (
        "    readonly property real dockBlurBoost: 8    // extra px of blur added on top of glassBlur for the Dock glass only\n",
        "    readonly property real dockBlurBoost: 8    // extra px of blur added on top of glassBlur for the Dock glass only\n"
        "    // Silky: the silky-dock-glass Hyprland plugin paints the Dock glass (Normal Blur style only)\n"
        "    readonly property bool dockGlassPlugin: Quickshell.env(\"SILKY_DOCK_GLASS_PLUGIN\") === \"1\" && !liquidActive\n",
    ),
    (
        "                Item {\n"
        "                    id: dock\n",
        "                // Silky: tells the silky-dock-glass plugin where the Dock glass is (invisible pixels, bottom row)\n"
        "                SilkyGlassMarker {\n"
        "                    enabled: root.dockGlassPlugin\n"
        "                    rects: [{ x: dock.x, y: dock.y, w: dock.width, h: dock.height, r: Math.min(root.cornerRadius, dock.height / 2),\n"
        "                              a: 1, dark: root.dockDark, kind: 0 }]\n"
        "                }\n"
        "\n"
        "                Item {\n"
        "                    id: dock\n",
    ),
    (
        "                        visible: !root.liquidActive\n"
        "                        anchors.fill: parent\n"
        "                        radius: root.cornerRadius\n",
        "                        visible: !root.liquidActive && !root.dockGlassPlugin\n"
        "                        anchors.fill: parent\n"
        "                        radius: root.cornerRadius\n",
    ),
])
