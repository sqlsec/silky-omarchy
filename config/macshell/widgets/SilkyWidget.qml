// One widget card in the notification centre: a glass tile of a fixed macOS size that loads the content for its kind.
//   small 172×172 · medium 356×172 · large 356×356 (two small tiles and the 12 px gap make one medium width)
import QtQuick

Item {
    id: card
    required property string kind
    required property string size
    property var info: null             // the latest JSON sample from silky-widgets.py
    property var pal: null              // the panel palette (fg, fg2, fg3, tile, tileBorder, track, dark)
    property string fam: "sans-serif"
    property string bold: "sans-serif"
    property color accent: "#6cb8ff"
    property bool upRed: true           // stock colours: red up / green down (Chinese convention) or the reverse

    readonly property real unit: 172
    readonly property real gap: 12
    readonly property bool dark: pal ? pal.dark : true
    readonly property color fg: pal ? pal.fg : "white"
    readonly property color fg2: pal ? pal.fg2 : Qt.rgba(1, 1, 1, 0.62)
    readonly property color fg3: pal ? pal.fg3 : Qt.rgba(1, 1, 1, 0.34)
    readonly property color track: pal ? pal.track : Qt.rgba(1, 1, 1, 0.2)
    readonly property color upColor: upRed ? (dark ? "#ff6b61" : "#d1332b") : (dark ? "#4cd97b" : "#1b8a3e")
    readonly property color downColor: upRed ? (dark ? "#4cd97b" : "#1b8a3e") : (dark ? "#ff6b61" : "#d1332b")

    width: size === "small" ? unit : unit * 2 + gap
    height: size === "large" ? unit * 2 + gap : unit

    // The glass comes from MacBar (the notification panel's liquid-glass context, the same material as the Control
    // Center tiles). Without it — or while that glass is off — a darker translucent tile stands in.
    property Component glass: null
    Loader {
        anchors.fill: parent
        active: card.glass !== null
        sourceComponent: card.glass
        onLoaded: item.r = 22
    }
    Rectangle {
        anchors.fill: parent
        radius: 22
        color: card.dark ? Qt.rgba(0.05, 0.04, 0.07, card.glass ? 0.26 : 0.34) : Qt.rgba(1, 1, 1, card.glass ? 0.10 : 0.34)
        border.width: card.glass ? 0 : 1
        border.color: card.dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.6)
    }

    // content is created with `host` already set, so its bindings never see a null host
    function load() {
        var file = ({ weather: "SilkyWWeather.qml", stocks: "SilkyWStocks.qml", screentime: "SilkyWScreenTime.qml",
                      battery: "SilkyWBattery.qml", calendar: "SilkyWCalendar.qml", system: "SilkyWSystem.qml",
                      ai: "SilkyWAI.qml" })[kind];
        if (file) content.setSource(file, { host: card });
        else content.source = "";
    }
    onKindChanged: load()
    Component.onCompleted: load()
    Loader {
        id: content
        anchors.fill: parent
    }
}
