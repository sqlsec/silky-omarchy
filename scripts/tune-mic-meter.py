#!/usr/bin/env python3
"""Add a live input-level meter under the microphone slider on the Control Center's Sound page.

The meter reads the default source's peak through Quickshell's PwNodePeakMonitor, and only while the Sound page is
open and the microphone is not muted. The level is the linear peak (the top segments mean close to clipping); it rises at once and falls back slowly.
"""
import sys
from pathlib import Path

path = Path(sys.argv[1])
source = path.read_text()
if "id: ccMicMeter" in source:
    sys.exit(0)

anchor = """                                        leftKind: "mic"; rightKind: "mic"
                                        onMoved: v => root.setMicVolume(v)
                                    }
                                }
"""
if source.count(anchor) != 1:
    sys.exit(f"Mic meter: expected one Sound page microphone slider in {path}")

meter = """                                Item {
                                    id: ccMicMeter
                                    width: parent.width; height: 16
                                    PwNodePeakMonitor {
                                        id: micPeak
                                        node: root.micSource
                                        enabled: ccSoundPage.shown && !root.micMuted
                                    }
                                    // Linear peak, so a quiet room sits low and speech jumps; falls back gently, like a hardware meter.
                                    property real level: 0
                                    readonly property real target: micPeak.enabled ? Math.max(0, Math.min(1, micPeak.peak)) : 0
                                    onTargetChanged: if (target > level) level = target
                                    Timer {
                                        interval: 33; repeat: true
                                        running: ccMicMeter.level > 0 || ccMicMeter.target > 0
                                        onTriggered: ccMicMeter.level = Math.max(ccMicMeter.target, ccMicMeter.level - 0.035)
                                    }
                                    Row {
                                        id: micBars
                                        x: 28; anchors.verticalCenter: parent.verticalCenter
                                        readonly property int count: 24
                                        spacing: 3
                                        Repeater {
                                            model: micBars.count
                                            Rectangle {
                                                required property int index
                                                readonly property real at: (index + 1) / micBars.count
                                                width: (ccMicMeter.width - 28 - 26 - micBars.spacing * (micBars.count - 1)) / micBars.count
                                                height: 6; radius: 3
                                                color: ccMicMeter.level >= at - 0.5 / micBars.count
                                                    ? (at > 0.9 ? "#ff453a" : at > 0.75 ? "#ffd60a" : "#30d158")
                                                    : ccPal.sep
                                                Behavior on color { ColorAnimation { duration: 60 } }
                                            }
                                        }
                                    }
                                }
"""
path.write_text(source.replace(anchor, anchor + meter, 1))
