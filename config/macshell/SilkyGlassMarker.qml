// SilkyGlassMarker — tells the silky-dock-glass Hyprland plugin where to paint Liquid Glass on this layer surface.
//
// Drawn as invisible pixels on the bottom row of the window (alpha 1..4 / 255 = one base-4 digit each). The plugin
// decodes them on the GPU from the very buffer Hyprland draws, so glass and content are always in the same frame.
// Layout (digits): magic 2,3,1,1 | count (4) | per rect: x, y, w, h, radius (8 each, half px, window coordinates),
// alpha (4, 0..255), dark (1), kind (1: 0 = Dock, 1 = panel / menu).
//
// Either set `rects` directly (the Dock), or set `items` to glass items that are polled every frame while one of
// them is visible (MacBar's popovers): rect = item mapped to the window, alpha = the item's effective opacity.
import QtQuick

Item {
    id: m
    property var rects: []              // [{x, y, w, h, r, a, dark, kind}]
    property var items: []              // glass items (with cornerR, silkyDark, silkyKind) to poll
    property bool enabled: true
    readonly property int maxRects: 16
    width: 0; height: 0                 // the digits are positioned in window coordinates by the parent window

    function digitsFor(list) {
        var d = [2, 3, 1, 1];
        var n = Math.min(list.length, maxRects);
        for (var k = 3; k >= 0; k--) d.push(Math.floor(n / Math.pow(4, k)) % 4);
        for (var i = 0; i < n; i++) {
            var r = list[i];
            var vals = [r.x, r.y, r.w, r.h, r.r];
            for (var j = 0; j < vals.length; j++) {
                var v = Math.max(0, Math.min(65535, Math.round(vals[j] * 2)));
                for (var k2 = 7; k2 >= 0; k2--) d.push(Math.floor(v / Math.pow(4, k2)) % 4);
            }
            var a = Math.max(0, Math.min(255, Math.round(r.a * 255)));
            for (var k3 = 3; k3 >= 0; k3--) d.push(Math.floor(a / Math.pow(4, k3)) % 4);
            d.push(r.dark ? 1 : 0);
            d.push(r.kind || 0);
        }
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

    // polled glass: visible items of THIS window, biggest first; items inside another listed rect are left to
    // their own (Qt) tint so they read as lighter platters on the glass
    function poll() {
        var out = [], win = m.Window.window;
        for (var i = 0; i < items.length; i++) {
            var it = items[i];
            if (!it || it.Window.window !== win) continue;
            var a = opacityOf(it);
            if (a < 0.01 || it.width < 2 || it.height < 2) { it.silkyOwned = false; continue; }
            var tl = it.mapToItem(null, 0, 0), br = it.mapToItem(null, it.width, it.height);
            var sc = (br.x - tl.x) / Math.max(1, it.width);
            out.push({ item: it, x: tl.x, y: tl.y, w: br.x - tl.x, h: br.y - tl.y, r: (it.cornerR || 0) * sc, a: a,
                       dark: !!it.silkyDark, kind: it.silkyKind || 1 });
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
        var key = JSON.stringify(kept.map(function (z) { return [Math.round(z.x * 2), Math.round(z.y * 2), Math.round(z.w * 2), Math.round(z.h * 2), Math.round(z.r * 2), Math.round(z.a * 255), z.dark, z.kind]; }));
        if (key !== m.lastKey) { m.lastKey = key; m.rects = kept; }
        m.anyVisible = kept.length > 0;
    }
    property string lastKey: ""
    property bool anyVisible: false

    // poll every frame while glass is showing, otherwise a few times a second (to notice a popover opening)
    FrameAnimation { running: m.enabled && m.items.length > 0 && m.anyVisible; onTriggered: m.poll() }
    Timer { interval: 120; repeat: true; running: m.enabled && m.items.length > 0 && !m.anyVisible; onTriggered: m.poll() }

    readonly property var digits: enabled ? digitsFor(rects) : []
    Repeater {
        model: m.digits.length
        delegate: Rectangle {
            required property int index
            parent: m.Window.window ? m.Window.window.contentItem : m
            x: index; y: (m.Window.window ? m.Window.window.height : 1) - 1; width: 1; height: 1
            color: Qt.rgba(0, 0, 0, (1 + (m.digits[index] || 0)) / 255)
        }
    }
}
