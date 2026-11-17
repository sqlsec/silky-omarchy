import QtQuick

Canvas {
    id: icon
    required property string kind
    property color ink: "white"
    implicitWidth: 16
    implicitHeight: 16
    onKindChanged: requestPaint()
    onInkChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        ctx.scale(width / 20, height / 20);
        ctx.strokeStyle = ink;
        ctx.lineWidth = 1.55;
        ctx.lineJoin = "round";
        ctx.lineCap = "round";
        ctx.beginPath();

        function line(points) {
            ctx.moveTo(points[0], points[1]);
            for (let i = 2; i < points.length; i += 2)
                ctx.lineTo(points[i], points[i + 1]);
        }
        function circle(x, y, radius) {
            ctx.moveTo(x + radius, y);
            ctx.arc(x, y, radius, 0, Math.PI * 2);
        }

        switch (kind) {
        case "chatgpt":
            ctx.save();
            ctx.translate(10, 10);
            for (let arm = 0; arm < 6; arm++) {
                ctx.moveTo(-2.6, -0.2);
                ctx.lineTo(-2.6, -4.1);
                ctx.quadraticCurveTo(-2.6, -6.8, 0.3, -7.2);
                ctx.quadraticCurveTo(3.4, -7.6, 4.7, -4.7);
                ctx.rotate(Math.PI / 3);
            }
            ctx.restore();
            break;
        case "chrome":
            circle(10, 10, 7.5);
            circle(10, 10, 3.25);
            line([10, 6.75, 16.75, 6.75]);
            line([12.8, 11.65, 9.45, 17.47]);
            line([7.2, 11.65, 3.82, 5.8]);
            break;
        case "clippy":
            ctx.moveTo(13.5, 7.5);
            ctx.lineTo(8, 13);
            ctx.quadraticCurveTo(6.1, 14.8, 5, 13.5);
            ctx.quadraticCurveTo(3.9, 12.4, 5.5, 10.8);
            ctx.lineTo(12.3, 4.1);
            ctx.quadraticCurveTo(14.8, 1.7, 17, 3.8);
            ctx.quadraticCurveTo(19.1, 6, 16.6, 8.5);
            ctx.lineTo(9.8, 15.3);
            ctx.quadraticCurveTo(6.3, 18.8, 3.4, 16);
            ctx.quadraticCurveTo(0.7, 13.2, 3.8, 10);
            break;
        case "netcatty":
            ctx.moveTo(4, 6);
            ctx.lineTo(4, 3.4);
            ctx.quadraticCurveTo(4, 2.7, 4.7, 3.1);
            ctx.lineTo(8, 6);
            ctx.lineTo(12, 6);
            ctx.lineTo(15.3, 3.1);
            ctx.quadraticCurveTo(16, 2.7, 16, 3.4);
            ctx.lineTo(16, 6);
            ctx.quadraticCurveTo(17.6, 6.3, 17.6, 8);
            ctx.lineTo(17.6, 14.7);
            ctx.quadraticCurveTo(17.6, 16.8, 15.5, 16.8);
            ctx.lineTo(4.5, 16.8);
            ctx.quadraticCurveTo(2.4, 16.8, 2.4, 14.7);
            ctx.lineTo(2.4, 8);
            ctx.quadraticCurveTo(2.4, 6.3, 4, 6);
            ctx.closePath();
            line([6.4, 9.5, 8.4, 11.4, 6.4, 13.3]);
            line([10.4, 13.4, 13.6, 13.4]);
            break;
        case "wechat": {
            // two speech bubbles, the small one in front: erase the big bubble's line where the small one covers it
            ctx.ellipse(1.6, 2.6, 12.8, 10.6);
            line([4.3, 12.2, 3.6, 15, 6.6, 13.2]);
            ctx.stroke();
            ctx.save();
            ctx.globalCompositeOperation = "destination-out";
            ctx.beginPath();
            ctx.ellipse(7.4, 7.0, 12.0, 10.0);
            ctx.fill();
            ctx.restore();
            ctx.beginPath();
            ctx.ellipse(8.4, 8.0, 10.0, 8.2);
            line([16.2, 15.4, 16.9, 17.8, 14.2, 16.3]);
            ctx.stroke();
            ctx.fillStyle = ink;
            ctx.beginPath();
            circle(5.6, 6.6, 0.95);
            circle(9.6, 6.6, 0.95);
            circle(11.6, 11.6, 0.8);
            circle(15.2, 11.6, 0.8);
            ctx.fill();
            ctx.beginPath();          // the final stroke below has nothing left to draw
            break;
        }
        case "remmina":
            ctx.roundedRect(2.5, 3.5, 15, 10.5, 2.2, 2.2);
            line([10, 14, 10, 16.7]);
            line([6.7, 17, 13.3, 17]);
            line([7.2, 10.4, 12.7, 6.6, 12.7, 10]);
            line([9.1, 6.6, 12.7, 6.6]);
            break;
        case "clash":
            ctx.moveTo(3.2, 9.2);
            ctx.lineTo(3.4, 3.7);
            ctx.quadraticCurveTo(3.5, 2.9, 4.2, 3.4);
            ctx.lineTo(7.6, 6.4);
            ctx.quadraticCurveTo(10, 5.6, 12.4, 6.4);
            ctx.lineTo(15.8, 3.4);
            ctx.quadraticCurveTo(16.5, 2.9, 16.6, 3.7);
            ctx.lineTo(16.8, 9.2);
            ctx.quadraticCurveTo(17.8, 10.9, 17.4, 12.7);
            ctx.quadraticCurveTo(16.6, 16.7, 10, 16.7);
            ctx.quadraticCurveTo(3.4, 16.7, 2.6, 12.7);
            ctx.quadraticCurveTo(2.2, 10.9, 3.2, 9.2);
            ctx.closePath();
            line([7.1, 10.7, 7.1, 11.8]);
            line([12.9, 10.7, 12.9, 11.8]);
            line([9.4, 13.1, 10, 13.6, 10.6, 13.1]);
            break;
        case "network":
            circle(10, 10, 7);
            ctx.moveTo(13.4, 10);
            ctx.ellipse(6.6, 3, 6.8, 14);
            line([3.2, 10, 16.8, 10]);
            break;
        case "down":
        case "up":
            if (kind === "up") {
                ctx.translate(0, 20);
                ctx.scale(1, -1);
            }
            line([10, 3.5, 10, 16.5]);
            line([5, 11.5, 10, 16.5, 15, 11.5]);
            break;
        case "thermal":
            ctx.moveTo(7.6, 11.6);
            ctx.lineTo(7.6, 5.1);
            ctx.arc(10, 5.1, 2.4, Math.PI, Math.PI * 2);
            ctx.lineTo(12.4, 11.6);
            ctx.arc(10, 14.1, 3.5, -0.8, 3.94);
            ctx.closePath();
            line([10, 8, 10, 14.1]);
            break;
        case "chip":
            ctx.rect(5, 5, 10, 10);
            ctx.rect(8, 8, 4, 4);
            for (let pin = 7; pin <= 13; pin += 3) {
                line([pin, 2.5, pin, 5]);
                line([pin, 15, pin, 17.5]);
                line([2.5, pin, 5, pin]);
                line([15, pin, 17.5, pin]);
            }
            break;
        case "battery":
            ctx.roundedRect(2, 5.5, 14.4, 9, 2, 2);
            line([18.2, 8.4, 18.2, 11.6]);
            line([5, 10, 12.8, 10]);
            break;
        case "power":
            line([11, 2.5, 4.5, 11, 9.2, 11, 8.6, 17.5, 15.5, 9, 10.5, 9, 11, 2.5]);
            break;
        case "apps":
            for (const y of [3.5, 11.5])
                for (const x of [3.5, 11.5])
                    ctx.roundedRect(x, y, 5, 5, 1.1, 1.1);
            break;
        case "copy":
            ctx.roundedRect(6.5, 6.5, 10, 10, 1.5, 1.5);
            line([3.5, 13, 3.5, 3.5, 13, 3.5]);
            break;
        case "check":
            line([4, 10, 8, 14, 16, 6]);
            break;
        case "close":
            line([5.5, 5.5, 14.5, 14.5]);
            line([5.5, 14.5, 14.5, 5.5]);
            break;
        default:
            line([2.5, 10, 6.5, 10, 9, 4.5, 12, 15.5, 14.5, 10, 17.5, 10]);
            break;
        }
        ctx.stroke();
    }
}
