import QtQuick
import QtQuick.Effects
import "I18n.js" as I18n
import "Fonts.js" as Fonts

// Dual-card macOS System Settings gesture showcase:
//   Left card  — Trackpad or Touchscreen hardware silhouette with live finger contact dots, ripples and hold rings.
//   Right card — Miniature Silky Omarchy / macOS desktop driven by the exact same phase (1:1 finger-to-screen sync).
Item {
    id: stage
    required property var t
    property string device: "trackpad"          // "trackpad" | "touchscreen"
    property string gesture: "tp_mission_control"
    property string caption: ""
    property bool naturalScroll: true
    property real scrollSpeed: 0.7
    property bool secondaryCorner: false
    property int workspaceFingers: 4
    property bool reduceMotion: false
    property bool running: true

    width: parent ? parent.width : 520
    height: 176

    property real elapsed: 0
    readonly property real cycleDuration: {
        if (gesture === "tp_workspace_swipe" || gesture === "ts_edge_swipe" || gesture === "ts_three_finger_swipe")
            return 3.8;
        if (gesture === "ts_hold_move" || gesture === "ts_kinetic_scroll" || gesture === "tp_drag3fg" || gesture === "ts_window_move")
            return 3.5;
        return 3.0;
    }
    readonly property real phase: reduceMotion ? 0.42 : ((elapsed % cycleDuration) / cycleDuration)

    function replay() {
        elapsed = 0;
        sceneFade.restart();
    }

    onGestureChanged: replay()
    onDeviceChanged: replay()

    NumberAnimation {
        id: sceneFade
        target: stageScene
        property: "opacity"
        from: 0.55
        to: 1.0
        duration: 150
        easing.type: Easing.OutCubic
    }

    FrameAnimation {
        running: stage.running && stage.visible && !stage.reduceMotion
        onTriggered: {
            var dt = frameTime > 0 ? Math.min(0.05, frameTime) : 0.016;
            stage.elapsed += dt;
        }
    }

    // ── Easing & curve helpers ──
    function clamp01(v) { return v < 0 ? 0 : (v > 1 ? 1 : v); }
    function seg(u, a, b) { return b > a ? clamp01((u - a) / (b - a)) : 0; }
    function smooth(v) { var x = clamp01(v); return x * x * (3 - 2 * x); }
    function easeOut(v) { var x = 1 - clamp01(v); return 1 - x * x * x; }
    function easeInOut(v) {
        var x = clamp01(v);
        return x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2;
    }
    function lerp(a, b, t) { return a + (b - a) * t; }
    function archY(idx, count) {
        if (count <= 1) return 0;
        var mid = (count - 1) * 0.5;
        var d = (idx - mid) / Math.max(1, mid);
        return d * d * 0.065 - 0.02;
    }

    // ── Unified 1:1 state computed once per frame from `phase` ──
    readonly property var anim: {
        var u = phase;
        var g = gesture;
        var pts = [];
        var palm = null;
        var edgeSide = 0;   // -1 left edge highlight, 1 right edge highlight
        var st = {
            mode: g,
            p: 0,
            p2: 0,
            wx: 0,
            wy: 0,
            ww: 0,
            wh: 0,
            snap: 0,
            topGuard: 0,
            lifted: 0,
            menu: 0,
            clickPulse: 0,
            toggleOn: false,
            scrollY: 0,
            scrollBar: 0,
            zoom: 1.0,
            pageShift: 0,
            wsShift: 0,
            wsIndex: 0,
            cursorX: 0.5,
            cursorY: 0.5,
            showCursor: false,
            sliderVal: 0.32,
            typingChars: 0,
            brakeFlash: 0
        };

        var i, n, fade, t1, t2, x0, y0, spread, ang;

        if (g === "tp_tap") {
            // Cursor glides to switch, single finger taps twice to toggle on & off
            var tap1 = u >= 0.24 && u < 0.42 ? Math.sin(seg(u, 0.24, 0.42) * Math.PI) : 0;
            var tap2 = u >= 0.68 && u < 0.86 ? Math.sin(seg(u, 0.68, 0.86) * Math.PI) : 0;
            var moveIn = easeOut(seg(u, 0.04, 0.22));
            st.showCursor = true;
            st.cursorX = lerp(0.34, 0.63, moveIn);
            st.cursorY = lerp(0.68, 0.43, moveIn);
            st.clickPulse = Math.max(tap1, tap2);
            st.toggleOn = u >= 0.31 && u < 0.75;
            fade = (u >= 0.14 && u < 0.90) ? Math.min(seg(u, 0.14, 0.22), 1 - seg(u, 0.84, 0.90)) : 0;
            pts.push({
                x: lerp(-0.12, 0.02, moveIn),
                y: lerp(0.14, 0.0, moveIn),
                alpha: fade,
                scale: 1 - 0.14 * st.clickPulse,
                ring: st.clickPulse,
                holdArc: 0
            });
        } else if (g === "tp_secondary") {
            var press = u >= 0.20 && u < 0.40 ? Math.sin(seg(u, 0.20, 0.40) * Math.PI) : 0;
            st.showCursor = true;
            st.cursorX = lerp(0.46, 0.52, smooth(seg(u, 0.42, 0.62)));
            st.cursorY = lerp(0.42, 0.53, smooth(seg(u, 0.42, 0.62)));
            st.menu = u < 0.26 ? 0 : (u < 0.84 ? easeOut(seg(u, 0.26, 0.38)) : 1 - smooth(seg(u, 0.84, 0.95)));
            st.p2 = smooth(seg(u, 0.46, 0.60));
            fade = (u >= 0.12 && u < 0.46) ? Math.min(seg(u, 0.12, 0.19), 1 - seg(u, 0.39, 0.46)) : 0;
            if (secondaryCorner) {
                pts.push({ x: 0.30, y: 0.26, alpha: fade, scale: 1 - 0.14 * press, ring: press, holdArc: 0 });
            } else {
                pts.push({ x: -0.09, y: 0.02, alpha: fade, scale: 1 - 0.14 * press, ring: press, holdArc: 0 });
                pts.push({ x: 0.09, y: 0.00, alpha: fade, scale: 1 - 0.14 * press, ring: press, holdArc: 0 });
            }
        } else if (g === "tp_drag3fg") {
            var dragT = easeInOut(seg(u, 0.14, 0.58));
            var settleSnap = easeOut(seg(u, 0.62, 0.74));
            var resetFade = 1 - smooth(seg(u, 0.88, 0.98));
            fade = (u >= 0.06 && u < 0.66) ? Math.min(seg(u, 0.06, 0.14), 1 - seg(u, 0.60, 0.66)) : 0;
            st.wx = lerp(0.10, 0.44, dragT);
            st.wy = lerp(0.22, 0.16, dragT);
            st.ww = lerp(0.44, 0.48, settleSnap);
            st.wh = lerp(0.50, 0.68, settleSnap);
            if (settleSnap > 0) {
                st.wx = lerp(st.wx, 0.50, settleSnap);
                st.wy = lerp(st.wy, 0.10, settleSnap);
            }
            st.snap = (u >= 0.44 && u < 0.64) ? Math.min(smooth(seg(u, 0.44, 0.52)), 1 - smooth(seg(u, 0.60, 0.64))) : 0;
            st.p = resetFade;
            st.showCursor = u < 0.88;
            st.cursorX = st.wx + st.ww * 0.45;
            st.cursorY = st.wy + 0.06;
            var fx = lerp(-0.20, 0.20, dragT);
            var fy = lerp(0.08, -0.04, dragT);
            for (i = 0; i < 3; i++) {
                pts.push({ x: fx + (i - 1) * 0.15, y: fy + archY(i, 3), alpha: fade, scale: 1.0, ring: 0, holdArc: 0 });
            }
        } else if (g === "tp_tap_drag") {
            var tapA = u >= 0.10 && u < 0.20 ? Math.sin(seg(u, 0.10, 0.20) * Math.PI) : 0;
            var tapB = u >= 0.24 && u < 0.32 ? seg(u, 0.24, 0.32) : (u >= 0.32 && u < 0.76 ? 1 : 0);
            var slideT = easeInOut(seg(u, 0.32, 0.72));
            fade = (u >= 0.06 && u < 0.84) ? Math.min(seg(u, 0.06, 0.12), 1 - seg(u, 0.76, 0.84)) : 0;
            st.sliderVal = lerp(0.22, 0.82, slideT);
            st.showCursor = true;
            st.cursorX = lerp(0.32, 0.72, slideT);
            st.cursorY = 0.50;
            pts.push({
                x: lerp(-0.20, 0.22, slideT),
                y: 0.02,
                alpha: fade,
                scale: 1 - 0.12 * Math.max(tapA, tapB > 0 && u < 0.34 ? 1 : 0),
                ring: Math.max(tapA, u >= 0.24 && u < 0.36 ? Math.sin(seg(u, 0.24, 0.36) * Math.PI) : 0),
                holdArc: 0
            });
        } else if (g === "tp_dwt") {
            st.typingChars = Math.floor(clamp01(seg(u, 0.05, 0.85)) * 18);
            st.showCursor = true;
            st.cursorX = 0.74;
            st.cursorY = 0.62;
            var palmAlpha = (u >= 0.24 && u < 0.80) ? Math.min(smooth(seg(u, 0.24, 0.34)), 1 - smooth(seg(u, 0.70, 0.80))) : 0;
            palm = {
                x: -0.27 + 0.02 * Math.sin(u * Math.PI * 6),
                y: 0.24,
                alpha: palmAlpha
            };
        } else if (g === "tp_natural_scroll" || g === "tp_scroll_speed") {
            var upLeg = easeInOut(seg(u, 0.12, 0.44));
            var downLeg = easeInOut(seg(u, 0.56, 0.88));
            var fingerTravel = upLeg - downLeg; // 0 -> +1 (fingers move up) -> 0 (fingers move down)
            var dirSign = naturalScroll ? 1 : -1;
            var factor = Math.max(0.35, Math.min(1.65, scrollSpeed / 0.7));
            st.scrollY = fingerTravel * dirSign * 0.52 * factor;
            st.scrollBar = (u >= 0.10 && u < 0.92) ? Math.min(seg(u, 0.10, 0.18), 1 - seg(u, 0.86, 0.92)) : 0;
            fade = st.scrollBar;
            var fyScroll = lerp(0.18, -0.18, fingerTravel);
            pts.push({ x: -0.09, y: fyScroll, alpha: fade, scale: 1.0, ring: 0, holdArc: 0 });
            pts.push({ x: 0.09, y: fyScroll - 0.015, alpha: fade, scale: 1.0, ring: 0, holdArc: 0 });
        } else if (g === "tp_zoom" || g === "ts_zoom") {
            var zOpen = easeInOut(seg(u, 0.12, 0.46));
            var zClose = easeInOut(seg(u, 0.58, 0.90));
            var zAmt = zOpen - zClose;
            st.zoom = 1.0 + 0.56 * zAmt;
            fade = (u >= 0.06 && u < 0.94) ? Math.min(seg(u, 0.06, 0.13), 1 - seg(u, 0.88, 0.94)) : 0;
            var dist = lerp(0.09, 0.25, zAmt);
            pts.push({ x: -dist, y: dist * 0.72, alpha: fade, scale: 1.0, ring: 0, holdArc: 0 });
            pts.push({ x: dist, y: -dist * 0.72, alpha: fade, scale: 1.0, ring: 0, holdArc: 0 });
        } else if (g === "tp_swipe_pages") {
            var pgLeft = easeInOut(seg(u, 0.12, 0.44));
            var pgRight = easeInOut(seg(u, 0.56, 0.88));
            st.pageShift = pgLeft - pgRight;
            fade = (u >= 0.06 && u < 0.94) ? Math.min(seg(u, 0.06, 0.13), 1 - seg(u, 0.88, 0.94)) : 0;
            var px = lerp(0.18, -0.18, st.pageShift);
            pts.push({ x: px - 0.07, y: 0.0, alpha: fade, scale: 1.0, ring: 0, holdArc: 0 });
            pts.push({ x: px + 0.07, y: -0.015, alpha: fade, scale: 1.0, ring: 0, holdArc: 0 });
        } else if (g === "tp_workspace_swipe" || g === "ts_edge_swipe" || g === "ts_three_finger_swipe") {
            // Phase 1 (0.08..0.42): full 1:1 workspace switch from Space 1 -> Space 2
            // Phase 2 (0.50..0.78): swipe further at end-of-list -> Silky rubber-band resistance & spring back!
            // Phase 3 (0.82..0.96): return smoothly to Space 1 for seamless loop
            var sw1 = easeInOut(seg(u, 0.08, 0.38));
            var overPull = seg(u, 0.48, 0.64);
            var overRelease = easeOut(seg(u, 0.64, 0.78));
            var rubber = u < 0.48 ? 0 : (u < 0.64 ? (1 - Math.exp(-overPull * 2.4)) * 0.22 : (1 - Math.exp(-2.4)) * 0.22 * (1 - overRelease));
            var backHome = easeInOut(seg(u, 0.82, 0.97));
            st.wsShift = sw1 + rubber - backHome;
            st.wsIndex = (sw1 > 0.5 && backHome < 0.5) ? 1 : 0;

            var f1Active = u >= 0.04 && u < 0.41;
            var f2Active = u >= 0.45 && u < 0.66;
            fade = f1Active ? Math.min(seg(u, 0.04, 0.10), 1 - seg(u, 0.36, 0.41))
                 : (f2Active ? Math.min(seg(u, 0.45, 0.50), 1 - seg(u, 0.62, 0.66)) : 0);
            var fingerSlide = f1Active ? seg(u, 0.08, 0.38) : (f2Active ? overPull * 0.85 : 0);

            if (g === "ts_edge_swipe") {
                edgeSide = 1; // swipe inward from right edge (or left edge)
                pts.push({
                    x: lerp(0.46, -0.14, easeOut(fingerSlide)),
                    y: 0.02,
                    alpha: fade,
                    scale: 1.0,
                    ring: 0,
                    holdArc: 0
                });
            } else {
                n = g === "ts_three_finger_swipe" ? 3 : (workspaceFingers === 3 ? 3 : 4);
                var span = n === 3 ? 0.24 : 0.32;
                var cx = lerp(0.18, -0.20, easeOut(fingerSlide));
                for (i = 0; i < n; i++) {
                    pts.push({
                        x: cx + (i - (n - 1) * 0.5) * (span / Math.max(1, n - 1)),
                        y: archY(i, n) + 0.02,
                        alpha: fade,
                        scale: 1.0,
                        ring: 0,
                        holdArc: 0
                    });
                }
            }
        } else if (g === "tp_mission_control" || g === "ts_overview_up") {
            var upOpen = smooth(seg(u, 0.10, 0.40));
            var downClose = smooth(seg(u, 0.64, 0.90));
            st.p = upOpen - downClose;
            fade = (u >= 0.05 && u < 0.94) ? Math.min(seg(u, 0.05, 0.12), 1 - seg(u, 0.88, 0.94)) : 0;
            var mcY = lerp(0.20, -0.18, st.p);
            for (i = 0; i < 4; i++) {
                pts.push({
                    x: (i - 1.5) * 0.155,
                    y: mcY + archY(i, 4),
                    alpha: fade,
                    scale: 1.0,
                    ring: 0,
                    holdArc: 0
                });
            }
        } else if (g === "tp_app_expose" || g === "ts_overview_down") {
            var expOpen = smooth(seg(u, 0.10, 0.40));
            var expClose = smooth(seg(u, 0.64, 0.90));
            st.p = expOpen - expClose;
            fade = (u >= 0.05 && u < 0.94) ? Math.min(seg(u, 0.05, 0.12), 1 - seg(u, 0.88, 0.94)) : 0;
            var aeY = lerp(-0.20, 0.18, st.p);
            for (i = 0; i < 4; i++) {
                pts.push({
                    x: (i - 1.5) * 0.155,
                    y: aeY + archY(i, 4),
                    alpha: fade,
                    scale: 1.0,
                    ring: 0,
                    holdArc: 0
                });
            }
        } else if (g === "tp_launchpad" || g === "ts_pinch_launchpad") {
            var pinchIn = easeInOut(seg(u, 0.10, 0.42));
            var pinchOut = easeInOut(seg(u, 0.62, 0.90));
            st.p = pinchIn - pinchOut;
            fade = (u >= 0.05 && u < 0.94) ? Math.min(seg(u, 0.05, 0.12), 1 - seg(u, 0.88, 0.94)) : 0;
            var rSpread = lerp(1.0, 0.36, st.p);
            var useFive = (g === "ts_pinch_launchpad");
            // Thumb at bottom-left/center, 3 or 4 fingers arranged on an upper arc pinching toward center
            pts.push({ x: -0.10 * rSpread, y: 0.28 * rSpread, alpha: fade, scale: 1.0, ring: 0, holdArc: 0 });
            var topCount = useFive ? 4 : 3;
            for (i = 0; i < topCount; i++) {
                ang = lerp(-2.35, -0.75, topCount > 1 ? i / (topCount - 1) : 0.5);
                pts.push({
                    x: Math.cos(ang) * 0.34 * rSpread + 0.03 * rSpread,
                    y: Math.sin(ang) * 0.29 * rSpread + 0.02 * rSpread,
                    alpha: fade,
                    scale: 1.0,
                    ring: 0,
                    holdArc: 0
                });
            }
        } else if (g === "ts_window_move") {
            // Finger grabs titlebar -> pushes up against menu bar (clamped cleanly!) -> drags right to snap preview -> lands
            var upTry = Math.sin(seg(u, 0.12, 0.34) * Math.PI);
            var toRight = easeInOut(seg(u, 0.34, 0.68));
            var snapLand = easeOut(seg(u, 0.70, 0.80));
            st.wx = lerp(0.14, 0.44, toRight);
            st.wy = lerp(0.22, 0.085, upTry); // stops right below menu bar (0.085)!
            st.ww = lerp(0.44, 0.48, snapLand);
            st.wh = lerp(0.50, 0.68, snapLand);
            if (snapLand > 0) {
                st.wx = lerp(st.wx, 0.50, snapLand);
                st.wy = lerp(st.wy, 0.10, snapLand);
            }
            st.topGuard = upTry;
            st.snap = (u >= 0.54 && u < 0.72) ? Math.min(smooth(seg(u, 0.54, 0.62)), 1 - smooth(seg(u, 0.68, 0.72))) : 0;
            st.p = 1 - smooth(seg(u, 0.90, 0.99));
            fade = (u >= 0.06 && u < 0.74) ? Math.min(seg(u, 0.06, 0.12), 1 - seg(u, 0.69, 0.74)) : 0;
            pts.push({
                x: (st.wx + st.ww * 0.5) - 0.5,
                y: (st.wy + 0.05) - 0.5,
                alpha: fade,
                scale: 1.0,
                ring: u >= 0.08 && u < 0.18 ? seg(u, 0.08, 0.18) : 0,
                holdArc: 0
            });
        } else if (g === "ts_window_resize") {
            var grow = easeInOut(seg(u, 0.14, 0.52));
            var shrink = easeInOut(seg(u, 0.62, 0.92));
            var amt = grow - shrink;
            st.wx = 0.12;
            st.wy = 0.16;
            st.ww = lerp(0.38, 0.70, amt);
            st.wh = lerp(0.38, 0.62, amt);
            fade = (u >= 0.06 && u < 0.95) ? Math.min(seg(u, 0.06, 0.13), 1 - seg(u, 0.89, 0.95)) : 0;
            pts.push({
                x: (st.wx + st.ww) - 0.5,
                y: (st.wy + st.wh) - 0.5,
                alpha: fade,
                scale: 1.0,
                ring: 0,
                holdArc: 0
            });
        } else if (g === "ts_hold_move") {
            // Finger holds still in window body for 0.4 s (ring fills 0..1), window lifts, then drags across screen
            var holdProg = clamp01(seg(u, 0.08, 0.34));
            var picked = u >= 0.34 && u < 0.84;
            var moveProg = easeInOut(seg(u, 0.38, 0.78));
            var backProg = easeInOut(seg(u, 0.86, 0.98));
            st.wx = lerp(lerp(0.14, 0.42, moveProg), 0.14, backProg);
            st.wy = lerp(lerp(0.24, 0.16, moveProg), 0.24, backProg);
            st.ww = 0.44;
            st.wh = 0.48;
            st.lifted = picked ? Math.min(easeOut(seg(u, 0.34, 0.41)), 1 - smooth(seg(u, 0.78, 0.84))) : 0;
            fade = (u >= 0.05 && u < 0.84) ? Math.min(seg(u, 0.05, 0.10), 1 - seg(u, 0.79, 0.84)) : 0;
            pts.push({
                x: (st.wx + st.ww * 0.5) - 0.5,
                y: (st.wy + st.wh * 0.55) - 0.5,
                alpha: fade,
                scale: 1.0 + 0.08 * st.lifted,
                ring: u >= 0.33 && u < 0.44 ? seg(u, 0.33, 0.44) : 0,
                holdArc: u < 0.36 ? holdProg : 0
            });
        } else if (g === "ts_context_menu") {
            var holdM = clamp01(seg(u, 0.10, 0.36));
            st.menu = u < 0.36 ? 0 : (u < 0.86 ? easeOut(seg(u, 0.36, 0.46)) : 1 - smooth(seg(u, 0.86, 0.96)));
            st.p2 = smooth(seg(u, 0.52, 0.66));
            fade = (u >= 0.06 && u < 0.46) ? Math.min(seg(u, 0.06, 0.12), 1 - seg(u, 0.40, 0.46)) : 0;
            pts.push({
                x: -0.08,
                y: -0.04,
                alpha: fade,
                scale: 1.0,
                ring: u >= 0.35 && u < 0.46 ? seg(u, 0.35, 0.46) : 0,
                holdArc: u < 0.38 ? holdM : 0
            });
        } else if (g === "ts_kinetic_scroll") {
            // 0.08..0.30: 1:1 finger flick upward -> 0.30..0.64: exponential kinetic glide -> 0.64: finger taps to brake!
            var flickT = seg(u, 0.08, 0.30);
            var glideT = seg(u, 0.30, 0.64);
            var resetS = easeInOut(seg(u, 0.82, 0.98));
            var pos = u < 0.08 ? 0
                    : (u < 0.30 ? flickT * 0.38
                    : (u < 0.64 ? 0.38 + (1 - Math.exp(-glideT * 2.8)) * 0.42
                    : (0.38 + (1 - Math.exp(-2.8)) * 0.42) * (1 - resetS)));
            st.scrollY = pos;
            st.scrollBar = (u >= 0.08 && u < 0.80) ? 1 : 0;
            st.brakeFlash = (u >= 0.63 && u < 0.76) ? Math.sin(seg(u, 0.63, 0.76) * Math.PI) : 0;

            if (u >= 0.06 && u < 0.32) {
                pts.push({
                    x: 0.02,
                    y: lerp(0.22, -0.14, flickT),
                    alpha: Math.min(seg(u, 0.06, 0.10), 1 - seg(u, 0.28, 0.32)),
                    scale: 1.0,
                    ring: 0,
                    holdArc: 0
                });
            } else if (u >= 0.62 && u < 0.76) {
                pts.push({
                    x: 0.02,
                    y: 0.04,
                    alpha: Math.min(seg(u, 0.62, 0.65), 1 - seg(u, 0.72, 0.76)),
                    scale: 0.90,
                    ring: seg(u, 0.63, 0.75),
                    holdArc: 0
                });
            }
        }

        return { fingers: pts, palm: palm, edgeSide: edgeSide, s: st };
    }

    Row {
        id: stageScene
        anchors.fill: parent
        spacing: 12

        // ═══════════════════════════════════════════════════════════════
        //  LEFT CARD: Trackpad / Touchscreen Hardware & Live Finger Dots
        // ═══════════════════════════════════════════════════════════════
        Rectangle {
            id: padCard
            width: Math.round((parent.width - 12) * 0.455)
            height: parent.height
            radius: 14
            color: stage.t.dark ? "#262629" : "#2F3137"
            border.width: 1
            border.color: stage.t.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.16)

            // Hardware outline (Trackpad vs Touchscreen)
            Rectangle {
                id: hwBox
                anchors.centerIn: parent
                anchors.verticalCenterOffset: stage.caption !== "" ? -6 : 0
                readonly property bool isScreen: stage.device === "touchscreen"
                width: isScreen ? Math.min(parent.width - 36, 152) : Math.min(parent.width - 52, 128)
                height: Math.round(width * (isScreen ? 0.64 : 0.74))
                radius: isScreen ? 9 : 11
                color: Qt.rgba(1, 1, 1, 0.025)
                border.width: 1.8
                border.color: Qt.rgba(1, 1, 1, 0.88)
                clip: true

                // Touchscreen top menu bar & dock hint inside the hardware silhouette
                Rectangle {
                    visible: hwBox.isScreen
                    width: parent.width
                    height: 6
                    color: Qt.rgba(1, 1, 1, 0.11)
                }
                Rectangle {
                    visible: hwBox.isScreen
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 3
                    width: 40
                    height: 3
                    radius: 1.5
                    color: Qt.rgba(1, 1, 1, 0.16)
                }

                // Touchscreen edge-swipe active zone highlight (20 px band)
                Rectangle {
                    visible: hwBox.isScreen && stage.anim.edgeSide !== 0
                    anchors.right: parent.right
                    width: 9
                    height: parent.height
                    color: Qt.rgba(0.18, 0.53, 1.0, 0.24)
                }

                // Touchscreen floating-window wireframe so user sees exact touch target (titlebar / corner / center)
                Rectangle {
                    visible: hwBox.isScreen && (stage.gesture === "ts_window_move" || stage.gesture === "ts_window_resize" || stage.gesture === "ts_hold_move")
                    x: stage.anim.s.wx * parent.width
                    y: stage.anim.s.wy * parent.height
                    width: stage.anim.s.ww * parent.width
                    height: stage.anim.s.wh * parent.height
                    radius: 4
                    color: Qt.rgba(1, 1, 1, 0.06)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.34)
                    Rectangle {
                        width: parent.width
                        height: 6
                        radius: 3
                        color: Qt.rgba(1, 1, 1, 0.14)
                    }
                }

                // Trackpad bottom-right secondary click zone hint
                Rectangle {
                    visible: !hwBox.isScreen && stage.gesture === "tp_secondary" && stage.secondaryCorner
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 4
                    width: 30
                    height: 22
                    radius: 5
                    color: Qt.rgba(0.18, 0.53, 1.0, 0.14)
                    border.width: 1
                    border.color: Qt.rgba(0.28, 0.62, 1.0, 0.38)
                }

                // Palm contact silhouette for "Ignore trackpad while typing"
                Rectangle {
                    visible: stage.anim.palm !== null && stage.anim.palm.alpha > 0.01
                    opacity: stage.anim.palm ? stage.anim.palm.alpha : 0
                    width: 34
                    height: 44
                    radius: 17
                    rotation: -18
                    x: hwBox.width * (0.5 + (stage.anim.palm ? stage.anim.palm.x : 0)) - width / 2
                    y: hwBox.height * (0.5 + (stage.anim.palm ? stage.anim.palm.y : 0)) - height / 2
                    color: Qt.rgba(1, 0.62, 0.24, 0.24)
                    border.width: 1.2
                    border.color: Qt.rgba(1, 0.68, 0.30, 0.65)
                }

                // Live finger contact dots (up to 5 simultaneous fingers)
                Repeater {
                    model: 5
                    delegate: Item {
                        id: fDot
                        required property int index
                        readonly property var fd: index < stage.anim.fingers.length ? stage.anim.fingers[index] : null
                        visible: fd !== null && fd.alpha > 0.01
                        opacity: fd ? fd.alpha : 0
                        x: hwBox.width * (0.5 + (fd ? fd.x : 0))
                        y: hwBox.height * (0.5 + (fd ? fd.y : 0))
                        width: 1
                        height: 1

                        // Tap / brake expanding ripple
                        Rectangle {
                            visible: fDot.fd !== null && fDot.fd.ring > 0.01
                            anchors.centerIn: parent
                            readonly property real rProg: fDot.fd ? fDot.fd.ring : 0
                            width: 12 + 18 * rProg
                            height: width
                            radius: width / 2
                            color: "transparent"
                            border.width: 1.5
                            border.color: Qt.rgba(0.35, 0.68, 1.0, (1 - rProg) * 0.85)
                        }

                        // 0.4 s long-press radial progress arc
                        Canvas {
                            id: arcCanvas
                            readonly property real arcValue: fDot.fd ? fDot.fd.holdArc : 0
                            visible: arcValue > 0.01
                            anchors.centerIn: parent
                            width: 26
                            height: 26
                            onArcValueChanged: requestPaint()
                            onPaint: {
                                var ctx = getContext("2d");
                                ctx.reset();
                                if (arcValue <= 0.01) return;
                                ctx.strokeStyle = "rgba(92, 172, 255, 0.92)";
                                ctx.lineWidth = 2.0;
                                ctx.lineCap = "round";
                                ctx.beginPath();
                                ctx.arc(13, 13, 10, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * arcValue, false);
                                ctx.stroke();
                            }
                        }

                        // Soft outer finger glow
                        Rectangle {
                            anchors.centerIn: parent
                            scale: fDot.fd ? fDot.fd.scale : 1
                            width: hwBox.isScreen ? 17 : 18
                            height: width
                            radius: width / 2
                            color: Qt.rgba(0.18, 0.52, 0.98, 0.28)
                        }

                        // Solid Apple-blue fingertip circle
                        Rectangle {
                            anchors.centerIn: parent
                            scale: fDot.fd ? fDot.fd.scale : 1
                            width: hwBox.isScreen ? 10.5 : 11.5
                            height: width
                            radius: width / 2
                            color: "#2E7CF6"
                            border.width: 1
                            border.color: Qt.rgba(0.62, 0.82, 1.0, 0.55)
                        }
                    }
                }
            }

            // Subtle gesture label pill at the bottom of the hardware card
            Text {
                visible: stage.caption !== ""
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 8
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - 20
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: stage.caption
                color: Qt.rgba(1, 1, 1, 0.62)
                font.family: Fonts.forWeight(Font.Medium, stage.t.fam)
                font.pixelSize: 11
            }
        }

        // ═══════════════════════════════════════════════════════════════
        //  RIGHT CARD: Miniature Silky Omarchy / macOS Live Desktop Stage
        // ═══════════════════════════════════════════════════════════════
        Item {
            id: screenWrap
            width: parent.width - padCard.width - 12
            height: parent.height

            Item {
                id: screenMask
                anchors.fill: parent
                visible: false
                layer.enabled: true
                layer.smooth: true
                Rectangle { anchors.fill: parent; radius: 14; color: "black" }
            }

            Item {
                id: desktop
                anchors.fill: parent
                layer.enabled: true
                layer.smooth: true
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: screenMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1.0
                }

                readonly property var s: stage.anim.s
                readonly property string g: stage.gesture

                // Tahoe / macOS desktop wallpaper backdrop (adapts to system Light / Dark mode)
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: stage.t.dark ? "#2A4B9C" : "#4A80E8" }
                        GradientStop { position: 0.55; color: stage.t.dark ? "#335AB8" : "#6295F2" }
                        GradientStop { position: 1.0; color: stage.t.dark ? "#3F69C9" : "#7FADFA" }
                    }
                }

                // ── SCENE A: Mission Control & App Exposé (5 windows linear interpolation + top workspace strip) ──
                Item {
                    id: overviewScene
                    anchors.fill: parent
                    visible: desktop.g === "tp_mission_control" || desktop.g === "ts_overview_up"
                          || desktop.g === "tp_app_expose" || desktop.g === "ts_overview_down"
                    readonly property bool isAppMode: desktop.g === "tp_app_expose" || desktop.g === "ts_overview_down"
                    readonly property real p: desktop.s.p

                    // Top workspace strip in Mission Control
                    Item {
                        visible: !overviewScene.isAppMode
                        y: stage.lerp(-22, 16, overviewScene.p)
                        opacity: overviewScene.p
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 118
                        height: 18
                        Row {
                            anchors.centerIn: parent
                            spacing: 6
                            Repeater {
                                model: 3
                                delegate: Rectangle {
                                    required property int index
                                    width: 34
                                    height: 18
                                    radius: 3.5
                                    color: Qt.rgba(1, 1, 1, index === 0 ? 0.28 : 0.16)
                                    border.width: index === 0 ? 1.4 : 0.8
                                    border.color: index === 0 ? "#66B2FF" : Qt.rgba(1, 1, 1, 0.28)
                                }
                            }
                        }
                    }

                    // 5 desktop windows interpolating between stacked desktop positions and overview grid!
                    Repeater {
                        model: [
                            // [deskX, deskY, deskW, deskH, mcX, mcY, mcW, mcH, expX, expY, expW, expH, sameApp, tint]
                            [0.14, 0.18, 0.54, 0.56,  0.07, 0.24, 0.32, 0.30,  0.06, 0.30, 0.27, 0.36, true,  0.34],
                            [0.28, 0.24, 0.50, 0.52,  0.43, 0.23, 0.21, 0.24,  0.365,0.27, 0.29, 0.40, true,  0.42],
                            [0.20, 0.14, 0.46, 0.50,  0.69, 0.25, 0.24, 0.36,  0.68, 0.30, 0.26, 0.36, true,  0.36],
                            [0.10, 0.28, 0.42, 0.46,  0.12, 0.58, 0.21, 0.24,  0.10, 0.28, 0.42, 0.46, false, 0.26],
                            [0.36, 0.20, 0.46, 0.50,  0.41, 0.54, 0.25, 0.28,  0.36, 0.20, 0.46, 0.50, false, 0.30]
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            readonly property real p: overviewScene.p
                            readonly property bool sameApp: modelData[12]
                            readonly property real tx: overviewScene.isAppMode ? modelData[8]  : modelData[4]
                            readonly property real ty: overviewScene.isAppMode ? modelData[9]  : modelData[5]
                            readonly property real tw: overviewScene.isAppMode ? modelData[10] : modelData[6]
                            readonly property real th: overviewScene.isAppMode ? modelData[11] : modelData[7]
                            x: stage.lerp(modelData[0], tx, p) * overviewScene.width
                            y: stage.lerp(modelData[1], ty, p) * overviewScene.height
                            width: stage.lerp(modelData[2], tw, p) * overviewScene.width
                            height: stage.lerp(modelData[3], th, p) * overviewScene.height
                            opacity: overviewScene.isAppMode && !sameApp ? (1 - p * 0.88) : 1.0
                            radius: 5
                            color: Qt.rgba(0.84, 0.90, 1.0, modelData[13])
                            border.width: (overviewScene.isAppMode && index === 1 && p > 0.55) ? 1.6 : 1
                            border.color: (overviewScene.isAppMode && index === 1 && p > 0.55)
                                          ? "#70B8FF" : Qt.rgba(1, 1, 1, 0.30)

                            // Mini window header strip
                            Rectangle {
                                width: parent.width
                                height: Math.min(8, parent.height * 0.22)
                                radius: 4
                                color: Qt.rgba(1, 1, 1, 0.18)
                                Row {
                                    x: 4; anchors.verticalCenter: parent.verticalCenter; spacing: 2.5
                                    Rectangle { width: 3.2; height: 3.2; radius: 1.6; color: "#FF5F57"; opacity: 0.85 }
                                    Rectangle { width: 3.2; height: 3.2; radius: 1.6; color: "#FEBC2E"; opacity: 0.85 }
                                    Rectangle { width: 3.2; height: 3.2; radius: 1.6; color: "#28C840"; opacity: 0.85 }
                                }
                            }
                        }
                    }
                }

                // ── SCENE B: Workspace Swipe & End-of-List Rubber-Band Bounce ──
                Item {
                    id: wsScene
                    anchors.fill: parent
                    visible: desktop.g === "tp_workspace_swipe" || desktop.g === "ts_edge_swipe" || desktop.g === "ts_three_finger_swipe"
                    readonly property real shift: desktop.s.wsShift

                    // Workspace 1
                    Item {
                        x: -wsScene.shift * (wsScene.width + 10)
                        width: wsScene.width; height: wsScene.height
                        Rectangle {
                            x: parent.width * 0.10; y: parent.height * 0.17
                            width: parent.width * 0.48; height: parent.height * 0.54
                            radius: 6; color: Qt.rgba(0.95, 0.97, 1.0, 0.90)
                            Rectangle { width: parent.width; height: 9; radius: 5; color: Qt.rgba(0, 0, 0, 0.07) }
                            Column {
                                x: 8; y: 16; spacing: 5
                                Rectangle { width: 54; height: 4; radius: 2; color: "#3A7AFE"; opacity: 0.75 }
                                Rectangle { width: 76; height: 3.5; radius: 1.75; color: Qt.rgba(0, 0, 0, 0.22) }
                                Rectangle { width: 64; height: 3.5; radius: 1.75; color: Qt.rgba(0, 0, 0, 0.16) }
                            }
                        }
                        Rectangle {
                            x: parent.width * 0.46; y: parent.height * 0.28
                            width: parent.width * 0.42; height: parent.height * 0.48
                            radius: 6; color: Qt.rgba(0.16, 0.18, 0.24, 0.88)
                            border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.22)
                            Column {
                                x: 8; y: 12; spacing: 4
                                Rectangle { width: 38; height: 3.5; radius: 1.75; color: "#30D158" }
                                Rectangle { width: 62; height: 3.5; radius: 1.75; color: Qt.rgba(1, 1, 1, 0.42) }
                                Rectangle { width: 48; height: 3.5; radius: 1.75; color: Qt.rgba(1, 1, 1, 0.28) }
                            }
                        }
                    }

                    // Workspace 2 (last workspace — demonstrates rubber-band stretch past 1.0!)
                    Item {
                        x: (1 - wsScene.shift) * (wsScene.width + 10)
                        width: wsScene.width; height: wsScene.height
                        Rectangle {
                            x: parent.width * 0.09; y: parent.height * 0.18
                            width: parent.width * 0.38; height: parent.height * 0.58
                            radius: 6; color: Qt.rgba(0.96, 0.97, 1.0, 0.92)
                            Rectangle { x: 6; y: 8; width: parent.width - 12; height: parent.height * 0.45; radius: 4; color: "#5AC8FA"; opacity: 0.45 }
                            Rectangle { x: 6; y: parent.height * 0.62; width: parent.width * 0.68; height: 4; radius: 2; color: Qt.rgba(0, 0, 0, 0.25) }
                        }
                        Rectangle {
                            x: parent.width * 0.51; y: parent.height * 0.18
                            width: parent.width * 0.40; height: parent.height * 0.27
                            radius: 6; color: Qt.rgba(1, 0.98, 0.94, 0.92)
                            Rectangle { x: 7; y: 8; width: 36; height: 4; radius: 2; color: "#FF9500" }
                            Rectangle { x: 7; y: 17; width: 62; height: 3.5; radius: 1.75; color: Qt.rgba(0, 0, 0, 0.22) }
                        }
                        Rectangle {
                            x: parent.width * 0.51; y: parent.height * 0.49
                            width: parent.width * 0.40; height: parent.height * 0.27
                            radius: 6; color: Qt.rgba(0.92, 0.96, 1.0, 0.90)
                            Rectangle { x: 7; y: 8; width: 44; height: 4; radius: 2; color: "#AF52DE" }
                            Rectangle { x: 7; y: 17; width: 54; height: 3.5; radius: 1.75; color: Qt.rgba(0, 0, 0, 0.22) }
                        }
                    }
                }

                // ── SCENE C: Launchpad / Applications Grid (4/5-finger pinch in & out) ──
                Item {
                    id: lpScene
                    anchors.fill: parent
                    visible: desktop.g === "tp_launchpad" || desktop.g === "ts_pinch_launchpad"
                    readonly property real p: desktop.s.p

                    // Underlying desktop window recedes slightly as Launchpad pinches in
                    Rectangle {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: -4
                        width: parent.width * 0.66
                        height: parent.height * 0.56
                        scale: 1 - 0.08 * lpScene.p
                        opacity: 1 - 0.82 * lpScene.p
                        radius: 6
                        color: Qt.rgba(0.95, 0.97, 1.0, 0.85)
                    }

                    // Frosted backdrop tint + 4x3 app grid converging from outer spread
                    Rectangle {
                        anchors.fill: parent
                        color: Qt.rgba(0.08, 0.12, 0.24, 0.42 * lpScene.p)
                    }

                    Item {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: -3
                        width: 146
                        height: 106
                        opacity: stage.clamp01(lpScene.p * 1.35)
                        scale: stage.lerp(1.42, 1.0, lpScene.p)

                        // Mini search pill at top of Applications panel
                        Rectangle {
                            anchors.top: parent.top
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 58; height: 10; radius: 5
                            color: Qt.rgba(1, 1, 1, 0.22)
                            border.width: 0.8; border.color: Qt.rgba(1, 1, 1, 0.30)
                        }

                        Grid {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 18
                            columns: 4
                            columnSpacing: 14
                            rowSpacing: 10
                            Repeater {
                                model: [
                                    "#2E86FF", "#FF9500", "#30D158", "#FF453A",
                                    "#AF52DE", "#5AC8FA", "#FFD60A", "#FF375F",
                                    "#32ADE6", "#64D2FF", "#A2845E", "#8E8E93"
                                ]
                                delegate: Column {
                                    required property string modelData
                                    spacing: 2.5
                                    Rectangle {
                                        width: 19; height: 19; radius: 5
                                        color: modelData
                                        border.width: 0.8; border.color: Qt.rgba(1, 1, 1, 0.35)
                                    }
                                    Rectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: 13; height: 2.2; radius: 1.1
                                        color: Qt.rgba(1, 1, 1, 0.72)
                                    }
                                }
                            }
                        }
                    }
                }

                // ── SCENE D: Window Move, Snap Preview, Resize & 0.4s Hold-to-Move ──
                Item {
                    id: winScene
                    anchors.fill: parent
                    visible: desktop.g === "tp_drag3fg" || desktop.g === "ts_window_move"
                          || desktop.g === "ts_window_resize" || desktop.g === "ts_hold_move"
                    opacity: desktop.g === "tp_drag3fg" || desktop.g === "ts_window_move" ? desktop.s.p : 1.0

                    // Top menu-bar guard glow when touchscreen tries to push window into the menu bar
                    Rectangle {
                        visible: desktop.s.topGuard > 0.02
                        y: 12
                        width: parent.width
                        height: 2.5
                        opacity: desktop.s.topGuard
                        color: "#70B8FF"
                    }

                    // Native Silky blue snap preview overlay on right half of screen
                    Rectangle {
                        visible: desktop.s.snap > 0.01
                        opacity: desktop.s.snap
                        x: parent.width * 0.50
                        y: parent.height * 0.10
                        width: parent.width * 0.47
                        height: parent.height * 0.76
                        radius: 7
                        color: Qt.rgba(0.10, 0.55, 1.0, 0.26)
                        border.width: 1.6
                        border.color: Qt.rgba(0.45, 0.78, 1.0, 0.92)
                    }

                    // Background passive window
                    Rectangle {
                        x: parent.width * 0.07
                        y: parent.height * 0.26
                        width: parent.width * 0.36
                        height: parent.height * 0.46
                        radius: 6
                        color: Qt.rgba(0.92, 0.95, 1.0, 0.42)
                    }

                    // Active manipulated floating window
                    Rectangle {
                        id: demoWin
                        x: desktop.s.wx * parent.width
                        y: desktop.s.wy * parent.height
                        width: desktop.s.ww * parent.width
                        height: desktop.s.wh * parent.height
                        scale: 1.0 + 0.04 * desktop.s.lifted
                        radius: 6.5
                        color: stage.t.dark ? "#F2F4F8" : "#FFFFFF"
                        border.width: desktop.s.lifted > 0.1 ? 1.5 : 1
                        border.color: desktop.s.lifted > 0.1 ? "#2E86FF" : Qt.rgba(0, 0, 0, 0.14)

                        // Header bar with red/yellow/green traffic lights
                        Rectangle {
                            width: parent.width
                            height: 12
                            radius: 6
                            color: Qt.rgba(0, 0, 0, 0.06)
                            Rectangle { y: 6; width: parent.width; height: 6; color: parent.color }
                            Row {
                                x: 5; anchors.verticalCenter: parent.verticalCenter; spacing: 3
                                Rectangle { width: 4; height: 4; radius: 2; color: "#FF5F57" }
                                Rectangle { width: 4; height: 4; radius: 2; color: "#FEBC2E" }
                                Rectangle { width: 4; height: 4; radius: 2; color: "#28C840" }
                            }
                        }

                        // Responsive window body content bars
                        Column {
                            x: 8; y: 18
                            width: Math.max(16, parent.width - 16)
                            spacing: 5
                            Rectangle { width: parent.width * 0.55; height: 4.5; radius: 2.25; color: "#2E86FF"; opacity: 0.8 }
                            Rectangle { width: parent.width * 0.85; height: 3.5; radius: 1.75; color: Qt.rgba(0, 0, 0, 0.18) }
                            Rectangle { width: parent.width * 0.70; height: 3.5; radius: 1.75; color: Qt.rgba(0, 0, 0, 0.14) }
                            Rectangle {
                                visible: demoWin.height > 78
                                width: parent.width * 0.90; height: Math.max(10, demoWin.height - 54)
                                radius: 4; color: Qt.rgba(0.18, 0.52, 0.98, 0.12)
                            }
                        }

                        // Resize corner handle highlight
                        Rectangle {
                            visible: desktop.g === "ts_window_resize"
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: 2
                            width: 10; height: 10; radius: 5
                            color: "#2E86FF"
                        }
                    }
                }

                // ── SCENE E: Scroll (Natural / Speed / Kinetic Flick + Tap-to-Brake) ──
                Item {
                    id: scrollScene
                    anchors.fill: parent
                    visible: desktop.g === "tp_natural_scroll" || desktop.g === "tp_scroll_speed" || desktop.g === "ts_kinetic_scroll"

                    Rectangle {
                        id: scrollWin
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: -3
                        width: parent.width * 0.76
                        height: parent.height * 0.68
                        radius: 7
                        color: "#F7F8FB"
                        clip: true

                        // Window header
                        Rectangle {
                            z: 3
                            width: parent.width; height: 13
                            color: "#EBEEF5"
                            Row {
                                x: 6; anchors.verticalCenter: parent.verticalCenter; spacing: 3
                                Rectangle { width: 4; height: 4; radius: 2; color: "#FF5F57" }
                                Rectangle { width: 4; height: 4; radius: 2; color: "#FEBC2E" }
                                Rectangle { width: 4; height: 4; radius: 2; color: "#28C840" }
                            }
                        }

                        // Scrolling feed items
                        Item {
                            x: 8
                            y: 18 - desktop.s.scrollY * 56
                            width: parent.width - 18
                            Column {
                                width: parent.width
                                spacing: 6
                                Repeater {
                                    model: [
                                        { c: "#2E86FF", h: 24 },
                                        { c: "#30D158", h: 18 },
                                        { c: "#FF9500", h: 24 },
                                        { c: "#AF52DE", h: 18 },
                                        { c: "#5AC8FA", h: 24 },
                                        { c: "#FF375F", h: 18 }
                                    ]
                                    delegate: Rectangle {
                                        required property var modelData
                                        width: parent.width
                                        height: modelData.h
                                        radius: 4.5
                                        color: "#FFFFFF"
                                        border.width: 1
                                        border.color: Qt.rgba(0, 0, 0, 0.06)
                                        Rectangle {
                                            x: 5; anchors.verticalCenter: parent.verticalCenter
                                            width: 11; height: 11; radius: 3
                                            color: modelData.c
                                        }
                                        Column {
                                            x: 21; anchors.verticalCenter: parent.verticalCenter; spacing: 3
                                            Rectangle { width: 64; height: 3.5; radius: 1.75; color: Qt.rgba(0, 0, 0, 0.55) }
                                            Rectangle { width: 92; height: 3; radius: 1.5; color: Qt.rgba(0, 0, 0, 0.22) }
                                        }
                                    }
                                }
                            }
                        }

                        // Kinetic brake subtle highlight flash when tapped to stop
                        Rectangle {
                            visible: desktop.s.brakeFlash > 0.01
                            anchors.fill: parent
                            color: Qt.rgba(0.18, 0.52, 0.98, 0.14 * desktop.s.brakeFlash)
                        }

                        // Overlay scrollbar thumb
                        Rectangle {
                            z: 4
                            opacity: desktop.s.scrollBar
                            anchors.right: parent.right
                            anchors.rightMargin: 2.5
                            y: 16 + stage.clamp01(0.35 + desktop.s.scrollY * 0.5) * (parent.height - 42)
                            width: 3
                            height: 22
                            radius: 1.5
                            color: Qt.rgba(0, 0, 0, 0.34)
                        }
                    }
                }

                // ── SCENE F: Two-Finger Pinch Zoom & Two-Finger Page Swipe ──
                Item {
                    anchors.fill: parent
                    visible: desktop.g === "tp_zoom" || desktop.g === "ts_zoom" || desktop.g === "tp_swipe_pages"

                    Rectangle {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: -3
                        width: parent.width * 0.76
                        height: parent.height * 0.68
                        radius: 7
                        color: "#F5F7FB"
                        clip: true

                        Rectangle {
                            z: 4
                            width: parent.width; height: 12; color: "#E9ECF4"
                            Row {
                                x: 6; anchors.verticalCenter: parent.verticalCenter; spacing: 3
                                Rectangle { width: 4; height: 4; radius: 2; color: "#FF5F57" }
                                Rectangle { width: 4; height: 4; radius: 2; color: "#FEBC2E" }
                                Rectangle { width: 4; height: 4; radius: 2; color: "#28C840" }
                            }
                        }

                        // Zoomable photo card
                        Item {
                            visible: desktop.g !== "tp_swipe_pages"
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: 5
                            width: parent.width * 0.64
                            height: parent.height * 0.62
                            scale: desktop.s.zoom

                            Rectangle {
                                anchors.fill: parent
                                radius: 6
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: "#56CCF2" }
                                    GradientStop { position: 1.0; color: "#2F80ED" }
                                }
                                border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.08)
                                // Sun & mountain vector graphic
                                Rectangle { x: parent.width * 0.68; y: 10; width: 12; height: 12; radius: 6; color: "#FFD60A" }
                                Canvas {
                                    anchors.fill: parent
                                    onPaint: {
                                        var c = getContext("2d"); c.reset();
                                        c.fillStyle = "rgba(255, 255, 255, 0.88)";
                                        c.beginPath();
                                        c.moveTo(8, height - 6);
                                        c.lineTo(width * 0.38, height * 0.38);
                                        c.lineTo(width * 0.62, height * 0.70);
                                        c.lineTo(width * 0.78, height * 0.50);
                                        c.lineTo(width - 8, height - 6);
                                        c.closePath();
                                        c.fill();
                                    }
                                }
                            }
                        }

                        // Browser page history swipe (two-finger left/right)
                        Item {
                            visible: desktop.g === "tp_swipe_pages"
                            y: 12
                            width: parent.width; height: parent.height - 12
                            // Underlying previous/current page
                            Rectangle {
                                x: -desktop.s.pageShift * parent.width * 0.35
                                width: parent.width; height: parent.height
                                color: "#EEF2FA"
                                Column {
                                    x: 12; y: 12; spacing: 6
                                    Rectangle { width: 68; height: 6; radius: 3; color: "#2E86FF" }
                                    Rectangle { width: 110; height: 4; radius: 2; color: Qt.rgba(0, 0, 0, 0.22) }
                                    Rectangle { width: 96; height: 4; radius: 2; color: Qt.rgba(0, 0, 0, 0.16) }
                                    Rectangle { width: 118; height: 34; radius: 5; color: Qt.rgba(46, 134, 255, 0.16) }
                                }
                            }
                            // Incoming next page sliding over with drop shadow
                            Rectangle {
                                x: (1 - desktop.s.pageShift) * parent.width
                                width: parent.width; height: parent.height
                                color: "#FFFFFF"
                                border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.10)
                                Column {
                                    x: 12; y: 12; spacing: 6
                                    Rectangle { width: 74; height: 6; radius: 3; color: "#30D158" }
                                    Rectangle { width: 116; height: 32; radius: 5; color: Qt.rgba(48, 209, 88, 0.18) }
                                    Rectangle { width: 102; height: 4; radius: 2; color: Qt.rgba(0, 0, 0, 0.22) }
                                    Rectangle { width: 84; height: 4; radius: 2; color: Qt.rgba(0, 0, 0, 0.16) }
                                }
                            }
                        }
                    }
                }

                // ── SCENE G: Tap to Click, Secondary Click Menu, Tap-and-Drag & Typing Guard ──
                Item {
                    anchors.fill: parent
                    visible: desktop.g === "tp_tap" || desktop.g === "tp_secondary"
                          || desktop.g === "tp_tap_drag" || desktop.g === "tp_dwt" || desktop.g === "ts_context_menu"

                    Rectangle {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: -3
                        width: parent.width * 0.74
                        height: parent.height * 0.66
                        radius: 7
                        color: "#F6F7FB"

                        Rectangle {
                            width: parent.width; height: 12; radius: 6; color: "#EAECEF"
                            Rectangle { y: 6; width: parent.width; height: 6; color: parent.color }
                            Row {
                                x: 6; anchors.verticalCenter: parent.verticalCenter; spacing: 3
                                Rectangle { width: 4; height: 4; radius: 2; color: "#FF5F57" }
                                Rectangle { width: 4; height: 4; radius: 2; color: "#FEBC2E" }
                                Rectangle { width: 4; height: 4; radius: 2; color: "#28C840" }
                            }
                        }

                        // Tap to click: interactive row with green macOS switch
                        Item {
                            visible: desktop.g === "tp_tap"
                            anchors.fill: parent
                            Rectangle {
                                x: 12; y: 30; width: parent.width - 24; height: 28; radius: 6
                                color: "#FFFFFF"; border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.07)
                                Rectangle { x: 8; anchors.verticalCenter: parent.verticalCenter; width: 58; height: 4.5; radius: 2.25; color: Qt.rgba(0, 0, 0, 0.55) }
                                Rectangle {
                                    anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                                    width: 26; height: 14; radius: 7
                                    color: desktop.s.toggleOn ? "#30D158" : Qt.rgba(0, 0, 0, 0.16)
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                    Rectangle {
                                        x: desktop.s.toggleOn ? 13 : 1.5; y: 1.5
                                        width: 11; height: 11; radius: 5.5; color: "#FFFFFF"
                                        Behavior on x { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                                    }
                                }
                            }
                            Rectangle {
                                x: 12; y: 64; width: parent.width - 24; height: 24; radius: 6
                                color: "#FFFFFF"; border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.06)
                                Rectangle { x: 8; anchors.verticalCenter: parent.verticalCenter; width: 72; height: 4; radius: 2; color: Qt.rgba(0, 0, 0, 0.30) }
                            }
                        }

                        // Tap-and-drag slider
                        Item {
                            visible: desktop.g === "tp_tap_drag"
                            anchors.fill: parent
                            Column {
                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: 4
                                width: parent.width - 28
                                spacing: 8
                                Rectangle { width: 56; height: 4.5; radius: 2.25; color: Qt.rgba(0, 0, 0, 0.48) }
                                Item {
                                    width: parent.width; height: 14
                                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 4; radius: 2; color: Qt.rgba(0, 0, 0, 0.14) }
                                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width * desktop.s.sliderVal; height: 4; radius: 2; color: "#0A84FF" }
                                    Rectangle {
                                        x: parent.width * desktop.s.sliderVal - 6
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 12; height: 12; radius: 6
                                        color: "#FFFFFF"; border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.22)
                                    }
                                }
                            }
                        }

                        // Typing palm-rejection editor
                        Item {
                            visible: desktop.g === "tp_dwt"
                            anchors.fill: parent
                            Column {
                                x: 12; y: 22; spacing: 6
                                Rectangle { width: 88; height: 4; radius: 2; color: Qt.rgba(0, 0, 0, 0.35) }
                                Row {
                                    spacing: 2
                                    Rectangle {
                                        width: 14 + desktop.s.typingChars * 4.8
                                        height: 4.5; radius: 2.25
                                        color: "#1D1D1F"
                                    }
                                    Rectangle {
                                        width: 1.8; height: 9; radius: 0.9
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: "#0A84FF"
                                    }
                                }
                            }
                        }

                        // File grid + Frosted Context Menu (tp_secondary & ts_context_menu)
                        Item {
                            visible: desktop.g === "tp_secondary" || desktop.g === "ts_context_menu"
                            anchors.fill: parent
                            Row {
                                x: 14; y: 24; spacing: 12
                                Repeater {
                                    model: 3
                                    delegate: Column {
                                        required property int index
                                        spacing: 3
                                        Rectangle {
                                            width: 26; height: 21; radius: 4
                                            color: index === 1 ? "#2E86FF" : "#64B5F6"
                                            border.width: index === 1 && desktop.s.menu > 0.1 ? 1.5 : 0
                                            border.color: "#0A84FF"
                                        }
                                        Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: 18; height: 3; radius: 1.5; color: Qt.rgba(0, 0, 0, 0.35) }
                                    }
                                }
                            }

                            // Frosted context menu popup
                            Rectangle {
                                visible: desktop.s.menu > 0.01
                                opacity: desktop.s.menu
                                scale: 0.90 + 0.10 * desktop.s.menu
                                transformOrigin: Item.TopLeft
                                x: 56; y: 34
                                width: 78; height: 54
                                radius: 6
                                color: Qt.rgba(0.98, 0.98, 1.0, 0.96)
                                border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.12)
                                Column {
                                    anchors.fill: parent; anchors.margins: 4; spacing: 2
                                    Repeater {
                                        model: 4
                                        delegate: Rectangle {
                                            required property int index
                                            width: parent.width; height: 10; radius: 3
                                            readonly property bool hi: index === 1 && desktop.s.p2 > 0.5
                                            color: hi ? "#0A84FF" : "transparent"
                                            Rectangle {
                                                x: 5; anchors.verticalCenter: parent.verticalCenter
                                                width: index === 2 ? 34 : 46; height: 3; radius: 1.5
                                                color: parent.hi ? "#FFFFFF" : Qt.rgba(0, 0, 0, 0.52)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ── Persistent miniature Menu Bar at top of desktop stage ──
                Rectangle {
                    z: 20
                    width: parent.width
                    height: 12
                    color: Qt.rgba(0.06, 0.10, 0.24, 0.28)
                    Row {
                        x: 7; anchors.verticalCenter: parent.verticalCenter; spacing: 4
                        Rectangle { width: 4; height: 4; radius: 2; color: Qt.rgba(1, 1, 1, 0.90) }
                        Rectangle { width: 9; height: 2.8; radius: 1.4; color: Qt.rgba(1, 1, 1, 0.85) }
                        Rectangle { width: 7; height: 2.6; radius: 1.3; color: Qt.rgba(1, 1, 1, 0.62) }
                        Rectangle { width: 8; height: 2.6; radius: 1.3; color: Qt.rgba(1, 1, 1, 0.62) }
                        // Mini workspace indicator pills
                        Row {
                            spacing: 2.5
                            Rectangle {
                                width: 6; height: 4; radius: 2
                                color: desktop.s.wsIndex === 0 ? Qt.rgba(1, 1, 1, 0.90) : Qt.rgba(1, 1, 1, 0.30)
                            }
                            Rectangle {
                                width: 6; height: 4; radius: 2
                                color: desktop.s.wsIndex === 1 ? Qt.rgba(1, 1, 1, 0.90) : Qt.rgba(1, 1, 1, 0.30)
                            }
                        }
                    }
                    Row {
                        anchors.right: parent.right; anchors.rightMargin: 7
                        anchors.verticalCenter: parent.verticalCenter; spacing: 3
                        Repeater {
                            model: 4
                            delegate: Rectangle { width: 2.8; height: 2.8; radius: 1.4; color: Qt.rgba(1, 1, 1, 0.80) }
                        }
                    }
                }

                // ── Persistent miniature colorful macOS Dock at bottom of desktop stage ──
                Rectangle {
                    z: 20
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 5
                    width: dockIconsRow.width + 8
                    height: 14
                    radius: 4.5
                    color: Qt.rgba(1, 1, 1, 0.20)
                    border.width: 0.8
                    border.color: Qt.rgba(1, 1, 1, 0.26)
                    Row {
                        id: dockIconsRow
                        anchors.centerIn: parent
                        spacing: 2.8
                        Repeater {
                            model: [
                                "#2E86FF", "#FF9500", "#FFD60A", "#30D158", "#FF453A",
                                "#F5F5F7", "#5E5CE6", "#BF5AF2", "#32D74B", "#8E8E93"
                            ]
                            delegate: Rectangle {
                                required property string modelData
                                width: 8.5; height: 8.5; radius: 2.2
                                color: modelData
                            }
                        }
                    }
                }

                // ── Miniature macOS pointer arrow when demonstrating cursor / click gestures ──
                Canvas {
                    z: 25
                    visible: desktop.s.showCursor
                    x: desktop.s.cursorX * desktop.width - 2
                    y: desktop.s.cursorY * desktop.height - 2
                    scale: 1 - 0.14 * desktop.s.clickPulse
                    width: 14; height: 18
                    onPaint: {
                        var c = getContext("2d"); c.reset();
                        c.fillStyle = "#1D1D1F";
                        c.strokeStyle = "#FFFFFF";
                        c.lineWidth = 1.3;
                        c.lineJoin = "round";
                        c.beginPath();
                        c.moveTo(2, 2);
                        c.lineTo(2, 13.5);
                        c.lineTo(5.2, 10.6);
                        c.lineTo(7.4, 15.2);
                        c.lineTo(9.2, 14.3);
                        c.lineTo(7.0, 9.8);
                        c.lineTo(11.2, 9.8);
                        c.closePath();
                        c.fill();
                        c.stroke();
                    }
                }
            }

            // Crisp rounded inner border over the masked viewport
            Rectangle {
                anchors.fill: parent
                radius: 14
                color: "transparent"
                border.width: 1
                border.color: stage.t.dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.12)
            }
        }
    }
}
