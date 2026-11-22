#!/usr/bin/env python3
"""Let MacShell hand its glass to the silky-dock-glass Hyprland plugin (see docs/02-macshell.md).

With `SILKY_DOCK_GLASS_PLUGIN=1` in MacShell's environment (~/.config/macshell/env) and the Normal Blur style:
  * the Dock gets a SilkyGlassMarker (installed next to the QML): its glass rectangle is written into invisible pixels
    on the bottom row of the layer, which the plugin decodes on the GPU from the same buffer Hyprland draws, so the
    glass follows the magnifying Dock in the same frame;
  * MacBar's popovers (Apple/app menus, Control Center, Wi-Fi, Bluetooth, Volume, Battery/Status, Notification Center,
    toasts) and overlays (Spotlight/Apps, Switcher, Wallpaper Picker, OSD) register their LGlass/GGlass items with per-
    window SilkyGlassMarker instances; nested platters inside a larger glass panel keep their own Qt tint;
  * the thin top menu bar strip (macbarbg) stays on native blur and is not touched;
  * plugin-owned glass items stop drawing their own translucent Normal Blur backdrop.

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


# ── Menu bar popovers & overlays (macbar, macswitch, macwall, macosd, macspot; macbarbg untouched) ──
bar = shell / "MacBar.qml"
if bar.is_file():
    # Upgrade existing installs so GGlass reads silkyKind from gg.gx (kind 2 for Control Center bubbles).
    bar_text = bar.read_text()
    bar_updated = bar_text.replace(
        "        readonly property bool silkyDark: !!gg.gx.dark\n"
        "        readonly property int silkyKind: 1\n",
        "        readonly property bool silkyDark: !!gg.gx.dark\n"
        "        readonly property int silkyKind: (gg.gx && gg.gx.silkyKind !== undefined) ? gg.gx.silkyKind : 1\n",
    )
    if bar_updated != bar_text:
        bar.write_text(bar_updated)

    tune(bar, [
        (
            "    readonly property bool liquidActive: barStyle === \"liquid\" && glassState === \"ready\" && !gaming\n",
            "    readonly property bool liquidActive: barStyle === \"liquid\" && glassState === \"ready\" && !gaming\n"
            "    // Silky: the silky-dock-glass Hyprland plugin paints menu/popover/overlay glass (Normal Blur style only)\n"
            "    readonly property bool barGlassPlugin: Quickshell.env(\"SILKY_DOCK_GLASS_PLUGIN\") === \"1\" && !liquidActive\n"
            "    property var silkyGlassItems: []\n"
            "    property int silkyGlassPoke: 0\n"
            "    function registerGlassItem(it) {\n"
            "        if (!it || silkyGlassItems.indexOf(it) !== -1) return;\n"
            "        silkyGlassItems = silkyGlassItems.concat([it]);\n"
            "    }\n"
            "    function unregisterGlassItem(it) {\n"
            "        var i = silkyGlassItems.indexOf(it);\n"
            "        if (i === -1) return;\n"
            "        var next = silkyGlassItems.slice();\n"
            "        next.splice(i, 1);\n"
            "        silkyGlassItems = next;\n"
            "    }\n"
            "    function pokeGlassMarkers() { if (barGlassPlugin) silkyGlassPoke++; }\n",
        ),
        (
            "        signal shaderError()\n"
            "\n"
            "        Rectangle {\n"
            "            visible: !g.liquid\n",
            "        signal shaderError()\n"
            "        // Silky: register with per-window SilkyGlassMarker for compositor Liquid Glass\n"
            "        property bool silkyOwned: false\n"
            "        readonly property bool silkyDark: g.dark\n"
            "        readonly property int silkyKind: 1\n"
            "        Component.onCompleted: root.registerGlassItem(g)\n"
            "        Component.onDestruction: root.unregisterGlassItem(g)\n"
            "        onVisibleChanged: if (visible) root.pokeGlassMarkers()\n"
            "\n"
            "        Rectangle {\n"
            "            visible: !g.liquid && !g.silkyOwned\n",
        ),
        (
            "        readonly property point fp: framePos()\n"
            "\n"
            "        Rectangle {\n"
            "            visible: !gg.gx.liquid\n",
            "        readonly property point fp: framePos()\n"
            "        // Silky: register with per-window SilkyGlassMarker for compositor Liquid Glass\n"
            "        property bool silkyOwned: false\n"
            "        readonly property bool silkyDark: !!gg.gx.dark\n"
            "        readonly property int silkyKind: (gg.gx && gg.gx.silkyKind !== undefined) ? gg.gx.silkyKind : 1\n"
            "        Component.onCompleted: root.registerGlassItem(gg)\n"
            "        Component.onDestruction: root.unregisterGlassItem(gg)\n"
            "        onVisibleChanged: if (visible) root.pokeGlassMarkers()\n"
            "\n"
            "        Rectangle {\n"
            "            visible: !gg.gx.liquid && !gg.silkyOwned\n",
        ),
        (
            "            Item {\n"
            "                id: ui\n"
            "                anchors.fill: parent\n",
            "            Item {\n"
            "                id: ui\n"
            "                anchors.fill: parent\n"
            "                SilkyGlassMarker {\n"
            "                    enabled: root.barGlassPlugin\n"
            "                    items: root.silkyGlassItems\n"
            "                    poke: root.silkyGlassPoke\n"
            "                }\n",
        ),
        (
            "            Item {\n"
            "                id: swRoot\n"
            "                anchors.fill: parent\n",
            "            Item {\n"
            "                id: swRoot\n"
            "                anchors.fill: parent\n"
            "                SilkyGlassMarker {\n"
            "                    enabled: root.barGlassPlugin\n"
            "                    items: root.silkyGlassItems\n"
            "                    poke: root.silkyGlassPoke\n"
            "                }\n",
        ),
        (
            "            Item {\n"
            "                id: wpRoot\n"
            "                anchors.fill: parent\n",
            "            Item {\n"
            "                id: wpRoot\n"
            "                anchors.fill: parent\n"
            "                SilkyGlassMarker {\n"
            "                    enabled: root.barGlassPlugin\n"
            "                    items: root.silkyGlassItems\n"
            "                    poke: root.silkyGlassPoke\n"
            "                }\n",
        ),
        (
            "            Item {\n"
            "                id: osdRoot\n"
            "                anchors.fill: parent\n",
            "            Item {\n"
            "                id: osdRoot\n"
            "                anchors.fill: parent\n"
            "                SilkyGlassMarker {\n"
            "                    enabled: root.barGlassPlugin\n"
            "                    items: root.silkyGlassItems\n"
            "                    poke: root.silkyGlassPoke\n"
            "                }\n",
        ),
        (
            "            Item {\n"
            "                id: spotRoot\n"
            "                anchors.fill: parent\n",
            "            Item {\n"
            "                id: spotRoot\n"
            "                anchors.fill: parent\n"
            "                SilkyGlassMarker {\n"
            "                    enabled: root.barGlassPlugin\n"
            "                    items: root.silkyGlassItems\n"
            "                    poke: root.silkyGlassPoke\n"
            "                }\n",
        ),
    ])
