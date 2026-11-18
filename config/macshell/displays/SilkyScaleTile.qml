import QtQuick
import QtQuick.Controls

Button {
    id: tile
    required property var t
    required property real factor
    required property bool selected
    hoverEnabled: true
    padding: 0
    Accessible.name: text
    Accessible.checkable: true
    Accessible.checked: selected

    background: Rectangle {
        radius: 10
        color: tile.selected ? Qt.rgba(tile.t.accent.r, tile.t.accent.g, tile.t.accent.b, 0.14)
                             : tile.hovered ? tile.t.hover : "transparent"
        border.width: tile.selected || tile.visualFocus ? 1 : 0
        border.color: tile.t.accent
    }

    contentItem: Column {
        topPadding: 7
        spacing: 6
        Rectangle {
            id: sample
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(61, tile.width - 12)
            height: 43
            radius: 5
            color: tile.t.contentSolid
            border.color: tile.t.sep
            clip: true

            Rectangle {
                width: parent.width - 2
                height: 10
                x: 1
                y: 1
                color: tile.t.ctrl
                radius: 3

                Row {
                    x: 4
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Repeater {
                        model: ["#ef766d", "#ebbc65", "#5db898"]
                        Rectangle {
                            required property color modelData
                            width: 3; height: 3; radius: 1.5
                            color: modelData
                        }
                    }
                }
            }

            Row {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: 6
                spacing: 3
                Text {
                    text: "Aa"
                    color: tile.t.text
                    font.family: tile.t.fam
                    font.pixelSize: Math.round(8 + 12 * tile.factor)
                    font.weight: Font.DemiBold
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3
                    Repeater {
                        model: [10, 15, 12]
                        Rectangle {
                            required property int modelData
                            width: modelData
                            height: 1
                            color: tile.t.text3
                        }
                    }
                }
            }
        }

        Text {
            width: parent.width
            text: tile.text
            color: tile.selected ? tile.t.accent : tile.t.text2
            horizontalAlignment: Text.AlignHCenter
            font.family: tile.t.fam
            font.pixelSize: 11
        }
    }
}
