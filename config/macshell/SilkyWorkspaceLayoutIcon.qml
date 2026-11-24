import QtQuick

Canvas {
    id: icon
    property string mode: "floating"
    property color color: "#ffffff"
    property real strokeWidth: Math.max(1.3, width * 0.09)

    renderStrategy: Canvas.Cooperative
    onModeChanged: requestPaint()
    onColorChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    function roundRectPath(ctx, x, y, w, h, r) {
        const rr = Math.min(r, w / 2, h / 2);
        ctx.beginPath();
        ctx.moveTo(x + rr, y);
        ctx.lineTo(x + w - rr, y);
        ctx.quadraticCurveTo(x + w, y, x + w, y + rr);
        ctx.lineTo(x + w, y + h - rr);
        ctx.quadraticCurveTo(x + w, y + h, x + w - rr, y + h);
        ctx.lineTo(x + rr, y + h);
        ctx.quadraticCurveTo(x, y + h, x, y + h - rr);
        ctx.lineTo(x, y + rr);
        ctx.quadraticCurveTo(x, y, x + rr, y);
        ctx.closePath();
    }

    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        ctx.clearRect(0, 0, width, height);
        const w = width;
        const h = height;
        const sw = strokeWidth;
        const pad = sw * 0.85;
        ctx.strokeStyle = icon.color;
        ctx.fillStyle = icon.color;
        ctx.lineWidth = sw;
        ctx.lineCap = "round";
        ctx.lineJoin = "round";

        if (mode === "dwindle") {
            // Tiling: crisp full-frame split grid (left pane + two stacked right panes)
            const x = pad, y = pad, rw = w - pad * 2, rh = h - pad * 2;
            const r = Math.max(1.8, rw * 0.14);
            const midX = Math.round(x + rw * 0.5) + 0.5;
            const midY = Math.round(y + rh * 0.5) + 0.5;
            ctx.save();
            ctx.globalAlpha = 0.28;
            roundRectPath(ctx, x, y, midX - x, rh, r);
            ctx.fill();
            ctx.restore();
            roundRectPath(ctx, x, y, rw, rh, r);
            ctx.stroke();
            ctx.beginPath();
            ctx.moveTo(midX, y);
            ctx.lineTo(midX, y + rh);
            ctx.moveTo(midX, midY);
            ctx.lineTo(x + rw, midY);
            ctx.stroke();
        } else if (mode === "scrolling") {
            // Scrolling: three distinct vertical columns side-by-side + horizontal track bar
            const top = pad + h * 0.04;
            const ch = h * 0.66;
            const gap = Math.max(1.6, w * 0.11);
            const colW = (w - pad * 2 - gap * 2) / 3;
            const r = Math.max(1.2, colW * 0.28);

            for (let i = 0; i < 3; i++) {
                const cx = pad + i * (colW + gap);
                const center = (i === 1);
                const cy = center ? top : top + ch * 0.10;
                const hh = center ? ch : ch * 0.80;
                ctx.save();
                ctx.globalAlpha = center ? 0.34 : 0.12;
                roundRectPath(ctx, cx, cy, colW, hh, r);
                ctx.fill();
                ctx.restore();
                ctx.save();
                ctx.globalAlpha = center ? 1.0 : 0.55;
                roundRectPath(ctx, cx, cy, colW, hh, r);
                ctx.stroke();
                ctx.restore();
            }

            // Bottom scroll indicator bar
            const barY = h - pad - sw * 0.5;
            ctx.save();
            ctx.globalAlpha = 0.75;
            ctx.beginPath();
            ctx.moveTo(w * 0.24, barY);
            ctx.lineTo(w * 0.76, barY);
            ctx.stroke();
            ctx.restore();
        } else {
            // Floating: two clearly offset overlapping windows
            const bw = w * 0.60;
            const bh = h * 0.54;
            const r = Math.max(1.6, w * 0.14);
            const backX = w - pad - bw;
            const backY = h - pad - bh;

            ctx.save();
            ctx.globalAlpha = 0.6;
            roundRectPath(ctx, backX, backY, bw, bh, r);
            ctx.stroke();
            ctx.restore();

            const fx = pad;
            const fy = pad;
            ctx.save();
            ctx.globalAlpha = 0.30;
            roundRectPath(ctx, fx, fy, bw, bh, r);
            ctx.fill();
            ctx.restore();
            roundRectPath(ctx, fx, fy, bw, bh, r);
            ctx.stroke();
        }
    }
}
