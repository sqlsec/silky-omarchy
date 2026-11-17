#!/usr/bin/env python3
"""Apply the Applications panel interaction tuning to a Silky MacBar.qml."""
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
s = path.read_text()
original = s

def replace(old, new):
    global s
    if new in s or (old.startswith('onWheel: event => { appsScroller.feed(event);') and 'onWheel: event => { appsScroller.wheel(event);' in s):
        return
    if old not in s:
        raise SystemExit(f'Applications panel tuning: expected text missing: {old[:80]!r}')
    s = s.replace(old, new, 1)

replace('readonly property real appsWheelStep: 180          // one mouse-wheel notch, eased in over ~0.15 s',
        'readonly property real appsWheelStep: 320          // pixels per mouse-wheel notch, smoothly eased')
replace('readonly property real appsGlideDecay: 2.2', 'readonly property real appsGlideDecay: 1.7')
if 'layer.sourceRect: Qt.rect(-10, -10, width + 20, height + 20)' not in s and 'id: appsGlassLayer' not in s:
    replace('opacity: Math.min(1, t / 0.25)', 'opacity: root.reduceMotion ? 1 : Math.min(1, t)')
old = '''                        // The MouseArea sits above the Flickable (a sibling: Flickable filters its children's wheel events) and
                        // takes no buttons, so clicks and touches still reach the icons and the Flickable's own drag.
                        MouseArea {
                            x: appsFlick.x; y: appsFlick.y
                            width: appsFlick.width; height: appsFlick.height
                            acceptedButtons: Qt.NoButton
                            onWheel: wheel => { appsScroller.feed(wheel); wheel.accepted = true; }
                        }'''
new = '''                        // Handle wheel input on the Flickable before its built-in wheel handling.
                        WheelHandler {
                            parent: appsFlick
                            target: null
                            orientation: Qt.Vertical
                            onWheel: event => { appsScroller.feed(event); event.accepted = true; }
                        }'''
if old in s:
    s = s.replace(old, new, 1)
elif 'parent: appsFlick\n                            target: null' not in s:
    raise SystemExit('Applications panel tuning: wheel handler missing')
# WheelHandler accepts one orientation, not a bitwise combination.
s = s.replace('orientation: Qt.Vertical | Qt.Horizontal', 'orientation: Qt.Vertical')
# Qt Quick WheelEvent exposes pixelDelta, but not QWheelEvent's phase or device.
# Using an unavailable phase made every mouse event look like a touchpad event.
if 'var pad = !mouseWheel && w.pixelDelta.y !== 0;' not in s and 'var pad = !mouseWheel;' not in s:
    replace('var pad = w.phase !== Qt.NoScrollPhase || (w.device && w.device.type === PointerDevice.TouchPad);',
            'var pad = w.pixelDelta.y !== 0;')
replace('''                                if (w.phase === Qt.ScrollEnd) { glide(measured()); return; }
                                if (w.phase === Qt.ScrollBegin || mode !== 2) {
                                    if (mode === 0 || w.phase === Qt.ScrollBegin) target = appsFlick.contentY;   // grab it where it is
                                    vel = 0; samples = []; mode = 2;
                                }''', '''                                if (mode !== 2) {
                                    if (mode === 0) target = appsFlick.contentY;
                                    vel = 0; samples = []; mode = 2;
                                }
                                appsPadEnd.restart();''')
replace('''                        FrameAnimation {
                            id: appsScroller''', '''                        Timer {
                            id: appsPadEnd
                            interval: 50
                            onTriggered: if (appsScroller.mode === 2) appsScroller.glide(appsScroller.measured())
                        }
                        FrameAnimation {
                            id: appsScroller''')
replace('''                                if (!pad) {
                                    if (mode !== 1) target = appsFlick.contentY;''', '''                                if (!pad) {
                                    appsPadEnd.stop();
                                    if (mode !== 1) target = appsFlick.contentY;''')

# MouseArea delegates receive wheel events before the Flickable's handler.
if 'scrollGestureEnabled: false\n                                                        onWheel: event => { appsScroller.wheel(event);' not in s:
    replace('''                                                        id: cma
                                                        anchors.fill: parent
                                                        onClicked:''', '''                                                        id: cma
                                                        anchors.fill: parent
                                                        scrollGestureEnabled: false
                                                        onWheel: event => { appsScroller.feed(event, true); event.accepted = true; }
                                                        onClicked:''')
