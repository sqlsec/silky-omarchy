#!/usr/bin/env python3
"""Add a Display page to MacShell's Control Center."""

import sys
from pathlib import Path


def replace_once(source, original, updated):
    if source.count(original) != 1:
        raise SystemExit(f"Display controls: expected one match for {original.strip()!r}")
    return source.replace(original, updated, 1)


path = Path(sys.argv[1])
source = path.read_text()
if "                        id: ccDisplayPage\n" in source:
    raise SystemExit(0)

if 'id: ccSoundPage' in source:
    source = replace_once(
        source,
        '                           : (ui.ccPage === "bt" ? ccBtPage.height : ccSoundPage.height))',
        """                           : (ui.ccPage === "bt" ? ccBtPage.height
                           : (ui.ccPage === "display" ? ccDisplayPage.height : ccSoundPage.height)))""",
    )
else:
    source = replace_once(
        source,
        'height: ui.ccPage === "" ? ccCol.height : (ui.ccPage === "wifi" ? ccWifiPage.height : ccBtPage.height)',
        'height: ui.ccPage === "" ? ccCol.height : (ui.ccPage === "wifi" ? ccWifiPage.height\n'
        '                           : (ui.ccPage === "display" ? ccDisplayPage.height : ccBtPage.height))',
    )

# Match the Sound tile's separate navigation and slider hit areas.
navigation = '''                            Item {
                                x: 8; y: 3
                                width: parent.width - 16; height: 24
                                Text {
                                    x: 6; anchors.verticalCenter: parent.verticalCenter
                                    text: I18n.tr("Display")
                                    color: ccPal.fg; font.family: Fonts.forWeight(Font.DemiBold, root.boldFontFamily); font.pixelSize: 12; font.weight: Font.DemiBold
                                }
                                Text {
                                    anchors.right: parent.right; anchors.rightMargin: 6
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "›"; color: ccPal.fg2
                                    font.family: root.fontForWeight(Font.DemiBold, ccPal.fam); font.pixelSize: 18; font.weight: Font.DemiBold
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: ui.ccPage = "display"
                                }
                            }
'''
display_start = source.index("                        id: cDisplay\n")
title_start = source.index("                            Text {\n", display_start)
title_end = source.index("                            HoverHandler { id: tileHovDisplay }\n", title_start)
source = source[:title_start] + navigation + source[title_end:]

# Insert beside the other Control Center pages, which differ by MacShell version.
anchor = "ccSoundPage" if "id: ccSoundPage" in source else "ccBtPage"
page_start = source.rindex("                    Item {\n", 0, source.index(f"                        id: {anchor}\n"))
page = '''                    Item {
                        id: ccDisplayPage
                        readonly property bool shown: ui.ccPage === "display"
                        width: parent.width
                        height: ccDisplayCol.y + ccDisplayCol.height + 12
                        enabled: shown
                        opacity: shown ? 1 : 0
                        visible: opacity > 0.01
                        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        GGlass { visible: root.ccStyle !== "macos"; anchors.fill: parent; gx: ccg; cornerR: 26; thickness: 22; shadowAmt: 0.45 }
                        CornerBorder { visible: root.ccStyle !== "macos"; z: 2; anchors.fill: parent; cornerR: 26; dark: ccg.dark; tint: ccg.borderTint; amount: ccg.borderAmount; lineW: 0.8 }
                        MouseArea { anchors.fill: parent }

                        Item {
                            id: ccDisplayHeader
                            x: 12; y: 10; width: parent.width - 24; height: 36
                            Item {
                                width: 36; height: 36
                                Text {
                                    anchors.centerIn: parent; text: "‹"; color: ccPal.fg
                                    font.family: root.fontForWeight(Font.DemiBold, ccPal.fam); font.pixelSize: 25; font.weight: Font.DemiBold
                                }
                                MouseArea { anchors.fill: parent; onClicked: ui.ccPage = "" }
                            }
                            Text {
                                anchors.centerIn: parent
                                text: I18n.tr("Display"); color: ccPal.fg
                                font.family: Fonts.forWeight(Font.DemiBold, root.boldFontFamily); font.pixelSize: 14; font.weight: Font.DemiBold
                            }
                        }

                        Column {
                            id: ccDisplayCol
                            x: 12; y: 50
                            width: parent.width - 24
                            spacing: 8

                            CCTile {
                                width: parent.width; height: 58
                                t: ccPal; gx: ccg; radius: 18
                                Text {
                                    x: 14; y: 8
                                    text: I18n.tr("Brightness")
                                    color: ccPal.fg; font.family: Fonts.forWeight(Font.DemiBold, ccPal.fam); font.pixelSize: 12; font.weight: Font.DemiBold
                                }
                                CCSlider {
                                    x: 10; y: 26
                                    width: parent.width - 20
                                    t: ccPal; gx: ccg
                                    value: root.brightness
                                    leftKind: "sun"; leftLevel: 1
                                    rightKind: "sun"; rightLevel: 3
                                    onMoved: v => root.setBrightness(v)
                                }
                            }

                            Repeater {
                                model: ["nightshift", "contrast"]
                                delegate: CCTile {
                                    id: displayToggle
                                    required property string modelData
                                    readonly property bool isNightShift: modelData === "nightshift"
                                    width: ccDisplayCol.width; height: 50
                                    t: ccPal; gx: ccg; radius: 18
                                    clickable: true
                                    on: isNightShift ? root.nightOn : root.darkMode
                                    onClicked: {
                                        if (isNightShift) root.nightOn = !root.nightOn;
                                        else root.setAppearance(root.darkMode ? "light" : "dark");
                                    }

                                    CCBtn {
                                        plain: true
                                        t: ccPal; gx: ccg; d: 34
                                        x: 12; anchors.verticalCenter: parent.verticalCenter
                                        kind: displayToggle.modelData
                                        on: displayToggle.on
                                    }
                                    Column {
                                        x: 57; anchors.verticalCenter: parent.verticalCenter
                                        spacing: 2
                                        Text {
                                            text: I18n.tr(displayToggle.isNightShift ? "Night Shift" : "Appearance")
                                            color: ccPal.fg; font.family: Fonts.forWeight(Font.DemiBold, ccPal.fam); font.pixelSize: 12; font.weight: Font.DemiBold
                                        }
                                        Text {
                                            text: I18n.tr(displayToggle.isNightShift ? (root.nightOn ? "On" : "Off")
                                                                                   : (root.darkMode ? "Dark" : "Light"))
                                            color: ccPal.fg2; font.family: ccPal.fam; font.pixelSize: 11
                                        }
                                    }
                                }
                            }
                        }
                    }

'''
source = source[:page_start] + page + source[page_start:]
path.write_text(source)
