#!/usr/bin/env python3
"""Install the Silky telemetry widgets into a compatible MacShell configuration."""
import argparse
import os
import shutil
import stat
from pathlib import Path
from tempfile import NamedTemporaryFile

SOURCE = Path(__file__).resolve().parents[1] / "config/macshell/status"

STATUS_OPEN_V1 = 'pop === "network" || pop === "thermal" || pop === "power"'
STATUS_OPEN = STATUS_OPEN_V1 + ' || pop === "profiles"'
STATUS_WIDTH_V1 = 'width: Math.min(430, Math.max(1, (ui.width - 16) / scale))'
STATUS_WIDTH = 'width: Math.min(mode === "profiles" ? 272 : 430, Math.max(1, (ui.width - 16) / scale))'

INLINE_V1 = """
                Item {
                    id: silkyStatusPop
                    z: 10
                    readonly property string mode: ui.silkyStatusOpen ? ui.pop : ""
                    readonly property bool active: ui.silkyStatusOpen
                    visible: active
                    scale: root.barPopupScale
                    transformOrigin: Item.TopLeft
                    width: Math.min(mode === "profiles" ? 272 : 430, Math.max(1, (ui.width - 16) / scale))
                    height: Math.max(1, Math.min(statusDetails.preferredHeight, (ui.height - y - 14) / scale, 625))
                    x: Math.max(8, Math.min(ui.width - width * scale - 8, ui.menuX - width * scale / 2))
                    y: root.barH + 6

                    PopGlassCtx { id: statusGlass; pop: silkyStatusPop; frame: ui; source: ui.glassSrc }
                    GGlass { anchors.fill: parent; gx: statusGlass.ctx; cornerR: 24; thickness: 22; shadowAmt: 0; flatInner: 1 }
                    MenuBorder { anchors.fill: parent; cornerR: 24; dark: statusGlass.ctx.dark; tint: statusGlass.ctx.borderTint; amount: 1 }
                    MouseArea { anchors.fill: parent }
                    SilkyStatusPanel {
                        id: statusDetails
                        anchors.fill: parent
                        mode: silkyStatusPop.mode
                        active: silkyStatusPop.active
                        summary: silkyStatusSummary.sample
                        palette: pal
                        battery: root.bat
                        charge: root.batPct
                        showPercent: root.showBatteryPercent
                        onTogglePercent: root.showBatteryPercent = !root.showBatteryPercent
                        onDismiss: ui.pop = ""
                    }
                }

"""