replace('onMovementStarted: { revealAnim.stop(); appsScroller.stop(); lastDragY = contentY; }',
        'onMovementStarted: if (dragging) { revealAnim.stop(); appsScroller.stop(); lastDragY = contentY; }')
replace('function feed(w) {', 'function feed(w, mouseWheel) {')
if 'var pad = !mouseWheel && w.pixelDelta.y !== 0;' not in s and 'var pad = !mouseWheel;' not in s:
    replace('var pad = w.pixelDelta.y !== 0;', 'var pad = !mouseWheel && w.pixelDelta.y !== 0;')
replace('onWheel: event => { appsScroller.feed(event); event.accepted = true; }',
        'onWheel: event => { appsScroller.feed(event, true); event.accepted = true; }')
replace('''                            Column {
                                id: appsCol''', '''                            MouseArea {
                                width: appsFlick.contentWidth; height: appsFlick.contentHeight
                                acceptedButtons: Qt.NoButton
                                scrollGestureEnabled: false
                                onWheel: event => { appsScroller.wheel(event); event.accepted = true; }
                            }
                            Column {
                                id: appsCol''')
# Apply mouse deltas immediately; Flickable movement signals can interrupt easing.
s = s.replace('appsScroller.feed(event, true);', 'appsScroller.wheel(event);')
s = s.replace('onWheel: event => { appsScroller.feed(event); event.accepted = true; }', 'onWheel: event => { appsScroller.wheel(event); event.accepted = true; }')
if 'function wheel(w) {' not in s:
    replace('''                            function feed(w, mouseWheel) {''', '''                            function wheel(w) {
                                revealAnim.stop();
                                appsPadEnd.stop();
                                stop();
                                appsFlick.cancelFlick();
                                appsFlick.contentY = clampY(appsFlick.contentY - w.angleDelta.y / 120 * root.appsWheelStep);
                            }
                            function feed(w, mouseWheel) {''')
replace('''                            function wheel(w) {
                                revealAnim.stop();
                                appsPadEnd.stop();
                                stop();
                                appsFlick.cancelFlick();
                                appsFlick.contentY = clampY(appsFlick.contentY - w.angleDelta.y / 120 * root.appsWheelStep);
                            }''', '''                            function wheel(w) {
                                revealAnim.stop();
                                appsPadEnd.stop();
                                if (mode !== 1) {
                                    appsFlick.cancelFlick();
                                    target = appsFlick.contentY;
                                }
                                target = clampY(target - w.angleDelta.y / 120 * root.appsWheelStep);
                                mode = 1;
                            }''')
replace('                property bool lpFromOpen: false',
        '                property bool lpFromOpen: false\n                property real lpStart: 0')
replace('''                        lpFromOpen = pop === "spot" && spMode === "apps" && lp > 0.5;
                        lpGesture = true;
                        lpVel = 0;
                        lpT = Date.now();
                        if (!lpFromOpen) { lp = 0; lpShow(); lp = 0; }''', '''                        lpFromOpen = pop === "spot" && spMode === "apps";
                        lpStart = spMode === "apps" ? lp : 0;
                        lpGesture = true;
                        lpVel = 0;
                        lpT = Date.now();
                        if (pop !== "spot" || spMode !== "apps") lpShow();''')
if 'var t = lpStart + amt / ' not in s:
    replace('var t = lpFromOpen ? 1 + amt / 0.45 : amt / 0.35;',
            'var t = lpStart + amt / (amt < 0 ? 0.45 : 0.35);')
replace('''                        if (ui.lpGesture) return;
                        if (ui.pop === "spot") {''', '''                        if (ui.lpGesture) { ui.lpGesture = false; ui.lpVel = 0; }
                        if (ui.pop === "spot") {''')
# A close can arrive before the first spring frame, when lp is still zero.
# Always reverse the running spring instead of letting it continue invisibly.
replace('} else if (spMode === "apps" && lp > 0 && !lpGesture) lpAnimate(0);',
        '} else if (spMode === "apps" && !lpGesture) lpAnimate(0);')
