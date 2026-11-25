// Silky Omarchy: MacShell's Bluetooth backend (docs/02-macshell.md#蓝牙面板与设置页).
//
// State comes from BlueZ over D-Bus through Quickshell.Bluetooth, so the menu bar, the Control Center and Settings update
// on events instead of polling `bluetoothctl info` for every cached device. Actions that can fail or need the user go
// through assets/silky-bt-helper.py, which reports BlueZ's real error names and answers PIN / passkey requests.
//
// MacBar.qml keeps its old API (btOn, btDevices, connectBt, ...) as aliases and wrappers around this object.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import "I18n.js" as I18n

Scope {
    id: bt

    readonly property var adapter: Bluetooth.defaultAdapter
    property bool on: false
    readonly property bool blocked: adapter !== null && adapter.state === BluetoothAdapterState.Blocked
    readonly property string adapterName: adapter ? adapter.name : ""
    readonly property bool discoverable: adapter !== null && adapter.discoverable
    readonly property bool scanning: adapter !== null && adapter.discovering

    // [ { mac, name, named, icon, connected, paired, bat, busy } ], connected first, then paired, then by name
    property var devices: []
    readonly property var myDevices: devices.filter(function (d) { return d.paired || d.connected; })
    // macOS lists only nearby devices that announce a name; BlueZ names the rest after their address
    readonly property var nearby: devices.filter(function (d) { return !d.paired && !d.connected && d.named; })
    property int connectedCount: 0
    property string connectedName: ""

    property string busy: ""            // mac of the device an action is running for
    property string busyOp: ""          // connect | disconnect | forget
    property var errors: ({})           // mac -> message of the last failed action on that device
    property string error: ""           // the last message, for the compact Control Center list
    property var prompt: null           // open pairing request: { id, kind, mac, name, passkey, entered }

    // ── device list ──
    function iconFor(icon, name) {
        var i = icon || "";
        if (i.indexOf("audio-head") === 0 || i === "audio-card" && /bud|pod|pods|clip|ear|head/i.test(name)) return "headphones";
        if (i === "audio-card" || i.indexOf("audio-speaker") === 0 || i.indexOf("multimedia") === 0) return "speaker";
        if (i === "input-gaming") return "gamepad";
        if (i === "input-keyboard") return "keyboard";
        if (i === "input-tablet" || /trackpad|妙控板/i.test(name)) return "trackpad";
        if (i === "input-mouse") return "mouse";
        if (i === "phone") return "phone";
        if (i === "computer") return "computer";
        if (i.indexOf("video-display") === 0) return "monitor";
        var n = (name || "").toLowerCase();
        if (/headphone|headset|earbud|airpod|buds|freeclip|freebuds|wh-|wf-/.test(n)) return "headphones";
        if (/controller|gamepad|xbox|dualshock|dualsense|joy-con/.test(n)) return "gamepad";
        if (/keyboard|keychron/.test(n)) return "keyboard";
        if (/mouse|鼠标|mx master/.test(n)) return "mouse";
        if (/speaker|soundbar|homepod/.test(n)) return "speaker";
        if (/iphone|phone|galaxy|pixel/.test(n)) return "phone";
        return "bluetooth";
    }

    function device(mac) {
        var vals = Bluetooth.devices.values;
        for (var i = 0; i < vals.length; i++) if (vals[i].address === mac) return vals[i];
        return null;
    }

    function rebuild() {
        var vals = Bluetooth.devices.values, list = [], count = 0, first = "";
        for (var i = 0; i < vals.length; i++) {
            var d = vals[i];
            if (!d || !d.address) continue;
            var name = d.name || d.address;
            var named = d.deviceName !== "" || !/^([0-9A-F]{2}[-:]){5}[0-9A-F]{2}$/i.test(name);
            var st = d.state;
            var row = {
                mac: d.address, name: name, named: named, icon: iconFor(d.icon, name),
                connected: d.connected, paired: d.paired || d.bonded,
                bat: d.batteryAvailable ? String(Math.round(d.battery <= 1 ? d.battery * 100 : d.battery)) : "",
                busy: d.pairing || st === BluetoothDeviceState.Connecting || st === BluetoothDeviceState.Disconnecting
            };
            if (row.connected) { count++; if (!first) first = name; }
            list.push(row);
        }
        list.sort(function (a, b) {
            if (a.connected !== b.connected) return a.connected ? -1 : 1;
            if (a.paired !== b.paired) return a.paired ? -1 : 1;
            return a.name.localeCompare(b.name);
        });
        connectedCount = count;
        connectedName = count === 1 ? first : "";
        if (JSON.stringify(list) !== JSON.stringify(devices)) devices = list;
    }
    Timer { id: rebuildTimer; interval: 60; onTriggered: bt.rebuild() }
    function schedule() { rebuildTimer.restart(); }

    Instantiator {
        model: Bluetooth.devices
        delegate: Connections {
            required property var modelData
            target: modelData
            function onNameChanged() { bt.schedule(); }
            function onDeviceNameChanged() { bt.schedule(); }
            function onIconChanged() { bt.schedule(); }
            function onConnectedChanged() { bt.schedule(); }
            function onPairedChanged() { bt.schedule(); }
            function onBondedChanged() { bt.schedule(); }
            function onPairingChanged() { bt.schedule(); }
            function onStateChanged() { bt.schedule(); }
            function onBatteryChanged() { bt.schedule(); }
            function onBatteryAvailableChanged() { bt.schedule(); }
        }
        onObjectAdded: bt.schedule()
        onObjectRemoved: bt.schedule()
    }

    // ── adapter power ──
    function syncPower() { on = adapter !== null && adapter.enabled; }
    Connections {
        target: bt.adapter
        function onEnabledChanged() { bt.syncPower(); }
        function onStateChanged() { bt.syncPower(); }
    }
    onAdapterChanged: { syncPower(); schedule(); }
    Component.onCompleted: { syncPower(); rebuild(); }
    Timer { id: powerSettle; interval: 2500; onTriggered: bt.syncPower() }

    function setPower(v) {
        on = v;                                  // optimistic, corrected by the adapter's signal or powerSettle
        if (v && (blocked || !adapter)) unblockProc.running = true;   // rfkill soft block (e.g. after Airplane Mode)
        else if (adapter) adapter.enabled = v;
        powerSettle.restart();
    }
    function toggle() { setPower(!on); }
    Process {
        id: unblockProc
        command: ["sh", "-c", "rfkill unblock bluetooth 2>/dev/null; sleep 0.4; exit 0"]
        onExited: { if (bt.adapter) bt.adapter.enabled = true; powerSettle.restart(); }
    }

    // ── discovery and visibility (Settings → Bluetooth keeps them on while it is open, like macOS) ──
    // Only what this page turned on is turned off again: another client may already be discovering (BlueZ runs one
    // discovery per client), and a computer that was discoverable before stays so.
    property int settingsOpen: 0
    property bool restoreDiscoverable: true
    property bool startedDiscovery: false
    function showInSettings() {
        if (!adapter || !adapter.enabled) return;
        adapter.pairable = true;
        if (!adapter.discoverable) { restoreDiscoverable = false; adapter.discoverable = true; }
        scan();
    }
    function enterSettings() {
        settingsOpen++;
        if (settingsOpen !== 1) return;
        restoreDiscoverable = true;
        startedDiscovery = false;
        showInSettings();
    }
    function leaveSettings() {
        settingsOpen = Math.max(0, settingsOpen - 1);
        if (settingsOpen !== 0) return;
        if (adapter && startedDiscovery && adapter.discovering) adapter.discovering = false;
        if (adapter && !restoreDiscoverable && adapter.discoverable) adapter.discoverable = false;
        startedDiscovery = false;
        restoreDiscoverable = true;
        if (prompt) answer(false, "");
    }
    // Bluetooth switched on while Settings is open: become visible and search then.
    onOnChanged: if (on && settingsOpen > 0) showInSettings()
    function scan() {
        if (!adapter || !adapter.enabled || adapter.discovering) return;
        startedDiscovery = true;
        adapter.discovering = true;
    }

    // ── actions (through the helper) ──
    function setError(mac, msg) {
        var e = Object.assign({}, errors);
        if (msg) e[mac] = msg; else delete e[mac];
        errors = e;
        error = msg || "";
    }
    function clearErrors() { errors = ({}); error = ""; }

    function connectDevice(mac, connected) {
        if (!mac || busy !== "") return;
        run(connected ? "disconnect" : "connect", mac);
    }
    function forget(mac) { if (mac) run("forget", mac); }
    function cancelPairing() { if (busy !== "" && busyOp === "connect") send({ op: "cancel", mac: busy }); }
    function rename(mac, name) {
        var d = device(mac);
        if (d && name.trim() !== "") d.name = name.trim();
    }
    function run(op, mac) {
        setError(mac, "");
        busy = mac; busyOp = op;
        send({ op: op, mac: mac });
    }

    property var queue: []
    function send(obj) {
        var line = JSON.stringify(obj) + "\n";
        if (helper.running && helper.ready) helper.write(line);
        else { queue = queue.concat([line]); helper.running = true; }
    }

    function messageFor(code, op) {
        switch (code) {
        case "AuthenticationFailed": case "AuthenticationRejected":
            return I18n.tr("Pairing was rejected. Check the code and try again.");
        case "AuthenticationCanceled": case "Canceled":
            return I18n.tr("Pairing was canceled.");
        case "AuthenticationTimeout": case "ConnectionAttemptFailed": case "NoReply": case "Timeout":
            return op === "connect" ? I18n.tr("The device did not respond. Make sure it is on and nearby.") : I18n.tr("The device did not respond.");
        case "AlreadyExists": case "AlreadyConnected": case "InProgress":
            return "";
        case "NotReady":
            return I18n.tr("Bluetooth is not ready yet.");
        case "DoesNotExist":
            return I18n.tr("The device is no longer available.");
        case "br-connection-profile-unavailable": case "NotAvailable":
            return I18n.tr("This device has no profile this computer can use.");
        }
        return op === "disconnect" ? I18n.tr("Could not disconnect the device.")
             : op === "forget" ? I18n.tr("Could not remove the device.")
             : I18n.tr("Could not connect to the device.");
    }

    function onHelperEvent(ev) {
        if (ev.ev === "ready") {
            helper.ready = true;
            var q = queue; queue = [];
            for (var i = 0; i < q.length; i++) helper.write(q[i]);
        } else if (ev.ev === "done" || ev.ev === "error") {
            if (ev.mac === busy) { busy = ""; busyOp = ""; }
            if (ev.ev === "error") {
                var msg = messageFor(ev.code, ev.op);
                if (msg === "" && /profile-unavailable/.test(ev.message || "")) msg = messageFor("NotAvailable", ev.op);
                setError(ev.mac, msg);
            }
            if (prompt && prompt.mac === ev.mac) prompt = null;
            schedule();
        } else if (ev.ev === "request") {
            prompt = { id: ev.id, kind: ev.kind, mac: ev.mac, name: ev.name || ev.mac, passkey: ev.passkey || "", entered: ev.entered || 0 };
        } else if (ev.ev === "cancel") {
            prompt = null;
        }
    }
    function answer(ok, value) {
        var p = prompt;
        prompt = null;
        if (!p) return;
        if (p.kind === "display-pin" || p.kind === "display-passkey") { if (!ok) cancelPairing(); return; }
        send({ op: "reply", id: p.id, ok: ok, value: value || "" });
    }

    Process {
        id: helper
        property bool ready: false
        command: ["/usr/bin/python3", decodeURIComponent(String(Qt.resolvedUrl("assets/silky-bt-helper.py")).replace(/^file:\/\//, ""))]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: data => { try { bt.onHelperEvent(JSON.parse(data)); } catch (e) {} }
        }
        onRunningChanged: if (!running) {
            var wasReady = ready;
            ready = false;
            bt.prompt = null;
            if (bt.busy !== "") { bt.setError(bt.busy, bt.messageFor("", bt.busyOp)); bt.busy = ""; bt.busyOp = ""; }
            // idle exit with work queued meanwhile: start again; a helper that never came up is not retried in a loop
            if (bt.queue.length > 0) { if (wasReady) running = true; else bt.queue = []; }
        }
    }
}
