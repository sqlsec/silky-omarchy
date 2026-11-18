#!/usr/bin/env python3
"""Apply Silky's menu glass and Chinese calendar to the MacBar clock popup."""

import sys
from pathlib import Path


def replace_once(source, original, updated):
    if source.count(original) != 1:
        raise SystemExit(f"Calendar: expected one match for {original.strip()!r}")
    return source.replace(original, updated, 1)


path = Path(sys.argv[1])
source = path.read_text()
calendar_import = 'import "ChinaCalendar.js" as ChinaCalendar'
if calendar_import in source:
    raise SystemExit(0)

source = replace_once(source, 'import "Fonts.js" as Fonts\n',
                      'import "Fonts.js" as Fonts\n' + calendar_import + '\n')

source = replace_once(source, 'function calCells() {', 'function calCells(today) {')
source = replace_once(source, '                    var today = new Date(), out = [];',
                      '                    var out = [];')
source = replace_once(
    source,
    'today: d.getFullYear() === today.getFullYear() && d.getMonth() === today.getMonth() && d.getDate() === today.getDate()',
    'today: d.toDateString() === today, china: ChinaCalendar.details(d)',
)
source = replace_once(
    source,
    '                readonly property var calData: { clock.date; return calCells(); }',
    '                readonly property string calToday: clock.date.toDateString()\n'
    '                readonly property var calData: calCells(calToday)',
)

material_start = source.index('                    id: menuGlassMaterial\n')
material_end = source.index('                // ═════════ dropdown menu', material_start)
material = source[material_start:material_end]
material = replace_once(material, '                            capScale: root.barPopupScale\n',
                        '                            capScale: menuGlass.parent.materialScale\n')
material = replace_once(
    material,
    '                        readonly property real cornerR: parent.materialRadius\n',
    '                        readonly property real cornerR: parent.materialRadius\n'
    '                        readonly property real veil: parent.materialVeil\n',
)
material = replace_once(
    material,
    """                        // dark mode: Dock-label style dark tint over the glass
                        Rectangle {
                            visible: root.panelDarkMode
                            anchors.fill: parent
                            radius: menuGlass.cornerR
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: Qt.rgba(56 / 255, 56 / 255, 62 / 255, 0.34) }
                                GradientStop { position: 1.0; color: Qt.rgba(30 / 255, 30 / 255, 34 / 255, 0.38) }
                            }
                        }""",
    """                        Rectangle {
                            visible: root.panelDarkMode || menuGlass.veil > 0
                            anchors.fill: parent
                            radius: menuGlass.cornerR
                            gradient: Gradient {
                                GradientStop {
                                    position: 0
                                    color: root.panelDarkMode
                                        ? Qt.rgba(56 / 255, 56 / 255, 62 / 255, 0.34 + menuGlass.veil)
                                        : Qt.rgba(1, 1, 1, menuGlass.veil)
                                }
                                GradientStop {
                                    position: 1
                                    color: root.panelDarkMode
                                        ? Qt.rgba(30 / 255, 30 / 255, 34 / 255, 0.38 + menuGlass.veil)
                                        : Qt.rgba(0.94, 0.94, 0.97, menuGlass.veil)
                                }
                            }
                        }""",
)
source = source[:material_start] + material + source[material_end:]
for radius in (14, 18):
    line = f'                        readonly property real materialRadius: {radius}\n'
    source = replace_once(
        source, line,
        '                        readonly property real materialScale: root.barPopupScale\n'
        '                        readonly property real materialVeil: 0\n' + line,
    )

# Include the scaled calendar bounds in the live backdrop region.
source = replace_once(
    source,
    '                        x0 = Math.min(x0, it.x); y0 = Math.min(y0, it.y); x1 = Math.max(x1, it.x + it.width); y1 = Math.max(y1, it.y + it.height);',
    '''                        var left = it === cal ? cal.glassX : it.x;
                        var bottom = it.y + it.height * (it === cal ? cal.scale : 1);
                        x0 = Math.min(x0, left); y0 = Math.min(y0, it.y);
                        x1 = Math.max(x1, it.x + it.width); y1 = Math.max(y1, bottom);''',
)

start = source.index('                    id: cal\n')
end = source.index('                // ═════════ Control Center ═════════', start)
calendar = source[start:end]
calendar = replace_once(calendar, '                    width: 310\n', '                    width: 326\n')
calendar = replace_once(
    calendar,
    '                    transformOrigin: Item.TopRight\n',
    '                    transformOrigin: Item.TopRight\n'
    '                    readonly property real glassX: x + width * (1 - scale)\n',
)

glass_start = calendar.index('                    LGlass {\n')
glass_end = calendar.index('                    Column {\n', glass_start)
calendar = calendar[:glass_start] + '''                    Loader {
                        anchors.fill: parent
                        active: cal.visible
                        readonly property real materialX: cal.glassX
                        readonly property real materialY: cal.y
                        readonly property real materialScale: cal.scale
                        // Keep the smaller date labels legible over bright or dark windows.
                        readonly property real materialVeil: pal.dark ? 0.20 : 0.46
                        readonly property real materialRadius: 24
                        sourceComponent: menuGlassMaterial
                    }
''' + calendar[glass_end:]

delegate_start = calendar.index('                                delegate: Item {\n', calendar.index('model: ui.calData'))
delegate_end = calendar.index('\n                                }', delegate_start) + len('\n                                }')
calendar = calendar[:delegate_start] + '''                                delegate: ChinaCalendarDay {
                                    width: calCol.width / 7
                                    dark: pal.dark
                                    foreground: pal.fg
                                    secondary: pal.dark ? "#dce0e6" : "#343940"
                                    accent: root.accent
                                    dayFont: root.fontForWeight(modelData.today ? Font.DemiBold : Font.Normal, pal.fam)
                                    labelFont: pal.fam
                                }''' + calendar[delegate_end:]

path.write_text(source[:start] + calendar + source[end:])