s = s.replace("// Launchpad transition, all derived from ui.lp (so a pinch scrubs it both ways): the glass is there within\n                        // the first quarter, the content comes from blurred to sharp, and every icon settles from 126 % to 100 %,", "// Launchpad transition follows ui.lp: the glass fades gradually, the content sharpens,\n                        // and every icon settles from 126 % to 100 %,")
# Upgrade both previous panel fade variants, preserving the independent icon fade.
s = s.replace('''                        opacity: root.reduceMotion ? 1 : Math.min(1, t)
                        layer.enabled: !root.reduceMotion && t < 0.997
                        visible: ui.spMode === "apps" && t > 0.001''', '''                        visible: ui.spMode === "apps" && t > 0.001''')
s = s.replace('''                        opacity: root.reduceMotion ? 1 : Math.min(1, t)
                        visible: ui.spMode === "apps" && t > 0.001''', '''                        visible: ui.spMode === "apps" && t > 0.001''')
if 'id: appsGlassLayer' not in s:
    replace(
    '''                        GGlass { anchors.fill: parent; gx: spg; cornerR: 32; thickness: 34; strengthMul: 1.0; shadowAmt: 0.22 }
                        MenuBorder { amount: 0.3; anchors.fill: parent; cornerR: 32; dark: root.panelDarkMode; tint: root.menuBorderColor }

                        Item {
                        id: appsBody''',
    '''                        Item {
                            anchors.fill: parent
                            opacity: root.reduceMotion ? 1 : Math.pow(Math.min(1, appsPanel.t), 1.35)
                            layer.enabled: !root.reduceMotion && appsPanel.t < 0.997
                            layer.sourceRect: Qt.rect(-10, -10, width + 20, height + 20)
                            GGlass { anchors.fill: parent; gx: spg; cornerR: 32; thickness: 34; strengthMul: 1.0; shadowAmt: 0.22 }
                        }

                        Item {
                        id: appsBody''')
# Rapid reversals should move in the newly requested direction immediately.
replace('var opening = goal > 0.5, w = opening ? 11.0 : 20.0, z = opening ? 0.97 : 0.96;',
        'var opening = goal > 0.5, w = opening ? 17.0 : 22.0, z = opening ? 0.97 : 0.96;')
if 'var direction = to > lp ? 1 : (to < lp ? -1 : 0);' not in s:
    replace(
    '''                    lpSpring.goal = to;
                    if (vel !== undefined) lpSpring.velocity = vel;
                    if (!lpSpring.running) lpSpring.start();''',
    '''                    var direction = to > lp ? 1 : (to < lp ? -1 : 0);
                    lpSpring.goal = to;
                    if (vel !== undefined) lpSpring.velocity = vel;
                    if (direction !== 0 && lpSpring.velocity * direction < 1.2)
                        lpSpring.velocity = direction * 1.2;
                    if (!lpSpring.running) lpSpring.start();''')
# Keep the first part of the glass fade visible during rapid reversals.
s = s.replace('Math.pow(Math.min(1, appsPanel.t), 1.7)', 'Math.pow(Math.min(1, appsPanel.t), 1.35)')
# Keep the offscreen glass geometry unchanged throughout the transition.
# A sourceRect larger than the item was scaled into its bounds, then snapped
# back to normal when the layer was disabled near the end of the animation.
old_glass = '''                        Item {
                            anchors.fill: parent
                            opacity: root.reduceMotion ? 1 : Math.pow(Math.min(1, appsPanel.t), 1.35)
                            layer.enabled: !root.reduceMotion && appsPanel.t < 0.997
                            layer.sourceRect: Qt.rect(-10, -10, width + 20, height + 20)
                            GGlass { anchors.fill: parent; gx: spg; cornerR: 32; thickness: 34; strengthMul: 1.0; shadowAmt: 0.22 }
                        }'''
new_glass = '''                        Item {
                            id: appsGlassLayer
                            x: -10; y: -10
                            width: appsPanel.width + 20; height: appsPanel.height + 20
                            opacity: root.reduceMotion ? 1 : Math.pow(Math.min(1, appsPanel.t), 1.35)
                            layer.enabled: true
                            GGlass { x: 10; y: 10; width: appsPanel.width; height: appsPanel.height; gx: spg; cornerR: 32; thickness: 34; strengthMul: 1.0; shadowAmt: 0; flatInner: 1 }
                        }'''
