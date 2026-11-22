#!/usr/bin/env python3
"""Reduce duplicate geometry updates and background capture in MacShell."""
import re
import sys
from pathlib import Path

directory = Path(sys.argv[1])
shell, dock, bar = (directory / name for name in ("shell.qml", "MacDock.qml", "MacBar.qml"))


def replace_once(text, old, new, upstream=None):
    # `upstream`: text that shows a newer MacShell already ships this change in its own form (for example 0.5.3).
    if new in text or (upstream and upstream in text):
        return text
    if text.count(old) != 1:
        raise SystemExit(f"MacShell performance: expected one occurrence of {old[:90]!r}")
    return text.replace(old, new, 1)


def defer_backdrop_sync(text):
    return replace_once(
        text,
        "function onMonDataChanged() { bd.sync(); }",
        "function onMonDataChanged() { Qt.callLater(bd.sync); }",
    )


shell_text = shell.read_text()
shell_text = replace_once(
    shell_text,
    '        Connections {\n            target: Hyprland\n            function onRawEvent(event) {\n                if (event.name === "openwindow"',
    '''        function refreshGeometryModels() {
            try {
                Hyprland.refreshMonitors();
                Hyprland.refreshToplevels();
            } catch (err) { }
        }
        Connections {
            target: Hyprland
            function onRawEvent(event) {
                if (event.name === "openwindow"''',
)
shell_text = replace_once(
    shell_text,
    '                // our own window previews',
    '                if (en === "silkyoverview" || en === "silkylaunchpad" || en === "silkypinch" || en === "silkyswipe") return;\n'
    '                // our own window previews',
)
shell_text = replace_once(
    shell_text,
    '                    try { Hyprland.refreshMonitors(); Hyprland.refreshToplevels(); } catch (err) { }',
    '                    Qt.callLater(sharedHub.refreshGeometryModels);',
)
shell_text = replace_once(
    shell_text,
    '(macBar.glassRealtime || macDock.glassLive) ? 33 : 80',
    '((sharedHub.barWantsGeo && macBar.glassRealtime) || sharedHub.dockGlassVisible) ? 33 : 80',
)
shell_text = replace_once(
    shell_text,
    '        property bool dockWantsGeo: false',
    '        property bool dockWantsGeo: false\n        property bool dockGlassVisible: false',
)

dock_text = defer_backdrop_sync(dock.read_text())
dock_text = replace_once(
    dock_text,
    'function onGlassClientsChanged() { bd.sync(); bd.burst(); }',
    'function onGlassClientsChanged() { Qt.callLater(bd.sync); bd.burst(); }',
)
# A tucked Dock still keeps the last frame and its existing release grace.
dock_text = replace_once(
    dock_text,
    'readonly property bool canRun: !quiet && !ui.menuOpen && (root.glassRT',
    'readonly property bool canRun: !quiet && !ui.tucked && !ui.menuOpen && (root.glassRT',
    upstream='readonly property bool canRun: !quiet && !ui.tucked && (',
)
# Count visible, live glass backdrops on each screen without changing Smart Hide itself.
dock_text = replace_once(
    dock_text,
    '    readonly property var glassClients: hub ? hub.glassClients : []',
    '''    property int visibleGlassDocks: 0
    Binding { target: root.hub; property: "dockGlassVisible"; value: root.visibleGlassDocks > 0 }
    readonly property var glassClients: hub ? hub.glassClients : []''',
)
dock_text = replace_once(
    dock_text,
    '                readonly property real refLeft:',
    '''                readonly property bool liveDockGlass: win.visible && root.liquidActive && root.glassLive && !tucked
                property bool countedGlass: false
                function updateGlassDemand() {
                    if (countedGlass === liveDockGlass) return;
                    countedGlass = liveDockGlass;
                    root.visibleGlassDocks += countedGlass ? 1 : -1;
                }
                Connections {
                    target: ui
                    function onLiveDockGlassChanged() { ui.updateGlassDemand(); }
                    Component.onCompleted: ui.updateGlassDemand()
                    Component.onDestruction: if (ui.countedGlass) root.visibleGlassDocks--;
                }
                readonly property real refLeft:''',
)
bar_text = defer_backdrop_sync(bar.read_text())
bar_text, changed = re.subn(r'(function onGlassClientsChanged\(\) \{ )bd\.sync\(\);( (?:if \(bd.hostShown\) )?bd\.burst\(\); \})',
                           r'\1Qt.callLater(bd.sync);\2', bar_text)
if changed != 1 and 'function onGlassClientsChanged() { Qt.callLater(bd.sync);' not in bar_text:
    raise SystemExit("MacShell performance: couldn't find the menu bar backdrop listener")
