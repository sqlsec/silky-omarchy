// Weather: small = now; medium = now + next 6 hours; large = now + hours + 6 days.
// Same glass tile as the other widgets, with a faint sky tint (day / cloud / rain / night) washed over its top.
import QtQuick
import "SilkyWidgetsFormat.js" as F

Item {
    id: w
    required property var host
    readonly property var d: host.info ? host.info.weather : null
    readonly property var cond: d ? F.wmo(d.code, d.day) : null
    readonly property string sky: !d ? "none" : !d.day ? "night"
                                 : (d.code >= 51 || d.code === 45 || d.code === 48) ? "rain" : d.code >= 3 ? "cloud" : "day"
    readonly property color ink: host.fg
    readonly property color ink2: host.fg2
    readonly property color tint: ({ day: "#3d8ee6", cloud: "#8094ab", rain: "#5d6f86", night: "#2a3c6e" })[sky] || "#3d8ee6"

    Rectangle {
        anchors.fill: parent
        radius: 22
        visible: w.d !== null
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(w.tint.r, w.tint.g, w.tint.b, w.host.dark ? 0.30 : 0.22) }
            GradientStop { position: 0.75; color: Qt.rgba(w.tint.r, w.tint.g, w.tint.b, 0.04) }
            GradientStop { position: 1; color: "transparent" }
        }
    }

    SilkyWLabel {
        visible: !w.d
        host: w.host
        anchors.centerIn: parent
        dim: true
        text: w.host.info && w.host.info.errors && w.host.info.errors.weather ? F.tr("Offline") : F.tr("Loading…")
    }

    // now: city, temperature, condition, high / low
    Item {
        id: now
        visible: w.d !== null
        x: 16; y: 14
        width: w.host.size === "small" ? parent.width - 32 : parent.width - 32
        height: 140
        SilkyWLabel { id: city; host: w.host; color: w.ink; strong: true; px: 14; width: parent.width - (w.host.size === "small" ? 0 : 130); text: w.d ? w.d.city + "  ➤" : "" }
        SilkyWLabel {
            id: temp
            host: w.host; color: w.ink; y: w.host.size === "small" ? 18 : 16; px: w.host.size === "small" ? 44 : 40
            font.weight: Font.Light; font.family: w.host.fam
            text: w.d ? w.d.temp + "°" : ""
        }
        WeatherIcon {
            visible: w.host.size === "small"
            y: 92; size: 20
            kind: w.cond ? w.cond.k : "cloud"
        }
        // small: condition and high / low on two lines; medium / large: one line under the temperature
        SilkyWLabel {
            visible: w.host.size === "small"
            host: w.host; color: w.ink; y: 116; px: 13; strong: true
            width: parent.width
            text: w.cond ? F.tr(w.cond.t) : ""
        }
        SilkyWLabel {
            visible: w.host.size === "small"
            host: w.host; color: w.ink2; y: 134; px: 12
            text: w.d ? F.tr("H") + " " + w.d.hi + "°  " + F.tr("L") + " " + w.d.lo + "°" : ""
        }
        Row {
            visible: w.host.size !== "small"
            y: 64
            spacing: 8
            SilkyWLabel { host: w.host; color: w.ink; px: 13; strong: true; text: w.cond ? F.tr(w.cond.t) : "" }
            SilkyWLabel { host: w.host; color: w.ink2; px: 12; anchors.baseline: parent.children[0].baseline
                          text: w.d ? F.tr("H") + " " + w.d.hi + "°  " + F.tr("L") + " " + w.d.lo + "°" : "" }
        }
        // medium / large: icon and extra readings on the right
        Column {
            visible: w.host.size !== "small"
            anchors.right: parent.right
            y: 2
            spacing: 2
            WeatherIcon { anchors.right: parent.right; size: 28; kind: w.cond ? w.cond.k : "cloud" }
            SilkyWLabel { anchors.right: parent.right; host: w.host; color: w.ink2; px: 11; text: w.d ? F.tr("Feels like") + " " + w.d.feels + "°" : "" }
            SilkyWLabel { anchors.right: parent.right; host: w.host; color: w.ink2; px: 11; text: w.d ? F.tr("Humidity") + " " + w.d.humidity + "%" : "" }
            SilkyWLabel { anchors.right: parent.right; host: w.host; color: w.ink2; px: 11; text: w.d ? F.tr("Wind") + " " + w.d.wind + " km/h" : "" }
        }
    }

    // next hours
    Row {
        visible: w.d !== null && w.host.size !== "small"
        x: 16; y: 106
        width: parent.width - 32
        Repeater {
            model: w.d ? w.d.hourly : []
            Column {
                required property var modelData
                required property int index
                width: (w.width - 32) / 6
                spacing: 2
                SilkyWLabel { anchors.horizontalCenter: parent.horizontalCenter; host: w.host; color: w.ink2; px: 11
                              text: index === 0 ? F.tr("Now") : modelData.time }
                WeatherIcon { anchors.horizontalCenter: parent.horizontalCenter; size: 16; kind: F.wmo(modelData.code, modelData.day).k }
                SilkyWLabel { anchors.horizontalCenter: parent.horizontalCenter; host: w.host; color: w.ink; px: 12; strong: true
                              text: modelData.temp + "°" }
            }
        }
    }

    // coming days, with a range bar scaled to the week's lowest / highest
    Column {
        id: days
        visible: w.d !== null && w.host.size === "large"
        x: 16; y: 190
        width: parent.width - 32
        spacing: 0
        readonly property real lo: w.d ? Math.min.apply(null, w.d.daily.map(x => x.lo)) : 0
        readonly property real hi: w.d ? Math.max.apply(null, w.d.daily.map(x => x.hi)) : 1
        Rectangle { width: parent.width; height: 1; color: w.host.track }
        Item { width: 1; height: 6 }
        Repeater {
            model: w.d ? w.d.daily.slice(0, 6) : []
            Item {
                required property var modelData
                required property int index
                width: days.width
                height: 25
                SilkyWLabel { host: w.host; color: w.ink; px: 13; strong: index === 0; width: 52
                              anchors.verticalCenter: parent.verticalCenter; text: F.weekday(modelData.date, index) }
                WeatherIcon { x: 56; anchors.verticalCenter: parent.verticalCenter; size: 17; kind: F.wmo(modelData.code, true).k }
                SilkyWLabel { x: 92; width: 32; horizontalAlignment: Text.AlignRight; host: w.host; color: w.ink2; px: 13
                              anchors.verticalCenter: parent.verticalCenter; text: modelData.lo + "°" }
                Rectangle {
                    id: rangeTrack
                    x: 132; width: parent.width - 132 - 40; height: 4; radius: 2
                    anchors.verticalCenter: parent.verticalCenter
                    color: w.host.track
                    Rectangle {
                        readonly property real span: Math.max(1, days.hi - days.lo)
                        x: rangeTrack.width * (modelData.lo - days.lo) / span
                        width: Math.max(4, rangeTrack.width * (modelData.hi - modelData.lo) / span)
                        height: 4; radius: 2
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: "#8fd3ff" }
                            GradientStop { position: 1; color: "#ffc66b" }
                        }
                    }
                }
                SilkyWLabel { anchors.right: parent.right; width: 32; horizontalAlignment: Text.AlignRight; host: w.host; color: w.ink; px: 13
                              anchors.verticalCenter: parent.verticalCenter; text: modelData.hi + "°" }
            }
        }
    }
}