# The shifted shader shadow and dark inner rim create a second bottom contour.
# Keep the outer glass edge while removing both from this panel only.
s = s.replace('GGlass { x: 10; y: 10; width: appsPanel.width; height: appsPanel.height; gx: spg; cornerR: 32; thickness: 34; strengthMul: 1.0; shadowAmt: 0.22 }', 'GGlass { x: 10; y: 10; width: appsPanel.width; height: appsPanel.height; gx: spg; cornerR: 32; thickness: 34; strengthMul: 1.0; shadowAmt: 0; flatInner: 1 }')
if old_glass in s:
    s = s.replace(old_glass, new_glass, 1)
elif new_glass not in s and 'id: appsStage' not in s:
    raise SystemExit('Applications panel tuning: glass layer missing')
# WheelHandler defaults to mouse-only. Give touchpad gestures their own path;
# Linux can provide angleDelta even when pixelDelta is unavailable.
replace(
    '''                        Timer {
                            id: appsPadEnd''',
    '''                        WheelHandler {
                            parent: appsFlick
                            target: null
                            acceptedDevices: PointerDevice.TouchPad
                            orientation: Qt.Vertical
                            onWheel: event => { appsScroller.feed(event, false); event.accepted = true; }
                        }
                        Timer {
                            id: appsPadEnd''')
replace('var pad = !mouseWheel && w.pixelDelta.y !== 0;', 'var pad = !mouseWheel;')
# ── Whole-panel entrance ──
# The glass frame and the content share one stage: it settles from 114 % to 100 % and from blurred to sharp as a
# single picture (one offscreen pass and one blur for both), instead of only the icons zooming inside a frame that
# merely faded. The icons keep a smaller staggered zoom of their own on top.
if 'readonly property real zoom: root.reduceMotion' not in s:
    replace('''                        readonly property real blurAmt: root.reduceMotion ? 0 : Math.max(0, 1 - t) * 0.95
''', '''                        readonly property real blurAmt: root.reduceMotion ? 0 : Math.max(0, 1 - t) * 0.95
                        readonly property real zoom: root.reduceMotion ? 1 : 1 + 0.14 * Math.max(0, 1 - t)
''')
old_stage = new_glass + '''

                        Item {
                        id: appsBody
                        anchors.fill: parent
                        transformOrigin: Item.Center
                        opacity: root.reduceMotion ? 1 : Math.pow(Math.min(1, appsPanel.t), 0.55)
                        layer.enabled: appsPanel.blurAmt > 0.003
                        layer.smooth: true
                        layer.effect: MultiEffect {
                            blurEnabled: true
                            blurMax: 32
                            blur: appsPanel.blurAmt
                            autoPaddingEnabled: true
                        }
'''
new_stage = '''                        Item {
                        id: appsStage
                        x: -10; y: -10
                        width: appsPanel.width + 20; height: appsPanel.height + 20
                        transformOrigin: Item.Center
                        scale: appsPanel.zoom
                        layer.enabled: appsPanel.blurAmt > 0.003
                        layer.smooth: true
                        layer.effect: MultiEffect {
                            blurEnabled: true
                            blurMax: 32
                            blur: appsPanel.blurAmt
                            autoPaddingEnabled: true
                        }
                        Item {
                            id: appsGlassLayer
                            anchors.fill: parent
                            opacity: root.reduceMotion ? 1 : Math.pow(Math.min(1, appsPanel.t), 1.35)
                            layer.enabled: true
                            GGlass { x: 10; y: 10; width: appsPanel.width; height: appsPanel.height; gx: spg; cornerR: 32; thickness: 34; strengthMul: 1.0; shadowAmt: 0; flatInner: 1 }
                        }

                        Item {
                        id: appsBody
                        x: 10; y: 10
                        width: appsPanel.width; height: appsPanel.height
                        opacity: root.reduceMotion ? 1 : Math.pow(Math.min(1, appsPanel.t), 0.55)
'''
if 'id: appsStage' not in s:
    if old_stage not in s:
        raise SystemExit('Applications panel tuning: stage anchor missing')
    s = s.replace(old_stage, new_stage, 1)
    end_old = '''
                        }

                        // ── Scrolling, frame-synced ──'''
    if s.count(end_old) != 1:
        raise SystemExit('Applications panel tuning: end of the panel body not found')
    s = s.replace(end_old, '''
                        }
                        }

                        // ── Scrolling, frame-synced ──''', 1)