INLINE = """
                Item {
                    id: silkyStatusPop
                    z: 10
                    readonly property bool opening: ui.silkyStatusOpen
                    property string shownMode: ""
                    property real mx: 0
                    readonly property string mode: opening ? ui.pop : shownMode
                    onOpeningChanged: {
                        if (opening) {
                            shownMode = ui.pop;
                            mx = ui.menuX;
                        }
                        root.pokeGlassMarkers();
                    }
                    Connections {
                        target: ui
                        function onPopChanged() {
                            if (ui.silkyStatusOpen) {
                                silkyStatusPop.shownMode = ui.pop;
                                silkyStatusPop.mx = ui.menuX;
                            }
                        }
                        function onMenuXChanged() {
                            if (ui.silkyStatusOpen) silkyStatusPop.mx = ui.menuX;
                        }
                    }

                    // Match Control Center's spring open / quick close and focus-in morph blur.
                    property real openT: opening ? 1 : 0
                    Behavior on openT {
                        NumberAnimation {
                            duration: silkyStatusPop.opening ? 520 : 150
                            easing.type: silkyStatusPop.opening ? Easing.OutBack : Easing.OutCubic
                            easing.overshoot: 1.5
                        }
                    }
                    readonly property real ps: root.barPopupScale
                    width: Math.min(mode === "profiles" ? 272 : 356, Math.max(1, (ui.width - 16) / ps))
                    height: Math.max(1, Math.min(statusDetails.preferredHeight, (ui.height - y - 14) / ps, 625))
                    readonly property real dstX: Math.max(8, Math.min(ui.width - width * ps - 8, mx - width * ps / 2))
                    x: dstX - width * (1 - ps) / 2
                    y: root.barH + 6
                    opacity: Math.max(0, Math.min(1, openT * 2.2))
                    visible: opacity > 0
                    scale: ps * (0.94 + 0.06 * Math.min(1.0, openT))
                    transformOrigin: Item.Top
                    readonly property real blurAmt: Math.pow(Math.max(0, 1 - Math.min(1, openT)), 1.4)
                    readonly property bool morphing: openT > 0.002 && Math.abs(openT - 1) > 0.002
                    layer.enabled: morphing
                    layer.smooth: true
                    layer.effect: MultiEffect {
                        blurEnabled: true
                        blurMax: 40
                        blur: silkyStatusPop.blurAmt * 0.85
                        autoPaddingEnabled: true
                    }

                    PopGlassCtx { id: statusGlass; pop: silkyStatusPop; frame: ui; source: ui.glassSrc; fullW: silkyStatusPop.width; fullH: silkyStatusPop.height; silkyKind: 2 }
                    GGlass { id: silkyStatusGlassSurface; anchors.fill: parent; gx: statusGlass.ctx; cornerR: 26; thickness: 22; shadowAmt: 0; flatInner: 1 }
                    MenuBorder { visible: !silkyStatusGlassSurface.silkyOwned; z: 2; anchors.fill: parent; cornerR: 26; dark: statusGlass.ctx.dark; tint: statusGlass.ctx.borderTint; amount: 1 }
                    MouseArea { anchors.fill: parent }
                    SilkyStatusPanel {
                        id: statusDetails
                        anchors.fill: parent
                        mode: silkyStatusPop.mode
                        active: silkyStatusPop.opening
                        compositorOwned: silkyStatusGlassSurface.silkyOwned
                        summary: silkyStatusSummary.sample
                        palette: pal
                        battery: root.bat
                        charge: root.batPct
                        showPercent: root.showBatteryPercent
                        onTogglePercent: root.showBatteryPercent = !root.showBatteryPercent
                        onDismiss: ui.pop = ""
                    }
                }

"""

BUTTONS = """                        SilkyStatusButton {
                            id: silkyNetworkButton
                            mode: "network"
                            sample: silkyStatusSummary.sample
                            palette: bpal
                            selected: ui.pop === mode
                            onClicked: ui.openPop(mode, mapToItem(ui, width / 2, 0).x)
                        }
                        SilkyStatusButton {
                            id: silkyThermalButton
                            mode: "thermal"
                            sample: silkyStatusSummary.sample
                            palette: bpal
                            selected: ui.pop === mode
                            onClicked: ui.openPop(mode, mapToItem(ui, width / 2, 0).x)
                        }
"""


TRAY_ICON = """                                Image {
                                    anchors.centerIn: parent
                                    width: 16; height: 16
                                    source: tray.modelData.icon
"""

TRAY_KIND_V1 = """                                readonly property string silkyIconKind: {
                                    if (tray.modelData.status === Status.NeedsAttention)
                                        return "";
                                    const appId = tray.modelData.id.toLowerCase();
                                    if (appId === "remmina-icon")
                                        return "remmina";
                                    if (appId === "tray-icon tray app clash-verge-rev-tray")
                                        return "clash";
                                    return "";
                                }
"""

TRAY_KIND_V2 = """                                readonly property string silkyIconKind: {
                                    const item = tray.modelData;
                                    if (item.status === Status.NeedsAttention)
                                        return "";
                                    switch (item.id.toLowerCase()) {
                                    case "remmina-icon": return "remmina";
                                    case "tray-icon tray app clash-verge-rev-tray": return "clash";
                                    case "clippy": return "clippy";
                                    case "netcatty_status_icon_1": return "netcatty";
                                    case "chrome_status_icon_1": {
                                        const name = (item.tooltipTitle || item.title).trim().toLowerCase();
                                        if (name === "chatgpt") return "chatgpt";
                                        if (name === "google chrome") return "chrome";
                                        return "";
                                    }
                                    default: return "";
                                    }
                                }
"""

