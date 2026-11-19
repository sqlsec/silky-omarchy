// Offscreen preview of the widgets (scripts/preview-macshell-widgets.sh): every kind / size listed below, rendered
// with a sample of real data into a PNG, without showing anything on screen.
import QtQuick
import Quickshell
import "info.js" as Sample
import QtQml

ShellRoot {
    Component.onCompleted: Qt.uiLanguage = Quickshell.env("SILKY_PREVIEW_LANG") || "zh-CN"
    FloatingWindow {
        id: win
        implicitWidth: 760; implicitHeight: 1150
        color: "#b0507e"
        QtObject {
            id: pal
            readonly property bool dark: true
            readonly property color fg: "white"
            readonly property color fg2: Qt.rgba(1, 1, 1, 0.62)
            readonly property color fg3: Qt.rgba(1, 1, 1, 0.34)
            readonly property color tile: Qt.rgba(1, 1, 1, 0.10)
            readonly property color tileBorder: Qt.rgba(1, 1, 1, 0.16)
            readonly property color track: Qt.rgba(1, 1, 1, 0.20)
            readonly property color sep: Qt.rgba(1, 1, 1, 0.14)
            readonly property color btnOff: Qt.rgba(1, 1, 1, 0.20)
            readonly property color btnHover: Qt.rgba(1, 1, 1, 0.30)
            readonly property color hover: Qt.rgba(1, 1, 1, 0.14)
        }
        Item {
            id: board
            anchors.fill: parent
            Rectangle { anchors.fill: parent; gradient: Gradient { GradientStop { position: 0; color: "#c96aa0" } GradientStop { position: 1; color: "#7a2bd6" } } }
            Flow {
                x: 12; y: 12; width: 740; spacing: 12
                Repeater {
                    model: (Quickshell.env("SILKY_PREVIEW_WIDGETS") || "ai:small ai:medium weather:medium ai:large weather:large stocks:small")
                           .split(/\s+/).filter(x => x).map(x => x.split(":"))
                    SilkyWidget {
                        required property var modelData
                        kind: modelData[0]; size: modelData[1]
                        info: Sample.info; pal: pal; fam: "Open Runde"; bold: "Open Runde Semibold"
                        accent: "#ab7df2"; upRed: true
                    }
                }
            }
        }
        Timer {
            interval: 1500; running: true
            onTriggered: board.grabToImage(r => { r.saveToFile(Quickshell.env("SILKY_PREVIEW_OUT")); Qt.quit(); })
        }
    }
}