replace('scale: 1 + 0.26 * (1 - tileReveal)', 'scale: 1 + 0.12 * (1 - tileReveal)')
s = s.replace("// Launchpad transition follows ui.lp: the glass fades gradually, the content sharpens,\n                        // and every icon settles from 126 % to 100 %,", "// Launchpad transition follows ui.lp: glass and content settle together from 114 % to 100 % and from\n                        // blurred to sharp (appsStage), and every icon adds a small zoom of its own,")
# ── Pinch: less finger travel ──
# A quarter of the spread opens it fully (was 35 %), and letting go a third of the way in is enough to finish.
replace("var t = lpStart + amt / (amt < 0 ? 0.45 : 0.35);",
        "var t = lpStart + amt / (amt < 0 ? 0.30 : 0.25);")
s = s.replace("// pinching in by ~35 % of the spread opens it fully; spreading by ~45 % closes it",
              "// pinching in by ~25 % of the spread opens it fully; spreading by ~30 % closes it")
replace("else to = lp > 0.5 ? 1 : 0;",
        "else to = lp > (lpFromOpen ? 0.67 : 0.33) ? 1 : 0;   // a third of the way is a decision")
# ── No stutter at the start of the motion ──
# The first frames after a toggle are the expensive ones (the panel's bindings wake up on opening: ~25 ms; the stage's
# offscreen pass and blur are set up again on closing: ~20 ms, measured at 90 Hz). Stepped by its real duration, such a
# frame made the panel jump ahead right after it started to move. For the first three frames after a (re)start or a
# change of direction the spring therefore advances by at most one display frame: a long frame only delays the motion
# by a few milliseconds. The stage is also set up in the very frame a close is requested, not two frames into it.
if 'property int fresh: 0' not in s:
    replace('''                    property real goal: 1
                    onTriggered: {
                        var dt = frameTime > 0 ? Math.min(0.05, frameTime) : 0;
                        if (dt <= 0) return;
''', '''                    property real goal: 1
                    property int fresh: 0
                    onTriggered: {
                        var dt = frameTime > 0 ? Math.min(0.05, frameTime) : 0;
                        if (dt <= 0) return;
                        if (fresh > 0) { fresh--; dt = Math.min(dt, 0.0125); }
''')
if 'lpSpring.fresh = 3;' not in s:
    replace('''                    var direction = to > lp ? 1 : (to < lp ? -1 : 0);
                    lpSpring.goal = to;
''', '''                    var direction = to > lp ? 1 : (to < lp ? -1 : 0);
                    if (lpSpring.goal !== to || !lpSpring.running) lpSpring.fresh = 3;
                    lpSpring.goal = to;
''')
if 'readonly property bool lpClosing' not in s:
    replace('''                property real lp: 0
                property bool lpGesture: false
''', '''                property real lp: 0
                readonly property bool lpClosing: lpSpring.running && lpSpring.goal < 0.5
                property bool lpGesture: false
''')
if 'appsPanel.blurAmt > 0.003 || ui.lpClosing' not in s:
    replace('''                        scale: appsPanel.zoom
                        layer.enabled: appsPanel.blurAmt > 0.003
''', '''                        scale: appsPanel.zoom
                        layer.enabled: appsPanel.blurAmt > 0.003 || ui.lpClosing
''')
# ── The first opening after login ──
# The very first time the panel is drawn, its shaders, offscreen passes, icon textures and glyphs are all created in
# one frame: ~200 ms with nothing on screen (measured), exactly when the animation should start. Three seconds after
# the shell starts the panel is therefore drawn once at 0.4 % opacity (below one 8-bit step: nothing is visible, no
# input is taken), so the first real opening is as smooth as every later one.
replace('''                property real lp: 0
                readonly property bool lpClosing: lpSpring.running && lpSpring.goal < 0.5
''', '''                property real lp: 0
                property bool lpWarm: false
                Timer {
                    interval: 3000
                    running: root.spotlightEnabled && !root.reduceMotion
                    onTriggered: {
                        if (ui.pop !== "" || ui.lp > 0 || ui.lpGesture || ui.spMode !== "home") return;
                        ui.lpWarm = true; ui.spMode = "apps"; ui.lp = 0.01;
                        lpWarmEnd.restart();
                    }
                }
                Timer {
                    id: lpWarmEnd
                    interval: 400
                    onTriggered: {
                        if (!ui.lpWarm) return;                 // an opening or a pinch took over (see lpAnimate, lpEvent)
                        ui.lpWarm = false;
                        ui.lp = 0;
                    }
                }
                readonly property bool lpClosing: lpSpring.running && lpSpring.goal < 0.5
''')
replace('''                    var direction = to > lp ? 1 : (to < lp ? -1 : 0);
                    if (lpSpring.goal !== to || !lpSpring.running) lpSpring.fresh = 3;
''', '''                    var direction = to > lp ? 1 : (to < lp ? -1 : 0);
                    lpWarm = false;
                    if (lpSpring.goal !== to || !lpSpring.running) lpSpring.fresh = 3;
''')
replace('''                        if (!root.spotlightEnabled) return;
                        lpSpring.running = false;
''', '''                        if (!root.spotlightEnabled) return;
                        lpWarm = false;
                        lpSpring.running = false;
''')
replace('''                        scale: appsPanel.zoom
                        layer.enabled: appsPanel.blurAmt > 0.003 || ui.lpClosing
''', '''                        scale: appsPanel.zoom
                        opacity: ui.lpWarm ? 0.004 : 1
                        layer.enabled: appsPanel.blurAmt > 0.003 || ui.lpClosing
''')
s = s.replace('                            property int dbgN: 0 // TESTONLY\n', '')
s = '\n'.join(line for line in s.split('\n') if 'console.log("WHEELDBG"' not in line)
for line in s.splitlines():
    if 'console.log("FLKDBG"' in line:
        s = s.replace(line, '                            onContentYChanged: if (dragging) { appsScroller.sample(contentY - lastDragY); lastDragY = contentY; }')
        break

