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
if s != original:
    path.write_text(s)
