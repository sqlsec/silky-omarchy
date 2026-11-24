import QtQuick
import Quickshell.Io

// Chooses dark or light ink for each menu-bar control from the wallpaper under it.
// The wallpaper strip is sampled once per wallpaper and output size; every Palette
// then reads its own span from the cached columns, so a split wallpaper gives black
// ink on one side and white on the other. Only a control that sits on a hard edge
// itself gets a backing plate, drawn the size of its hover pill and kept inside the bar.
Canvas {
    id: tone

    required property bool active
    required property string wallpaper
    required property int outputHeight
    required property real barHeight
    required property real barFill
    required property string fontFamily

    readonly property string sampler: decodeURIComponent(String(Qt.resolvedUrl("assets/silky-bar-tone.py")).replace(/^file:\/\//, ""))
    readonly property string request: active && wallpaper !== "" && width > 0 && outputHeight > 0 && barHeight > 0
        ? JSON.stringify([wallpaper, Math.round(width), outputHeight, Math.ceil(barHeight), Math.round(barFill * 100) / 100])
        : ""
    property string sampled: ""
    // Per sample column: [12th percentile, median, 88th percentile] of the luminance.
    property var columns: []
    property real sampledWidth: 0
    property var plates: ({})
    property int plateSerial: 0
    height: barHeight
    visible: active

    // WCAG 4.5:1 against white ink (#ffffff) and dark ink (#1d1d1f).
    readonly property real lightLimit: 1.05 / 4.5 - 0.05
    readonly property real darkLimit: 4.5 * (0.0124 + 0.05) - 0.05

    function encode(level) {
        return level <= 0.0031308 ? 12.92 * level : 1.055 * Math.pow(level, 1 / 2.4) - 0.055;
    }

    function percentile(values, fraction) {
        values.sort((a, b) => a - b);
        return values[Math.round((values.length - 1) * fraction)];
    }

    // Returns [darkInk, plateOpacity] for a span in bar coordinates, or null before the first sample.
    function read(x0, x1) {
        const count = columns.length;
        if (!active || count === 0 || sampledWidth <= 0 || x1 <= x0)
            return null;
        const first = Math.max(0, Math.min(count - 1, Math.floor(x0 * count / sampledWidth)));
        const last = Math.max(first + 1, Math.min(count, Math.ceil(x1 * count / sampledWidth)));
        const lows = [], middles = [], highs = [];
        for (let i = first; i < last; i++) {
            lows.push(columns[i][0]);
            middles.push(columns[i][1]);
            highs.push(columns[i][2]);
        }
        // Leave thin highlights and shadows out of the decision.
        const low = percentile(lows, 0.12);
        const high = percentile(highs, 0.88);
        const middle = percentile(middles, 0.5);
        // White ink: darken the brightest part until it passes; dark ink: lighten the darkest part.
        const bright = encode(high), dim = encode(low);
        const toWhite = high <= lightLimit ? 0 : 1 - encode(lightLimit) / Math.max(bright, 0.0001);
        const toDark = low >= darkLimit ? 0 : (encode(darkLimit) - dim) / Math.max(1 - dim, 0.0001);
        if (toWhite <= 0 && toDark <= 0)
            return [middle >= 0.21, 0];
        // For a mixed area with similar costs, prefer white ink on a dark plate.
        const dark = toDark <= 0 || toDark + 0.06 < toWhite;
        return [dark, Math.min(0.56, Math.max(0, dark ? toDark : toWhite))];
    }

    function setPlate(key, plate) {
        const next = Object.assign({}, plates);
        if (plate)
            next[key] = plate;
        else if (next[key] !== undefined)
            delete next[key];
        else
            return;
        plates = next;
    }

    component Palette: QtObject {
        id: palette
        required property SilkyBarContrast contrast
        // The control this ink is for, or several controls that share one ink.
        property Item item: null
        property var items: []
        property int key: 0
        readonly property var targets: item ? [item] : items.filter(it => it && it.visible && it.width > 0)
        readonly property rect bounds: {
            let x0 = Infinity, x1 = -Infinity, y0 = Infinity, y1 = -Infinity;
            for (const it of targets) {
                // Dependencies: the control, and the row that positions and scales it.
                void (it.x + it.y + it.width + it.height);
                if (it.parent)
                    void (it.parent.x + it.parent.width + it.parent.scale);
                const a = it.mapToItem(contrast, 1, 3);
                const b = it.mapToItem(contrast, it.width - 1, it.height - 3);
                x0 = Math.min(x0, a.x); x1 = Math.max(x1, b.x);
                y0 = Math.min(y0, a.y); y1 = Math.max(y1, b.y);
            }
            return x1 > x0 ? Qt.rect(x0, y0, x1 - x0, y1 - y0) : Qt.rect(0, 0, 0, 0);
        }
        // A single control is judged by its middle half, where the glyph sits, so an edge that only
        // crosses its padding does not earn a plate. Shared palettes use their whole span.
        readonly property real inset: item ? bounds.width / 4 : 0
        readonly property var reading: contrast.read(bounds.x + inset, bounds.x + bounds.width - inset)
        readonly property bool dark: !(reading && reading[0])
        readonly property real plate: reading ? reading[1] : 0
        readonly property string fam: contrast.fontFamily
        property color fg: dark ? "#ffffff" : "#1d1d1f"
        property color fg2: dark ? Qt.rgba(1, 1, 1, 0.76) : Qt.rgba(0, 0, 0, 0.70)
        // On a plate the faintest ink would lose most of the contrast the plate buys, so it steps up to fg2.
        property color fg3: plate > 0 ? fg2 : (dark ? Qt.rgba(1, 1, 1, 0.53) : Qt.rgba(0, 0, 0, 0.50))
        property color hover: dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.12)
        Behavior on fg { ColorAnimation { duration: 200 } }
        Behavior on fg2 { ColorAnimation { duration: 200 } }
        Behavior on fg3 { ColorAnimation { duration: 200 } }
        Behavior on hover { ColorAnimation { duration: 200 } }

        function publish() {
            if (key === 0)
                return;
            contrast.setPlate(key, plate > 0 && bounds.width > 0
                ? { x: bounds.x, y: bounds.y, w: bounds.width, h: bounds.height, channel: dark ? 0 : 1, opacity: plate }
                : null);
        }
        onPlateChanged: publish()
        onBoundsChanged: if (plate > 0) publish()
        onDarkChanged: if (plate > 0) publish()
        Component.onCompleted: { key = ++contrast.plateSerial; publish(); }
        Component.onDestruction: contrast.setPlate(key, null)
    }

    onPlatesChanged: requestPaint()
    onBarHeightChanged: requestPaint()
    onRequestChanged: {
        if (request === "") {
            sampled = "";
            columns = [];
        }
        debounce.restart();
    }
    Component.onCompleted: debounce.restart()

    Timer {
        id: debounce
        interval: 120
        onTriggered: {
            if (worker.running || tone.request === "" || tone.sampled === tone.request)
                return;
            const args = JSON.parse(tone.request);
            worker.key = tone.request;
            worker.command = ["python3", "-I", tone.sampler].concat(args.map(String));
            worker.running = true;
        }
    }

    Process {
        id: worker
        property string key: ""
        stdout: StdioCollector {
            onStreamFinished: {
                if (worker.key !== tone.request)
                    return;
                tone.sampled = worker.key;
                try {
                    const result = JSON.parse(text);
                    tone.sampledWidth = result.w;
                    tone.columns = result.c;
                } catch (error) {
                    // Unreadable wallpaper (for example a video): white ink, no plates.
                    tone.columns = [];
                }
            }
        }
        onExited: if (key !== tone.request) debounce.restart()
    }

    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        ctx.clearRect(0, 0, width, height);
        for (const key in plates) {
            const plate = plates[key];
            const radius = Math.min(6, plate.h / 2);
            ctx.fillStyle = Qt.rgba(plate.channel, plate.channel, plate.channel, plate.opacity);
            ctx.beginPath();
            ctx.roundedRect(plate.x, plate.y, plate.w, plate.h, radius, radius);
            ctx.fill();
        }
    }
}
