// Bar chart with rounded bars; the highlighted bar is drawn in full ink, the rest dimmer.
import QtQuick

Item {
    id: bars
    property var values: []
    property int highlight: -1
    property color ink: "white"
    property color track: Qt.rgba(1, 1, 1, 0.12)
    property real gap: 2
    property real ceiling: 0            // > 0: scale against this instead of the largest value (for overlaid series)
    readonly property real peak: ceiling > 0 ? ceiling : Math.max(1, Math.max.apply(null, (values && values.length) ? values : [0]))
    Row {
        anchors.fill: parent
        spacing: bars.gap
        Repeater {
            model: bars.values ? bars.values.length : 0
            Item {
                required property int index
                width: (bars.width - bars.gap * (bars.values.length - 1)) / bars.values.length
                height: bars.height
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: Math.max(2, parent.height * (bars.values[index] || 0) / bars.peak)
                    radius: Math.min(width / 2, 2.5)
                    visible: bars.track.a > 0 || (bars.values[index] || 0) > 0
                    color: (bars.values[index] || 0) <= 0 ? bars.track
                         : index === bars.highlight || bars.highlight < 0 ? bars.ink
                         : Qt.rgba(bars.ink.r, bars.ink.g, bars.ink.b, 0.55)
                }
            }
        }
    }
}
