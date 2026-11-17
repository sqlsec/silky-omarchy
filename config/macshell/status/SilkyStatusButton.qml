pragma ComponentBehavior: Bound

import QtQuick
import "SilkyStatusFormat.js" as Status

Item {
    id: root
    required property string mode
    required property var sample
    required property var palette
    property bool selected: false
    signal clicked()
    readonly property font speedFont: Qt.font({family: palette.fam, pixelSize: 9, weight: Font.DemiBold})
    readonly property font temperatureFont: Qt.font({family: palette.fam, pixelSize: 12, weight: Font.DemiBold})
    width: (mode === "network" ? speeds.implicitWidth : temperature.implicitWidth) + 4
    height: 28

    Accessible.role: Accessible.Button
    Accessible.name: mode === "network" ? Status.tr("Network") : Status.tr("CPU Temperature")
    Accessible.onPressAction: root.clicked()

    Rectangle {
        anchors.fill: parent
        anchors.margins: 2
        radius: 6
        color: root.selected || mouse.containsMouse ? root.palette.hover : "transparent"
    }

    TextMetrics { id: speedMetrics; font: root.speedFont; text: "888M/s" }
    TextMetrics { id: temperatureMetrics; font: root.temperatureFont; text: "888°" }

    Column {
        id: speeds
        anchors.centerIn: parent
        visible: root.mode === "network"
        spacing: -1
        Repeater {
            model: ["down", "up"]
            Row {
                spacing: 2
                required property string modelData
                SilkyStatusIcon {
                    width: 9
                    height: 9
                    anchors.verticalCenter: parent.verticalCenter
                    kind: parent.modelData
                    ink: kind === "down" ? (root.palette.dark ? "#83e5f4" : "#006c7f")
                                         : (root.palette.dark ? "#c5b3ff" : "#6542a4")
                }
                Text {
                    width: Math.ceil(speedMetrics.advanceWidth)
                    text: root.sample ? Status.rate(root.sample[parent.modelData], true) : "—"
                    color: root.palette.fg
                    font: root.speedFont
                    textFormat: Text.PlainText
                }
            }
        }
    }

    Row {
        id: temperature
        anchors.centerIn: parent
        visible: root.mode === "thermal"
        spacing: 2
        SilkyStatusIcon {
            anchors.verticalCenter: parent.verticalCenter
            width: 14
            height: 14
            kind: "thermal"
            ink: root.palette.dark ? "#ffbf89" : "#8a4210"
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.ceil(temperatureMetrics.advanceWidth)
            text: root.sample && root.sample.temp !== null ? Math.round(root.sample.temp) + "°" : "—"
            color: root.palette.fg
            font: root.temperatureFont
            textFormat: Text.PlainText
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