# Touch-screen drag: Flickable writes contentY straight from each touch event, which arrive out of step with the
# display (uneven steps, the judder). The finger now only moves the scroller's target and the list follows it per
# frame, like the touchpad; any release, slow or fast, glides on with the same decay instead of stopping dead.
replace('''                            onContentYChanged: if (dragging) { appsScroller.sample(contentY - lastDragY); lastDragY = contentY; }
                            onFlickStarted: { var v = appsScroller.measured(); cancelFlick(); appsScroller.glide(v); }''',
        '''                            onContentYChanged: {
                                if (appsScroller.writing) return;
                                if (dragging) appsScroller.finger(contentY); else appsScroller.shown = contentY;
                            }
                            onDraggingChanged: if (!dragging && appsScroller.mode === 4) appsScroller.glide(appsScroller.measured())
                            onFlickStarted: cancelFlick()''')
replace('''                            property int mode: 0            // 0 idle · 1 wheel easing · 2 touchpad follow · 3 glide''',
        '''                            property int mode: 0            // 0 idle · 1 wheel easing · 2 touchpad follow · 3 glide · 4 finger follow
                            property real shown: 0          // the contentY on screen, restored when Flickable writes the finger's
                            property bool writing: false''')
if 'function finger(y) {' not in s:
    replace('''                            function glide(v) {
                                samples = [];
                                if (Math.abs(v) < 60) { if (mode === 2) mode = 1; else stop(); return; }   // no speed: just settle''',
        '''                            function finger(y) {
                                if (mode !== 4) {
                                    appsPadEnd.stop();
                                    vel = 0; samples = []; mode = 4;
                                    target = shown;
                                }
                                y = clampY(y);
                                sample(y - target);
                                target = y;
                                writing = true;
                                appsFlick.contentY = shown;
                                writing = false;
                            }
                            function glide(v) {
                                samples = [];
                                if (Math.abs(v) < 60) { if (mode === 2 || mode === 4) mode = 1; else stop(); return; }   // no speed: just settle''')
replace('''                                y += (target - y) * (1 - Math.exp(-dt * (mode === 1 ? 20 : 40)));
                                if (mode === 1 && Math.abs(target - y) < 0.5) { y = target; mode = 0; }
                                f.contentY = clampY(y);''',
        '''                                y += (target - y) * (1 - Math.exp(-dt * (mode === 1 ? 20 : mode === 4 ? 55 : 40)));
                                if (mode === 1 && Math.abs(target - y) < 0.5) { y = target; mode = 0; }
                                writing = true;
                                f.contentY = clampY(y);
                                shown = f.contentY;
                                writing = false;''')

