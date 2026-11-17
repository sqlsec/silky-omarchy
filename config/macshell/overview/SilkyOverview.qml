// SilkyOverview — macOS-style window overview, driven by four-finger touchpad swipes.
//
//   four fingers up    -> every window of the current workspace (Mission Control)
//   four fingers down  -> every window of the focused app, on any workspace (App Exposé); the other windows of the
//                         workspace stay where they are and fade out
//   the opposite swipe -> back to the desktop
//
// The silky-gestures Hyprland plugin streams the swipe over socket2 ("silkyoverview>>begin,up|down",
// "update,<travel>", "end[,cancel]"; travel in touchpad units, positive = up). Everything here hangs off one number,
// `p` (0 = desktop, 1 = overview):
//   * while the fingers are down, p is the finger travel divided by `distance`: it follows the fingers 1:1, both ways;
//   * every window is a live capture whose rectangle is a LINEAR interpolation between where the window really is and
//     its place in the grid (no easing curve on top), so the motion always matches the fingers;
//   * on release p carries on at a constant speed taken from the fingers (at least `minSpeed`), linear too, towards
//     open or closed; fingers that come down again mid-way take p over from wherever it is (interrupt / reverse).
//
// Testing without a touchpad (the same code path as the gesture):
//   qs -c MacShell ipc call overview begin up
//   qs -c MacShell ipc call overview update 150
//   qs -c MacShell ipc call overview end
//   qs -c MacShell ipc call overview toggle workspace     (or: app)
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: root
    property var hub: null

    // ── tuning ──
    // touchpad travel for a full open / close. libinput hands out ≈ 11.7 units per mm for a touchpad swipe; 240 ≈ 20 mm,
    // a quarter of this 77 mm-tall pad: a slow push opens it at the fingers' own pace, with room to spare
    readonly property real distance: 240
    readonly property real minSpeed: 2.4      // progress per second a release carries on at, at least (≈ 0.4 s for all of it)
    readonly property real maxSpeed: 10.0
    readonly property real project: 0.12      // a release is judged by where the fingers' speed would take p in this many seconds
    readonly property int primeMs: 60         // longest wait for the first captured frames before anything is drawn
    readonly property int freshMs: 24         // after a begin, give the refreshed frames this long to arrive (≈ 2 frames)
    readonly property real fadeIn: 0.12       // the overview cross-fades in over this much of the progress
    readonly property real dim: 0.22          // how much the wallpaper darkens when fully open
    readonly property real gap: 28            // between windows in the grid
    readonly property real labelH: 30         // room under each row for the hovered window's title
    readonly property real maxScale: 0.88     // a single small window still visibly shrinks
    readonly property real cornerR: 14        // Hyprland's decoration:rounding

    // ── state ──
    property real p: 0
    property string mode: ""                  // "workspace" | "app"
    property string screenName: ""
    property int wsId: -1
    property string appClass: ""
    property bool gesture: false
    property real base: 0                     // p when the fingers came down
    property real sign: 1                     // +1: travelling up opens (workspace), -1: travelling down opens (app)
    property var samples: []                  // recent [time, p], for the release speed
    property real goal: 0
    property real speed: minSpeed
    property bool primed: false
    property real fadeFrom: 0                 // the progress at which the picture first appeared: the cross-fade starts there
    property double primeAt: 0
    property string picked: ""                // address of a clicked window: raised above the others while closing
    property bool fadeOut: false              // the clicked window is on another workspace: dissolve instead of flying back
    property var slots: ({})                  // address -> layout entry (see build())
    property int revision: 0
    signal freshen()                          // every capture takes a new frame (at each begin)
    // MacShell's crash-safety pauses for window captures (a capture storm, a close in progress, Game Mode)
    readonly property bool captureOk: !hub || (!hub.storm && !hub.preClose && !(hub.bar && hub.bar.gaming))
    // app icon per window class, looked up once (heuristicLookup scans every .desktop entry)
    property var icons: ({})
    function iconFor(cls) {
        if (icons[cls] !== undefined) return icons[cls];
        var en = DesktopEntries.heuristicLookup(cls);
        var src = Quickshell.iconPath(en && en.icon ? en.icon : "application-x-executable", "application-x-executable");
        icons[cls] = src;
        return src;
    }
    property bool dbg: false                  // qs -c MacShell ipc call overview debug true: one log line per event and per frame
    function log(m) { if (dbg) console.log("[overview " + Date.now() + "] " + m); }
    FrameAnimation { running: root.dbg && root.shown; onTriggered: root.log("frame p=" + root.p.toFixed(3) + " vp=" + root.vp.toFixed(3) + " primed=" + root.primed + " dt=" + (frameTime * 1000).toFixed(1)) }

    readonly property bool shown: mode !== "" && (p > 0.0005 || gesture || runner.running)
    readonly property real vp: primed ? p : 0                 // what is drawn: always exactly where the fingers are
    // Startup: the overlay is drawn once, invisibly, with every effect on, so the shader pipelines exist before the first swipe
    // (compiling them on the first frame of a gesture stalled it).
    property bool warm: true
    Timer { running: true; interval: 1500; onTriggered: root.warm = false }
    readonly property bool settledOpen: !gesture && !runner.running && p >= 0.999

    function clamp01(x) { return Math.max(0, Math.min(1, x)); }
    function lerp(a, b, t) { return a + (b - a) * t; }

    // ── data ──
    function monitorObj(name) {
        var ms = Hyprland.monitors.values;
        for (var i = 0; i < ms.length; i++) if (ms[i].name === name) return ms[i];
        return null;
    }
    function screenFor(name) {
        var ss = Quickshell.screens;
        for (var i = 0; i < ss.length; i++) if (ss[i].name === name) return ss[i];
        return ss.length ? ss[0] : null;
    }
    function activeClass() {
        var a = Hyprland.activeToplevel;
        var o = a ? a.lastIpcObject : null;
        if (o && o["class"]) return String(o["class"]);
        var ts = Hyprland.toplevels.values, best = null, bestId = 1e9;
        for (var i = 0; i < ts.length; i++) {
            var q = ts[i].lastIpcObject;
            if (q && q.focusHistoryID !== undefined && q.focusHistoryID < bestId && q.workspace && q.workspace.id > 0) { best = q; bestId = q.focusHistoryID; }
        }
        return best ? String(best["class"] || "") : "";
    }

    // Uniform-scale grid, like Mission Control: windows keep their relative sizes and roughly their places (rows are
    // filled top to bottom, each row left to right). Every row count is tried; the one with the largest scale wins.
    function grid(items, area) {
        var n = items.length;
        if (n === 0) return;
        var order = items.slice().sort(function (a, b) { return (a.cy - b.cy) || (a.cx - b.cx); });
        var best = null;
        for (var rows = 1; rows <= n; rows++) {
            var per = Math.ceil(n / rows), groups = [];
            for (var i = 0; i < n; i += per) groups.push(order.slice(i, i + per).sort(function (a, b) { return a.cx - b.cx; }));
            var s = maxScale, sumH = 0;
            for (var g = 0; g < groups.length; g++) {
                var sw = 0, mh = 0;
                for (var k = 0; k < groups[g].length; k++) { sw += groups[g][k].w; mh = Math.max(mh, groups[g][k].h); }
                s = Math.min(s, (area.w - gap * (groups[g].length - 1)) / sw);
                sumH += mh;
            }
            s = Math.min(s, (area.h - (gap + labelH) * (groups.length - 1) - labelH) / sumH);
            if (!best || s > best.s + 1e-6) best = { s: s, groups: groups };
            if (per === 1) break;
        }
        var S = Math.max(0.05, best.s), total = 0;
        for (g = 0; g < best.groups.length; g++) {
            var h = 0;
            for (k = 0; k < best.groups[g].length; k++) h = Math.max(h, best.groups[g][k].h * S);
            best.groups[g].rowH = h;
            total += h;
        }
        total += (gap + labelH) * (best.groups.length - 1);
        var y = area.y + (area.h - labelH - total) / 2;
        for (g = 0; g < best.groups.length; g++) {
            var row = best.groups[g], rw = gap * (row.length - 1);
            for (k = 0; k < row.length; k++) rw += row[k].w * S;
            var x = area.x + (area.w - rw) / 2;
            for (k = 0; k < row.length; k++) {
                var it = row[k];
                it.tw = it.w * S; it.th = it.h * S;
                it.tx = x; it.ty = y + (row.rowH - it.th) / 2;
                x += it.tw + gap;
            }
            y += row.rowH + gap + labelH;
        }
    }

    function build() {
        var scr = screenFor(screenName), mon = monitorObj(screenName);
        if (!scr) { slots = ({}); return; }
        var mo = mon ? mon.lastIpcObject : null;
        var res = (mo && mo.reserved) ? mo.reserved : [0, 0, 0, 0];
        var W = scr.width, H = scr.height, ox = scr.x, oy = scr.y;
        var ts = Hyprland.toplevels.values, mains = [], out = {};
        for (var i = 0; i < ts.length; i++) {
            var o = ts[i].lastIpcObject;
            if (!o || !o.address || !o.at || !o.size || !o.workspace || o.workspace.id <= 0) continue;
            if (o.hidden || o.mapped === false || o.size[0] < 2 || o.size[1] < 2) continue;
            var onWs = o.workspace.id === wsId;
            var isMain = mode === "workspace" ? onWs : String(o["class"]) === appClass;
            if (!onWs && !isMain) continue;
            var e = {
                addr: String(o.address).replace(/^0x/, ""),
                x: o.at[0] - ox, y: o.at[1] - oy, w: o.size[0], h: o.size[1],
                onWs: onWs, main: isMain,
                title: String(o.title || ""), cls: String(o["class"] || ""),
                ws: o.workspace.id,
                z: (o.fullscreen ? 2000 : 0) + (o.floating ? 1000 : 0) + (500 - Math.min(500, o.focusHistoryID || 0))
            };
            e.cx = e.x + e.w / 2; e.cy = e.y + e.h / 2;
            e.tx = e.x; e.ty = e.y; e.tw = e.w; e.th = e.h;
            out[e.addr] = e;
            if (isMain) mains.push(e);
        }
        var top = res[1] + 44, bottom = res[3] + 64;
        grid(mains, { x: res[0] + 48, y: top, w: W - res[0] - res[2] - 96, h: H - top - bottom });
        slots = out;
        revision++;
        if (dbg) { var w = 0, c = 0; for (var k in captures) { if (captures[k].want !== null) w++; if (captures[k].hasContent) c++; } log("captures want=" + w + " content=" + c); }
    }

    // ── progress ──
    function startGesture(dir) {
        if (gesture) return;
        var fresh = mode === "" || (p <= 0.0005 && !runner.running);
        if (fresh) {
            var fm = Hyprland.focusedMonitor;
            if (!fm) return;
            var m = dir === "down" ? "app" : "workspace";
            appClass = m === "app" ? activeClass() : "";
            if (m === "app" && appClass === "") return;       // App Exposé needs an app
            screenName = fm.name;
            wsId = fm.activeWorkspace ? fm.activeWorkspace.id : -1;
            picked = ""; fadeOut = false;
            try { Hyprland.refreshToplevels(); Hyprland.refreshMonitors(); } catch (err) {}
            p = 0;
            mode = m;
            build();
            primed = false;
            primeAt = Date.now();
            freshen();
            primeCheck.start();
            refreshLater.restart();
        }
        sign = mode === "workspace" ? 1 : -1;
        runner.stop();
        base = p;
        samples = [[Date.now(), p]];
        gesture = true;
    }
    function moveGesture(travel) {
        if (!gesture) return;
        var np = clamp01(base + sign * travel / distance);
        var now = Date.now(), s = samples;
        s.push([now, np]);
        while (s.length > 2 && now - s[0][0] > 90) s.shift();
        samples = s;
        p = np;
    }
    function releaseSpeed() {
        var s = samples;
        if (s.length < 2) return 0;
        var dt = (s[s.length - 1][0] - s[0][0]) / 1000;
        return dt > 0.008 ? (s[s.length - 1][1] - s[0][1]) / dt : 0;
    }
    function endGesture(cancelled) {
        if (!gesture) return;
        gesture = false;
        var v = releaseSpeed();
        var to = cancelled ? (base >= 0.5 ? 1 : 0) : (p + v * project >= 0.5 ? 1 : 0);
        var along = (to - p) * v > 0 ? Math.abs(v) : 0;      // only speed towards the goal carries over
        animateTo(to, along);
    }
    function animateTo(to, v) {
        goal = to;
        speed = Math.max(minSpeed, Math.min(maxSpeed, v || 0));
        if (Math.abs(p - goal) < 0.0005) { p = goal; settle(); return; }
        runner.start();
    }
    function settle() {
        runner.stop();
        if (goal <= 0 && !gesture) {
            mode = ""; picked = ""; fadeOut = false; primed = false; fadeFrom = 0; slots = ({});
        }
    }
    function close() { if (mode !== "" && !gesture) animateTo(0, 0); }
    function toggle(m) {
        if (mode !== "" && (goal > 0.5 || gesture)) { close(); return; }
        startGesture(m === "app" ? "down" : "up");
        gesture = false;
        if (mode !== "") animateTo(1, 0);
    }

    // a click on a window: focus it (switching workspace if needed) and close around it
    function pick(e) {
        if (!e || gesture) return;
        picked = e.addr;
        fadeOut = e.ws !== wsId;
        var lua = "";
        if (fadeOut) lua += "hl.dispatch(hl.dsp.focus({ workspace = \"" + e.ws + "\" })); ";
        lua += "hl.dispatch(hl.dsp.focus({ window = \"address:0x" + e.addr + "\" })); ";
        lua += "hl.dispatch(hl.dsp.window.bring_to_top())";
        Quickshell.execDetached(["hyprctl", "eval", lua]);
        animateTo(0, 0);
    }

    // linear: p moves at a constant speed until it reaches the goal
    FrameAnimation {
        id: runner
        onTriggered: {
            if (!root.primed) return;           // nothing moves before the first frames are in
            var dt = Math.min(0.05, frameTime > 0 ? frameTime : 0.016);
            var d = root.goal - root.p, step = root.speed * dt;
            if (Math.abs(d) <= step) { root.p = root.goal; root.settle(); return; }
            root.p += d > 0 ? step : -step;
        }
    }
    // nothing moves until the windows' first frames are in (or primeMs is over): the overlay never shows a hole
    Timer {
        id: primeCheck
        interval: 16; repeat: true
        onTriggered: {
            if (root.mode === "") { stop(); return; }
            var waiting = 0;
            var pre = root.screenName + "|";
            for (var k in root.captures) {
                var c = root.captures[k];
                if (k.indexOf(pre) === 0 && c && c.onWs && c.want !== null && !c.hasContent) waiting++;
            }
            var age = Date.now() - root.primeAt;
            if ((waiting === 0 && age >= root.freshMs) || age > root.primeMs) {
                // the fingers' travel while waiting is kept; with the window already mapped this wait is a frame or
                // two, so the picture simply appears where the fingers are
                root.fadeFrom = root.gesture ? Math.min(root.p, 0.5) : 0;
                root.primed = true;
                stop();
            }
        }
    }
    property var captures: ({})               // "screen|address" -> capture item (registered by the delegates)
    // the toplevel list asked for at begin arrives a moment later: lay out again with it (delegates are kept)
    Timer { id: refreshLater; interval: 60; onTriggered: if (root.mode !== "" && root.goal >= 0) root.build() }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "silkyoverview") {
                root.log("event " + event.data);
                var a = String(event.data).split(",");
                if (a[0] === "begin") root.startGesture(a[1]);
                else if (a[0] === "update") root.moveGesture(parseFloat(a[1]) || 0);
                else if (a[0] === "end") root.endGesture(a[1] === "cancel");
                return;
            }
            // a window opened / closed / moved while the overview is up: lay out again
            if (root.mode !== "" && !root.gesture && /^(openwindow|closewindow|movewindow)/.test(event.name)) relayout.restart();
        }
    }
    Timer { id: relayout; interval: 80; onTriggered: { try { Hyprland.refreshToplevels(); } catch (err) {} relayout2.restart(); } }
    Timer { id: relayout2; interval: 60; onTriggered: if (root.mode !== "") root.build() }

    Timer {
        id: simT
        property string dir: "up"
        property int total: 600
        property double t0: 0
        interval: 7; repeat: true
        onTriggered: {
            var f = Math.min(1, (Date.now() - t0) / total);
            root.moveGesture((dir === "down" ? -1 : 1) * root.distance * 1.1 * f);
            if (f >= 1) { stop(); root.endGesture(false); }
        }
    }
    IpcHandler {
        target: "overview"
        function begin(dir: string): void { root.startGesture(dir); }
        function update(travel: string): void { root.moveGesture(parseFloat(travel) || 0); }
        function end(): void { root.endGesture(false); }
        function cancel(): void { root.endGesture(true); }
        function toggle(mode: string): void { root.toggle(mode); }
        function close(): void { root.close(); }
        function debug(on: bool): void { root.dbg = on; }
        function hub(): string { var h = root.hub; return h ? JSON.stringify({ previewHold: h.previewHold, windowCapture: h.windowCapture, storm: h.storm, preClose: h.preClose, captureQuiet: h.captureQuiet, n: Object.keys(root.captures).length }) : "no hub"; }
        // replays a swipe through the gesture path with an update every 7 ms (like the touchpad): sim up 600
        function sim(dir: string, ms: int): void { simT.dir = dir; simT.total = Math.max(50, ms); simT.t0 = Date.now(); root.startGesture(dir); simT.start(); }
        function state(): string { return JSON.stringify({ mode: root.mode, p: root.p, primed: root.primed, windows: Object.keys(root.slots).length }); }
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: win
            required property var modelData
            readonly property bool mine: root.shown && root.screenName === modelData.name
            // Kept mapped all the time and parked just off-screen at full size while closed, like MacShell's Spotlight: mapping
            // the window at the start of a swipe created its Vulkan surface, swapchain and pipelines on the GUI thread, which
            // measured 0.5 s with no frames on every swipe (the fingers were a third of the way before anything moved).
            // Opening is now only a move. Parked, it takes no input, no keyboard focus, and Hyprland does not draw it.
            screen: modelData
            visible: true
            color: "transparent"
            anchors { left: true; right: true; top: true; bottom: true }
            margins {
                left: win.mine ? 0 : -(win.modelData.width + 64)
                right: win.mine ? 0 : win.modelData.width + 64
            }
            mask: Region { item: win.mine ? stage : noInput }
            Item { id: noInput; width: 0; height: 0 }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "silkyoverview"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: mine && root.goal > 0.5 && !root.gesture ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            // this screen's active workspace: its windows keep a capture attached while closed (see `warmCap`)
            readonly property var hmon: Hyprland.monitorFor(modelData)
            readonly property int activeWs: hmon && hmon.activeWorkspace ? hmon.activeWorkspace.id : -1
            readonly property var res: {
                root.revision;
                var m = root.monitorObj(modelData.name), o = m ? m.lastIpcObject : null;
                return (o && o.reserved) ? o.reserved : [0, 0, 0, 0];
            }
            readonly property string wallpaper: {
                var m = root.hub ? root.hub.wallpaperMap : null;
                if (!m) return "";
                var f = m["wallpaper.monitors." + modelData.name] || m["wallpaper.last"] || m["wallpaper.default"] || "";
                return /\.(mp4|webm|mkv|mov|gif)$/i.test(f) ? "" : f;
            }

            Item {
                id: stage
                anchors.fill: parent
                focus: true
                // The overview cross-fades in over the first `fadeIn` of the progress: the real windows' Hyprland shadow, border
                // and title bar (none of them is in a window capture) dissolve instead of vanishing in one frame, and while the
                // captures still nearly cover their windows the two pictures blend like motion blur.
                opacity: root.warm ? 0.01
                       : (!root.primed || !win.mine) ? 0
                       : root.fadeOut ? root.p
                       : Math.max(0, Math.min(1, (root.vp - root.fadeFrom) / root.fadeIn))
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) { root.close(); event.accepted = true; }
                    else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && hoverAddr !== "") { root.pick(root.slots[hoverAddr]); event.accepted = true; }
                }
                property string hoverAddr: ""

                // The desktop below the menu bar's reserved strip (left uncovered: the bar stays where it is). Only the wallpaper
                // and a dim on top: a full-screen blur re-computed every frame cost more than a 90 Hz frame on this GPU.
                Item {
                    id: desk
                    x: win.res[0]; y: win.res[1]
                    width: parent.width - win.res[0] - win.res[2]
                    height: parent.height - win.res[1] - win.res[3]
                    clip: true
                    Rectangle { anchors.fill: parent; color: "#1c1c1e" }
                    Image {
                        x: -desk.x; y: -desk.y
                        width: stage.width; height: stage.height
                        source: win.wallpaper !== "" ? "file://" + win.wallpaper : ""
                        fillMode: Image.PreserveAspectCrop
                        sourceSize: Qt.size(stage.width * 2, stage.height * 2)
                        smooth: true
                        cache: true
                    }
                    Rectangle { anchors.fill: parent; color: "black"; opacity: root.dim * root.vp }
                    MouseArea { anchors.fill: parent; onClicked: root.close() }
                }

                Repeater {
                    model: Hyprland.toplevels
                    delegate: Item {
                        id: cell
                        required property var modelData
                        readonly property string addr: String(modelData.address).replace(/^0x/, "")
                        readonly property var e: { root.revision; return root.slots[addr] || null; }
                        readonly property bool live: e !== null && win.mine
                        // A window on this screen's active workspace keeps its capture attached while closed (no frames are
                        // requested then), so a swipe starts on a picture that is already there; every begin asks for a fresh one.
                        // Independent of the Dock's "live window capture" switch (that one is about the Dock's previews); only
                        // MacShell's crash-safety pauses (a capture storm, a close in progress, Game Mode) hold it.
                        readonly property bool warmCap: modelData.workspace !== null && modelData.workspace.id === win.activeWs
                        // the window's own size, also while closed: the picture's texture never changes size between swipes
                        readonly property var own: {
                            var o = modelData.lastIpcObject;
                            return e ? [e.w, e.h] : (o && o.size ? [Math.max(1, o.size[0]), Math.max(1, o.size[1])] : [1, 1]);
                        }
                        readonly property real t: root.vp
                        readonly property real k: !e ? 0 : (e.main ? t : 0)
                        readonly property bool hovered: hov.hovered && root.settledOpen && e && e.main
                        // where it is drawn: a straight line from the real window to its grid place
                        readonly property real bx: !e ? 0 : (e.onWs ? e.x : e.tx + e.tw * 0.06)
                        readonly property real by: !e ? 0 : (e.onWs ? e.y : e.ty + e.th * 0.06)
                        readonly property real bw: !e ? 1 : (e.onWs ? e.w : e.tw * 0.88)
                        visible: live && opacity > 0.001
                        z: !e ? 0 : (addr === root.picked ? 5000 : (e.onWs ? e.z : -3000 + e.z))        // the desktop's own stacking
                        opacity: !e ? 0 : (e.main ? (e.onWs ? 1 : t) : 1 - t)
                        x: !e ? 0 : root.lerp(bx, e.tx, k)
                        y: !e ? 0 : root.lerp(by, e.ty, k)
                        width: !e ? 0 : root.lerp(bw, e.tw, k)
                        height: !e ? 0 : width * e.h / e.w
                        onEChanged: if (!e) stage.hoverAddr = stage.hoverAddr === addr ? "" : stage.hoverAddr

                        // Hyprland's own shadow (range 36, 60 % black), from the first frame on
                        RectangularShadow {
                            anchors.fill: parent
                            radius: root.cornerR * cell.width / Math.max(1, cell.own[0])
                            blur: 30; spread: 0
                            color: Qt.rgba(0, 0, 0, 0.45)
                        }
                        // The picture at the window's own, fixed size. It is copied into a texture only when a new frame arrives
                        // (a plain copy, no effect pass) and drawn by `round` at whatever size the cell has: moving and scaling
                        // cost nothing extra. A layer + mask effect per window used to be re-rendered at full resolution
                        // whenever a frame arrived, and reallocated whenever the size changed: the stutter.
                        Item {
                            id: face
                            width: cell.own[0]
                            height: cell.own[1]
                            Rectangle {      // a window Hyprland would not capture (yet): the app's icon on a card
                                anchors.fill: parent
                                visible: !cap.hasContent
                                color: "#2c2c2e"
                                Image {
                                    anchors.centerIn: parent
                                    width: Math.min(192, parent.width * 0.3); height: width
                                    sourceSize: Qt.size(256, 256)
                                    asynchronous: true
                                    source: parent.visible && cell.e ? root.iconFor(cell.e.cls) : ""
                                }
                            }
                            SafeCapture {
                                id: cap
                                anchors.fill: parent
                                readonly property bool onWs: cell.e ? cell.e.onWs : false
                                want: (cell.live || cell.warmCap) && root.captureOk ? cell.modelData.wayland : null
                                // one frame carries the gesture; the stream only starts once the overview has settled open
                                wantLive: cell.live && root.settledOpen && root.captureOk && (!root.hub || !root.hub.captureQuiet)
                                graceMs: 300
                                readonly property string key: win.modelData.name + "|" + cell.addr
                                Component.onCompleted: { var c = root.captures; c[key] = cap; root.captures = c; }
                                Component.onDestruction: { var c = root.captures; if (c[key] === cap) delete c[key]; root.captures = c; }
                                Connections { target: root; function onFreshen() { if (cell.warmCap || cell.live) cap.snap(); } }
                            }
                        }
                        ShaderEffectSource {
                            id: faceTex
                            sourceItem: face
                            hideSource: true
                            visible: false
                            live: cell.live
                            smooth: true
                        }
                        ShaderEffect {
                            anchors.fill: parent
                            visible: cell.live
                            property var source: faceTex
                            property size size: Qt.size(width, height)
                            property real radius: root.cornerR * cell.width / Math.max(1, cell.own[0])
                            fragmentShader: Qt.resolvedUrl("silkyround.frag.qsb")
                        }
                        Rectangle {      // hover: macOS outlines the window
                            anchors.fill: parent
                            anchors.margins: -4
                            radius: root.cornerR * cell.width / Math.max(1, face.width) + 4
                            color: "transparent"
                            border.width: 3
                            border.color: "#0a84ff"
                            opacity: cell.hovered ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 120 } }
                        }
                        Rectangle {      // the title, under the hovered window
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.bottom
                            anchors.topMargin: 8
                            width: Math.min(titleText.implicitWidth + 24, Math.max(160, parent.width + 40))
                            height: 24; radius: 12
                            color: Qt.rgba(0.12, 0.12, 0.13, 0.82)
                            border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.12)
                            opacity: cell.hovered ? 1 : 0
                            visible: opacity > 0
                            Behavior on opacity { NumberAnimation { duration: 120 } }
                            Text {
                                id: titleText
                                anchors.centerIn: parent
                                width: Math.min(implicitWidth, parent.width - 24)
                                elide: Text.ElideRight
                                text: cell.e ? (cell.e.title || cell.e.cls) : ""
                                color: "white"
                                font.family: root.hub && root.hub.boldFontFamily ? root.hub.boldFontFamily : "Open Runde"
                                font.pixelSize: 13
                            }
                        }
                        HoverHandler {
                            id: hov
                            enabled: cell.e !== null && cell.e.main
                            onHoveredChanged: if (hovered) stage.hoverAddr = cell.addr; else if (stage.hoverAddr === cell.addr) stage.hoverAddr = ""
                        }
                        TapHandler {
                            enabled: cell.e !== null && cell.e.main && !root.gesture
                            onTapped: root.pick(cell.e)
                        }
                    }
                }
            }
        }
    }
}
