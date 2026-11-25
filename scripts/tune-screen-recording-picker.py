#!/usr/bin/env python3
"""Let Screen Recording pick a monitor or a region before it starts.

MacShell's Record button (Control Center, Apple menu, IPC) used to record the focused monitor straight away. Now a
slurp overlay comes up first: click a monitor to record all of it, drag to record a region, Esc to cancel. A region is
clipped to the monitor its top-left corner is on and rounded to even logical sizes, so the encoder gets a valid frame.
The Control Center closes before the overlay appears, so it is not left over the picked area.
"""
import sys
from pathlib import Path

path = Path(sys.argv[1])
source = path.read_text()
if "function recPickStart()" in source:
    sys.exit(0)


def replace_once(old, new, what):
    global source
    if source.count(old) != 1:
        sys.exit(f"Screen recording picker: expected one {what} in {path}")
    source = source.replace(old, new, 1)


# 1. The recorder takes either a whole output (-o) or a region (-g). The region is read into $geom first, because the
#    script's `set --` replaces the positional arguments.
replace_once(
    """            'f="$1"; out="$2"; pf=""",
    """            'f="$1"; out="$2"; geom="$3"; pf=""",
    "recorder argument names",
)
replace_once(
    """            '# with more than one monitor wf-recorder stops to ask which one (and fails with no terminal): record the focused one',
            '[ -n "$out" ] && set -- "$@" -o "$out"',""",
    """            '# with more than one monitor wf-recorder stops to ask which one (and fails with no terminal): record the picked one',
            '# Silky Omarchy: a region picked with slurp is recorded with -g, a whole monitor with -o',
            'if [ -n "$geom" ]; then set -- "$@" -g "$geom"; elif [ -n "$out" ]; then set -- "$@" -o "$out"; fi',""",
    "recorder output selection",
)
replace_once(
    """].join("\\n"), "sh", root.recordFile, Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""]""",
    """].join("\\n"), "sh", root.recordFile, root.recordOutput, root.recordGeom]""",
    "recorder arguments",
)

# 2. Starting a recording opens the picker; the old start runs once something is picked.
replace_once(
    """        if (!recording) {
            recordFile = Quickshell.env("HOME") + "/Videos/Screen-Recording-" + Qt.formatDateTime(new Date(), "yyyyMMdd-HHmmss") + ".mp4";
            recSecs = 0;""",
    """        if (!recording) {
            recPickStart();
        } else {
            recStartDelay.stop();
            recording = false;
            if (recRun) {
                // ask the recorder to finish (SIGINT: it writes the end of the file); recRun goes false when it has exited
                Quickshell.execDetached(["sh", "-c", "kill -INT \\"$(cat \\"${XDG_RUNTIME_DIR:-/tmp}/macbar-recorder.pid\\" 2>/dev/null)\\" 2>/dev/null || pkill -INT -x wf-recorder"]);
                recKill.restart();
            }
        }
    }
    // ── Silky Omarchy: pick what to record ──
    // A slurp overlay: click a monitor to record all of it, drag for a region, Esc cancels. The short delay lets the
    // Control Center finish closing so it is not on screen under the overlay.
    property string recordOutput: ""
    property string recordGeom: ""
    property bool recPicking: false
    function recPickStart() {
        if (recPicking || recRun) return;
        recPicking = true;
        recPickDelay.restart();
    }
    Timer { id: recPickDelay; interval: 220; onTriggered: recPick.running = true }
    Process {
        id: recPick
        // slurp reads extra boxes from stdin and waits for it to close before showing: give it /dev/null
        command: ["sh", "-c", "exec slurp \\"$@\\" </dev/null", "sh", "-o", "-d", "-b", "#00000059", "-c", "#0a84ffff", "-s", "#0a84ff1f",
                  "-B", "#ffffff0d", "-w", "2", "-f", "%o\\t%X\\t%Y\\t%W\\t%H"]
        stdout: StdioCollector { id: recPickOut }
        onExited: (code, status) => {
            root.recPicking = false;
            if (code !== 0) return;                                  // Esc / right click: nothing is recorded
            var p = recPickOut.text.trim().split("\\t");
            if (p.length !== 5) return;
            var scr = null;
            for (var i = 0; i < Quickshell.screens.length; i++) if (Quickshell.screens[i].name === p[0]) scr = Quickshell.screens[i];
            if (!scr) return;
            var x = Math.round(Number(p[1])), y = Math.round(Number(p[2])), w = Math.round(Number(p[3])), h = Math.round(Number(p[4]));
            if (x <= 0 && y <= 0 && w >= scr.width && h >= scr.height) root.recBegin(scr.name, "");
            else {
                w -= w % 2; h -= h % 2;                              // the encoder wants even frame sizes
                if (w < 16 || h < 16) return;
                root.recBegin(scr.name, (scr.x + x) + "," + (scr.y + y) + " " + w + "x" + h);
            }
        }
    }
    function recBegin(output, geom) {
        recordOutput = output;
        recordGeom = geom;
        if (!recording) {
            recordFile = Quickshell.env("HOME") + "/Videos/Screen-Recording-" + Qt.formatDateTime(new Date(), "yyyyMMdd-HHmmss") + ".mp4";
            recSecs = 0;""",
    "recording start",
)
replace_once(
    """            recording = true;                            // the glass captures go quiet right away ...
            recStartDelay.restart();                     // ... and the recorder follows once they have
        } else {
            recStartDelay.stop();
            recording = false;
            if (recRun) {
                // ask the recorder to finish (SIGINT: it writes the end of the file); recRun goes false when it has exited
                Quickshell.execDetached(["sh", "-c", "kill -INT \\"$(cat \\"${XDG_RUNTIME_DIR:-/tmp}/macbar-recorder.pid\\" 2>/dev/null)\\" 2>/dev/null || pkill -INT -x wf-recorder"]);
                recKill.restart();
            }
        }
    }""",
    """            recording = true;                            // the glass captures go quiet right away ...
            recStartDelay.restart();                     // ... and the recorder follows once they have
        }
    }""",
    "recording stop",
)

# 3. The Control Center button closes the panel before the picker comes up.
replace_once(
    """                            subtitle: root.recording ? root.recTime() : I18n.tr("Screen")
                            onClicked: root.toggleRecording()""",
    """                            subtitle: root.recording ? root.recTime() : I18n.tr("Screen")
                            onClicked: { if (!root.recording) ui.pop = ""; root.toggleRecording(); }""",
    "Control Center record button",
)

path.write_text(source)
