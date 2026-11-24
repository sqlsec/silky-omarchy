#!/usr/bin/env python3
"""Let MacShell hand its glass to the silky-dock-glass Hyprland plugin (see docs/02-macshell.md).

With `SILKY_DOCK_GLASS_PLUGIN=1` in MacShell's environment (~/.config/macshell/env) and the Normal Blur style:
  * the Dock and its context menu share a SilkyGlassMarker and the same glass material. Their rectangles are written into invisible pixels
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


def tune_popup_edges(path):
    text = path.read_text()
    original = text

    # The shared dropdown material may also have a calendar-specific veil.
    start = text.find("                    id: menuGlassMaterial\n")
    if start >= 0:
        end = text.index("                // ═════════ dropdown menu", start)
        material = text[start:end]
        if "id: menuSurface" not in material:
            material = material.replace("                        LGlass {\n",
                                        "                        LGlass {\n                            id: menuSurface\n", 1)
            material = material.replace("visible: root.panelDarkMode",
                                        "visible: (!menuSurface.silkyOwned && root.panelDarkMode)", 1)
            material = material.replace("                        MenuBorder {\n",
                                        "                        MenuBorder {\n                            visible: !menuSurface.silkyOwned\n", 1)
        text = text[:start] + material + text[end:]

    # These popovers still have a Qt border over their GGlass. Bind it to the
    # owning item so the fallback keeps its edge when the plugin is inactive.
    for context in ("volPopGlass", "wifiPopGlass", "btPopGlass", "notifPopGlass"):
        if context == "notifPopGlass" and "id: notifCardMaterial" in text:
            continue
        surface = context + "Surface"
        if f"id: {surface}" in text:
            continue
        match = re.search(
            rf"(GGlass \{{)([^{{}}]*\bgx: {context}\.ctx\b[^{{}}]*\}}\n"
            rf"(?: *//[^\n]*\n)? *MenuBorder \{{)",
            text,
        )
        if match is None:
            raise SystemExit(f"Glass plugin tuning ({path.name}): missing edge for {context}")
        glass, edge = match.groups()
        if edge.startswith("\n"):
            glass_id = f"\n                        id: {surface}"
            border_visibility = f"\n                        visible: !{surface}.silkyOwned"
        else:
            glass_id = f" id: {surface};"
            border_visibility = f" visible: !{surface}.silkyOwned;"
        replacement = glass + glass_id + edge + border_visibility
        text = text[:match.start()] + replacement + text[match.end():]

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
        "                        visible: !root.liquidActive\n"
        "                        anchors.fill: parent\n"
        "                        radius: root.cornerRadius\n",
        "                        visible: !root.liquidActive && !root.dockGlassPlugin\n"
        "                        anchors.fill: parent\n"
        "                        radius: root.cornerRadius\n",
    ),
])

dock_item = "                Item {\n                    id: dock\n"
old_rects = (
    "                    rects: [{ x: dock.x, y: dock.y, w: dock.width, h: dock.height, r: Math.min(root.cornerRadius, dock.height / 2),\n"
    "                              a: 1, dark: root.dockDark, kind: 0 }]\n"
)
# Use the Dock material (kind 0) for the context menu on the same layer.
dock_rects = (
    "                    rects: {\n"
    "                        const surfaces = [{ x: dock.x, y: dock.y, w: dock.width, h: dock.height,\n"
    "                            r: Math.min(root.cornerRadius, dock.height / 2), a: 1, dark: root.dockDark, kind: 0 }];\n"
    "                        if (menu.visible && menu.opacity > 0) {\n"
    "                            const s = menu.scale;\n"
    "                            surfaces.push({ x: menu.x + menu.width * (1 - s) / 2,\n"
    "                                y: menu.y + menu.height * (1 - s), w: menu.width * s, h: menu.bodyH * s,\n"
    "                                r: menu.radius * s, a: menu.opacity, dark: root.dockDark, kind: 0 });\n"
    "                        }\n"
    "                        return surfaces;\n"
    "                    }\n"
)
marker_start = (
    "                // Silky: tells the silky-dock-glass plugin where the Dock glass is (invisible pixels, bottom row)\n"
    "                SilkyGlassMarker {\n"
    "                    enabled: root.dockGlassPlugin\n"
)
marker_end = "                }\n\n" + dock_item
existing_marker = marker_start + old_rects + marker_end
tune(dock, [
    (existing_marker if existing_marker in text else dock_item, marker_start + dock_rects + marker_end),
    (
        "                    id: menu\n"
        "                    shadow: false\n",
        "                    id: menu\n"
        "                    compositorGlass: root.dockGlassPlugin\n"
        "                    shadow: false\n",
    ),
    (
        "                    tailH: 9 * k\n"
        "                    tailTipR: 3.6 * k\n"
        "                    readonly property real pad:",
        "                    tailH: compositorGlass ? 0 : 9 * k\n"
        "                    tailTipR: 3.6 * k\n"
        "                    readonly property real pad:",
    ),
])

tune(shell / "DockGlassPanel.qml", [
    (
        "    property var backdrop: null",
        "    property bool compositorGlass: false\n"
        "    property var backdrop: null",
    ),
    (
        "        id: skin\n",
        "        id: skin\n"
        "        visible: !gp.compositorGlass\n",
    ),
])


# ── Menu bar popovers & overlays (macbar, macswitch, macwall, macosd, macspot; macbarbg untouched) ──
bar = shell / "MacBar.qml"
if bar.is_file():
    # Upgrade existing installs so GGlass reads silkyKind from gg.gx (kind 2 for Control Center bubbles),
    # LGlass/GGlass wake SilkyGlassMarker on both show and hide, and appsGlassLayer skips its offscreen FBO when plugin-owned.
    bar_text = bar.read_text()
    bar_updated = bar_text.replace(
        "        readonly property bool silkyDark: !!gg.gx.dark\n"
        "        readonly property int silkyKind: 1\n",
        "        readonly property bool silkyDark: !!gg.gx.dark\n"
        "        readonly property int silkyKind: (gg.gx && gg.gx.silkyKind !== undefined) ? gg.gx.silkyKind : 1\n",
    ).replace(
        "        onVisibleChanged: if (visible) root.pokeGlassMarkers()\n",
        "        onVisibleChanged: root.pokeGlassMarkers()\n",
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
            "        onVisibleChanged: root.pokeGlassMarkers()\n"
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
            "        onVisibleChanged: root.pokeGlassMarkers()\n"
            "\n"
            "        Rectangle {\n"
            "            visible: !gg.gx.liquid && !gg.silkyOwned\n",
        ),
        (
            "                onLpChanged: if (lp <= 0.001 && pop !== \"spot\" && spot.vis <= 0.001) spResetClosed()\n",
            "                onLpChanged: { root.pokeGlassMarkers(); if (lp <= 0.001 && pop !== \"spot\" && spot.vis <= 0.001) spResetClosed(); }\n",
        ),
        (
            "                onPopChanged: {\n",
            "                onPopChanged: {\n"
            "                    root.pokeGlassMarkers();\n",
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
    # Skip appsGlassLayer's 2K offscreen FBO when silky-dock-glass owns the panel backdrop.
    bar_text = bar.read_text()
    for exp in ("0.85", "1.6"):
        old_apps_layer = (
            "                        Item {\n"
            "                            id: appsGlassLayer\n"
            "                            anchors.fill: parent\n"
            f"                            opacity: root.reduceMotion ? 1 : Math.pow(Math.min(1, appsPanel.t), {exp})\n"
            "                            layer.enabled: true\n"
            "                            GGlass { x: 10; y: 10; width: appsPanel.width; height: appsPanel.height; gx: spg; cornerR: 32; thickness: 34; strengthMul: 1.0; shadowAmt: 0; flatInner: 1 }\n"
            "                        }"
        )
        new_apps_layer = (
            "                        Item {\n"
            "                            id: appsGlassLayer\n"
            "                            anchors.fill: parent\n"
            f"                            opacity: root.reduceMotion ? 1 : Math.pow(Math.min(1, appsPanel.t), {exp})\n"
            "                            layer.enabled: !appsGlass.silkyOwned\n"
            "                            GGlass { id: appsGlass; x: 10; y: 10; width: appsPanel.width; height: appsPanel.height; gx: spg; cornerR: 32; thickness: 34; strengthMul: 1.0; shadowAmt: 0; flatInner: 1 }\n"
            "                        }"
        )
        if old_apps_layer in bar_text:
            bar_text = bar_text.replace(old_apps_layer, new_apps_layer, 1)
            bar.write_text(bar_text)
            break
    tune_popup_edges(bar)
