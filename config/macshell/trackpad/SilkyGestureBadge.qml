import QtQuick
import "Fonts.js" as Fonts

// Compact macOS capsule badge describing a fixed trackpad / touchscreen gesture trigger.
Rectangle {
    id: badge
    required property var t
    property string text: ""
    width: badgeLbl.implicitWidth + 18
    height: 22
    radius: 7
    color: t.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.055)
    border.width: 1
    border.color: t.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.08)

    Text {
        id: badgeLbl
        anchors.centerIn: parent
        text: badge.text
        color: badge.t.text2
        font.family: Fonts.forWeight(Font.Medium, badge.t.fam)
        font.weight: Font.Medium
        font.pixelSize: 12
    }
}
