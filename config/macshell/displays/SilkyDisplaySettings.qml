import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "DisplayModes.js" as Modes

Scope {
    id: controller

    property var monitors: []
    property var saved: ({ primary: "", modes: {}, scales: {}, layouts: {} })
    readonly property string primary: saved.primary || ""
    property string error: ""
    property var preview: null
    property int seconds: 0
    readonly property bool busy: job !== null || preview !== null
    property var job: null
    property bool restoreSaved: false
    property bool refreshRequested: false

    FileView {
        id: settings
        path: Quickshell.env("HOME") + "/.config/macshell/displays.json"
        printErrors: false
        onLoaded: {
            try {
                const data = JSON.parse(text());
                if (data && typeof data === "object") controller.saved = data;
            } catch (error) {
                console.warn("MacShell display settings:", error);
            }
            controller.scheduleRestore();
        }
        onLoadFailed: controller.refresh()
        onSaveFailed: controller.error = "Could not save display settings."
    }

    function save(data) {
        saved = data;
        settings.setText(JSON.stringify(data, null, 2));
    }

    function setPrimary(name) {
        save(Object.assign({}, saved, { primary: name }));
    }

    function refresh() {
        if (readMonitors.running) refreshRequested = true;
        else readMonitors.running = true;
    }

    function scheduleRestore() {
        restoreSaved = true;
        settle.restart();
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (["monitoradded", "monitoraddedv2", "monitorremoved", "configreloaded"].includes(event.name))
                controller.scheduleRestore();
        }
    }

    Timer { id: settle; interval: 400; onTriggered: controller.refresh() }
    Timer {
        id: countdown
        interval: 1000
        repeat: true
        onTriggered: {
            --controller.seconds;
            if (controller.seconds <= 0) controller.revert();
        }
    }

    Process {
        id: readMonitors
        command: ["hyprctl", "-j", "monitors"]
        stdout: StdioCollector { id: monitorOutput }
        onExited: code => {
            let list = null;
            try {
                if (code === 0) list = JSON.parse(monitorOutput.text);
            } catch (error) {
                console.warn("MacShell could not read monitors:", error);
            }
            if (Array.isArray(list)) {
                controller.monitors = list.filter(m => !m.disabled);
                if (controller.job && controller.job.verify && Date.now() >= controller.job.verifyAt) controller.verify();
                else if (controller.preview && (!controller.sameTopology(controller.preview)
                    || !controller.matchesTargets(controller.preview.targets, false))) controller.revert();
                else if (!controller.busy && controller.restoreSaved) controller.applySaved();
            } else if (controller.job && controller.job.verify && Date.now() >= controller.job.verifyAt) {
                controller.finish(false);
            }
            if (controller.refreshRequested) {
                controller.refreshRequested = false;
                Qt.callLater(controller.refresh);
            }
        }
    }

    Process {
        id: writeMonitors
        stdout: StdioCollector { id: commandOutput }
        onExited: code => {
            controller.job.verify = true;
            controller.job.verifyAt = Date.now() + 350;
            controller.job.accepted = code === 0 && commandOutput.text.trim() === "ok";
            settle.restart();
        }
    }

    function apply(targets, kind, previous, output = "") {
        job = { targets, kind, previous, output, verify: false,
            topology: Modes.layoutKey(Modes.layoutBoxes(monitors)) };
        const lua = targets.map(target => {
            // Named rules retain their other fields in Hyprland. Carry live rotation for fallback rules too.
            const name = JSON.stringify(target.name);
            const position = JSON.stringify(target.x + "x" + target.y);
            const mode = JSON.stringify(target.width + "x" + target.height + "@" + target.refreshRate);
            return `hl.monitor({ output = ${name}, mode = ${mode}, position = ${position}, scale = ${target.scale}, transform = ${target.transform} })`;
        }).join("\n");
        writeMonitors.exec(["hyprctl", "eval", lua]);
    }

    function matchesTargets(targets, allowDisconnected) {
        return targets.every(expected => {
            const actual = monitors.find(m => m.name === expected.name);
            if (!actual) return allowDisconnected;
            return Modes.matchesMode(actual, expected) && Math.abs(actual.scale - expected.scale) < 0.0001
                && actual.x === expected.x && actual.y === expected.y;
        });
    }

    function sameTopology(operation) {
        return operation.topology === Modes.layoutKey(Modes.layoutBoxes(monitors));
    }

    function verify() {
        // A successful eval only means the rule was accepted, so check the actual output state.
        finish(job.accepted && (job.kind !== "preview" || sameTopology(job))
            && matchesTargets(job.targets, job.kind === "revert"));
    }

    function finish(success) {
        const finished = job;
        job = null;
        if (finished.kind === "preview") {
            if (success) {
                preview = finished;
                seconds = 15;
                countdown.start();
            } else {
                error = "The display could not apply these settings.";
                apply(finished.previous, "revert", [], finished.output);
            }
        } else if (!success) {
            error = finished.kind === "revert" ? "Could not restore the previous display settings."
                                              : "Could not restore the saved display settings.";
            restoreSaved = false;
        } else if (restoreSaved) {
            applySaved();
        }
    }

    function tryChange(name, mode, scale) {
        const monitor = monitors.find(m => m.name === name);
        if (busy || !monitor || !Modes.validScale(mode, scale)) return;
        if (Modes.matchesMode(monitor, mode) && Math.abs(monitor.scale - scale) < 0.0001) return;
        error = "";
        const targets = Modes.plan(monitors, monitor, mode, scale);
        if (!targets.length) {
            error = "This setting would overlap another display.";
            return;
        }
        const previous = targets.map(target => monitors.find(m => m.name === target.name));
        apply(targets, "preview", previous, name);
    }

    function tryLayout(draft) {
        if (busy) return;
        const current = Modes.layoutBoxes(monitors);
        // A display may have disconnected or changed mode while the editor was open.
        if (current.length < 2 || Modes.layoutKey(current) !== Modes.layoutKey(draft)
            || !current.every(box => draft.some(d => d.name === box.name && d.width === box.width && d.height === box.height))) {
            error = "The connected displays changed. Open Arrange again.";
            return;
        }

        error = "";
        const boxes = current.map(box => {
            const placement = draft.find(d => d.name === box.name);
            return Object.assign({}, box, { x: Math.round(placement.x), y: Math.round(placement.y) });
        });
        if (!Modes.validLayout(boxes)) {
            error = "This setting would overlap another display.";
            return;
        }
        const moved = boxes.filter(box => box.x !== box.monitor.x || box.y !== box.monitor.y);
        if (!moved.length) return;
        const targets = moved.map(box => Object.assign({}, box.monitor, { x: box.x, y: box.y }));
        apply(targets, "preview", moved.map(box => box.monitor));
    }

    function keep() {
        if (!preview) return;
        const output = preview.output;
        const modes = Object.assign({}, saved.modes);
        const scales = Object.assign({}, saved.scales);
        const layouts = Object.assign({}, saved.layouts);
        if (output) {
            const applied = preview.targets.find(m => m.name === output);
            const previous = preview.previous.find(m => m.name === output);
            if (!Modes.matchesMode(previous, applied))
                modes[output] = applied.width + "x" + applied.height + "@" + applied.refreshRate;
            if (Math.abs(previous.scale - applied.scale) >= 0.0001)
                scales[output] = applied.scale;
        }

        // A later scale or mode change can shift neighboring screens in a saved arrangement.
        const boxes = Modes.layoutBoxes(monitors);
        const key = Modes.layoutKey(boxes);
        if (!output || layouts[key]) {
            const positions = {};
            for (const box of boxes) positions[box.name] = { x: box.x, y: box.y };
            layouts[key] = positions;
        }
        countdown.stop();
        preview = null;
        save(Object.assign({}, saved, { modes, scales, layouts }));
        if (restoreSaved) applySaved();
    }

    function revert() {
        if (!preview) return;
        const reverted = preview;
        countdown.stop();
        preview = null;
        const connected = reverted.previous.filter(old => monitors.some(m => m.name === old.name));
        if (connected.length) apply(connected, "revert", [], reverted.output);
        else if (restoreSaved) applySaved();
    }

    function savedMode(monitor) {
        const match = /^(\d+)x(\d+)@([\d.]+)$/.exec(saved.modes?.[monitor.name] || "");
        const candidate = match ? { width: Number(match[1]), height: Number(match[2]), hz: Number(match[3]) } : null;
        const current = { width: monitor.width, height: monitor.height, hz: monitor.refreshRate };
        const mode = candidate && Modes.modesOf(monitor).some(item =>
            item.width === candidate.width && item.height === candidate.height && Math.abs(item.hz - candidate.hz) < 0.01)
            ? candidate : current;
        // Old files with only a saved timing retain the live scale when compatible.
        let scale = Number(saved.scales?.[monitor.name]) || monitor.scale;
        if (!Modes.validScale(mode, scale)) scale = Modes.closest(Modes.availableScales(mode), scale);
        return { mode, scale };
    }

    function applySaved() {
        const boxes = Modes.layoutBoxes(monitors);
        const positions = saved.layouts?.[Modes.layoutKey(boxes)];
        if (positions && boxes.every(box => Number.isInteger(positions[box.name]?.x) && Number.isInteger(positions[box.name]?.y))) {
            const targets = boxes.map(box => {
                const { mode, scale } = savedMode(box.monitor);
                return Object.assign({}, box.monitor, positions[box.name], {
                    width: mode.width, height: mode.height, refreshRate: mode.hz, scale
                });
            });
            // Apply timing, scale and position together, so a restored layout never briefly overlaps.
            if (Modes.validLayout(Modes.layoutBoxes(targets))) {
                restoreSaved = false;
                const changed = targets.filter(target => !matchesTargets([target], false));
                if (changed.length) apply(changed, "saved", []);
                return;
            }
        }

        for (const { monitor } of boxes) {
            if (!saved.modes?.[monitor.name] && !saved.scales?.[monitor.name]) continue;
            const { mode, scale } = savedMode(monitor);
            if (Modes.matchesMode(monitor, mode) && Math.abs(monitor.scale - scale) < 0.0001) continue;
            const targets = Modes.plan(monitors, monitor, mode, scale);
            if (targets.length) {
                apply(targets, "saved", [], monitor.name);
                return;
            }
        }
        restoreSaved = false;
    }
}
