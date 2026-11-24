// Local Claude Code and Codex usage plus the Gemini model quota from Antigravity.
// Every provider is shown the same way: badge + name, one main figure, its caption, two detail lines.
//   Claude   tokens today      · requests, output tokens
//   Codex    5-hour quota left · this week's quota left, next reset   (remaining, as the Codex app shows it)
//   Antigravity  Gemini 5-hour quota left · weekly quota left, next reset
//   small = one row per provider; medium = three columns; large = columns + tokens per hour + quota resets
import QtQuick
import "SilkyWidgetsFormat.js" as F

Item {
    id: w
    required property var host
    readonly property var d: host.info ? host.info.ai : null
    readonly property var claude: d ? d.claude : null
    readonly property var codex: d ? d.codex : null
    readonly property var antigravity: d ? d.antigravity : null
    readonly property var claudeQuota: claude ? claude.quota : null
    readonly property bool claudeUsesWeekly: !!claudeQuota && (remaining(claudeQuota.secondary) === 0 || !claudeQuota.primary)
    readonly property var claudeWindow: claudeQuota ? (claudeUsesWeekly ? claudeQuota.secondary : claudeQuota.primary) : null

    readonly property var providers: [
        // brand colours; logos are fetched by the installer into assets/ai-logos (LobeHub icons, see docs)
        { key: "claude", name: "Claude", glyph: "✳", color: "#d97757", inset: 0.18 },
        { key: "codex", name: "Codex", glyph: "◎", color: "#7a6cff", inset: 0 },
        { key: "antigravity", name: "Antigravity", glyph: "A", color: "#4285f4", inset: 0.14 }
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
            if (remaining(claudeWindow) !== null) {
                var other = claudeUsesWeekly ? claudeQuota.primary : claudeQuota.secondary;
                return [pct(remaining(claudeWindow)), F.tr(claudeUsesWeekly ? "Weekly quota left" : "5-hour quota left"),
                        other ? F.tr(claudeUsesWeekly ? "5-hour quota left" : "Week left") + " " + pct(remaining(other)) : "",
                        remaining(claudeWindow) === 0 ? F.tr("Limit reached") : ""];
            }
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
        if (!antigravity) return ["—", F.tr("Quota unavailable"), F.tr("Gemini models"), ""];
        var primary = antigravity.primary, weekly = antigravity.secondary;
        return [pct(remaining(primary)), F.tr("5-hour quota left"),
                F.tr("Week left") + " " + pct(remaining(weekly)), resetText(primary)];
    }
    // A progress bar for the displayed quota, where one is available.
    function bar(key) {
        if (key === "claude") {
            var quota = remaining(claudeWindow);
            return quota !== null ? quota : claude && claude.limited ? 0 : -1;
        }
        var usage = key === "codex" ? codex : antigravity;
        var left = usage ? remaining(usage.primary) : null;
        return left === null ? -1 : left;
    }
    // Both 5-hour (primary) and weekly (secondary) remaining percentages for the compact dual-meter view.
    function quotas(key) {
        if (key === "claude") {
            if (claudeQuota)
                return { fiveHour: remaining(claudeQuota.primary), weekly: remaining(claudeQuota.secondary) };
            if (claude && claude.limited) {
                return claude.limited.type === "five_hour"
                    ? { fiveHour: 0, weekly: null }
                    : { fiveHour: null, weekly: 0 };
            }
            return { fiveHour: null, weekly: null };
        }
        var usage = key === "codex" ? codex : antigravity;
        if (!usage) return { fiveHour: null, weekly: null };
        return { fiveHour: remaining(usage.primary), weekly: remaining(usage.secondary) };
    }
    // 4-tier quota scale (remaining %): abundant (> 65%) green, normal (36-65%) cyan,
    // low (16-35%) amber, critical (<= 15%) red — mirrors the system load & battery palette.
    function barInk(v) {
        if (v <= 15) return w.host.dark ? "#ff453a" : "#c92a22";
        if (v <= 35) return w.host.dark ? "#ff9f0a" : "#b85d00";
        if (v <= 65) return w.host.dark ? "#64d2ff" : "#0071a4";
        return w.host.dark ? "#30d158" : "#1c8241";
    }

    SilkyWLabel { visible: !w.d; host: w.host; anchors.centerIn: parent; dim: true; text: F.tr("Loading…") }

    // (inline components cannot see this file's ids, so everything comes in as properties)
    // The real logo on a white rounded tile (like an app icon); a coloured letter tile if the logo is not installed.
    component Badge: Rectangle {
        id: badge
        property string key: ""
        property color tint: "white"
        property string glyph: ""
        property real inset: 0.16           // Bare marks sit inside the tile; Codex's logo is the tile.
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
        Rectangle {
            width: parent.width * Math.max(0, Math.min(100, parent.value)) / 100
            height: parent.height; radius: parent.radius; color: parent.ink
        }
    }
    component QuotaSlot: Item {
        required property var host
        property string label: ""
        property var value: null        // 0..100 or null
        property string display: "—"
        property color ink: "white"
        property bool muted: false      // e.g. 5h window blocked because weekly quota is exhausted
        height: 20
        SilkyWLabel { x: 0; y: 1; host: parent.host; dim: true; px: 10; text: parent.label }
        SilkyWLabel {
            anchors.right: parent.right; y: 0
            host: parent.host; strong: parent.value !== null && !parent.muted; dim: parent.value === null || parent.muted
            px: 11; text: parent.display
        }
        Meter {
            x: 0; y: 16; width: parent.width; height: 3; radius: 1.5
            value: parent.value === null ? 0 : parent.value
            ink: parent.value === null ? "transparent"
                : parent.muted ? (parent.host.dark ? Qt.rgba(1, 1, 1, 0.28) : Qt.rgba(0, 0, 0, 0.24))
                : parent.ink
            trackInk: parent.host.track
        }
    }

    // ───── small: one row per provider with 5h + weekly dual meters ─────
    Column {
        visible: w.d !== null && w.host.size === "small"
        x: 14; y: 12; width: parent.width - 28
        spacing: 7
        SilkyWLabel { host: w.host; dim: true; strong: true; px: 12; text: F.tr("AI usage today") }
        Repeater {
            model: w.providers
            Item {
                required property var modelData
                readonly property var qs: w.quotas(modelData.key)
                readonly property real slotW: (width - 32 - 8) / 2
                width: parent.width; height: 36
                Badge { key: modelData.key; tint: modelData.color; glyph: modelData.glyph; inset: modelData.inset; s: 24; y: 6 }
                SilkyWLabel { x: 32; y: 0; width: parent.width - 32; host: w.host; strong: true; px: 12; text: modelData.name }
                QuotaSlot {
                    x: 32; y: 16; width: parent.slotW
                    host: w.host; label: "5h"
                    value: parent.qs.fiveHour; display: w.pct(parent.qs.fiveHour)
                    muted: parent.qs.weekly === 0
                    ink: parent.qs.fiveHour === null ? "transparent" : w.barInk(parent.qs.fiveHour)
                }
                QuotaSlot {
                    x: 32 + parent.slotW + 8; y: 16; width: parent.slotW
                    host: w.host; label: F.tr("7d")
                    value: parent.qs.weekly; display: w.pct(parent.qs.weekly)
                    ink: parent.qs.weekly === null ? "transparent" : w.barInk(parent.qs.weekly)
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
