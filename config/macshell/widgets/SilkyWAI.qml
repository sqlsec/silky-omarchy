// AI usage today: Claude Code and Codex from their local session logs, DeepSeek from its balance API.
// Every provider is shown the same way: badge + name, one main figure, its caption, two detail lines.
//   Claude   tokens today      · requests, output tokens
//   Codex    5-hour quota left · this week's quota left, next reset   (remaining, as the Codex app shows it)
//   DeepSeek spent today       · balance                               (needs an API key, right-click)
//   small = one row per provider; medium = three columns; large = columns + tokens per hour + quota resets
import QtQuick
import "SilkyWidgetsFormat.js" as F

Item {
    id: w
    required property var host
    readonly property var d: host.info ? host.info.ai : null
    readonly property var claude: d ? d.claude : null
    readonly property var codex: d ? d.codex : null
    readonly property var ds: d ? d.deepseek : null
    readonly property bool dsReady: ds !== null && ds.configured === true && !ds.error

    readonly property var providers: [
        // brand colours; logos are fetched by the installer into assets/ai-logos (LobeHub icons, see docs)
        { key: "claude", name: "Claude", glyph: "✳", color: "#d97757", inset: 0.18 },
        { key: "codex", name: "Codex", glyph: "◎", color: "#7a6cff", inset: 0 },
        { key: "deepseek", name: "DeepSeek", glyph: "◆", color: "#4d6bfe", inset: 0.14 }
    ]
    function remaining(win) { return win && typeof win.left === "number" ? win.left : null; }
    function pct(v) { return v === null ? "—" : Math.round(v) + "%"; }
    // when a quota window resets: today → "14:31", later → "11月25日 07:15" / "Nov 25 07:15"
    function resetText(win) {
        if (!win) return "";
        if (!win.resetsAt) return F.tr("Fresh window");
        var t = new Date(win.resetsAt * 1000), now = new Date();
        var clock = Qt.formatTime(t, "hh:mm");
        if (t.toDateString() === now.toDateString()) return clock + " " + F.tr("resets");
        return (F.zh() ? (t.getMonth() + 1) + "月" + t.getDate() + "日 " : Qt.formatDate(t, "MMM d") + " ") + clock + " " + F.tr("resets");
    }

    // [main figure, caption, detail 1, detail 2] per provider
    function figures(key) {
        if (key === "claude") {
            if (!claude) return ["—", F.tr("tokens today"), F.tr("No logs"), ""];
            if (claude.limited)      // Claude Code refused a request: the plan limit is used up until the reset
                return ["0%", F.tr(claude.limited.type === "five_hour" ? "5-hour quota left" : "Weekly quota left"),
                        F.tr("Limit reached"), resetText({ resetsAt: claude.limited.resetsAt })];
            return [F.compact(claude.tokens), F.tr("tokens today"),
                    F.tr("Requests") + " " + claude.requests, F.tr("Output") + " " + F.compact(claude.output)];
        }
        if (key === "codex") {
            if (!codex) return ["—", F.tr("5-hour quota left"), F.tr("No logs"), ""];
            return [pct(remaining(codex.primary)), F.tr("5-hour quota left"),
                    F.tr("Week left") + " " + pct(remaining(codex.secondary)), resetText(codex.primary)];
        }
        if (!ds || !ds.configured) return ["—", F.tr("spent today"), F.tr("Not set"), F.tr("Right-click to add a key")];
        if (ds.error) return ["—", F.tr("spent today"), F.tr("Key error"), ds.error];
        return [F.money(ds.spent, ds.currency), F.tr("spent today"), F.tr("Balance") + " " + F.money(ds.balance, ds.currency), ""];
    }
    // a quota bar where there is a quota (Codex, the 5-hour window); -1 = none
    function bar(key) {
        if (key === "claude") return claude && claude.limited ? 0 : -1;
        return key === "codex" && codex ? (remaining(codex.primary) === null ? -1 : remaining(codex.primary)) : -1;
    }
    function barInk(v) { return v <= 15 ? (w.host.dark ? "#ff6b61" : "#c4302b") : v <= 35 ? (w.host.dark ? "#ffb35c" : "#b45a0f") : providers[1].color; }

    SilkyWLabel { visible: !w.d; host: w.host; anchors.centerIn: parent; dim: true; text: F.tr("Loading…") }

    // (inline components cannot see this file's ids, so everything comes in as properties)
    // The real logo on a white rounded tile (like an app icon); a coloured letter tile if the logo is not installed.
    component Badge: Rectangle {
        id: badge
        property string key: ""
        property color tint: "white"
        property string glyph: ""
        property real inset: 0.16           // the bare marks (Claude, DeepSeek) sit inside the tile; Codex's logo is the tile
        property real s: 20
        width: s; height: s; radius: s * 0.26
        color: logo.status === Image.Ready ? "white" : tint
        clip: true
        Image {
            id: logo
            anchors.fill: parent
            anchors.margins: badge.s * badge.inset
            source: badge.key ? Qt.resolvedUrl("assets/ai-logos/" + badge.key + ".svg") : ""
            sourceSize: Qt.size(badge.s * 3, badge.s * 3)
            fillMode: Image.PreserveAspectFit
            smooth: true
            visible: status === Image.Ready
        }
        Text {
            visible: logo.status !== Image.Ready
            anchors.centerIn: parent; text: badge.glyph; color: "white"; font.pixelSize: badge.s * 0.6; font.bold: true
        }
    }
    component Meter: Rectangle {
        property real value: 0          // 0..100
        property color ink: "white"
        property color trackInk: "gray"
        height: 4; radius: 2
        color: trackInk
        Rectangle { width: Math.max(4, parent.width * Math.min(100, parent.value) / 100); height: parent.height; radius: 2; color: parent.ink }
    }

    // ───── small: one row per provider ─────
    Column {
        visible: w.d !== null && w.host.size === "small"
        x: 14; y: 13; width: parent.width - 28
        spacing: 6
        SilkyWLabel { host: w.host; dim: true; strong: true; px: 12; text: F.tr("AI usage today") }
        Repeater {
            model: w.providers
            Item {
                required property var modelData
                readonly property var f: w.figures(modelData.key)
                readonly property real q: w.bar(modelData.key)
                width: parent.width; height: 36
                Badge { key: modelData.key; tint: modelData.color; glyph: modelData.glyph; inset: modelData.inset; s: 22; y: 3 }
                SilkyWLabel { id: value; anchors.right: parent.right; y: 1; host: w.host; strong: true; px: 15; text: parent.f[0] }
                SilkyWLabel { x: 30; y: 1; width: value.x - 34; host: w.host; strong: true; px: 12; text: modelData.name }
                SilkyWLabel { x: 30; y: 18; width: parent.width - 30 - (parent.q >= 0 ? 62 : 0); host: w.host; dim: true; px: 10; text: parent.f[1] }
                // the quota bar sits on the caption line, right-aligned under the figure
                Meter {
                    visible: parent.q >= 0
                    anchors.right: parent.right; y: 23; width: 56
                    value: parent.q; ink: w.barInk(parent.q); trackInk: w.host.track
                }
            }
        }
    }

    // ───── medium / large: three columns ─────
    Row {
        id: cols
        visible: w.d !== null && w.host.size !== "small"
        x: 14; y: 14
        width: parent.width - 28
        Repeater {
            model: w.providers
            Item {
                required property var modelData
                required property int index
                readonly property var f: w.figures(modelData.key)
                readonly property real q: w.bar(modelData.key)
                readonly property real pad: index > 0 ? 10 : 0
                width: cols.width / 3; height: 144
                Rectangle { visible: index > 0; width: 1; height: parent.height - 8; y: 4; color: w.host.pal ? w.host.pal.sep : Qt.rgba(1, 1, 1, 0.12) }
                Row {
                    x: parent.pad
                    spacing: 6
                    Badge { key: modelData.key; tint: modelData.color; glyph: modelData.glyph; inset: modelData.inset; s: 20 }
                    SilkyWLabel { anchors.verticalCenter: parent.verticalCenter; host: w.host; strong: true; px: 13; text: modelData.name }
                }
                SilkyWLabel { x: parent.pad; y: 34; width: parent.width - parent.pad - 6; host: w.host; strong: true; px: 24; text: parent.f[0] }
                SilkyWLabel { x: parent.pad; y: 66; width: parent.width - parent.pad - 6; host: w.host; dim: true; px: 11; text: parent.f[1] }
                Meter {
                    x: parent.pad; y: 86; width: parent.width - parent.pad - 12
                    visible: parent.q >= 0
                    value: parent.q; ink: w.barInk(parent.q); trackInk: w.host.track
                }
                SilkyWLabel { x: parent.pad; y: 100; width: parent.width - parent.pad - 6; host: w.host; px: 11; text: parent.f[2] }
                SilkyWLabel { x: parent.pad; y: 118; width: parent.width - parent.pad - 6; host: w.host; dim: true; px: 11; text: parent.f[3] }
            }
        }
    }

    // ───── large: tokens per hour + quota windows ─────
    Item {
        visible: w.d !== null && w.host.size === "large"
        x: 14; y: 170; width: parent.width - 28; height: parent.height - y - 14
        Rectangle { width: parent.width; height: 1; color: w.host.pal ? w.host.pal.sep : Qt.rgba(1, 1, 1, 0.12) }
        SilkyWLabel { y: 10; host: w.host; dim: true; strong: true; px: 11; text: F.tr("Tokens per hour") }
        Row {
            anchors.right: parent.right; y: 10; spacing: 10
            Repeater {
                model: w.providers.slice(0, 2)
                Row {
                    required property var modelData
                    spacing: 4
                    Rectangle { width: 8; height: 8; radius: 2; anchors.verticalCenter: parent.verticalCenter; color: modelData.color }
                    SilkyWLabel { host: w.host; dim: true; px: 10; text: modelData.name }
                }
            }
        }
        Item {
            id: chart
            y: 30; width: parent.width; height: 74
            readonly property var total: w.claude ? w.claude.hours.map((v, i) => v + (w.codex ? w.codex.hours[i] : 0))
                                                   : (w.codex ? w.codex.hours : [])
            readonly property real peakTokens: Math.max(1, Math.max.apply(null, total.length ? total : [0]))
            // stacked: Claude's colour fills the whole bar, Codex's share is drawn from the bottom
            SilkyWBars { anchors.fill: parent; values: chart.total; ceiling: chart.peakTokens; ink: w.providers[0].color; track: w.host.track; gap: 2 }
            SilkyWBars { anchors.fill: parent; visible: w.codex !== null; values: w.codex ? w.codex.hours : []; ceiling: chart.peakTokens
                         ink: w.providers[1].color; track: "transparent"; gap: 2 }
            Repeater {
                model: [0, 6, 12, 18]
                SilkyWLabel {
                    required property int modelData
                    x: chart.width * modelData / 24; y: chart.height + 2
                    host: w.host; dim: true; px: 9; text: modelData + (F.zh() ? "时" : "h")
                }
            }
        }
        Column {
            y: 122; width: parent.width
            spacing: 6
            Repeater {
                model: w.codex ? [{ label: F.tr("Codex 5-hour quota"), win: w.codex.primary }, { label: F.tr("Codex weekly quota"), win: w.codex.secondary }] : []
                Item {
                    required property var modelData
                    width: parent.width; height: 16
                    visible: modelData.win !== null
                    readonly property real v: w.remaining(modelData.win) === null ? 0 : w.remaining(modelData.win)
                    SilkyWLabel { width: 96; host: w.host; px: 11; text: modelData.label }
                    Meter { x: 100; width: 50; anchors.verticalCenter: parent.verticalCenter
                            value: parent.v; ink: w.barInk(parent.v); trackInk: w.host.track }
                    SilkyWLabel { anchors.right: parent.right; width: parent.width - 158; horizontalAlignment: Text.AlignRight; host: w.host; dim: true; px: 11
                                  text: F.tr("left") + " " + w.pct(w.remaining(modelData.win)) + " · " + w.resetText(modelData.win) }
                }
            }
        }
    }
}
