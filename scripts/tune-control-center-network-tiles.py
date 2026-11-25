#!/usr/bin/env python3
"""Split the Control Center WiFi / Bluetooth tiles into an icon switch and a page opener.

macOS behaviour: only the round icon turns the radio on or off; the label, the subtitle, the empty part of the tile and
the "›" at its right edge open the tile's network / device list inside the Control Center. The "›" is always shown and
uses the same glyph, size, colour and right inset as the Display and Sound rows. The icon has its own hover ring and
press bounce, so it reads as a separate control from the rest of the tile. One-cell (small) tiles stay a single
switch, since they only hold the icon. The WiFi tile is titled "WiFi" (no translation, in every language).

Usage: tune-control-center-network-tiles.py <MacShell>/MacBar.qml   (idempotent)
"""
import sys
from pathlib import Path

path = Path(sys.argv[1])
source = path.read_text()
MARK = "property bool splitIcon: false"
if MARK in source:
    sys.exit(0)


def swap(old, new, what):
    global source
    if source.count(old) != 1:
        sys.exit(f"Control Center network tiles: expected one {what} in {path}")
    source = source.replace(old, new, 1)


# 1. CCButton: split mode flag, tile click opens the page in split mode.
swap(
    """            clickable: true
            radius: btn.radius
            scale: 1
            onClicked: btn.clicked()
        }
        property string kind: \"\"""",
    """            clickable: true
            radius: btn.radius
            scale: 1
            onClicked: btn.splitOn ? btn.arrowClicked() : btn.clicked()
        }
        // splitIcon (WiFi, Bluetooth): the round icon is the on / off switch, the rest of the tile and the always-shown
        // "›" open the page (arrowClicked). Small one-cell tiles only hold the icon, so they stay a single switch.
        property bool splitIcon: false
        readonly property bool splitOn: splitIcon && arrowOn
        property string kind: \"\"""",
    "CCButton tile",
)

# 2. The icon gets its own click area, hover ring and press bounce in split mode.
swap(
    """            kind: btn.kind; level: btn.level
            on: btn.on; onTint: btn.onTint
        }
        Column {
            visible: !btn.isSmall""",
    """            kind: btn.kind; level: btn.level
            on: btn.on; onTint: btn.onTint
            scale: iconMa.pressed ? 0.88 : 1     // CCBtn already springs its scale (Behavior on scale)
            Rectangle {     // hover ring of the icon switch (the tile's own hover tint goes away while over the icon)
                anchors.fill: parent
                radius: width / 2
                color: !iconMa.containsMouse ? Qt.rgba(0, 0, 0, 0)
                     : (btn.on ? Qt.rgba(0, 0, 0, 0.07) : (btn.t.dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.07)))
                Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }
            }
            MouseArea {
                id: iconMa
                anchors.fill: parent
                anchors.margins: -4
                enabled: btn.splitOn
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: btn.clicked()
            }
        }
        Column {
            visible: !btn.isSmall""",
    "CCButton icon",
)

swap(
    "            width: btn.width - x - (btn.arrowOn && btn.isWide ? 28 : 12)\n",
    "            width: btn.width - x - (btn.splitOn && btn.isWide ? 34 : (btn.arrowOn && btn.isWide ? 28 : 12))\n",
    "CCButton label width",
)

# 3. Split mode: a permanent "›" like the Display / Sound rows; the old hover arrow stays for other tiles.
swap(
    """            opacity: btn.hovered ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            Glyph {
                width: 14; height: 14""",
    """            opacity: (btn.hovered || btn.splitOn) ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            Text {      // same glyph, size, colour and 22 px right inset as the Display / Sound rows
                visible: btn.splitOn
                anchors.right: parent.right; anchors.rightMargin: 22   // btnArrow ends at the tile edge
                y: btn.isBig ? 12 + (44 - height) / 2 : (parent.height - height) / 2
                text: "›"; color: btn.fg2
                font.family: root.fontForWeight(Font.DemiBold, btn.t.fam); font.pixelSize: 18; font.weight: Font.DemiBold
            }
            Glyph {
                visible: !btn.splitOn
                width: 14; height: 14""",
    "CCButton arrow",
)
swap(
    """                id: arrowMa
                anchors.fill: parent
                enabled: btnArrow.opacity > 0.2""",
    """                id: arrowMa
                anchors.fill: parent
                enabled: !btn.splitOn && btnArrow.opacity > 0.2     // split mode: the tile's own click area opens the page""",
    "CCButton arrow click area",
)

# 4. WiFi / Bluetooth tiles use split mode; the WiFi tile is titled "WiFi".
swap(
    """                            title: I18n.tr("Wi-Fi")
                            subtitle: !root.wifiOn ? I18n.tr("Off") : (root.wifiSsid !== "" ? root.wifiSsid : I18n.tr("Not Connected"))
                            hasArrow: true
                            onClicked: root.toggleWifi()
                            // only the arrow opens the Wi-Fi page inside the Control Center; the rest of the tile switches Wi-Fi on / off
""",
    """                            title: "WiFi"
                            subtitle: !root.wifiOn ? I18n.tr("Off") : (root.wifiSsid !== "" ? root.wifiSsid : I18n.tr("Not Connected"))
                            hasArrow: true; splitIcon: true
                            onClicked: root.toggleWifi()
                            // the round icon switches WiFi on / off; the rest of the tile opens the WiFi page inside the Control Center
""",
    "WiFi tile",
)
swap(
    """                            hasArrow: true
                            onClicked: root.toggleBt()
""",
    """                            hasArrow: true; splitIcon: true
                            onClicked: root.toggleBt()
""",
    "Bluetooth tile",
)

path.write_text(source)