bar_text = replace_once(
    bar_text,
    'interval: sv.hush ? 1500 : (bd.hostShown ? (sv.busy ? 250 : 1500) : 1000); repeat: true',
    'interval: sv.hush ? 1500 : (sv.busy ? (bd.hostShown ? 250 : 1000) : 5000); repeat: true',
)

# Keep light grid slots so positions and keyboard reveal remain available.
# Create icon, label, highlight and input objects only in and near the viewport.
if "id: nearbyTile" not in bar_text:
    preloader = re.compile(
        r"^                        // Keeps every app icon decoded[^\n]*\n"
        r".*?^                        }\n", re.S | re.M,
    )
    bar_text, removed = preloader.subn("", bar_text)
    if removed != 1:
        raise SystemExit("MacShell performance: Applications icon preloader not found")
    icon = bar_text.index("                                                        id: cellIcon")
    start = bar_text.rindex("                                                    Rectangle {", 0, icon)
    cell_end = bar_text.index("\n                                                }\n", icon)
    visual = bar_text[start:cell_end]
    visual = re.sub(r"(?m)^ +// already decoded by the preloader[^\n]*\n", "", visual)
    visual = visual.replace("asynchronous: false", "asynchronous: true")
    visual = "\n".join("        " + line if line else "" for line in visual.splitlines())
    bar_text = bar_text[:start] + """                                                    Loader {
                                                        id: nearbyTile
                                                        anchors.fill: parent
                                                        readonly property real tileTop: sec.y + (cell.parent ? cell.parent.y : 0) + cell.y
                                                        active: tileTop + cell.height >= appsFlick.contentY - cell.height * 2
                                                                && tileTop <= appsFlick.contentY + appsFlick.height + cell.height * 2
                                                        sourceComponent: Item {
""" + visual + """
                                                        }
                                                    }""" + bar_text[cell_end:]

# Scrolling must not tear tiles down and rebuild them (that re-decoded each icon and made them pop in).
# Near tiles are built at once so the panel opens as fast as before; a built tile is kept for good; once the
# open animation has settled, the rest are built in the background (incubated across frames). A kept tile's
# binding no longer reads contentY, so scrolling stops re-evaluating ~100 bindings per frame.
bar_text = replace_once(
    bar_text,
    """                                                        active: tileTop + cell.height >= appsFlick.contentY - cell.height * 2
                                                                && tileTop <= appsFlick.contentY + appsFlick.height + cell.height * 2
""",
    """                                                        property bool kept: false
                                                        active: kept || appsPanel.warm
                                                                || (tileTop + cell.height >= appsFlick.contentY - cell.height * 2
                                                                    && tileTop <= appsFlick.contentY + appsFlick.height + cell.height * 2)
                                                        // off-screen tiles built in the background; anything near the viewport (and every
                                                        // search result) appears in the same frame
                                                        asynchronous: !kept && appsPanel.warm && !appsPanel.searching
                                                                      && tileTop > appsFlick.contentY + appsFlick.height + cell.height
                                                        onLoaded: kept = true
""",
)
bar_text = replace_once(
    bar_text,
    "                        readonly property bool entering: t < 0.997 && !root.reduceMotion\n",
    """                        readonly property bool entering: t < 0.997 && !root.reduceMotion
                        // set once, after the first open has settled: from then on every tile exists (see nearbyTile)
                        property bool warm: false
                        Timer {
                            interval: 200
                            running: !appsPanel.warm && appsPanel.visible && !appsPanel.entering
                            onTriggered: appsPanel.warm = true
                        }
""",
)
# Keep every app icon decoded in Qt's pixmap cache (~5 MB), so a tile shows its icon in the frame it is built,
# including after a search rebuilds the grid. Decoded once in the background; costs nothing afterwards.
bar_text = replace_once(
    bar_text,
    """                        NumberAnimation { id: revealAnim; target: appsFlick; property: "contentY"; duration: root.reduceMotion ? 0 : 180; easing.type: Easing.OutCubic }
""",
    """                        NumberAnimation { id: revealAnim; target: appsFlick; property: "contentY"; duration: root.reduceMotion ? 0 : 180; easing.type: Easing.OutCubic }
                        Item {
                            visible: false
                            Repeater {
                                model: root.appList
                                delegate: Image {
                                    required property var modelData
                                    source: root.iconSrc(modelData.icon)
                                    sourceSize: Qt.size(128, 128)
                                    asynchronous: true
                                }
                            }
                        }
""",
)

for path, result in ((shell, shell_text), (dock, dock_text), (bar, bar_text)):
    if result != path.read_text():
        path.write_text(result)
