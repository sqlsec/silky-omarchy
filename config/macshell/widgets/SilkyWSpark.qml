// Sparkline with a soft fill and an optional dotted reference (previous close).
import QtQuick

Canvas {
    id: spark
    property var values: []
    property real reference: NaN
    property color ink: "white"
    property color guide: Qt.rgba(1, 1, 1, 0.3)
    property real line: 1.6
    antialiasing: true
    onValuesChanged: requestPaint()
    onInkChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
        var ctx = getContext("2d");
        ctx.reset();
        var v = values || [];
        if (v.length < 2) return;
        var lo = Math.min.apply(null, v), hi = Math.max.apply(null, v);
        if (isFinite(reference)) { lo = Math.min(lo, reference); hi = Math.max(hi, reference); }
        if (hi - lo < 1e-9) { hi += 1; lo -= 1; }
        var pad = line + 1, h = height - pad * 2;
        function y(p) { return pad + h * (1 - (p - lo) / (hi - lo)); }
        function x(i) { return (width - 1) * i / (v.length - 1); }
        if (isFinite(reference)) {
            ctx.strokeStyle = guide;
            ctx.lineWidth = 1;
            ctx.setLineDash([2, 3]);
            ctx.beginPath();
            ctx.moveTo(0, y(reference));
            ctx.lineTo(width, y(reference));
            ctx.stroke();
            ctx.setLineDash([]);
        }
        ctx.beginPath();
        ctx.moveTo(x(0), y(v[0]));
        for (var i = 1; i < v.length; i++) ctx.lineTo(x(i), y(v[i]));
        ctx.lineWidth = line;
        ctx.lineJoin = "round";
        ctx.strokeStyle = ink;
        ctx.stroke();
        ctx.lineTo(x(v.length - 1), height);
        ctx.lineTo(0, height);
        ctx.closePath();
        var g = ctx.createLinearGradient(0, 0, 0, height);
        g.addColorStop(0, Qt.rgba(ink.r, ink.g, ink.b, 0.28));
        g.addColorStop(1, Qt.rgba(ink.r, ink.g, ink.b, 0));
        ctx.fillStyle = g;
        ctx.fill();
    }
}
