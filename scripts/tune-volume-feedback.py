#!/usr/bin/env python3
"""Play a feedback sound while the volume slider moves, at the new volume.

The sound goes through the default sink, so it follows the slider's level. It uses MacShell's pop.wav when that was
generated (macshell-make-sounds.py needs numpy) and the freedesktop volume-change sound otherwise. Taps are throttled
while dragging, and a trailing tap plays the level the slider stopped at.
"""
import sys
from pathlib import Path

path = Path(sys.argv[1])
source = path.read_text()
if "function volumeFeedback()" in source:
    sys.exit(0)

original = (
    "    function setVolume(v) { osdQuiet(\"volume\", 600); if (sink && sink.audio) { sink.audio.muted = false; "
    "sink.audio.volume = Math.max(0, Math.min(1, v)); } }\n"
)
if source.count(original) != 1:
    sys.exit(f"Volume feedback: expected one unmodified setVolume in {path}")

updated = (
    "    function setVolume(v) { osdQuiet(\"volume\", 600); if (sink && sink.audio) { sink.audio.muted = false; "
    "sink.audio.volume = Math.max(0, Math.min(1, v)); volumeFeedback(); } }\n"
    """    // Slider feedback: a tap through the default sink, so it is as loud as the level just set.
    property real volumeFeedbackLast: 0
    function volumeFeedback() {
        if (!uiSounds) return;
        var wait = 110 - (Date.now() - volumeFeedbackLast);
        if (wait > 0) { volumeFeedbackTimer.interval = wait; volumeFeedbackTimer.restart(); return; }
        volumeFeedbackTimer.stop();
        volumeFeedbackLast = Date.now();
        Quickshell.execDetached(["sh", "-c", "f=\\"$1/pop.wav\\"; [ -f \\"$f\\" ] || f=/usr/share/sounds/freedesktop/stereo/audio-volume-change.oga; "
            + "exec pw-play --volume=1 \\"$f\\"", "sh", soundDir]);
    }
    Timer { id: volumeFeedbackTimer; onTriggered: root.volumeFeedback() }
"""
)
path.write_text(source.replace(original, updated, 1))
