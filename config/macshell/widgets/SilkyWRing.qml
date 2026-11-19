// Circular gauge: value 0..100 drawn clockwise from 12 o'clock.
import QtQuick

Canvas {
    id: ring
    property real value: 0
    property color ink: "white"
    property color track: Qt.rgba(1, 1, 1, 0.16)
    property real line: 6
    antialiasing: true
    onValueChanged: requestPaint()
    onInkChanged: requestPaint()
    onTrackChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
        var ctx = getContext("2d");
        ctx.reset();
        var r = Math.min(width, height) / 2 - line / 2, cx = width / 2, cy = height / 2, start = -Math.PI / 2;
        ctx.lineWidth = line;
        ctx.lineCap = "round";
        ctx.beginPath();
        ctx.arc(cx, cy, r, 0, Math.PI * 2);
        ctx.strokeStyle = track;
        ctx.stroke();
        var v = Math.max(0, Math.min(100, value || 0));
        if (v > 0) {
            ctx.beginPath();
            ctx.arc(cx, cy, r, start, start + Math.PI * 2 * v / 100);
            ctx.strokeStyle = ink;
            ctx.stroke();
        }
    }
}
