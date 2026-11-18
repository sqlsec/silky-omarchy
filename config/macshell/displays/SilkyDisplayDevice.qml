import QtQuick

Item {
    id: device
    property bool builtIn: false
    property real aspect: 1.6
    readonly property real bezelWidth: Math.min(width * (builtIn ? 0.84 : 0.92), (height - 13) * aspect)

    Rectangle {
        id: bezel
        anchors.horizontalCenter: parent.horizontalCenter
        width: device.bezelWidth
        height: width / device.aspect
        radius: 5
        color: "#20262f"
        border.color: "#637182"

        Rectangle {
            anchors.fill: parent
            anchors.margins: device.builtIn ? 4 : 3
            radius: 2
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "#203664" }
                GradientStop { position: 0.55; color: "#356c9c" }
                GradientStop { position: 1; color: "#62abae" }
            }
            clip: true

            Rectangle {
                width: parent.width * 0.67
                height: parent.height * 1.36
                x: parent.width * 0.49
                y: parent.height * 0.15
                rotation: -37
                radius: width / 3
                color: "#33d1f5ff"
            }
        }
    }

    Rectangle {
        visible: device.builtIn
        anchors.top: bezel.bottom
        anchors.horizontalCenter: bezel.horizontalCenter
        width: bezel.width * 1.18
        height: 5
        radius: 2
        gradient: Gradient {
            GradientStop { position: 0; color: "#a9b5c2" }
            GradientStop { position: 1; color: "#555f6d" }
        }
    }

    Rectangle {
        visible: !device.builtIn
        anchors.top: bezel.bottom
        anchors.horizontalCenter: bezel.horizontalCenter
        width: 11
        height: 8
        color: "#788595"
    }

    Rectangle {
        visible: !device.builtIn
        y: bezel.height + 8
        anchors.horizontalCenter: bezel.horizontalCenter
        width: bezel.width * 0.35
        height: 3
        radius: 1.5
        color: "#a5afbb"
    }
}