TRAY_KIND_V3 = """                                readonly property string silkyIconKind: {
                                    const item = tray.modelData;
                                    if (item.status === Status.NeedsAttention)
                                        return "";
                                    switch (item.id.toLowerCase()) {
                                    case "remmina-icon": return "remmina";
                                    case "tray-icon tray app clash-verge-rev-tray": return "clash";
                                    case "clippy": return "clippy";
                                    case "netcatty_status_icon_1": return "netcatty";
                                    case "wechat": return "wechat";
                                    case "chrome_status_icon_1": {
                                        const name = (item.tooltipTitle || item.title).trim().toLowerCase();
                                        if (name === "chatgpt") return "chatgpt";
                                        if (name === "google chrome") return "chrome";
                                        return "";
                                    }
                                    default: return "";
                                    }
                                }
"""

TRAY_KIND_V4 = TRAY_KIND_V3.replace(
    '                                    case "wechat": return "wechat";\n',
    '                                    case "wechat": return "wechat";\n'
    '                                    case "netease-cloud-music-gtk4": return "netease-cloud-music";\n',
)

TRAY_KIND = """                                readonly property string silkyIconKind: {
                                    const item = tray.modelData;
                                    if (item.status === Status.NeedsAttention)
                                        return "";
                                    const name = (item.tooltipTitle || item.title).trim().toLowerCase();
                                    const appId = item.id.toLowerCase();
                                    if (name.startsWith("antigravity") || appId.startsWith("antigravity"))
                                        return "antigravity";
                                    switch (appId) {
                                    case "remmina-icon": return "remmina";
                                    case "tray-icon tray app clash-verge-rev-tray": return "clash";
                                    case "clippy": return "clippy";
                                    case "netcatty_status_icon_1": return "netcatty";
                                    case "wechat": return "wechat";
                                    case "netease-cloud-music-gtk4": return "netease-cloud-music";
                                    case "chrome_status_icon_1": {
                                        if (name === "chatgpt") return "chatgpt";
                                        if (name === "google chrome") return "chrome";
                                        return "";
                                    }
                                    default: return "";
                                    }
                                }
"""

TRAY_ICON_STYLED = TRAY_KIND + """                                SilkyStatusIcon {
                                    anchors.centerIn: parent
                                    width: 17; height: 17
                                    visible: tray.silkyIconKind !== ""
                                    kind: tray.silkyIconKind
                                    ink: bpal.fg
                                }
                                Image {
                                    anchors.centerIn: parent
                                    width: 16; height: 16
                                    visible: tray.silkyIconKind === ""
                                    source: visible ? tray.modelData.icon : ""
"""


BATTERY_INDICATOR_V1 = '''                            readonly property color indicatorColor: root.batPct < 25
                                ? (bpal.dark ? "#ff6057" : "#b72a2a")
                                : UPower.onBattery ? (bpal.dark ? "#ffae42" : "#a95100")
                                                    : (bpal.dark ? "#30d158" : "#187b45")
'''

BATTERY_INDICATOR_V2 = '''                            readonly property color indicatorColor: root.bat.state === UPowerDeviceState.Charging
                                ? (bpal.dark ? "#30d158" : "#187b45")
                                : root.batPct < 25 ? (bpal.dark ? "#ff6057" : "#b72a2a")
                                : UPower.onBattery ? (bpal.dark ? "#ff9f0a" : "#b4530f")
                                                    : (bpal.dark ? "#ffd60a" : "#8a6a00")
'''

