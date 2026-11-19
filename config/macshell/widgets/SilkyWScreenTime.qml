// Screen Time: today's focused-window time per app (idle and locked time excluded).
//   small = total + top 3 apps; medium = total + hourly chart + top 3; large = + this week + top 6 apps
import QtQuick
import Quickshell
import "SilkyWidgetsFormat.js" as F

Item {
    id: w
    required property var host
    readonly property var d: host.info ? host.info.screenTime : null
    readonly property var apps: d ? d.apps : []
    readonly property int hour: new Date().getHours()

    function entry(cls) { return cls ? DesktopEntries.heuristicLookup(cls) : null; }
    function appName(cls) { var e = entry(cls); return e && e.name ? e.name : cls; }
    function appIcon(cls) { var e = entry(cls); return e && e.icon ? Quickshell.iconPath(e.icon, true) : ""; }

    SilkyWLabel {
        visible: !w.d
        host: w.host; anchors.centerIn: parent; dim: true; text: F.tr("Loading…")
    }

    Item {
        visible: w.d !== null
        anchors.fill: parent
        anchors.margins: 16

        SilkyWLabel { host: w.host; dim: true; px: 12; strong: true; text: F.tr("Screen Time") }
        SilkyWLabel {
            id: total
            y: 17; host: w.host; strong: true; px: w.host.size === "small" ? 22 : 26
            width: w.host.size === "small" ? parent.width : 150
            text: w.d ? F.duration(w.d.total) : ""
        }
        SilkyWLabel {
            visible: w.host.size !== "small"
            y: 52; host: w.host; dim: true; px: 11
            readonly property int diff: w.d ? w.d.total - w.d.yesterday : 0
            text: !w.d || w.d.yesterday <= 0 ? F.tr("Today")
                 : (diff >= 0 ? "▲ " : "▼ ") + F.duration(Math.abs(diff)) + " " + F.tr("vs yesterday")
        }

        // hourly bars for today (medium: right of the total; large: full width)
        Item {
            visible: w.host.size !== "small"
            x: w.host.size === "large" ? 0 : 160
            y: w.host.size === "large" ? 74 : 4
            width: parent.width - x
            height: w.host.size === "large" ? 70 : 62
            SilkyWBars {
                width: parent.width; height: parent.height - 14
                values: w.d ? w.d.hours : []
                highlight: w.hour
                ink: w.host.accent
                track: w.host.track
                gap: 2
            }
            Repeater {
                model: [0, 6, 12, 18]
                SilkyWLabel {
                    required property int modelData
                    x: parent.width * modelData / 24; y: parent.height - 12
                    host: w.host; dim: true; px: 9; text: modelData + (F.zh() ? "时" : "h")
                }
            }
        }

        // this week (large)
        Item {
            visible: w.host.size === "large"
            y: 150; width: parent.width; height: 52
            SilkyWLabel { host: w.host; dim: true; px: 11; strong: true; text: F.tr("This week") }
            SilkyWBars {
                x: 0; y: 16; width: parent.width; height: 28
                values: w.d ? w.d.week.map(x => x.seconds) : []
                highlight: 6
                ink: w.host.accent
                track: w.host.track
                gap: 8
            }
        }

        // most used apps
        Column {
            id: appList
            y: w.host.size === "small" ? 52 : w.host.size === "large" ? 206 : 76
            width: parent.width
            spacing: w.host.size === "large" ? 2 : 5
            readonly property real maxSeconds: w.apps.length ? Math.max(1, w.apps[0].seconds) : 1
            Repeater {
                model: w.apps.slice(0, w.host.size === "large" ? 6 : 3)
                Item {
                    required property var modelData
                    width: parent.width
                    height: w.host.size === "small" ? 26 : 18
                    Image {
                        id: icon
                        width: 16; height: 16
                        y: w.host.size === "small" ? 0 : 1
                        source: w.appIcon(modelData.app)
                        sourceSize: Qt.size(32, 32)
                        visible: source != ""
                    }
                    Rectangle { visible: !icon.visible; width: 16; height: 16; radius: 4; color: w.host.track; y: icon.y }
                    SilkyWLabel {
                        x: 22; y: w.host.size === "small" ? 0 : 1
                        width: w.host.size === "small" ? parent.width - 22 : 130
                        host: w.host; px: 12; text: w.appName(modelData.app)
                    }
                    // small: the duration bar sits under the name; medium / large: bar + duration on the right
                    Rectangle {
                        x: w.host.size === "small" ? 22 : 158
                        y: w.host.size === "small" ? 18 : 7
                        readonly property real room: w.host.size === "small" ? parent.width - 22 : parent.width - 158 - 70
                        width: Math.max(3, room * modelData.seconds / appList.maxSeconds)
                        height: 4; radius: 2
                        color: w.host.accent
                    }
                    SilkyWLabel {
                        visible: w.host.size !== "small"
                        anchors.right: parent.right; y: 1
                        host: w.host; dim: true; px: 11; text: F.duration(modelData.seconds)
                    }
                }
            }
            SilkyWLabel {
                visible: w.apps.length === 0
                host: w.host; dim: true; px: 12; text: F.tr("No screen time yet")
            }
        }
    }
}
