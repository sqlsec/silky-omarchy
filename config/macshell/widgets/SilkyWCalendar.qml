// Calendar: small = today with the lunar date; medium = today + this month; large = the month with lunar dates.
import QtQuick
import "SilkyWidgetsFormat.js" as F
import "ChinaCalendar.js" as ChinaCalendar

Item {
    id: w
    required property var host
    property date today: new Date()
    Timer { interval: 60000; running: true; repeat: true; onTriggered: w.today = new Date() }

    readonly property bool zh: F.zh()
    readonly property color red: host.dark ? "#ff6b61" : "#d1332b"
    readonly property var china: ChinaCalendar.details(today)
    readonly property string weekdayText: zh ? "星期" + "日一二三四五六"[today.getDay()]
                                             : ["SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY"][today.getDay()]
    readonly property string monthText: zh ? (today.getFullYear() + " 年 " + (today.getMonth() + 1) + " 月")
                                           : Qt.formatDate(today, "MMMM yyyy")
    // 6×7 cells starting on Monday (zh) or Sunday
    readonly property var cells: {
        var first = new Date(today.getFullYear(), today.getMonth(), 1);
        var offset = zh ? (first.getDay() + 6) % 7 : first.getDay();
        var days = new Date(today.getFullYear(), today.getMonth() + 1, 0).getDate(), out = [];
        for (var i = 0; i < 42; i++) {
            var n = i - offset + 1;
            if (n < 1 || n > days) { out.push(null); continue; }
            var d = new Date(today.getFullYear(), today.getMonth(), n);
            var info = zh ? ChinaCalendar.details(d) : { lunar: "", festival: "", status: "" };
            out.push({ n: n, today: n === today.getDate(), weekend: d.getDay() === 0 || d.getDay() === 6,
                       lunar: info.festival || info.lunar, status: info.status });
        }
        while (out.length > 35 && out.slice(out.length - 7).every(c => c === null)) out.length -= 7;
        return out;
    }
    readonly property var heads: zh ? ["一", "二", "三", "四", "五", "六", "日"] : ["S", "M", "T", "W", "T", "F", "S"]

    // today (small, and the left half of medium)
    Item {
        visible: w.host.size !== "large"
        x: 16; y: 14; width: 140; height: 144
        SilkyWLabel { host: w.host; strong: true; px: 13; color: w.red; text: w.weekdayText }
        SilkyWLabel { y: 14; host: w.host; px: 56; font.weight: Font.Light; text: w.today.getDate() }
        SilkyWLabel {
            y: 90; host: w.host; px: 13; strong: true; width: parent.width
            text: w.zh ? (w.china.festival || ("农历" + w.china.lunar)) : Qt.formatDate(w.today, "MMMM")
        }
        SilkyWLabel { y: 110; host: w.host; dim: true; px: 12; width: parent.width; text: F.tr("No events today") }
    }

    // month grid (medium: right half; large: full card)
    Item {
        id: month
        visible: w.host.size !== "small"
        readonly property bool big: w.host.size === "large"
        x: big ? 16 : 172; y: big ? 14 : 12
        width: parent.width - x - (big ? 16 : 14)
        height: parent.height - y - (big ? 14 : 12)
        readonly property real cellW: width / 7
        readonly property int rows: Math.ceil(w.cells.length / 7)
        readonly property real cellH: (height - (big ? 42 : 27)) / rows

        SilkyWLabel {
            visible: month.big
            host: w.host; strong: true; px: 15; color: w.red; text: w.monthText
        }
        SilkyWLabel {
            visible: !month.big
            host: w.host; strong: true; px: 10; color: w.red; text: w.monthText
        }
        Row {
            y: month.big ? 24 : 14
            Repeater {
                model: w.heads
                SilkyWLabel {
                    required property string modelData
                    width: month.cellW; horizontalAlignment: Text.AlignHCenter
                    host: w.host; dim: true; strong: true; px: month.big ? 11 : 9; text: modelData
                }
            }
        }
        Grid {
            y: month.big ? 42 : 27
            columns: 7
            Repeater {
                model: w.cells
                Item {
                    required property var modelData
                    width: month.cellW; height: month.cellH
                    Rectangle {
                        visible: modelData !== null && modelData.today
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: month.big ? 1 : (parent.height - height) / 2
                        width: month.big ? Math.min(parent.width - 4, 36) : Math.min(parent.width, parent.height) - 1
                        height: month.big ? parent.height - 2 : width
                        radius: month.big ? 9 : width / 2
                        color: w.red
                    }
                    SilkyWLabel {
                        visible: modelData !== null
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: month.big ? 3 : (parent.height - height) / 2
                        host: w.host
                        px: month.big ? 14 : 10
                        strong: modelData !== null && modelData.today
                        color: modelData && modelData.today ? "white" : modelData && modelData.weekend ? w.host.fg2 : w.host.fg
                        text: modelData ? modelData.n : ""
                    }
                    SilkyWLabel {
                        visible: month.big && modelData !== null && modelData.lunar !== ""
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 21; width: parent.width - 2; horizontalAlignment: Text.AlignHCenter
                        host: w.host; px: 8
                        color: modelData && modelData.today ? Qt.rgba(1, 1, 1, 0.85) : w.host.fg2
                        text: modelData ? modelData.lunar : ""
                    }
                    SilkyWLabel {
                        visible: month.big && modelData !== null && modelData.status !== ""
                        anchors.right: parent.right; y: 0
                        host: w.host; px: 7; strong: true
                        color: modelData && modelData.status === "休" ? "#4cd97b" : w.red
                        text: modelData ? modelData.status : ""
                    }
                }
            }
        }
    }
}