BATTERY_INDICATOR_V3 = '''                            readonly property color indicatorColor: root.bat.state === UPowerDeviceState.Charging
                                ? (bpal.dark ? "#30d158" : "#187b45")
                                : root.batPct < 20 ? (bpal.dark ? "#ff6057" : "#b72a2a")
                                : UPower.onBattery ? bpal.fg
                                                    : (bpal.dark ? "#5eb4ff" : "#0a64d6")
'''

BATTERY_INDICATOR_V4 = '''                            readonly property color indicatorColor: root.bat.state === UPowerDeviceState.Charging
                                ? (bpal.dark ? "#30d158" : "#187b45")
                                : root.batPct < 20 ? (bpal.dark ? "#ff6057" : "#b72a2a")
                                : UPower.onBattery ? bpal.fg
                                : silkyStatusSummary.sample?.wallpaperAccent?.[bpal.dark ? "dark" : "light"]
                                  ?? (bpal.dark ? "#5eb4ff" : "#0a64d6")
'''

BATTERY_INDICATOR_V5 = '''                            readonly property color indicatorColor: root.bat.state === UPowerDeviceState.Charging
                                ? (bpal.dark ? "#30d158" : "#1c8241")
                                : root.batPct < 20 ? (bpal.dark ? "#ff453a" : "#c92a22")
                                : UPower.onBattery ? (root.batPct < 35 ? (bpal.dark ? "#ff9f0a" : "#b85d00") : bpal.fg)
                                : (bpal.dark ? "#64d2ff" : "#0071a4")
'''

BATTERY_INDICATOR_V6 = '''                            readonly property color indicatorColor: root.bat.state === UPowerDeviceState.Charging
                                ? (bpal.dark ? "#30d158" : "#1c8241")
                                : root.batPct < 20 ? (bpal.dark ? "#ff453a" : "#c92a22")
                                : !UPower.onBattery ? (bpal.dark ? "#30d158" : "#1c8241")
                                : root.batPct <= 35 ? (bpal.dark ? "#ff9f0a" : "#b85d00")
                                : root.batPct <= 65 ? (bpal.dark ? "#64d2ff" : "#0071a4")
                                : (bpal.dark ? "#30d158" : "#1c8241")
'''

# The menu bar stays monochrome like macOS: the battery only takes a colour while charging or when it needs
# attention (amber at 35% and below, red under 20% on battery). The status panel keeps the full semantic scale.
BATTERY_INDICATOR = '''                            readonly property color indicatorColor: root.bat.state === UPowerDeviceState.Charging
                                ? (bpal.dark ? "#30d158" : "#1c8241")
                                : root.batPct < 20 ? (bpal.dark ? "#ff453a" : "#c92a22")
                                : UPower.onBattery && root.batPct <= 35 ? (bpal.dark ? "#ff9f0a" : "#b85d00")
                                : bpal.fg
'''

# A shorter battery pill (28 -> 24 px body): the number inside is two digits most of the time, and macOS keeps
# the battery about this wide. Every pair is applied only where the old value is still there.
BATTERY_SHELL = "Qt.rgba(bpal.fg.r, bpal.fg.g, bpal.fg.b, 0.45)"

BATTERY_COMPACT = [
    ("width: root.hasBattery ? 36 : 0; height: 28", "width: root.hasBattery ? 32 : 0; height: 28"),
    ("                                width: 31; height: 14\n", "                                width: 27; height: 14\n"),
    ("                                    width: 28; height: 14; radius: 4.5\n", "                                    width: 24; height: 14; radius: 4.5\n"),
    ("Rectangle { x: 29; y: 4.5; width: 2; height: 5; radius: 1;", "Rectangle { x: 25; y: 4.5; width: 2; height: 5; radius: 1;"),
]


