// Silky Omarchy: Bluetooth device-type icon, the round badge macOS puts in front of every device row.
// kind comes from SilkyBluetooth.iconFor(): headphones, speaker, gamepad, keyboard, mouse, trackpad, phone, computer, monitor,
// bluetooth. WGlyph draws the shapes it already has; gamepad, phone and computer are drawn here on the same 18-unit grid.
import QtQuick

Item {
    id: ic
    property string kind: "bluetooth"
    property bool active: false            // connected: accent disc, white symbol
    property bool badge: true              // round disc behind the symbol
    property bool dark: true
    property color accent: "#0A84FF"
    property color fg: dark ? "white" : "#1d1d1f"
    readonly property color symbol: badge && active ? "white" : fg
    readonly property bool own: kind === "gamepad" || kind === "phone" || kind === "computer"
    width: 26; height: 26

    Rectangle {
        visible: ic.badge
        anchors.fill: parent
        radius: width / 2
        color: ic.active ? ic.accent : (ic.dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.07))
        Behavior on color { ColorAnimation { duration: 180 } }
    }
    WGlyph {
        visible: !ic.own
        anchors.centerIn: parent
        width: Math.round(ic.width * (ic.badge ? 0.58 : 1)); height: width
        kind: ic.kind === "computer" ? "monitor" : ic.kind
        color: ic.symbol
    }
    Canvas {
        id: cv
        visible: ic.own
        anchors.centerIn: parent
        width: Math.round(ic.width * (ic.badge ? 0.62 : 1)); height: width
        antialiasing: true
        property string k: ic.kind
        property color c: ic.symbol
        onKChanged: requestPaint()
        onCChanged: requestPaint()
        onWidthChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            var s = width / 18;
            ctx.scale(s, s);
            ctx.strokeStyle = c; ctx.fillStyle = c;
            ctx.lineWidth = 1.5; ctx.lineCap = "round"; ctx.lineJoin = "round";
            function line(x1, y1, x2, y2) { ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2); ctx.stroke(); }
            function rr(x, y, w, h, r) {
                ctx.beginPath();
                ctx.moveTo(x + r, y); ctx.lineTo(x + w - r, y); ctx.arcTo(x + w, y, x + w, y + r, r);
                ctx.lineTo(x + w, y + h - r); ctx.arcTo(x + w, y + h, x + w - r, y + h, r);
                ctx.lineTo(x + r, y + h); ctx.arcTo(x, y + h, x, y + h - r, r);
                ctx.lineTo(x, y + r); ctx.arcTo(x, y, x + r, y, r);
                ctx.closePath();
            }
            if (k === "gamepad") {
                // same outline as MacBar's Control Center gamepad glyph
                ctx.beginPath();
                ctx.moveTo(5, 5); ctx.lineTo(13, 5);
                ctx.bezierCurveTo(16.4, 5, 17.4, 9.5, 16.6, 12.6); ctx.bezierCurveTo(16.1, 14.4, 14.2, 14.6, 13.1, 13.2);
                ctx.lineTo(11.8, 11.6); ctx.lineTo(6.2, 11.6); ctx.lineTo(4.9, 13.2);
                ctx.bezierCurveTo(3.8, 14.6, 1.9, 14.4, 1.4, 12.6); ctx.bezierCurveTo(0.6, 9.5, 1.6, 5, 5, 5);
                ctx.closePath(); ctx.stroke();
                line(5.3, 7.4, 5.3, 10.2); line(3.9, 8.8, 6.7, 8.8);
                ctx.beginPath(); ctx.arc(12.4, 8.0, 0.9, 0, Math.PI * 2); ctx.fill();
                ctx.beginPath(); ctx.arc(14.0, 9.6, 0.9, 0, Math.PI * 2); ctx.fill();
            } else if (k === "phone") {
                rr(5, 1.6, 8, 14.8, 2.2); ctx.stroke();
                line(7.8, 3.6, 10.2, 3.6);
            } else if (k === "computer") {
                rr(3, 3.4, 12, 8.4, 1.4); ctx.stroke();
                line(1.4, 14.2, 16.6, 14.2);
            }
        }
    }
}
