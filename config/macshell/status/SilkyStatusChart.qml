import QtQuick

Canvas {
    id: chart
    required property var series
    required property color gridColor
    property bool thermal: false
    property int sampleCount: 40
    property real minimumUpper: 1024
    onSampleCountChanged: requestPaint()
    onMinimumUpperChanged: requestPaint()
    onSeriesChanged: requestPaint()
    onGridColorChanged: requestPaint()
    onThermalChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        const bottom = height - 1;
        const top = 3;
        const values = [];
        for (const line of series) {
            for (const value of line.values) {
                if (Number.isFinite(value))
                    values.push(value);
            }
        }
        const highest = values.length ? Math.max.apply(null, values) : 0;
        const lowest = values.length ? Math.min.apply(null, values) : highest;
        const upper = thermal ? Math.max(55, Math.ceil(highest / 5) * 5) : Math.max(minimumUpper, highest);
        const lower = thermal ? Math.min(upper - 15, Math.floor(lowest / 5) * 5) : 0;

        ctx.strokeStyle = gridColor;
        ctx.lineWidth = 1;
        ctx.beginPath();
        for (let i = 0; i < 3; i++) {
            const y = Math.round(top + (bottom - top) * i / 2) + 0.5;
            ctx.moveTo(0, y);
            ctx.lineTo(width, y);
        }
        ctx.stroke();

        function draw(points, color) {
            if (!points.length)
                return;
            ctx.beginPath();
            ctx.moveTo(points[0].x, points[0].y);
            for (const point of points.slice(1))
                ctx.lineTo(point.x, point.y);
            ctx.lineWidth = 1.5;
            ctx.lineJoin = "round";
            ctx.strokeStyle = color;
            if (points.length === 1) {
                ctx.lineTo(points[0].x + 1, points[0].y);
                ctx.stroke();
                return;
            }
            ctx.stroke();

            const gradient = ctx.createLinearGradient(0, top, 0, bottom);
            gradient.addColorStop(0, Qt.rgba(color.r, color.g, color.b, 0.24));
            gradient.addColorStop(1, Qt.rgba(color.r, color.g, color.b, 0.015));
            ctx.lineTo(points[points.length - 1].x, bottom);
            ctx.lineTo(points[0].x, bottom);
            ctx.closePath();
            ctx.fillStyle = gradient;
            ctx.fill();
        }

        for (const line of series) {
            let points = [];
            for (let index = 0; index < line.values.length; index++) {
                const value = line.values[index];
                if (Number.isFinite(value)) {
                    points.push({
                        "x": (width - 1) * (sampleCount - line.values.length + index) / (sampleCount - 1),
                        "y": bottom - (bottom - top) * (value - lower) / (upper - lower)
                    });
                } else if (points.length) {
                    draw(points, line.color);
                    points = [];
                }
            }
            draw(points, line.color);
        }
    }
}
