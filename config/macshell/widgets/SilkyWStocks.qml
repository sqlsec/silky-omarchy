// Stocks: small = the first symbol with a large chart; medium = 3 rows; large = 6 rows. Data: Tencent quotes.
import QtQuick
import "SilkyWidgetsFormat.js" as F

Item {
    id: w
    required property var host
    readonly property var list: host.info && host.info.stocks ? host.info.stocks.filter(s => s.price !== null && s.price !== undefined) : []
    readonly property var first: list.length ? list[0] : null
    function tone(s) { return !s || s.change === 0 ? w.host.fg2 : s.change > 0 ? w.host.upColor : w.host.downColor; }

    SilkyWLabel {
        visible: w.list.length === 0
        host: w.host
        anchors.centerIn: parent
        dim: true
        text: w.host.info && w.host.info.errors && w.host.info.errors.stocks ? F.tr("Offline") : F.tr("Loading…")
    }

    // small: one symbol
    Item {
        visible: w.host.size === "small" && w.first !== null
        anchors.fill: parent
        anchors.margins: 16
        SilkyWLabel { host: w.host; strong: true; px: 15; width: parent.width; text: w.first ? w.first.name : "" }
        SilkyWLabel { y: 20; host: w.host; dim: true; px: 11; text: w.first ? w.first.code + " · " + F.tr(w.first.span === "month" ? "1 month" : "Intraday") : "" }
        SilkyWSpark {
            y: 40; width: parent.width; height: 52
            values: w.first ? w.first.series : []
            reference: w.first && w.first.span === "intraday" ? w.first.prev : NaN
            ink: w.tone(w.first)
            guide: w.host.fg3
        }
        SilkyWLabel { y: 98; host: w.host; strong: true; px: 22; width: parent.width; text: w.first ? F.price(w.first.price) : "" }
        SilkyWLabel {
            y: 124; host: w.host; px: 13; strong: true; color: w.tone(w.first)
            text: w.first ? F.signed(w.first.change, 2) + "  " + F.signed(w.first.percent, 2, "%") : ""
        }
    }

    // medium / large: rows
    Column {
        visible: w.host.size !== "small" && w.list.length > 0
        x: 16; y: 10
        width: parent.width - 32
        Repeater {
            model: w.list.slice(0, w.host.size === "large" ? 6 : 3)
            Item {
                required property var modelData
                required property int index
                width: parent.width
                height: w.host.size === "large" ? 56 : 51
                Rectangle { visible: index > 0; width: parent.width; height: 1; color: w.host.pal ? w.host.pal.sep : Qt.rgba(1, 1, 1, 0.12) }
                SilkyWLabel { y: 11; host: w.host; strong: true; px: 14; width: 110; text: modelData.name }
                SilkyWLabel { y: 30; host: w.host; dim: true; px: 11; width: 110; text: modelData.code }
                SilkyWSpark {
                    x: 116; y: 9; width: parent.width - 116 - 104; height: parent.height - 18
                    values: modelData.series
                    reference: modelData.span === "intraday" ? modelData.prev : NaN
                    ink: w.tone(modelData)
                    guide: w.host.fg3
                    line: 1.3
                }
                SilkyWLabel {
                    anchors.right: parent.right; y: 8; host: w.host; strong: true; px: 14
                    horizontalAlignment: Text.AlignRight; text: F.price(modelData.price)
                }
                Rectangle {
                    anchors.right: parent.right; y: 28
                    width: 66; height: 18; radius: 5
                    color: w.tone(modelData)
                    SilkyWLabel {
                        anchors.centerIn: parent; host: w.host; px: 11; strong: true; color: "white"
                        text: F.signed(modelData.percent, 2, "%") || "0.00%"
                    }
                }
            }
        }
    }
}
