import QtQuick
import Quickshell
import Quickshell.Io

// Hardware state and toggle bridge for Omarchy's built-in / external touchscreen controls.
Item {
    id: ctrl
    visible: false

    property bool ready: false
    property bool busy: false
    property bool hasDevice: false
    property string deviceName: ""
    property bool touchEnabled: true

    function refresh() {
        if (probeProc.running) return;
        probeProc.running = true;
    }

    function setTouchEnabled(enable) {
        if (busy || !hasDevice) return;
        busy = true;
        touchEnabled = enable;
        toggleProc.targetState = enable ? "on" : "off";
        toggleProc.command = ["omarchy", "device", "touchscreen", toggleProc.targetState];
        toggleProc.running = true;
    }

    Process {
        id: probeProc
        command: [
            "sh", "-c",
            "dev=$(omarchy-hw-touchscreen 2>/dev/null || true); " +
            "if [ -z \"$dev\" ]; then dev=$(hyprctl devices -j 2>/dev/null | jq -r '.touch[0].name // empty' 2>/dev/null || true); fi; " +
            "dis=0; [ -f \"$HOME/.local/state/omarchy/toggles/hypr/touchscreen-disabled-name\" ] && dis=1; " +
            "printf '%s\\n%s\\n' \"$dev\" \"$dis\""
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = String(text || "").split("\n");
                var dev = (lines[0] || "").trim();
                var disabled = (lines[1] || "").trim() === "1";
                ctrl.deviceName = dev;
                ctrl.hasDevice = dev !== "";
                ctrl.touchEnabled = !disabled;
                ctrl.ready = true;
            }
        }
    }

    Process {
        id: toggleProc
        property string targetState: "on"
        onExited: {
            ctrl.busy = false;
            ctrl.refresh();
        }
    }

    Component.onCompleted: refresh()
}
