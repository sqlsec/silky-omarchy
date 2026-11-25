// Silky Omarchy: Wi-Fi model for MacShell's menu-bar list and Settings → Wi-Fi (docs/02-macshell.md#wi-fi-面板与设置页).
//
// MacBar.qml keeps scanning through assets/silky-wifi-scan.py (see install-macshell-wifi.sh); this object turns that
// output into the macOS groups: known networks (matched by SSID, not by profile name, so "hidden-2021" is the known
// network "2021"), other networks, the security level of each, and the details shown by Option-click and "Details…"
// (assets/silky-wifi-info.py). It also forgets networks and switches Auto-Join.
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: wf
    property var bar: null

    property var known: []              // saved profiles: [{ uuid, name, ssid, autoconnect }]
    property var info: ({})             // silky-wifi-info.py output
    property int infoUsers: 0           // views that show details right now (Option-click list, Details sheet)
    property string actionError: ""

    // ── scan output → list rows ──
    // level: "open" (no encryption), "weak" (WEP, WPA1 / TKIP without WPA3), "ok"
    function securityLevel(sec) {
        var s = (sec || "").trim();
        if (s === "" || s === "--") return "open";
        if (/WEP|WPA1|TKIP/.test(s) && !/WPA3/.test(s)) return "weak";
        return "ok";
    }
    function parseScan(text) {
        var lines = text.split("\n"), profiles = [], bySsid = Object.create(null), best = Object.create(null), i;
        for (i = 0; i < lines.length; i++) {
            if (lines[i].indexOf("K:") !== 0) continue;
            try {
                var p = JSON.parse(lines[i].substring(2));
                profiles.push(p);
                if (!bySsid[p.ssid]) bySsid[p.ssid] = p;
            } catch (e) {}
        }
        for (i = 0; i < lines.length; i++) {
            if (lines[i].indexOf("N:") !== 0) continue;
            var f = bar.splitNm(lines[i].substring(2));
            if (f.length < 4 || f[1] === "") continue;
            var ssid = f[1], sig = parseInt(f[2]) || 0, sec = f[3], prof = bySsid[ssid];
            var n = {
                ssid: ssid, signal: sig, secure: (sec !== "" && sec !== "--"), level: securityLevel(sec),
                inUse: f[0] === "*", saved: prof !== undefined,
                uuid: prof ? prof.uuid : "", autoconnect: prof ? prof.autoconnect : false
            };
            var o = best[ssid];
            if (!o) best[ssid] = n;
            else {
                if (n.signal > o.signal) o.signal = n.signal;
                if (n.inUse) o.inUse = true;
                if (n.level === "weak") o.level = "weak";
            }
        }
        if (JSON.stringify(profiles) !== JSON.stringify(known)) known = profiles;
        var arr = [];
        for (var k in best) arr.push(best[k]);
        arr.sort(function (a, b) {
            if (a.inUse !== b.inUse) return a.inUse ? -1 : 1;
            if (a.saved !== b.saved) return a.saved ? -1 : 1;
            return b.signal - a.signal;
        });
        return arr;
    }

    readonly property var nets: bar ? bar.wifiNets : []
    readonly property var current: { for (var i = 0; i < nets.length; i++) if (nets[i].inUse) return nets[i]; return null; }
    readonly property var knownNearby: nets.filter(function (n) { return n.saved; })
    readonly property var others: nets.filter(function (n) { return !n.saved; })
    // Settings lists every saved network, also the ones out of range (no signal glyph then)
    readonly property var knownAll: {
        var out = [], seen = Object.create(null), i;
        for (i = 0; i < knownNearby.length; i++) { out.push(knownNearby[i]); seen[knownNearby[i].ssid] = true; }
        for (i = 0; i < known.length; i++) {
            var p = known[i];
            if (seen[p.ssid]) continue;
            seen[p.ssid] = true;
            out.push({ ssid: p.ssid, signal: -1, secure: true, level: "ok", inUse: false, saved: true, uuid: p.uuid, autoconnect: p.autoconnect });
        }
        return out;
    }
    function find(ssid) {
        var all = knownAll.concat(others);
        for (var i = 0; i < all.length; i++) if (all[i].ssid === ssid) return all[i];
        return null;
    }

    // ── actions ──
    function forget(uuid) { if (uuid) act(["nmcli", "connection", "delete", "uuid", uuid]); }
    function setAutoJoin(uuid, on) {
        if (uuid) act(["nmcli", "connection", "modify", "uuid", uuid, "connection.autoconnect", on ? "yes" : "no"]);
    }
    function act(cmd) {
        if (actProc.running) return;
        actionError = "";
        actProc.command = ["env", "LC_ALL=C"].concat(cmd);
        actProc.running = true;
    }
    Process {
        id: actProc
        stderr: StdioCollector { id: actErr }
        onExited: (code, status) => {
            if (code !== 0) wf.actionError = (actErr.text || "").trim().split("\n")[0].replace(/^Error:\s*/, "");
            if (wf.bar) { wf.bar.scanWifi(false); wf.bar.refreshWifi(); }
        }
    }

    // ── details (Option-click, Details…) ──
    function acquireInfo() { infoUsers++; refreshInfo(); }
    function releaseInfo() { infoUsers = Math.max(0, infoUsers - 1); }
    function refreshInfo() { if (!infoProc.running) infoProc.running = true; }
    Process {
        id: infoProc
        command: ["/usr/bin/python3", "-I", decodeURIComponent(String(Qt.resolvedUrl("assets/silky-wifi-info.py")).replace(/^file:\/\//, ""))]
        stdout: StdioCollector {
            onStreamFinished: { try { wf.info = JSON.parse(text); } catch (e) {} }
        }
    }
    Timer { interval: 2000; repeat: true; running: wf.infoUsers > 0; onTriggered: wf.refreshInfo() }

    // "149 (5 GHz, 40 MHz)"
    function channelText(i) {
        if (!i || !i.channel) return "";
        return i.channel + " (" + (i.band || "") + (i.width ? ", " + i.width + " MHz" : "") + ")";
    }
}