# Touch-screen drag moves the list further than the finger (and so glides further on release).
replace('''    readonly property real appsGlideDecay: 1.7''',
        '''    readonly property real appsTouchScroll: 1.1        // touch-screen finger pixels → content pixels
    readonly property real appsGlideDecay: 1.7''')
replace('''                                    vel = 0; samples = []; mode = 4;
                                    target = shown;
                                }
                                y = clampY(y);
                                sample(y - target);
                                target = y;''', '''                                    vel = 0; samples = []; mode = 4;
                                    target = shown;
                                    fingerY = shown;   // Flickable measures the drag from where the list was at the press
                                }
                                var d = (y - fingerY) * root.appsTouchScroll;
                                fingerY = y;
                                var to = clampY(target + d);
                                sample(to - target);
                                target = to;''')
replace('''                            property bool writing: false''', '''                            property bool writing: false
                            property real fingerY: 0        // the last finger position Flickable reported''')

# Closing (Esc, a click outside, the Dock icon) only blurs and fades: the panel and its icons no longer zoom back up.
# zoomMix drops to 0 at once when a close starts from the open panel; a close released mid-pinch, or a reopening
# during the close, eases it instead so the size never jumps.
replace('''                        readonly property real zoom: root.reduceMotion ? 1 : 1 + 0.14 * Math.max(0, 1 - t)''',
        '''                        property real zoomMix: ui.lpClosing ? 0 : 1
                        Behavior on zoomMix {
                            enabled: !ui.lpClosing || appsPanel.t < 0.97
                            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                        }
                        readonly property real zoom: root.reduceMotion ? 1 : 1 + 0.14 * Math.max(0, 1 - t) * zoomMix''')
replace('''                                                    scale: 1 + 0.12 * (1 - tileReveal)''',
        '''                                                    scale: 1 + 0.12 * (1 - tileReveal) * appsPanel.zoomMix''')

# A plain close (Esc, a click outside, an app launched) is a short timed fade instead of the spring: the spring's
# acceleration and long settling tail read as a bounce. Openings and pinch releases (which carry a speed) keep it.
replace('''                    property int fresh: 0
                    onTriggered: {
                        var dt = frameTime > 0 ? Math.min(0.05, frameTime) : 0;
                        if (dt <= 0) return;
                        if (fresh > 0) { fresh--; dt = Math.min(dt, 0.0125); }''', '''                    property int fresh: 0
                    property bool fade: false           // timed close: lp eases from fadeFrom to 0 over fadeTime
                    property real fadeFrom: 1
                    property real fadeAt: 0
                    readonly property real fadeTime: 0.15
                    onTriggered: {
                        var dt = frameTime > 0 ? Math.min(0.05, frameTime) : 0;
                        if (dt <= 0) return;
                        if (fresh > 0) { fresh--; dt = Math.min(dt, 0.0125); }
                        if (fade) {
                            fadeAt += dt;
                            var k = Math.min(1, fadeAt / fadeTime);
                            ui.lp = fadeFrom * (1 - k) * (1 - k);   // ease-out: quick to start, no tail
                            if (k < 1) return;
                            ui.lp = 0;
                            fade = false;
                            running = false;
                            velocity = 0;
                            ui.lpSettled();
                            return;
                        }''')
replace('''                    lpWarm = false;
                    if (lpSpring.goal !== to || !lpSpring.running) lpSpring.fresh = 3;''', '''                    lpWarm = false;
                    if (lpSpring.goal !== to || !lpSpring.running) lpSpring.fresh = 3;
                    if (to === 0 && vel === undefined && lp > 0) {
                        if (!lpSpring.fade || !lpSpring.running) { lpSpring.fade = true; lpSpring.fadeFrom = lp; lpSpring.fadeAt = 0; lpSpring.fresh = 3; }
                        lpSpring.goal = 0;
                        lpSpring.velocity = 0;
                        if (!lpSpring.running) lpSpring.start();
                        return;
                    }
                    lpSpring.fade = false;''')