# Even spacing and a readable number: 5 px either side of the 27 px battery (button 32 -> 37 px), the number
# from 9 to 10 px, and the cap half a pixel from the body (one device pixel at 2x) so the two read as one shape.
BATTERY_SPACING = [
    ("width: root.hasBattery ? 32 : 0; height: 28", "width: root.hasBattery ? 37 : 0; height: 28"),
    ("                                        font.pixelSize: 9\n", "                                        font.pixelSize: 10\n"),
    ("Rectangle { x: 25; y: 4.5; width: 2; height: 5; radius: 1;", "Rectangle { x: 24.5; y: 4.5; width: 2; height: 5; radius: 1;"),
]


def integrate(text):
    previous_color_placement = "                            id: silkyBatteryButton\n" + BATTERY_INDICATOR
    if previous_color_placement in text:
        text = text.replace(previous_color_placement, "                            id: silkyBatteryButton\n", 1)
    for old_indicator in (BATTERY_INDICATOR_V1, BATTERY_INDICATOR_V2, BATTERY_INDICATOR_V3, BATTERY_INDICATOR_V4, BATTERY_INDICATOR_V5, BATTERY_INDICATOR_V6):
        if old_indicator in text:
            text = text.replace(old_indicator, BATTERY_INDICATOR, 1)
    for old_kind in (TRAY_KIND_V1, TRAY_KIND_V2, TRAY_KIND_V3, TRAY_KIND_V4):
        if old_kind in text:
            text = text.replace(old_kind, TRAY_KIND, 1)
    if STATUS_OPEN not in text:
        text = text.replace(STATUS_OPEN_V1, STATUS_OPEN, 1)
    percent_before = '                        charge: root.batPct\n                        onDismiss: ui.pop = ""\n'
    if percent_before in text:
        text = text.replace(percent_before, '                        charge: root.batPct\n'
                            '                        showPercent: root.showBatteryPercent\n'
                            '                        onTogglePercent: root.showBatteryPercent = !root.showBatteryPercent\n'
                            '                        onDismiss: ui.pop = ""\n', 1)
    if STATUS_WIDTH_V1 in text and 'id: silkyStatusPop' in text:
        text = text.replace(STATUS_WIDTH_V1, STATUS_WIDTH, 1)
    if "        property int silkyKind: 1\n" not in text:
        text = text.replace(
            "        property bool grouped: false\n",
            "        property bool grouped: false\n        property int silkyKind: 1\n",
            1,
        )
    pop_ctx_prop = "        property bool fromCC: false"
    if "        property int silkyKind: 1\n        property bool fromCC: false" not in text and pop_ctx_prop in text:
        text = text.replace(
            pop_ctx_prop,
            "        property int silkyKind: 1\n" + pop_ctx_prop,
            1,
        )
    pop_ctx_bind = "            id: pgc\n            src: pgBlur\n"
    if "            id: pgc\n            silkyKind: pg.silkyKind\n" not in text and pop_ctx_bind in text:
        text = text.replace(
            pop_ctx_bind,
            "            id: pgc\n            silkyKind: pg.silkyKind\n            src: pgBlur\n",
            1,
        )
    if INLINE_V1 in text:
        text = text.replace(INLINE_V1, INLINE, 1)
    if 'width: Math.min(mode === "profiles" ? 272 : 430, Math.max(1, (ui.width - 16) / ps))' in text:
        text = text.replace(
            'width: Math.min(mode === "profiles" ? 272 : 430, Math.max(1, (ui.width - 16) / ps))',
            'width: Math.min(mode === "profiles" ? 272 : 356, Math.max(1, (ui.width - 16) / ps))',
            1,
        )
    changes = [
        (TRAY_ICON, TRAY_ICON_STYLED),
        ('    // battery\n    readonly property var bat:',
         '    SilkyStatusStream { id: silkyStatusSummary; mode: "bar"; active: root.barEnabled }\n\n'
         '    // battery\n    readonly property var bat:'),
        ('                property real menuX: 0\n',
         '                readonly property bool silkyStatusOpen: ' + STATUS_OPEN + '\n'
         '                property real menuX: 0\n'),
        ('toastArea, volPop, kbPop]', 'toastArea, volPop, kbPop, silkyStatusPop]'),
        ('|| volPop.visible || kbPop.visible\n', '|| volPop.visible || kbPop.visible || silkyStatusPop.visible\n'),
        ('                        // battery\n                        Item {\n                            visible: root.hasBattery',
         BUTTONS + '                        // battery\n                        Item {\n'
         '                            id: silkyBatteryButton\n'
         '                            visible: root.hasBattery\n'
         '                            Accessible.role: Accessible.Button\n'
         '                            Accessible.name: I18n.tr("Power")\n'
         '                            Accessible.onPressAction: ui.openPop("power", silkyBatteryButton.mapToItem(ui, silkyBatteryButton.width / 2, 0).x)\n'
         '                            Rectangle {\n'
         '                                anchors.fill: parent; anchors.margins: 2; radius: 6\n'
         '                                color: ui.pop === "power" || silkyBatteryMouse.containsMouse ? bpal.hover : "transparent"\n'
         '                            }'),
        ('                Item {\n                    id: volPop\n',
         INLINE + '                Item {\n                    id: volPop\n'),
    ]
    for before, after in changes:
        if after in text:
            continue
        if before == TRAY_ICON and "readonly property string silkyIconKind:" in text:
            continue
        if text.count(before) != 1:
            raise ValueError(f"MacBar integration point changed: {before.strip().splitlines()[0]}")
        text = text.replace(before, after, 1)
    start = text.index("                            id: silkyBatteryButton\n")
    end = text.index("\n                        //", start)
    battery = text[start:end]
    previous_click = 'MouseArea { anchors.fill: parent; onClicked: ui.openPop("cc", 0) }'
    updated_click = """MouseArea {
                                id: silkyBatteryMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: ui.openPop("power", silkyBatteryButton.mapToItem(ui, silkyBatteryButton.width / 2, 0).x)
                            }"""
    if updated_click not in battery and 'mouse.button === Qt.RightButton ? "profiles" : "power"' not in battery:
        if battery.count(previous_click) != 1:
            raise ValueError("MacBar battery click handler changed.")
        battery = battery.replace(previous_click, updated_click, 1)
    if BATTERY_INDICATOR not in battery:
        width_binding = "                            width: root.hasBattery ?"
        if battery.count(width_binding) != 1:
            raise ValueError("MacBar battery width binding changed.")
        battery = battery.replace(width_binding, BATTERY_INDICATOR + width_binding, 1)
        battery = battery.replace('color: root.charging ? "#30D158" : (root.batPct <= 15 ? "#FF453A" : bpal.fg)',
                                  'color: silkyBatteryButton.indicatorColor', 1)
        battery = battery.replace('color: root.batPct >= 48 ? (root.charging || bpal.dark ? "#111" : "#fff") : bpal.fg',
                                  'color: root.batPct >= 48 ? (bpal.dark ? "#111" : "#fff") : bpal.fg', 1)
    # Keep the battery outer shell and terminal cap monochrome (white on dark bar, dark on light bar);
    # only the inner charge fill uses indicatorColor.
    battery = battery.replace('border.color: silkyBatteryButton.indicatorColor', 'border.color: bpal.fg', 1)
    battery = battery.replace('border.color: bpal.fg2', 'border.color: bpal.fg', 1)
    battery = battery.replace('radius: 1; color: silkyBatteryButton.indicatorColor', 'radius: 1; color: bpal.fg', 1)
    battery = battery.replace('radius: 1; color: bpal.fg2', 'radius: 1; color: bpal.fg', 1)
    # Then soften the shell and cap to 45% of the ink, like macOS 26: the charge fill and number carry the
    # weight, and a nearly full battery no longer reads as the darkest block in the bar.
    battery = battery.replace('border.color: bpal.fg\n', 'border.color: ' + BATTERY_SHELL + '\n', 1)
    battery = battery.replace('radius: 1; color: bpal.fg }', 'radius: 1; color: ' + BATTERY_SHELL + ' }', 1)
    battery_click = 'onClicked: ui.openPop("power", silkyBatteryButton.mapToItem(ui, silkyBatteryButton.width / 2, 0).x)'
    if battery_click in battery:
        battery = battery.replace(battery_click, """acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onClicked: mouse => ui.openPop(mouse.button === Qt.RightButton ? "profiles" : "power",
                                    silkyBatteryButton.mapToItem(ui, silkyBatteryButton.width / 2, 0).x)""", 1)
    for before, after in BATTERY_COMPACT:
        if before in battery:
            battery = battery.replace(before, after, 1)
    for before, after in BATTERY_SPACING:
        if before in battery:
            battery = battery.replace(before, after, 1)
    return text[:start] + battery + text[end:]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("shell_dir", type=Path, nargs="?", default=Path(
        os.environ.get("MACSHELL_DIR", Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
                       / "quickshell/MacShell")))
    args = parser.parse_args()
    root = args.shell_dir
    bar = root / "MacBar.qml"
    try:
        if (root / "VERSION").read_text().strip() not in {"0.5.1", "0.5.2", "0.5.3"}:
            raise ValueError("This integration targets MacShell 0.5.1 to 0.5.3.")
        original = bar.read_text()
        updated = integrate(original)
    except (OSError, ValueError) as error:
        parser.exit(1, f"{error}\n")
    if args.check:
        print(f"MacShell status integration compatible at {root}")
        return

    assets = root / "assets"
    assets.mkdir(exist_ok=True)
    assets_changed = False
    for source in SOURCE.iterdir():
        if not source.is_file():
            continue
        destination = assets / "silky-status.py" if source.name == "status.py" else root / source.name
        if not destination.exists() or destination.read_bytes() != source.read_bytes():
            with NamedTemporaryFile(dir=destination.parent, delete=False) as tmp:
                tmp.write(source.read_bytes())
            Path(tmp.name).replace(destination)
            assets_changed = True

    # Build and install the native C++ silky-status binary (bar + thermal modes); fall back to a thin Python wrapper.
    native_dir = SOURCE.parents[2] / "plugins/silky-status"
    native_bin = native_dir / "silky-status"
    status_exec = assets / "silky-status"
    built_bytes = None
    if native_dir.is_dir() and shutil.which("g++") and shutil.which("make"):
        import subprocess
        res = subprocess.run(["make", "-C", str(native_dir)], capture_output=True, text=True)
        if res.returncode == 0 and native_bin.is_file():
            built_bytes = native_bin.read_bytes()
    if built_bytes is None:
        built_bytes = b'#!/bin/sh\nexec /usr/bin/python3 -I "$(dirname "$0")/silky-status.py" "$@"\n'
    if not status_exec.exists() or status_exec.read_bytes() != built_bytes:
        with NamedTemporaryFile(dir=assets, delete=False) as tmp:
            tmp.write(built_bytes)
            os.fchmod(tmp.fileno(), 0o755)
        Path(tmp.name).replace(status_exec)
        assets_changed = True
    if updated != original:
        backup = bar.with_name(f"MacBar.qml.bak.silky-status-{os.urandom(4).hex()}")
        shutil.copy2(bar, backup)
        with NamedTemporaryFile(mode="w", dir=root, delete=False) as tmp:
            tmp.write(updated)
            os.fchmod(tmp.fileno(), stat.S_IMODE(bar.stat().st_mode))
        Path(tmp.name).replace(bar)
        print(f"Backup: {backup}")
    elif assets_changed:
        # Atomic replacement of a child QML file can leave its old file watcher behind.
        bar.touch()
    print(f"MacShell status installed at {root}")


if __name__ == "__main__":
    main()
