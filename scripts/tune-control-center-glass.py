#!/usr/bin/env python3
"""Use the top-bar dropdown material for MacShell's grouped Control Center."""

import sys
from pathlib import Path
from textwrap import dedent, indent


def replace_once(source, original, updated):
    if source.count(original) != 1:
        raise SystemExit(f"Control Center glass: expected one match for {original.strip()!r}")
    return source.replace(original, updated, 1)


path = Path(sys.argv[1])
source = path.read_text()
if "                    id: menuGlassMaterial\n" in source:
    raise SystemExit(0)

# MacShell 0.5.2 fixes the Control Center to dark even in light appearance.
source = source.replace(
    '    // The Control Center no longer switches between light and dark: it always keeps the same natural (dark glass) look.\n'
    '    readonly property bool ccDark: true',
    '    readonly property bool ccDark: panelDarkMode',
)
source = replace_once(source, 'property string ccStyle: "tiles"', 'property string ccStyle: "macos"')
source = replace_once(source, 'ccStyle = "tiles";', 'ccStyle = "macos";')

# Clear the heavier per-tile tint from the previous tuning on upgraded installs.
source = source.replace(
    '''                        // Keep text readable over both bright and dark wallpaper.
                        veil: dark ? 1.40 : 0
                        lightVeil: 1.90
                        saturation: dark ? 0.72 : 1.0
''',
    "",
)
source = source.replace(
    '''                        borderTint: dark ? "#848a96" : root.menuBorderColor
                        borderAmount: dark ? 0.55 : 1''',
    '''                        borderTint: root.menuBorderColor
                        borderAmount: 1''',
)
source = source.replace(
    "                    property real saturation: gg.gx.saturation",
    "                    property real saturation: 1.25",
)
source = source.replace("\n        property real saturation: 1.25\n", "\n")

# Lift the menu's existing slab, gradient and outline together so both panes
# pick up future adjustments to the same material.
menu_start = source.index("                    id: menuPop\n")
material_start = source.index("                    LGlass {\n", menu_start)
material_end = source.index("                    Column {\n                        id: menuCol\n", material_start)
material = dedent(source[material_start:material_end])
material = replace_once(material, "bx: menuPop.x; by: menuPop.y", "bx: menuGlass.bx; by: menuGlass.by")
material = replace_once(material, "    id: menuBorder\n", "")
material = material.replace("cornerR: 14", "cornerR: menuGlass.cornerR").replace("radius: 14", "radius: menuGlass.cornerR")
source = source[:material_start] + '''                    Loader {
                        anchors.fill: parent
                        active: menuPop.visible
                        readonly property real materialX: menuPop.x
                        readonly property real materialY: menuPop.y
                        readonly property real materialRadius: 14
                        sourceComponent: menuGlassMaterial
                    }
''' + source[material_end:]
component = '''                Component {
                    id: menuGlassMaterial
                    Item {
                        id: menuGlass
                        readonly property real bx: parent.materialX
                        readonly property real by: parent.materialY
                        readonly property real cornerR: parent.materialRadius

''' + indent(material, "                        ") + '''                    }
                }

'''
glass_context = "    component GlassCtx: QtObject {\n"
source = replace_once(source, glass_context, glass_context + "        property bool grouped: false\n")
menu_comment = "                // ═════════ dropdown menu (Apple / app / File / Edit / …) ═════════"
source = replace_once(source, menu_comment, component + menu_comment)

for control, corner, effect in (
    ("tile", "tile.radius", "thickness: 22"),
    ("pl", "14", "thickness: 14; strengthMul: 0.6"),
):
    slab = f"        GGlass {{ anchors.fill: parent; gx: {control}.gx; cornerR: {corner}; {effect}; shadowAmt: 0; flatInner: 1 }}"
    source = replace_once(
        source,
        slab,
        f'''        GGlass {{ visible: !{control}.gx.grouped; anchors.fill: parent; gx: {control}.gx; cornerR: {corner}; {effect}; shadowAmt: 0; flatInner: 1 }}
        Rectangle {{
            visible: {control}.gx.grouped
            anchors.fill: parent
            radius: Math.min(18, {corner})
            color: {control}.t.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.055)
        }}''',
    )
    source = replace_once(
        source,
        f"        CornerBorder {{ z: 2; anchors.fill: parent; cornerR: {corner}; dark: {control}.gx.dark;",
        f"        CornerBorder {{ visible: !{control}.gx.grouped; z: 2; anchors.fill: parent; cornerR: {corner}; dark: {control}.gx.dark;",
    )

source = replace_once(
    source,
    "                        id: ccg\n",
    '                        id: ccg\n                        grouped: root.ccStyle === "macos"\n',
)
cc_start = source.index("                    id: cc\n")
x_after = source.index("                    // opening (ColorOS 17)", cc_start)
x_start = source.index("                    x: Math.max(8, ui.width - width - 10)\n", cc_start, x_after)
source = source[:x_start] + '''                    readonly property real paneInset: ccg.grouped ? 10 : 0
                    x: Math.max(8, ui.width - width - 10 - paneInset * root.barPopupScale)
                    y: root.barH + (ccg.grouped ? 3 + paneInset * root.barPopupScale : 8)
''' + source[x_after:]
panel_start = source.index("                    // macOS Control Center: one frosted slab")
panel_end = source.index("                    // Wi-Fi page: ", panel_start)
source = source[:panel_start] + '''                    Loader {
                        active: ccg.grouped && cc.visible
                        x: -cc.paneInset; y: -cc.paneInset
                        width: cc.width + 2 * cc.paneInset
                        height: cc.height + 2 * cc.paneInset
                        // The Control Center scales around its top-right corner.
                        readonly property real materialX: cc.x + cc.width - (cc.width + cc.paneInset) * root.barPopupScale
                        readonly property real materialY: cc.y - cc.paneInset * root.barPopupScale
                        readonly property real materialRadius: 18
                        sourceComponent: menuGlassMaterial
                    }

''' + source[panel_end:]
path.write_text(source)
