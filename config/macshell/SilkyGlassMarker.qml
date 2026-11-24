// SilkyGlassMarker — tells the silky-dock-glass Hyprland plugin where to paint Liquid Glass on this layer surface.
//
// Drawn as invisible pixels on the bottom row of the window (alpha 1..4 / 255 = one base-4 digit each). The plugin
// decodes them on the GPU from the very buffer Hyprland draws, so glass and content are always in the same frame.
// Layout (digits): magic 2,3,1,1 | count (4) | per rect: x, y, w, h, radius (8 each, half px, window coordinates),
// alpha (4, 0..255), dark (1), kind (1: 0 = Dock, 1 = panel / menu, 2 = Control Center bubbles).
// With a compatible plugin, kind 3 uses the Control Center material in a scrolling viewport. Its y coordinate
// is biased by 32768, and the list ends with the shared viewport top, bottom and feather width (8 digits each).
//
// Either set `rects` directly (the Dock), or set `items` to glass items that are polled every frame while one of
// them is visible (MacBar's popovers): rect = item mapped to the window, alpha = the item's effective opacity.
import QtQuick

Item {
    id: m
    property var rects: []              // [{x, y, w, h, r, a, dark, kind}]
    property var items: []              // glass items (with cornerR, silkyDark, silkyKind) to poll
    property bool enabled: true
    property int poke: 0                // increment when a popover opens to poll immediately without waiting for Timer
    readonly property int maxRects: 24
    width: 0; height: 0                 // the digits are positioned in window coordinates by the parent window

    onPokeChanged: if (enabled && items.length > 0) wake()
    onEnabledChanged: {
        if (!enabled) {
            var win = m.Window.window;
            for (var i = 0; i < items.length; i++) {
                var it = items[i];
                if (it && (!win || it.Window.window === win) && it.silkyOwned) it.silkyOwned = false;
            }
            m.lastKey = "";
            m.rects = [];
            m.anyVisible = false;
            m.activeMotion = false;
            m.idleFrames = 0;
            m.watchedViewport = null;
        } else if (items.length > 0) {
            wake();
        }
    }

    function wake() {
        m.idleFrames = 0;
        if (!m.activeMotion || !m.anyVisible) {
            m.activeMotion = true;
            m.poll();
        }
    }

    function appendNumber(digits, value, width) {
        for (var shift = width - 1; shift >= 0; shift--)
            digits.push((value >> (2 * shift)) & 3);
    }
    function halfPixels(value, bias) {
        return Math.max(0, Math.min(65535, Math.round(value * 2) + bias));
    }
    function digitsFor(list) {
        var d = [2, 3, 1, 1];
        var n = Math.min(list.length, maxRects);
        var clip = null;
        appendNumber(d, n, 4);
        for (var i = 0; i < n; i++) {
            var r = list[i];
            var vals = [r.x, r.y, r.w, r.h, r.r];
            if (r.viewport) clip = r.viewport;
            for (var j = 0; j < vals.length; j++)
                appendNumber(d, halfPixels(vals[j], j === 1 && r.viewport ? 32768 : 0), 8);
            appendNumber(d, Math.max(0, Math.min(255, Math.round(r.a * 255))), 4);
            d.push(r.dark ? 1 : 0);
            d.push(r.kind || 0);
        }
        if (clip)
            for (var i = 0; i < clip.length; i++) appendNumber(d, halfPixels(clip[i], 0), 8);
        return d;
    }

    // effective opacity of an item inside this window (0 when it or an ancestor is hidden)
    function opacityOf(it) {
        var o = 1;
        for (var p = it; p; p = p.parent) {
            if (!p.visible) return 0;
            o *= p.opacity;
        }
        return o;
    }

    // Without a compositor viewport, partly clipped cards stay in Qt.
    function fitsClip(it, vertical) {
        for (var p = it.parent; p; p = p.parent) {
            if (!p.clip) continue;
            var tl = it.mapToItem(p, 0, 0), br = it.mapToItem(p, it.width, it.height);
            var bottomInset = p.silkyClipBottomInset || 0;
            if (tl.x < -0.5 || br.x > p.width + 0.5
                    || (vertical && (tl.y < -0.5 || br.y > p.height - bottomInset + 0.5)))
                return false;
        }
        return true;
    }

    // polled glass: visible items of THIS window, biggest first; items inside another listed rect are left to
    // their own (Qt) tint so they read as lighter platters on the glass
    function poll() {
        var out = [], win = m.Window.window;
        var viewport = null, clip = null;
        for (var i = 0; i < items.length; i++) {
            var it = items[i];
            if (!it || it.Window.window !== win) continue;
            var a = opacityOf(it);
            var view = it.silkyClipViewport || null;
            if (a < 0.01 || it.width < 2 || it.height < 2 || (it.silkyRespectClip && !fitsClip(it, !view))) {
                it.silkyOwned = false;
                continue;
            }
            if (view && view !== viewport) {
                viewport = view;
                var top = view.mapToItem(null, 0, 0).y, bottom = view.mapToItem(null, 0, view.height).y;
                var scale = (bottom - top) / Math.max(1, view.height);
                clip = [Math.max(0, top), Math.min(win ? win.height : bottom, bottom), view.silkyClipBottomInset * scale];
            }
            var tl = it.mapToItem(null, 0, 0), br = it.mapToItem(null, it.width, it.height);
            if (view && (clip[1] <= clip[0] || br.y <= clip[0] || tl.y >= clip[1])) {
                it.silkyOwned = false;
                continue;
            }
            var sc = (br.x - tl.x) / Math.max(1, it.width);
            var x0 = Math.max(0, tl.x), y0 = view ? tl.y : Math.max(0, tl.y);
            var x1 = Math.min(win ? win.width : br.x, br.x), y1 = view ? br.y : Math.min(win ? win.height : br.y, br.y);
            if (x1 - x0 < 2 || y1 - y0 < 2) { it.silkyOwned = false; continue; }
            out.push({ item: it, x: x0, y: y0, w: x1 - x0, h: y1 - y0, r: (it.cornerR || 0) * sc, a: a,
                       dark: !!it.silkyDark, kind: view ? 3 : it.silkyKind || 1, viewport: view ? clip : null });
        }
        out.sort(function (p, q) { return q.w * q.h - p.w * p.h; });
        var kept = [];
        for (var u = 0; u < out.length; u++) {
            var o = out[u], inside = false;
            for (var v = 0; v < kept.length && !inside; v++) {
                var k = kept[v];
                inside = o.x >= k.x - 1 && o.y >= k.y - 1 && o.x + o.w <= k.x + k.w + 1 && o.y + o.h <= k.y + k.h + 1;
            }
            var own = !inside && kept.length < maxRects;
            if (o.item.silkyOwned !== own) o.item.silkyOwned = own;
            if (own) kept.push(o);
        }
        var key = JSON.stringify(kept.map(function (z) {
            return [Math.round(z.x * 2), Math.round(z.y * 2), Math.round(z.w * 2), Math.round(z.h * 2),
                    Math.round(z.r * 2), Math.round(z.a * 255), z.dark, z.kind, z.viewport && z.viewport.map(v => Math.round(v * 2))];
        }));
        m.watchedViewport = viewport;
        if (key !== m.lastKey) {
            m.lastKey = key;
            m.rects = kept;
            m.idleFrames = 0;
            m.activeMotion = kept.length > 0;
        } else if (kept.length === 0) {
            m.idleFrames = 0;
            m.activeMotion = false;
        } else if (m.activeMotion) {
            m.idleFrames++;
            if (m.idleFrames >= 12) m.activeMotion = false;
        }
        m.anyVisible = kept.length > 0;
    }
    property string lastKey: ""
    property bool anyVisible: false
    property bool activeMotion: false
    property int idleFrames: 0
    property Item watchedViewport: null

    Connections {
        target: m.watchedViewport
        ignoreUnknownSignals: true
        function onContentYChanged() { if (m.enabled) m.wake(); }
    }

    // Poll every frame only while glass geometry or opacity is changing; once settled, drop to the fallback timer.
    FrameAnimation { running: m.enabled && m.items.length > 0 && m.anyVisible && m.activeMotion; onTriggered: m.poll() }
    Timer { interval: 120; repeat: true; running: m.enabled && m.items.length > 0 && (!m.anyVisible || !m.activeMotion); onTriggered: m.poll() }

    readonly property var digits: enabled ? digitsFor(rects) : []
    Item {
        parent: m.Window.window ? m.Window.window.contentItem : m
        x: 0; y: (m.Window.window ? m.Window.window.height : 1) - 1
        width: 0; height: 0
        Repeater {
            model: m.digits.length
            delegate: Rectangle {
                required property int index
                x: index; y: 0; width: 1; height: 1
                color: Qt.rgba(0, 0, 0, (1 + (m.digits[index] || 0)) / 255)
            }
        }
    }
}
