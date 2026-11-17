#!/usr/bin/env python3
"""Give the Settings navigation list a useful mouse-wheel step."""
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
s = path.read_text()
old = '''                    boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: navCol'''
new = '''                    boundsBehavior: Flickable.StopAtBounds
                    WheelHandler {
                        target: null
                        acceptedDevices: PointerDevice.Mouse
                        onWheel: event => {
                            navFlick.cancelFlick();
                            navFlick.contentY = Math.max(0, Math.min(
                                Math.max(0, navFlick.contentHeight - navFlick.height),
                                navFlick.contentY - event.angleDelta.y / 120 * 140));
                            event.accepted = true;
                        }
                    }
                Column {
                    id: navCol'''
# Upgrade earlier tuning as well as pristine installations.
previous = new.replace("                            navFlick.cancelFlick();", "                            // Leave pixel-based touchpad gestures to Flickable.\n                            if (event.pixelDelta.y !== 0) { event.accepted = false; return; }\n                            navFlick.cancelFlick();")
s = s.replace(previous, new)
if new not in s and "function wheel(delta) {" not in s:
    if old not in s:
        raise SystemExit('Settings scroll tuning: navigation list missing')
    s = s.replace(old, new, 1)
row = """                                id: navMa
                                anchors.fill: parent
                                onClicked:"""
tuned_row = """                                id: navMa
                                anchors.fill: parent
                                scrollGestureEnabled: false
                                onWheel: event => {
                                    navFlick.cancelFlick();
                                    navFlick.contentY = Math.max(0, Math.min(
                                        Math.max(0, navFlick.contentHeight - navFlick.height),
                                        navFlick.contentY - event.angleDelta.y / 120 * 140));
                                    event.accepted = true;
                                }
                                onClicked:"""
if tuned_row not in s and "navFlick.wheel(event.angleDelta.y);" not in s:
    if row not in s:
        raise SystemExit('Settings scroll tuning: navigation row missing')
    s = s.replace(row, tuned_row, 1)
# Accumulate wheel deltas and ease toward the target on each frame.
old_handler = """navFlick.cancelFlick();
                            navFlick.contentY = Math.max(0, Math.min(
                                Math.max(0, navFlick.contentHeight - navFlick.height),
                                navFlick.contentY - event.angleDelta.y / 120 * 140));"""
new_handler = "navFlick.wheel(event.angleDelta.y);"
s = s.replace(old_handler, new_handler)
old_row_handler = """navFlick.cancelFlick();
                                    navFlick.contentY = Math.max(0, Math.min(
                                        Math.max(0, navFlick.contentHeight - navFlick.height),
                                        navFlick.contentY - event.angleDelta.y / 120 * 140));"""
s = s.replace(old_row_handler, new_handler)
needle = """                    id: navFlick
                    layer.enabled: true"""
replacement = """                    id: navFlick
                    property real wheelTarget: 0
                    function wheel(delta) {
                        if (!navWheelAnimation.running) {
                            cancelFlick();
                            wheelTarget = contentY;
                        }
                        wheelTarget = Math.max(0, Math.min(Math.max(0, contentHeight - height), wheelTarget - delta / 120 * 140));
                        navWheelAnimation.running = true;
                    }
                    onDragStarted: navWheelAnimation.running = false
                    FrameAnimation {
                        id: navWheelAnimation
                        onTriggered: {
                            var maxY = Math.max(0, navFlick.contentHeight - navFlick.height);
                            navFlick.wheelTarget = Math.max(0, Math.min(maxY, navFlick.wheelTarget));
                            var y = navFlick.contentY + (navFlick.wheelTarget - navFlick.contentY) * (1 - Math.exp(-Math.min(frameTime, 0.05) * 24));
                            if (Math.abs(navFlick.wheelTarget - y) < 0.5) { y = navFlick.wheelTarget; running = false; }
                            navFlick.contentY = Math.max(0, Math.min(maxY, y));
                        }
                    }
                    layer.enabled: true"""
if replacement not in s:
    if needle not in s:
        raise SystemExit('Settings scroll tuning: navigation scroller missing')
    s = s.replace(needle, replacement, 1)
path.write_text(s)
