import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

Scope {
    id: preview

    property string output: ""
    property rect destination
    property bool showing: false
    property bool movePreview: false

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            const prefix = "silky-folio-snap,"
            if (event.name !== "custom" || !event.data.startsWith(prefix))
                return
            const fields = event.data.slice(prefix.length).split(",")
            if (fields[0] === "hide") {
                preview.showing = false
                return
            }
            if (fields.length !== 5)
                return
            preview.movePreview = preview.showing && preview.output === fields[0]
            preview.output = fields[0]
            preview.destination = Qt.rect(Number(fields[1]), Number(fields[2]), Number(fields[3]), Number(fields[4]))
            preview.showing = true
        }
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: panel
            required property var modelData
            screen: modelData
            readonly property bool selected: preview.output === modelData.name
            visible: selected && (preview.showing || highlight.opacity > 0)
            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            mask: Region {}
            WlrLayershell.namespace: "silky-folio-snap"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Rectangle {
                id: highlight
                x: preview.destination.x + 4
                y: preview.destination.y + 4
                width: Math.max(0, preview.destination.width - 8)
                height: Math.max(0, preview.destination.height - 8)
                radius: 13
                color: "#3d3b9eff"
                border.color: "#b866b5ff"
                border.width: 2
                opacity: panel.selected && preview.showing ? 1 : 0

                readonly property int moveMs: 90
                Behavior on x { enabled: preview.movePreview; NumberAnimation { duration: highlight.moveMs } }
                Behavior on y { enabled: preview.movePreview; NumberAnimation { duration: highlight.moveMs } }
                Behavior on width { enabled: preview.movePreview; NumberAnimation { duration: highlight.moveMs } }
                Behavior on height { enabled: preview.movePreview; NumberAnimation { duration: highlight.moveMs } }
                Behavior on opacity { NumberAnimation { duration: preview.showing ? 65 : 45 } }
            }
        }
    }
}
