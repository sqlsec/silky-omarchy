// SilkyOverview — macOS-style window overview, driven by four-finger swipes on the touchpad or the touch screen.
//
//   four fingers up    -> every window of the current workspace (Mission Control)
//   four fingers down  -> every window of the focused app, on any workspace (App Exposé); the other windows of the
//                         workspace stay where they are and fade out
//   the opposite swipe -> back to the desktop
//
// The silky-gestures Hyprland plugin streams the swipe over socket2 ("silkyoverview>>begin,up|down",
// "update,<travel>,<wall ms>", "end[,cancel]"; travel in touchpad units, positive = up; a touch-screen swipe is converted
// to the same units by the plugin; <wall ms> is when the fingers were there, see moveGesture). Everything here hangs off one number,
// `p` (0 = desktop, 1 = overview):
//   * while the fingers are down, p is the finger travel divided by `distance`, read at each frame's time from the
//     timestamped finger track (`lagMs` behind): it follows the fingers 1:1, both ways, in even steps;
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
    readonly property real pickSpeed: 3.4     // a click flies back a little faster than a plain close (≈ 0.3 s from fully open)
    readonly property real project: 0.12      // a release is judged by where the fingers' speed would take p in this many seconds
    readonly property int primeMs: 60         // longest wait for the first captured frames before anything is drawn
    readonly property int freshMs: 24         // after a begin, give the refreshed frames this long to arrive (≈ 2 frames)
    readonly property real fadeIn: 0.12       // the overview cross-fades in over this much of the progress
    readonly property real workspaceStripHeight: 126
    readonly property real gap: 28            // between windows in the grid
    readonly property real labelH: 30         // room under each row for the hovered window's title
    readonly property real maxScale: 0.88     // a single small window still visibly shrinks
    readonly property real cornerR: 14        // Hyprland's decoration:rounding

    // ── state ──
    property real p: 0
    property string mode: ""                  // "workspace" | "app"
    property string screenName: ""
    property int wsId: -1
    property int entryWsId: -1
    property string appClass: ""
    property bool gesture: false
    property real base: 0                     // p when the fingers came down
    property real sign: 1                     // +1: travelling up opens (workspace), -1: travelling down opens (app)
    property var samples: []                  // recent [time, p], for the release speed
    property real goal: 0
    property real speed: minSpeed
    property bool primed: false
    property real fadeFrom: 0                 // the progress at which the picture first appeared: the cross-fade starts there
    // Closing never cross-fades. Once the overview has been fully opaque (`solid`), the thumbnails stay solid all the way
    // back until they sit exactly on the real windows (same places, same stacking, the picked one on top), and
    // only then does the whole layer fade out over `outroMs`. What changes then is only what a capture does not have:
    // Hyprland's borders, title bars and shadows. The old cross-fade over the last part of the progress showed the
    // half-transparent overview over the real desktop (a double image), and after a fast swipe its start had been pushed up
    // to p = 0.5, so half of the way back was already see-through.
    property bool solid: false
    // The keyboard. Exclusive while the overview is on screen, from the first frame of the swipe until the windows have landed:
    // an app that has the keyboard keeps redrawing (a blinking caret, a focus ring) and every redraw makes Hyprland
    // composite every window under the full-screen overview again, which missed about one frame in six for as long as
    // the app had focus. Handing the keyboard back (and focusing a picked window) only once the thumbnails sit on the real
    // windows took the misses on the way back from ~18 % to ~4 %. See land().
    property bool kbdFree: false
    property double kbdReleasedAt: 0
    property bool landing: false              // landed, the keyboard / focus handed back, waiting to fade (see land())
    property string pendingLua: ""            // the picked window's focus + raise, sent at landing
    property real outro: 1                    // the layer's opacity once the windows have landed
    readonly property int outroMs: 80
    onVpChanged: if (!solid && primed && vp >= fadeFrom + fadeIn - 1e-6) solid = true
    property double primeAt: 0
    property string picked: ""                // address of a clicked window: raised above the others while closing
    property bool fadeOut: false              // the clicked window is on another workspace: dissolve instead of flying back
    property string dragAddr: ""              // address of a window being dragged to another workspace
    property int dragSourceWs: -1
    property real dragX: 0                    // pointer position in stage coordinates during a window drag
    property real dragY: 0
    property real dragGrabX: 0.5              // normalized grab point inside the dragged thumbnail
    property real dragGrabY: 0.5
    property int dragTargetWs: -1             // workspace card currently under the dragged window (-1 = none)
    property var pendingMoves: ({})           // addr -> { ws, at }: optimistic move while Hyprland updates
    readonly property bool draggingWindow: dragAddr !== ""
    property var slots: ({})                  // address -> layout entry (see build())
    property var workspacePictures: ({})      // workspace id -> its windows in desktop stacking order
    property var workspaceWindows: ({})       // address -> the window's grid entry on its own workspace
    property var workspaceIds: []
    property real workspacePosition: 0
    property bool workspaceDragging: false
    readonly property bool workspaceMoving: workspaceDragging || workspaceSlide.running
    property var activeWallpapers: ({})       // output name -> the desktop's current image
    property int revision: 0
    // ── fresh pictures ──
    // Every request for a new window picture costs Hyprland's main loop tens of ms, more or less independent of how many
    // windows are in the batch: requested one window at a time (tried: one every 10 ms, or one every 150 ms while open)
    // each request froze Hyprland (every app, the cursor and this overview) for ~50 ms; requested together, the batch
    // freezes it once. Request one batch before the first frame and refresh the active windows after a workspace switch.
    // There is no live stream while the overview stands open. A live window
    // sends a picture every time it redraws (a blinking caret, a spinner), and every one of those froze Hyprland, the mouse
    // pointer included: all 16 streaming froze it for 45-70 ms about once a second, even the hovered one alone did it
    // whenever that window was busy. With none, an open overview costs Hyprland nothing (measured: no freeze at all).
    function freshen(activeOnly) {
        var pre = screenName + "|";
        for (var key in captures) {
            var capture = captures[key];
            if (key.startsWith(pre) && (!activeOnly || capture.onWs) && capture.want !== null)
                capture.snap();
        }
    }
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
    FrameAnimation { running: root.dbg && root.shown; onTriggered: root.log("frame p=" + root.p.toFixed(3) + " vp=" + root.vp.toFixed(3) + " primed=" + root.primed + " fadeFrom=" + root.fadeFrom.toFixed(3) + " solid=" + root.solid + " outro=" + root.outro.toFixed(2) + " dt=" + (frameTime * 1000).toFixed(1)) }

    readonly property bool shown: mode !== "" && (p > 0.0005 || gesture || runner.running || landing || outroAnim.running)
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

    function wallpaperUrl(path) {
        if (!path || /\.(mp4|webm|mkv|mov|gif)$/i.test(path)) return "";
        if (path.startsWith("file:")) return path;
        return path.startsWith("/") ? "file://" + path.split("/").map(encodeURIComponent).join("/") : "";
    }
    function refreshWallpaper() {
        if (hub && hub.refreshWallpaper) hub.refreshWallpaper();
        wallpaperQuery.running = true;
    }
    Component.onCompleted: refreshWallpaper()
    Process {
        id: wallpaperQuery
        command: ["sh", "-c",
            'readlink -f "${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/current/background" || printf "\n"; '
            + 'hyprctl -j layers; printf "\n--\n"; awww query -j 2>/dev/null || swww query -j 2>/dev/null']
        stdout: StdioCollector {
            onStreamFinished: {
                var paths = {};
                var sections = text.split("\n--\n");
                try {
                    var groups = JSON.parse(sections[1]);
                    for (var group in groups) {
                        for (var output of groups[group]) {
                            if (output.name && output.displaying && output.displaying.image)
                                paths[output.name] = output.displaying.image;
                        }
                    }
                } catch (err) {}
                try {
                    var newline = sections[0].indexOf("\n");
                    var omarchyPath = sections[0].slice(0, newline);
                    var layers = JSON.parse(sections[0].slice(newline + 1));
                    // Omarchy's wallpaper layer can be above a running awww daemon.
                    for (var name in layers) {
                        if (root.wallpaperUrl(omarchyPath) && layers[name].levels["0"].some(layer => layer.namespace === "omarchy-background"))
                            paths[name] = omarchyPath;
                    }
                } catch (err) {}
                root.activeWallpapers = paths;
            }
        }
    }

    function updateWorkspaceIds() {
        var ids = Hyprland.workspaces.values
            .filter(ws => ws.id > 0 && ws.monitor && ws.monitor.name === screenName)
            .map(ws => ws.id);
        if (!ids.includes(wsId)) ids.push(wsId);
        ids.sort((a, b) => a - b);
        if (ids.join() === workspaceIds.join()) return;

        // Keep the same visual anchor when an empty workspace is added or removed.
        var oldIndex = workspaceIds.indexOf(wsId);
        var newIndex = ids.indexOf(wsId);
        var offset = oldIndex >= 0 ? workspacePosition - oldIndex : 0;
        var wasSliding = workspaceSlide.running;
        workspaceSlide.stop();
        workspaceIds = ids;
        workspacePosition = newIndex + offset;
        if (wasSliding) animateWorkspace();
    }

    function animateWorkspace() {
        workspaceRelease.stop();
        workspaceDragging = false;
        workspaceSlide.stop();
        var target = workspaceIds.indexOf(wsId);
        var distance = Math.abs(workspacePosition - target);
        if (distance < 0.001) {
            workspacePosition = target;
            return;
        }
        workspaceSlide.to = target;
        workspaceSlide.duration = Math.round(165 + 95 * Math.min(distance, 1.5));
        workspaceSlide.start();
    }

    function resetWorkspaceSlide() {
        workspaceRelease.stop();
        workspaceSlide.stop();
        workspaceDragging = false;
        workspacePosition = Math.max(0, workspaceIds.indexOf(wsId));
    }

    function followWorkspace(name, origin, target, progress) {
        if (!settledOpen || mode !== "workspace" || screenName !== name || wsId !== origin) return;
        var start = workspaceIds.indexOf(origin), end = workspaceIds.indexOf(target);
        if (start < 0 || end < 0 || !Number.isFinite(progress)) return;
        workspaceSlide.stop();
        workspaceRelease.stop();
        workspaceDragging = true;
        workspacePosition = start + (end === start ? progress : (end - start) * clamp01(Math.abs(progress)));
    }

    function releaseWorkspace(name) {
        if (screenName === name && workspaceDragging) workspaceRelease.restart();
    }
    Timer {
        id: workspaceRelease
        // The native swipe publishes its final workspace asynchronously on socket2.
        interval: 45
        onTriggered: root.animateWorkspace()
    }
    NumberAnimation {
        id: workspaceSlide
        target: root
        property: "workspacePosition"
        easing.type: Easing.OutCubic
    }

    function syncWorkspace(id) {
        if (mode !== "workspace" || kbdFree || id <= 0 || id === wsId) return;
        wsId = id;
        build();
        if (settledOpen) animateWorkspace();
        else resetWorkspaceSlide();
        // Refresh geometry and the frames once the compositor has settled the native swipe.
        relayout.restart();
        workspaceCapture.restart();
        refreshWallpaper();
    }
    function selectWorkspace(id) {
        if (mode !== "workspace" || !settledOpen || draggingWindow || id === wsId) return;
        // Hyprland's workspace dispatcher works while the overview holds the keyboard.
        Hyprland.dispatch(workspaceFocus(id));
    }
    function workspaceFocus(id) {
        return 'hl.dsp.focus({ workspace = "' + id + '" })';
    }
    Timer {
        id: workspaceCapture
        interval: 260
        onTriggered: {
            if (root.mode !== "workspace" || root.goal !== 1) return;
            if (root.workspaceMoving) restart();
            else root.freshen(true);
        }
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
        var ts = Hyprland.toplevels.values, mains = [], out = {}, pictures = {}, pages = {};
        var nowMs = Date.now(), nextPending = {};
        for (var i = 0; i < ts.length; i++) {
            var o = ts[i].lastIpcObject;
            if (!o || !o.address || !o.at || !o.size || !o.workspace || o.workspace.id <= 0) continue;
            if (o.hidden || o.mapped === false || o.size[0] < 2 || o.size[1] < 2) continue;
            var addr = String(o.address).replace(/^0x/, "");
            var winWs = o.workspace.id;
            var pm = pendingMoves[addr];
            if (pm) {
                if (winWs !== pm.ws && nowMs - pm.at < 800) {
                    winWs = pm.ws;
                    nextPending[addr] = pm;
                }
            }
            var onWs = winWs === wsId;
            var isMain = mode === "workspace" ? onWs : String(o["class"]) === appClass;
            var workspace = ts[i].workspace;
            var inStrip = mode === "workspace" && ((workspace && workspace.monitor && workspace.monitor.name === screenName) || winWs !== o.workspace.id);
            if (!onWs && !isMain && !inStrip) continue;
            var e = {
                addr: addr,
                x: o.at[0] - ox, y: o.at[1] - oy, w: o.size[0], h: o.size[1],
                onWs: onWs, main: isMain,
                title: String(o.title || ""), cls: String(o["class"] || ""),
                ws: winWs,
                z: (o.fullscreen ? 2000 : 0) + (o.floating ? 1000 : 0) + (500 - Math.min(500, o.focusHistoryID || 0))
            };
            e.cx = e.x + e.w / 2; e.cy = e.y + e.h / 2;
            e.tx = e.x; e.ty = e.y; e.tw = e.w; e.th = e.h;
            if (onWs || isMain) out[e.addr] = e;
            if (isMain) mains.push(e);
            if (inStrip || (mode === "workspace" && onWs)) {
                (pictures[e.ws] || (pictures[e.ws] = [])).push(e);
                pages[e.addr] = e;
            }
        }
        pendingMoves = nextPending;
        var top = res[1] + (mode === "workspace" ? workspaceStripHeight + 16 : 44);
        var bottom = res[3] + (mode === "workspace" ? 20 : 64);
        var area = { x: res[0] + 48, y: top, w: W - res[0] - res[2] - 96, h: H - top - bottom };
        if (mode === "workspace") {
            updateWorkspaceIds();
            for (var id in pictures) {
                pictures[id].sort((a, b) => a.z - b.z);
                grid(pictures[id], area);
            }
        } else grid(mains, area);
        slots = out;
        workspacePictures = pictures;
        workspaceWindows = pages;
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
            entryWsId = wsId;
            picked = ""; fadeOut = false; pendingLua = ""; kbdFree = false;
            refreshWallpaper();
            Hyprland.refreshToplevels();
            Hyprland.refreshMonitors();
            if (m === "workspace") Hyprland.refreshWorkspaces();
            p = 0;
            mode = m;
            build();
            primed = false;
            primeAt = Date.now();
            freshen();
            primeCheck.start();
            refreshLater.restart();
        }
        cancelWindowDrag();
        resetWorkspaceSlide();
        sign = mode === "workspace" ? 1 : -1;
        runner.stop();
        outroAnim.stop(); outro = 1;
        landing = false; landWait.stop();
        base = p;
        samples = [];
        gesture = true;
        gestureTimeout.restart();
    }
    // The fingers' progress, sampled by the time the touchpad / touch screen reported it (the plugin's `<wall ms>`; arrival
    // time for the IPC test path). socket2 delivers the updates in bursts (half of them within 1 ms of each other, then
    // nothing for 30 ms): setting p on arrival moved the overview in uneven jumps although every frame was on time. Now p is
    // read off this track at each frame's own time, `lagMs` in the past (see `follower`), so the steps follow the fingers'
    // real speed, frame by frame.
    function moveGesture(travel, at) {
        if (!gesture) return;
        gestureTimeout.restart();
        var np = clamp01(base + sign * travel / distance);
        var now = Date.now(), t = (at > 0 && Math.abs(now - at) < 500) ? at : now, s = samples;
        if (s.length === 0) s.push([t - 8, base]);            // where the fingers started, one event earlier
        var i = s.length;
        while (i > 0 && s[i - 1][0] > t) i--;                 // (in order unless the clocks hiccup)
        s.splice(i, 0, [t, np]);
        while (s.length > 2 && s[s.length - 1][0] - s[0][0] > 200) s.shift();
        samples = s;
        if (dbg) log("arrival lag " + (now - t).toFixed(1));
    }
    readonly property real lagMs: 10          // how far behind the newest finger sample the overview is drawn
    readonly property real extrapMs: 16       // past the newest sample, carry on at the fingers' speed for at most this long
    function trackAt(T) {
        var s = samples, n = s.length;
        if (n === 0) return base;
        if (T <= s[0][0]) return s[0][1];
        var a = s[n - 1];
        if (T >= a[0]) {
            if (n < 2) return a[1];
            var b = s[n - 2], dt = a[0] - b[0];
            var v = dt > 0.5 ? (a[1] - b[1]) / dt : 0;
            return clamp01(a[1] + v * Math.min(T - a[0], extrapMs));
        }
        for (var i = n - 1; i > 0; i--) {
            if (s[i - 1][0] <= T) {
                var x = s[i - 1], y = s[i], d = y[0] - x[0];
                return d > 0 ? x[1] + (y[1] - x[1]) * (T - x[0]) / d : y[1];
            }
        }
        return s[0][1];
    }
    FrameAnimation {
        id: follower
        running: root.gesture
        onTriggered: root.p = root.trackAt(Date.now() - root.lagMs)
    }
    Timer {
        id: gestureTimeout
        interval: 3000
        onTriggered: {
            root.log("gesture timed out");
            root.endGesture(true);
        }
    }
    function latest() { var s = samples; return s.length ? s[s.length - 1][1] : p; }
    // the fingers' speed (progress per second) over their last 90 ms, by their own timestamps
    function releaseSpeed() {
        var s = samples, n = s.length;
        if (n < 2) return 0;
        var j = n - 1;
        while (j > 0 && s[n - 1][0] - s[j - 1][0] <= 90) j--;
        var dt = (s[n - 1][0] - s[j][0]) / 1000;
        return dt > 0.008 ? (s[n - 1][1] - s[j][1]) / dt : 0;
    }
    function endGesture(cancelled) {
        if (!gesture) return;
        gestureTimeout.stop();
        gesture = false;
        var v = releaseSpeed();
        var to = cancelled ? (base >= 0.5 ? 1 : 0) : (latest() + v * project >= 0.5 ? 1 : 0);
        var along = (to - p) * v > 0 ? Math.abs(v) : 0;      // only speed towards the goal carries over
        animateTo(to, along);
    }
    function animateTo(to, v) {
        goal = to;
        speed = Math.max(minSpeed, Math.min(maxSpeed, v || 0));
        if (Math.abs(p - goal) < 0.0005) { p = goal; settle(); return; }
        runner.p0 = p; runner.t0 = Date.now(); runner.last = runner.t0;
        runner.start();
    }
    function settle() {
        runner.stop();
        if (goal <= 0 && !gesture) {
            if (solid && !fadeOut && primed) { land(); return; }    // landed: hand the desktop back, then fade the layer
            finish();
        }
    }
    // The thumbnails sit exactly on the real windows. Now the keyboard goes back (and a picked window gets focus and is
    // raised); the picture does not move meanwhile, so whatever the apps and Hyprland do about it costs no visible frame.
    // The fade starts once the picked window is the active one (Hyprland has raised it, so the desktop that shows through
    // has the same stacking as the picture), or after `landMaxMs` at the latest.
    readonly property int landMaxMs: 200
    // The hand-over starts a little before the landing (p <= handoverAt on the way back, the last ~60 ms): by the time the
    // thumbnails sit on the windows the picked one is normally active and raised already, so the fade follows at once
    // instead of after a pause. (Handing over at landing measured a 230 ms standstill before the fade.)
    readonly property real handoverAt: 0.2
    function handOver() {
        if (kbdFree) return;
        log("hand over pending=" + (pendingLua !== ""));
        kbdFree = true;
        // Releasing an exclusive layer can restore the previously focused window's workspace.
        var switched = mode === "workspace" && wsId !== entryWsId;
        if (pendingLua !== "" || switched) {
            focusLater.workspace = switched ? wsId : -1;
            focusLater.lua = pendingLua;
            focusLater.tries = 0;
            pendingLua = "";
            focusLater.restart();
        }
    }
    function land() {
        log("land");
        landing = true;
        handOver();
        // a picked window that is not the active one yet: wait for it (at most landMaxMs); otherwise fade right away
        if ((picked !== "" && !isActive(picked)) || (focusLater.running && focusLater.workspace > 0)) landWait.restart();
        else fadeNow();
    }
    function fadeNow() { landWait.stop(); if (landing && !outroAnim.running) { log("outro"); outroAnim.restart(); } }
    function isActive(addr) { var a = Hyprland.activeToplevel; return !!a && String(a.address).replace(/^0x/, "") === addr; }
    Timer { id: landWait; interval: root.landMaxMs; onTriggered: root.fadeNow() }
    Connections {
        target: Hyprland
        function onActiveToplevelChanged() {
            root.log("active " + (Hyprland.activeToplevel ? Hyprland.activeToplevel.address : "none"));
            if (root.landing && landWait.running && root.isActive(root.picked)) { focusLater.stop(); root.fadeNow(); }
        }
    }
    function finish() {
        log("finish");
        outroAnim.stop(); landWait.stop(); focusLater.interval = 30;
        landing = false; kbdFree = false; kbdReleasedAt = 0; pendingLua = "";
        mode = ""; picked = ""; fadeOut = false; primed = false; fadeFrom = 0; solid = false; outro = 1; slots = ({});
        pendingMoves = ({});
        workspacePictures = ({});
        workspaceWindows = ({});
        workspaceIds = [];
        cancelWindowDrag();
        resetWorkspaceSlide();
    }
    NumberAnimation {
        id: outroAnim
        target: root; property: "outro"
        from: 1; to: 0
        duration: root.outroMs
        onFinished: if (!root.gesture && root.goal <= 0 && root.p <= 0.0005) root.finish()
    }
    function releaseKeyboard() {
        if (!kbdFree) {
            kbdFree = true;
            kbdReleasedAt = Date.now();
        }
    }
    // Dismiss the overview when the user clicks the Dock or Menu Bar: release exclusive keyboard immediately
    // and let the clicked action own focus / workspace changes instead of snapping back to entryWsId.
    function dismiss(fade) {
        if (mode === "") return;
        cancelWindowDrag();
        gestureTimeout.stop();
        gesture = false;
        releaseKeyboard();
        picked = "";
        pendingLua = "";
        entryWsId = wsId;
        focusLater.stop();
        if (fade) fadeOut = true;
        resetWorkspaceSlide();
        animateTo(0, pickSpeed);
    }
    function close() {
        if (mode === "") return;
        if (gesture) { dismiss(true); return; }
        cancelWindowDrag();
        resetWorkspaceSlide();
        animateTo(0, 0);
    }
    function beginWindowDrag(addr, sourceWs, sx, sy, gx, gy) {
        if (!settledOpen || mode !== "workspace" || gesture || workspaceMoving) return;
        dragAddr = addr;
        dragSourceWs = sourceWs;
        dragX = sx;
        dragY = sy;
        dragGrabX = gx;
        dragGrabY = gy;
        dragTargetWs = -1;
    }
    function updateWindowDrag(sx, sy, targetWs) {
        if (!draggingWindow) return;
        dragX = sx;
        dragY = sy;
        dragTargetWs = targetWs;
    }
    function cancelWindowDrag() {
        dragAddr = "";
        dragSourceWs = -1;
        dragTargetWs = -1;
    }
    function moveWindowToWorkspace(addr, targetWs) {
        var clean = String(addr).replace(/^0x/, "");
        if (!clean || targetWs <= 0) return;
        log("move window " + clean + " -> ws " + targetWs);
        Hyprland.dispatch('hl.dsp.window.move({ workspace = "' + targetWs + '", follow = false, window = "address:0x' + clean + '" })');
        var next = {};
        for (var k in pendingMoves) next[k] = pendingMoves[k];
        next[clean] = { ws: targetWs, at: Date.now() };
        pendingMoves = next;
        build();
        relayout.restart();
    }
    function finishWindowDrag() {
        if (!draggingWindow) return;
        var addr = dragAddr;
        var sourceWs = dragSourceWs;
        var targetWs = dragTargetWs;
        cancelWindowDrag();
        if (targetWs > 0 && targetWs !== sourceWs) moveWindowToWorkspace(addr, targetWs);
    }
    function toggle(m) {
        if (mode !== "" && (goal > 0.5 || gesture)) { close(); return; }
        startGesture(m === "app" ? "down" : "up");
        gesture = false;
        if (mode !== "") animateTo(1, 0);
    }

    // a click (or a tap) on a window: focus it (switching workspace if needed) and close around it.
    // While the overview holds exclusive keyboard focus Hyprland refuses to focus any window (the dispatch used to be
    // dropped and the previously active window stayed on top), so the focus is sent once the keyboard has been released:
    // at landing (land()), or, for a window on another workspace, right away (the overview dissolves while it switches).
    function pick(e) {
        if (!e || gesture || workspaceMoving) return;
        log("pick " + e.addr);
        picked = e.addr;
        fadeOut = e.ws !== wsId;
        var lua = "";
        if (fadeOut) lua += "hl.dispatch(hl.dsp.focus({ workspace = \"" + e.ws + "\" })); ";
        lua += "hl.dispatch(hl.dsp.focus({ window = \"address:0x" + e.addr + "\" })); ";
        lua += "hl.dispatch(hl.dsp.window.bring_to_top())";
        animateTo(0, pickSpeed);
        if (fadeOut) {
            kbdFree = true;
            focusLater.workspace = -1;
            focusLater.lua = lua;
            focusLater.tries = 0;
            focusLater.restart();
        } else pendingLua = lua;
    }
    Timer {
        id: focusLater
        property string lua: ""
        property int workspace: -1
        interval: 30          // the keyboard release reaches the compositor first
        // The keyboard release is double-buffered Wayland state: it reaches Hyprland with the overview's next commit, and a
        // landed overview may not draw (commit) again right away, so a focus sent too early is still refused. Sent again
        // every 50 ms until the window is the active one (landWait gives up after landMaxMs and fades anyway).
        property int tries: 0
        onTriggered: {
            var monitor = root.monitorObj(root.screenName);
            var wrongWorkspace = workspace > 0 && monitor && (!monitor.activeWorkspace || monitor.activeWorkspace.id !== workspace);
            var needsWindow = root.picked !== "" && (root.fadeOut || !root.isActive(root.picked));
            if (!wrongWorkspace && !needsWindow) {
                if (root.landing) root.fadeNow();
                return;
            }
            var command = wrongWorkspace ? "hl.dispatch(" + root.workspaceFocus(workspace) + "); " : "";
            if (needsWindow) command += lua;
            root.log("focus try " + tries + ": " + command);
            Quickshell.execDetached(["hyprctl", "eval", command]);
            if (!root.fadeOut && ++tries < 4) { interval = 50; restart(); } else interval = 30;
        }
    }

    // linear: p moves at a constant speed until it reaches the goal. By the clock, not by the last frame's duration: a
    // frame that came late used to make the NEXT frame take the double step, a visible hitch. A long stall (> 50 ms) does
    // not make it jump though: the clock is moved on so it carries on from where it was.
    FrameAnimation {
        id: runner
        property real p0: 0
        property double t0: 0
        property double last: 0
        onTriggered: {
            var now = Date.now();
            if (!root.primed) { p0 = root.p; t0 = now; last = now; return; }      // nothing moves before the first frames are in
            if (now - last > 50) t0 += now - last - 50;
            last = now;
            var d = root.goal - p0, travel = root.speed * (now - t0) / 1000;
            if (travel >= Math.abs(d)) { root.p = root.goal; root.settle(); return; }
            root.p = p0 + (d > 0 ? travel : -travel);
            if (root.goal <= 0 && root.solid && !root.fadeOut && root.p <= root.handoverAt) root.handOver();
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
                else if (a[0] === "update") root.moveGesture(parseFloat(a[1]) || 0, parseFloat(a[2]) || 0);
                else if (a[0] === "end") root.endGesture(a[1] === "cancel");
                else if (a[0] === "workspace-move") root.followWorkspace(a[1], Number(a[2]), Number(a[3]), Number(a[4]));
                else if (a[0] === "workspace-end") root.releaseWorkspace(a[1]);
                return;
            }
            if (root.mode === "workspace" && /^(workspace|createworkspace|destroyworkspace|moveworkspace|renameworkspace)v2$/.test(event.name)) {
                Hyprland.refreshWorkspaces();
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
        function update(travel: string): void { root.moveGesture(parseFloat(travel) || 0, 0); }
        function end(): void { root.endGesture(false); }
        function cancel(): void { root.endGesture(true); }
        function toggle(mode: string): void { root.toggle(mode); }
        function close(): void { root.close(); }
        function dismiss(fade: bool): void { root.dismiss(fade); }
        // what a click on a window does, by address (hex, with or without 0x): pick 0x5d3a...
        function pick(addr: string): void { root.pick(root.slots[String(addr).replace(/^0x/, "")]); }
        function moveWindow(addr: string, wsId: int): void { root.moveWindowToWorkspace(addr, wsId); }
        function debug(on: bool): void { root.dbg = on; }
        function workspaceSwipe(id: int, percent: int): void { root.followWorkspace(root.screenName, root.wsId, id, percent / 100); }
        function workspaceSwipeEnd(): void { root.releaseWorkspace(root.screenName); }
        function hub(): string { var h = root.hub; return h ? JSON.stringify({ previewHold: h.previewHold, windowCapture: h.windowCapture, storm: h.storm, preClose: h.preClose, captureQuiet: h.captureQuiet, n: Object.keys(root.captures).length }) : "no hub"; }
        // replays a swipe through the gesture path with an update every 7 ms (like the touchpad): sim up 600
        function sim(dir: string, ms: int): void { simT.dir = dir; simT.total = Math.max(50, ms); simT.t0 = Date.now(); root.startGesture(dir); simT.start(); }
        // every capture's picture size next to its window's size (debugging the landing)
        function sizes(): string { var o = []; for (var k in root.captures) { var c = root.captures[k]; o.push(k + " src=" + c.sourceSize.width + "x" + c.sourceSize.height + " item=" + Math.round(c.width) + "x" + Math.round(c.height) + " content=" + c.hasContent); } return o.join("\n"); }
        function state(): string { return JSON.stringify({ mode: root.mode, p: root.p, primed: root.primed, fadeFrom: root.fadeFrom, workspace: root.wsId, workspacePosition: root.workspacePosition, workspaceMoving: root.workspaceMoving, dragging: root.dragAddr, dragTargetWs: root.dragTargetWs, windows: Object.keys(root.slots).length, wallpaper: root.activeWallpapers[root.screenName] || "" }); }
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: win
            required property var modelData
            readonly property bool targetScreen: root.screenName === modelData.name
            readonly property bool mine: root.shown && targetScreen
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
            // Stacked on Top before MacBar and MacDock in shell.qml: covers every normal window (including parts
            // extending behind the Dock or Menu Bar) while letting the Dock and Menu Bar render and receive clicks on top.
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: mine && !root.kbdFree ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            // this screen's active workspace: its windows keep a capture attached while closed (see `warmCap`)
            readonly property var hmon: Hyprland.monitorFor(modelData)
            readonly property int activeWs: hmon && hmon.activeWorkspace ? hmon.activeWorkspace.id : -1
            onActiveWsChanged: if (targetScreen) root.syncWorkspace(activeWs)
            readonly property var workspaces: Hyprland.workspaces.values.filter(ws =>
                ws.id > 0 && ws.monitor && ws.monitor.name === win.modelData.name).sort((a, b) => a.id - b.id)
            readonly property var res: {
                root.revision;
                var m = root.monitorObj(modelData.name), o = m ? m.lastIpcObject : null;
                return (o && o.reserved) ? o.reserved : [0, 0, 0, 0];
            }
            readonly property string wallpaper: {
                var m = root.hub ? root.hub.wallpaperMap : null;
                var bar = root.hub ? root.hub.bar : null;
                return root.wallpaperUrl(root.activeWallpapers[modelData.name]
                    || (m && m["wallpaper.monitors." + modelData.name])
                    || (bar && bar.wallpaperPath)
                    || (m && (m["wallpaper.last"] || m["wallpaper.default"])));
            }

            Item {
                id: stage
                anchors.fill: parent
                focus: true
                // The overview cross-fades in over the first `fadeIn` of the progress: the real windows' Hyprland shadow, border
                // and title bar (none of them is in a window capture) dissolve instead of vanishing in one frame, and while the
                // captures still nearly cover their windows the two pictures blend like motion blur. On the way back it stays
                // opaque until the windows have landed, then fades over `outroMs` (see `solid`).
                // The fade is applied to the overview as ONE flattened picture (a layer). An Item's opacity is otherwise applied
                // to every child on its own: each thumbnail turned half-transparent and the windows stacked under it showed
                // through (Firefox and Claude through Chrome), so the frames of the fade were a mix of every window: the flash at
                // the end. Flattened, the fading picture is the desktop itself, landed exactly on it, so nothing shows through.
                // The layer stays on while the overview is on screen (and during the start-up warm pass), so its buffer is never
                // allocated in the middle of an animation.
                layer.enabled: win.mine || root.warm
                opacity: root.warm ? 0.01
                       : (!root.primed || !win.mine) ? 0
                       : root.fadeOut ? root.p
                       : root.solid ? root.outro
                       : Math.max(0, Math.min(1, (root.vp - root.fadeFrom) / root.fadeIn))
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        if (root.draggingWindow) root.cancelWindowDrag();
                        else root.close();
                        event.accepted = true;
                    } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && hoverAddr !== "" && !root.draggingWindow) {
                        root.pick(root.slots[hoverAddr]);
                        event.accepted = true;
                    }
                }
                property string hoverAddr: ""
                function hitWorkspaceCard(sx, sy) {
                    if (!strip.visible) return -1;
                    if (sx < strip.x || sx > strip.x + strip.width || sy < strip.y || sy > strip.y + strip.height) return -1;
                    for (var i = 0; i < cards.children.length; i++) {
                        var child = cards.children[i];
                        if (!child || child.workspaceId === undefined || child.width <= 0) continue;
                        var pt = child.mapToItem(stage, 0, 0);
                        if (sx >= pt.x - 4 && sx <= pt.x + child.width + 4 && sy >= pt.y - 4 && sy <= pt.y + child.height + 4)
                            return child.workspaceId;
                    }
                    return -1;
                }

                // Cover the full screen so windows extending behind the Dock or Menu Bar cannot bleed through;
                // MacBar and MacDock sit above silkyoverview on WlrLayer.Top and blur this wallpaper cleanly.
                Item {
                    id: desk
                    anchors.fill: parent
                    clip: true
                    Rectangle { anchors.fill: parent; color: "#1c1c1e" }
                    Image {
                        anchors.fill: parent
                        source: win.wallpaper
                        fillMode: Image.PreserveAspectCrop
                        sourceSize: Qt.size(Math.ceil(width * win.modelData.devicePixelRatio),
                                            Math.ceil(height * win.modelData.devicePixelRatio))
                        asynchronous: true
                        smooth: true
                        cache: true
                    }
                    MouseArea { anchors.fill: parent; onClicked: root.close() }
                }

                Repeater {
                    model: Hyprland.toplevels
                    delegate: Item {
                        id: cell
                        required property var modelData
                        readonly property string addr: String(modelData.address).replace(/^0x/, "")
                        readonly property var pageEntry: root.workspaceWindows[addr] || null
                        readonly property int page: pageEntry ? root.workspaceIds.indexOf(pageEntry.ws) : -1
                        readonly property bool paged: page >= 0 && root.mode === "workspace" && root.settledOpen
                        readonly property real pageDelta: paged ? page - root.workspacePosition : 0
                        readonly property var e: paged ? pageEntry : root.slots[addr] || null
                        readonly property bool live: e !== null && win.mine && (!paged || Math.abs(pageDelta) < 1)
                        readonly property bool inStrip: win.mine && root.mode === "workspace"
                            && !!modelData.workspace && modelData.workspace.id > 0
                            && !!modelData.workspace.monitor && modelData.workspace.monitor.name === win.modelData.name
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
                        readonly property bool interactive: !!e && e.main && !root.workspaceMoving && !root.gesture
                        readonly property bool dragging: root.dragAddr === addr && !!e
                        readonly property bool nearStrip: dragging && root.dragY < strip.y + strip.height + 44
                        property real dragScale: !dragging ? 1.0 : (nearStrip ? Math.min(0.46, 150 / Math.max(1, e ? e.tw : 150)) : 0.88)
                        Behavior on dragScale { enabled: cell.dragging; NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                        readonly property bool hovered: hov.hovered && root.settledOpen && interactive && !root.draggingWindow
                        // where it is drawn: a straight line from the real window to its grid place
                        readonly property real bx: !e ? 0 : (e.onWs ? e.x : e.tx + e.tw * 0.06)
                        readonly property real by: !e ? 0 : (e.onWs ? e.y : e.ty + e.th * 0.06)
                        readonly property real bw: !e ? 1 : (e.onWs ? e.w : e.tw * 0.88)
                        readonly property real baseW: !e ? 0 : (paged ? e.tw : root.lerp(bw, e.tw, k))
                        visible: live && opacity > 0.001
                        z: !e ? 0 : (dragging ? 7000 : (addr === root.picked ? 5000 : (e.onWs ? e.z : -3000 + e.z)))        // the desktop's own stacking
                        opacity: !e ? 0 : (dragging ? (root.dragTargetWs > 0 && root.dragTargetWs !== root.dragSourceWs ? 0.92 : 0.97) : (paged ? 1 : (e.main ? (e.onWs ? 1 : t) : 1 - t)))
                        width: dragging ? baseW * dragScale : baseW
                        height: !e ? 0 : width * e.h / e.w
                        x: !e ? 0 : (dragging ? root.dragX - width * root.dragGrabX : (paged ? e.tx + pageDelta * stage.width : root.lerp(bx, e.tx, k)))
                        y: !e ? 0 : (dragging ? root.dragY - height * root.dragGrabY : (paged ? e.ty : root.lerp(by, e.ty, k)))
                        onEChanged: if (!e) {
                            stage.hoverAddr = stage.hoverAddr === addr ? "" : stage.hoverAddr;
                            if (root.dragAddr === addr) root.cancelWindowDrag();
                        }

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
                                want: (cell.live || cell.warmCap || cell.inStrip) && root.captureOk ? cell.modelData.wayland : null
                                readonly property alias previewTexture: faceTex
                                // Nonmatching App Exposé windows fade out. Keep their last frame for the return gesture.
                                wantLive: false          // never: see freshen()
                                graceMs: 300
                                readonly property string key: win.modelData.name + "|" + cell.addr
                                Component.onCompleted: { var c = root.captures; c[key] = cap; root.captures = c; }
                                Component.onDestruction: { var c = root.captures; if (c[key] === cap) delete c[key]; root.captures = c; }
                            }
                        }
                        ShaderEffectSource {
                            id: faceTex
                            sourceItem: face
                            hideSource: true
                            visible: false
                            live: cell.live || cell.inStrip
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
                            enabled: cell.interactive && !root.draggingWindow
                            onHoveredChanged: {
                                if (hovered) stage.hoverAddr = cell.addr;
                                else if (stage.hoverAddr === cell.addr) stage.hoverAddr = "";
                            }
                        }
                        MouseArea {
                            id: cellDrag
                            anchors.fill: parent
                            enabled: cell.interactive && (!root.draggingWindow || cell.dragging)
                            acceptedButtons: Qt.LeftButton
                            preventStealing: moved
                            property real pressX: 0
                            property real pressY: 0
                            property real grabFx: 0.5
                            property real grabFy: 0.5
                            property bool moved: false
                            onPressed: mouse => {
                                var pt = cellDrag.mapToItem(stage, mouse.x, mouse.y);
                                pressX = pt.x; pressY = pt.y;
                                grabFx = cell.width > 0 ? Math.max(0.1, Math.min(0.9, mouse.x / cell.width)) : 0.5;
                                grabFy = cell.height > 0 ? Math.max(0.1, Math.min(0.9, mouse.y / cell.height)) : 0.5;
                                moved = false;
                            }
                            onPositionChanged: mouse => {
                                if (!(pressedButtons & Qt.LeftButton) || !cell.e) return;
                                if (root.mode !== "workspace" || !root.settledOpen) return;
                                var pt = cellDrag.mapToItem(stage, mouse.x, mouse.y);
                                if (!moved) {
                                    if (Math.hypot(pt.x - pressX, pt.y - pressY) < 8) return;
                                    moved = true;
                                    stage.hoverAddr = "";
                                    root.beginWindowDrag(cell.addr, cell.e.ws, pt.x, pt.y, grabFx, grabFy);
                                }
                                root.updateWindowDrag(pt.x, pt.y, stage.hitWorkspaceCard(pt.x, pt.y));
                            }
                            onReleased: mouse => {
                                if (moved) {
                                    moved = false;
                                    root.finishWindowDrag();
                                } else if (containsMouse) {
                                    root.pick(cell.e);
                                }
                            }
                            onCanceled: {
                                if (moved) {
                                    moved = false;
                                    root.cancelWindowDrag();
                                }
                            }
                        }
                    }
                }
                Flickable {
                    id: strip
                    x: win.res[0] + 16
                    y: win.res[1] + 12 - 12 * (1 - root.vp)
                    width: Math.max(0, stage.width - win.res[0] - win.res[2] - 32)
                    height: root.workspaceStripHeight
                    z: 6000
                    visible: win.mine && root.mode === "workspace" && root.vp > 0
                    opacity: root.vp
                    clip: true
                    interactive: !root.draggingWindow
                    contentWidth: Math.max(width, cards.implicitWidth)
                    flickableDirection: Flickable.HorizontalFlick
                    boundsBehavior: Flickable.StopAtBounds

                    function reveal(card) {
                        var left = cards.x + card.x;
                        contentX = Math.max(0, Math.min(contentWidth - width,
                            Math.max(left + card.width - width, Math.min(contentX, left))));
                    }

                    MouseArea {
                        width: strip.contentWidth
                        height: strip.height
                        z: -1
                        enabled: root.settledOpen && !root.draggingWindow
                        onClicked: mouse => {
                            var pt = mapToItem(stage, mouse.x, mouse.y);
                            if (stage.hitWorkspaceCard(pt.x, pt.y) < 0) root.close();
                        }
                    }

                    Row {
                        id: cards
                        x: (strip.contentWidth - width) / 2
                        width: implicitWidth
                        spacing: 14
                        Repeater {
                            model: win.workspaces
                            delegate: Item {
                                id: card
                                required property var modelData
                                readonly property int workspaceId: modelData.id
                                readonly property bool selected: workspaceId === root.wsId
                                readonly property bool dropTarget: root.draggingWindow && root.dragTargetWs === workspaceId && workspaceId !== root.dragSourceWs
                                readonly property real ratio: preview.width / stage.width
                                width: preview.width + 8
                                height: strip.height
                                scale: dropTarget ? 1.06 : 1.0
                                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                onSelectedChanged: if (selected && strip.visible) Qt.callLater(() => strip.reveal(card))
                                Component.onCompleted: if (selected) Qt.callLater(() => strip.reveal(card))
                                Connections {
                                    target: strip
                                    function onVisibleChanged() { if (strip.visible && card.selected) strip.reveal(card); }
                                }

                                Rectangle {
                                    anchors.fill: preview
                                    anchors.margins: card.dropTarget ? -4 : -3
                                    radius: card.dropTarget ? 13 : 12
                                    color: card.dropTarget ? "#0a84ff" : (card.selected ? "#8de2d4" : "#35404a")
                                }
                                Item {
                                    id: preview
                                    x: 4; y: 4
                                    height: Math.min(90, 164 * stage.height / stage.width)
                                    width: height * stage.width / stage.height
                                    layer.enabled: strip.visible
                                    layer.effect: ShaderEffect {
                                        property var source
                                        property size size: Qt.size(width, height)
                                        property real radius: 9
                                        fragmentShader: Qt.resolvedUrl("silkyround.frag.qsb")
                                    }
                                    clip: true
                                    Rectangle { anchors.fill: parent; color: "#1c1c1e" }
                                    Image {
                                        anchors.fill: parent
                                        source: win.wallpaper
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                    }
                                    Repeater {
                                        model: strip.visible ? root.workspacePictures[card.workspaceId] || [] : []
                                        delegate: Rectangle {
                                            required property var modelData
                                            readonly property var capture: root.captures[win.modelData.name + "|" + modelData.addr]
                                            x: modelData.x * card.ratio
                                            y: modelData.y * card.ratio
                                            width: modelData.w * card.ratio
                                            height: modelData.h * card.ratio
                                            color: "#3a444e"
                                            radius: 2
                                            ShaderEffect {
                                                anchors.fill: parent
                                                visible: !!parent.capture && parent.capture.hasContent
                                                property var source: parent.capture ? parent.capture.previewTexture : null
                                                property size size: Qt.size(width, height)
                                                property real radius: 2
                                                fragmentShader: Qt.resolvedUrl("silkyround.frag.qsb")
                                            }
                                        }
                                    }
                                }
                                Rectangle {
                                    anchors.top: preview.bottom
                                    anchors.topMargin: 8
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: Math.min(label.implicitWidth + 16, parent.width)
                                    height: 20
                                    radius: 6
                                    color: card.dropTarget ? "#0a84ff" : (card.selected ? "#8de2d4" : "#29323a")
                                    Text {
                                        id: label
                                        anchors.centerIn: parent
                                        width: Math.min(implicitWidth, parent.width - 12)
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                        text: card.modelData.name
                                        color: card.dropTarget ? "#ffffff" : (card.selected ? "#152c29" : "#f4f5f6")
                                        font.pixelSize: 12
                                    }
                                }
                                TapHandler {
                                    enabled: root.settledOpen
                                    onTapped: root.selectWorkspace(card.workspaceId)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
