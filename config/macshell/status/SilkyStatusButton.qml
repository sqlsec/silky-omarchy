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
    // Tabular figures keep the digits from shifting each time the sample changes.
    readonly property font speedFont: Qt.font({family: palette.fam, pixelSize: 12, weight: Font.DemiBold, features: {"tnum": 1}})
    readonly property font temperatureFont: Qt.font({family: palette.fam, pixelSize: 12, weight: Font.DemiBold, features: {"tnum": 1}})
    // About 6 px of visible space on each side, so neighbours sit ~8–9 px apart like Wi-Fi and search.
    // The arrow and thermometer canvases already carry blank space on their left (~2.75 and ~3.5 px).
    readonly property real inkPad: 6
    readonly property real leadIn: mode === "network" ? 2.75 : 3.5
    // The network reading reserves three digits so the tray does not shift as it changes.
    readonly property real speedSlot: Math.max(speedArrow.width + speeds.spacing + Math.ceil(speedMetrics.advanceWidth), speeds.implicitWidth)
    width: Math.ceil((mode === "network" ? speedSlot : temperature.implicitWidth) + inkPad * 2 - leadIn)
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

    // Reserve three digits and K/s, the widest common reading. Faster rates widen the button only while they last.
    TextMetrics { id: speedMetrics; font: root.speedFont; text: "888K/s" }
    TextMetrics { id: temperatureMetrics; font: root.temperatureFont; text: "88°" }  // CPU readings are two digits

    // One line, like the temperature: the busier direction with its arrow. The panel shows both.
    // It only switches when the other direction is clearly ahead (1.5x and over 1 KB/s), so a near tie
    // does not flip the arrow on every 1.5 s sample.
    property string lead: "down"
    onSampleChanged: {
        if (!sample)
            return;
        const up = Number(sample.up) || 0, down = Number(sample.down) || 0;
        if (lead === "down" && up > Math.max(down * 1.5, 1024))
            lead = "up";
        else if (lead === "up" && down > Math.max(up * 1.5, 1024))
            lead = "down";
    }
    Accessible.description: sample ? "↑ " + Status.rate(sample.up, true) + "  ↓ " + Status.rate(sample.down, true) : ""

    Row {
        id: speeds
        anchors.verticalCenter: parent.verticalCenter
        // Arrow and digits stay together, right-aligned in the reserved slot; spare room goes to the left.
        x: root.inkPad - root.leadIn + root.speedSlot - implicitWidth
        visible: root.mode === "network"
        spacing: 1
        SilkyStatusIcon {
            id: speedArrow
            width: 11
            height: 11
            anchors.verticalCenter: parent.verticalCenter
            kind: root.lead
            ink: Status.networkColor(root.lead, root.palette.dark)
            weight: 2.4
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.sample ? Status.rate(root.sample[root.lead], true) : "—"
            color: root.palette.fg
            font: root.speedFont
            textFormat: Text.PlainText
        }
    }

    Row {
        id: temperature
        anchors.verticalCenter: parent.verticalCenter
        x: root.inkPad - root.leadIn
        visible: root.mode === "thermal"
        // The 16 px canvas already leaves ~3.5 px beside the narrow glyph; that is the gap to the digits.
        spacing: 0
        SilkyStatusIcon {
            anchors.verticalCenter: parent.verticalCenter
            width: 16
            height: 16
            kind: "thermal"
            weight: 2.0
            ink: Status.barThermalColor(root.sample ? root.sample.temp : null, root.palette.dark, root.palette.fg)
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(Math.ceil(temperatureMetrics.advanceWidth), implicitWidth)
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
