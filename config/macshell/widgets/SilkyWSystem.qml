// System: small = CPU / memory / disk bars; medium = three rings; large = rings + CPU history + details.
import QtQuick
import "SilkyWidgetsFormat.js" as F

Item {
    id: w
    required property var host
    readonly property var d: host.info ? host.info.system : null
    property var history: []
    onDChanged: if (d && typeof d.cpu === "number") history = history.concat([d.cpu]).slice(-60)

    readonly property var gauges: d ? [
        { label: F.tr("CPU"), value: d.cpu, detail: d.cores + (F.zh() ? " 核" : " cores") },
        { label: F.tr("Memory"), value: d.memory, detail: F.bytes(d.memUsed) + " / " + F.bytes(d.memTotal) },
        { label: F.tr("Disk"), value: d.disk, detail: F.bytes(d.diskUsed) + " / " + F.bytes(d.diskTotal) }
    ] : []
    function ink(v) {
        if (v >= 90) return w.host.dark ? "#ff6b61" : "#c4302b";
        if (v >= 75) return w.host.dark ? "#ffb35c" : "#b45a0f";
        return w.host.accent;
    }
    function pct(v) { return typeof v === "number" && isFinite(v) ? Math.round(v) + "%" : "—"; }

    SilkyWLabel { visible: !w.d; host: w.host; anchors.centerIn: parent; dim: true; text: F.tr("Loading…") }

    // small: bars
    Column {
        visible: w.d !== null && w.host.size === "small"
        x: 16; y: 14; width: parent.width - 32
        spacing: 10
        SilkyWLabel { host: w.host; dim: true; strong: true; px: 12; text: F.tr("System") }
        Repeater {
            model: w.gauges
            Column {
                required property var modelData
                width: parent.width
                spacing: 4
                Item {
                    width: parent.width; height: 16
                    SilkyWLabel { host: w.host; px: 12; text: modelData.label }
                    SilkyWLabel { anchors.right: parent.right; host: w.host; strong: true; px: 12; text: w.pct(modelData.value) }
                }
                Rectangle {
                    width: parent.width; height: 6; radius: 3; color: w.host.track
                    Rectangle {
                        width: Math.max(6, parent.width * Math.min(100, modelData.value || 0) / 100)
                        height: 6; radius: 3; color: w.ink(modelData.value)
                        Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                    }
                }
            }
        }
    }

    // medium / large: rings
    Row {
        visible: w.d !== null && w.host.size !== "small"
        x: 16; y: w.host.size === "large" ? 18 : 22
        width: parent.width - 32
        Repeater {
            model: w.gauges
            Column {
                required property var modelData
                width: (w.width - 32) / 3
                spacing: 6
                Item {
                    width: 82; height: 82
                    anchors.horizontalCenter: parent.horizontalCenter
                    SilkyWRing { anchors.fill: parent; value: modelData.value || 0; ink: w.ink(modelData.value); track: w.host.track; line: 8 }
                    SilkyWLabel { anchors.centerIn: parent; host: w.host; strong: true; px: 18; text: w.pct(modelData.value) }
                }
                SilkyWLabel { anchors.horizontalCenter: parent.horizontalCenter; host: w.host; strong: true; px: 12; text: modelData.label }
                SilkyWLabel {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(implicitWidth, parent.width - 4)
                    host: w.host; dim: true; px: 10; text: modelData.detail
                }
            }
        }
    }

    // large: CPU history + uptime / load
    Item {
        visible: w.d !== null && w.host.size === "large"
        x: 16; y: 168; width: parent.width - 32; height: parent.height - y - 16
        Rectangle { width: parent.width; height: 1; color: w.host.pal ? w.host.pal.sep : Qt.rgba(1, 1, 1, 0.12) }
        SilkyWLabel { y: 12; host: w.host; dim: true; strong: true; px: 12; text: F.tr("CPU") + " · " + (F.zh() ? "最近 5 分钟" : "last 5 min") }
        SilkyWSpark {
            y: 32; width: parent.width; height: 92
            values: w.history.length > 1 ? w.history : []
            ink: w.host.accent
            guide: w.host.fg3
        }
        Row {
            anchors.bottom: parent.bottom
            width: parent.width
            SilkyWLabel { width: parent.width / 2; host: w.host; dim: true; px: 12
                          text: w.d ? F.tr("Uptime") + " " + F.uptime(w.d.uptime) : "" }
            SilkyWLabel { width: parent.width / 2; horizontalAlignment: Text.AlignRight; host: w.host; dim: true; px: 12
                          text: w.d ? F.tr("Load") + " " + w.d.load.toFixed(2) : "" }
        }
    }
}