# The plain close is a single fade of the whole panel as one picture: while it runs the panel's own progress stays at
# 1 (no blur, no separate glass / content curves, no per-icon stagger, no zoom) and only its opacity follows ui.lp.
replace('''                property double lpT: 0
''', '''                property double lpT: 0
                readonly property bool lpFading: lpSpring.running && lpSpring.fade
''')
replace('''                        readonly property real t: ui.lp
''', '''                        readonly property real t: ui.lpFading ? 1 : ui.lp
                        opacity: ui.lpFading ? ui.lp : 1
''')

# Entrance colour order, like macOS: the light frosted glass is there first and the icons / text solidify on top of
# it. With the content leading (t^0.55) and the glass trailing (t^1.35), the first frames showed blurred icons over
# the dark window behind, darker than the finished panel, and the panel then lightened.
s = s.replace('opacity: root.reduceMotion || ui.lpFading ? 1 : Math.pow(Math.min(1, appsPanel.t), 1.35)', 'opacity: root.reduceMotion ? 1 : Math.pow(Math.min(1, appsPanel.t), 1.6)')
s = s.replace('opacity: root.reduceMotion ? 1 : Math.pow(Math.min(1, appsPanel.t), 1.35)', 'opacity: root.reduceMotion ? 1 : Math.pow(Math.min(1, appsPanel.t), 1.6)')
s = s.replace('opacity: root.reduceMotion ? 1 : Math.pow(Math.min(1, appsPanel.t), 0.5)', 'opacity: root.reduceMotion ? 1 : Math.pow(Math.min(1, appsPanel.t), 1.6)')   # glass starts faint, darkens evenly
s = s.replace('opacity: root.reduceMotion ? 1 : Math.pow(Math.min(1, appsPanel.t), 0.55)', 'opacity: root.reduceMotion ? 1 : Math.pow(Math.min(1, appsPanel.t), 1.8)')
s = s.replace('opacity: root.reduceMotion ? 1 : Math.pow(Math.min(1, appsPanel.t), 1.2)', 'opacity: root.reduceMotion ? 1 : Math.pow(Math.min(1, appsPanel.t), 1.8)')
s = s.replace('opacity: root.reduceMotion ? 1 : Math.pow(Math.min(1, appsPanel.t), 1.0)', 'opacity: root.reduceMotion ? 1 : Math.pow(Math.min(1, appsPanel.t), 1.6)')   # glass: fainter start

# The Applications panel's glass blurs captures of the windows behind it. Windows are only captured while glass over
# them is visible, so on opening every capture behind the panel started from nothing and the glass first blurred the
# dark placeholder (or an old frame) for a few frames, then jumped to the real, often lighter, windows. While the
# panel is closed, the windows in its area now keep a single snapshot every 1.5 s (no live stream), so it opens on a
# current picture of them.
if 'property bool warm: false' not in s:
    for old, new in [
        ('                        property rect region: Qt.rect(0, 0, 0, 0)',
         '                        property bool warm: false          // keep single snapshots of the windows in `region` while no glass is shown\n'
         '                        property rect region: Qt.rect(0, 0, 0, 0)'),
        ('                        property alias region: bd.region\n',
         '                        property alias region: bd.region\n                        property alias warm: bd.warm\n'),
        ('want: root.glassRealtime && sv.glassOn && gw.onGlass ? gw.tl : null',
         'want: root.glassRealtime && (sv.glassOn || bd.warm) && gw.onGlass ? gw.tl : null'),
        ('item.region = Qt.binding(function () { return Qt.rect(spot.x - 128, spot.y - 128, spot.width + 256, spot.height + 256); });',
         'item.region = Qt.binding(function () {\n'
         '                                    if (!spotWin.openish) {     // closed: where the Applications panel will open\n'
         '                                        var aw = appsPanel.panelW, ah = appsPanel.height;\n'
         '                                        return Qt.rect((spotRoot.sw - aw) / 2 - 128, (spotRoot.sh - ah) / 2 - 128, aw + 256, ah + 256);\n'
         '                                    }\n'
         '                                    return Qt.rect(spot.x - 128, spot.y - 128, spot.width + 256, spot.height + 256);\n'
         '                                });\n'
         '                                item.warm = Qt.binding(function () { return root.spotlightEnabled && !root.gaming; });'),
    ]:
        if s.count(old) != 1:
            raise SystemExit(f'Applications panel tuning: backdrop warm-up anchor missing: {old.strip()[:80]!r}')
        s = s.replace(old, new, 1)
if s != original:
    path.write_text(s)
