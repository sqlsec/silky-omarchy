#!/usr/bin/env python3
"""Install the Silky widgets under MacShell's notifications, the notifications stacked by app, and one shared scroll."""
import argparse
import os
import shutil
import re
import stat
import urllib.request
from pathlib import Path
from tempfile import NamedTemporaryFile

import macshell_notification_center

SOURCE = Path(__file__).resolve().parents[1] / "config/macshell/widgets"
VERSIONS = {"0.5.1", "0.5.2", "0.5.3"}
NEEDS = ["WeatherIcon.qml", "ChinaCalendar.js", "I18n.js"]
# Brand logos for the AI usage widget, from LobeHub's MIT-licensed icon set (the logos are their owners' trademarks,
# so they are fetched at install time instead of being kept in this repository). Pinned for reproducibility.
LOGO_PACKAGE = "https://cdn.jsdelivr.net/npm/@lobehub/icons-static-svg@1.104.0/icons/"
LOGOS = {"claude": "claude-color.svg", "codex": "codex-color.svg", "antigravity": "antigravity-color.svg"}

# ───── MacBar patches ─────
# Earlier releases of this installer wrote FULL_H_V1 and a deck block beside the list; both are migrated.
FULL_H_OLD = ("                    property real fullH: 92 + (notifHist.count === 0 ? 70 : "
              "(root.notifClearing ? Math.max(70, nfl.height) : nfl.height)) + 14\n")
FULL_H_V1 = ("                    readonly property real silkyListH: notifHist.count === 0 ? 70 : "
             "(root.notifClearing ? Math.max(70, nfl.height) : nfl.height)\n"
             "                    // Silky widgets sit under the list (scripts/install-macshell-widgets.py)\n"
             "                    property real fullH: 92 + silkyListH + 14 + (silkyWidgetDeck.height > 0 ? silkyWidgetDeck.height + 6 : 0)\n")
FULL_H_PREVIOUS = ("                    // Silky: notifications and widgets scroll together in nfl (scripts/install-macshell-widgets.py)\n"
              "                    readonly property real silkyNotifH: notifHist.count === 0 ? 64 : ncol.height\n"
              "                    readonly property real silkyAvail: Math.max(160, (ui.height - dstY - 12) / ps - 92 - 14)\n"
              "                    property real fullH: 92 + nfl.height + 14\n")
FULL_H_WITH_DOCK = FULL_H_PREVIOUS.replace(
    "Math.max(160, (ui.height - dstY - 12) / ps - 92 - 14)",
    "Math.max(0, (Math.min(ui.height, win.modelData.height - root.notificationDockInset(win.modelData)) - dstY - 12) / ps - 92 - 14)",
)
FULL_H_WITH_COMPACT_HEADER = """                    // Silky: notifications and widgets scroll together in nfl (scripts/install-macshell-widgets.py)
                    readonly property real bodyTop: 44
                    readonly property real silkyNotifH: notifHist.count === 0 ? 40 : ncol.height
                    readonly property real silkyAvail: Math.max(0, (Math.min(ui.height, win.modelData.height - root.notificationDockInset(win.modelData)) - dstY - 12) / ps - bodyTop - 14)
                    property real fullH: bodyTop + nfl.height + 14
"""

FULL_H_NEW = FULL_H_WITH_COMPACT_HEADER.replace("bodyTop: 44", "bodyTop: 4").replace(
    "40 : ncol.height", "40 : ncol.height + notifClearFooter.height",
)

CLEAR_NOTIFICATIONS = """                        Item {
                            id: notifClearFooter
                            y: ncol.height
                            width: nfl.width
                            height: visible ? 34 : 0
                            visible: notifHist.count > 0 && !root.notifClearing
                            Rectangle {
                                id: notifClearButton
                                anchors.centerIn: parent
                                width: clrText.implicitWidth + 20; height: 26; radius: 13
                                color: "transparent"
                                Accessible.role: Accessible.Button
                                Accessible.name: clrText.text
                                Accessible.onPressAction: notifPop.silkyClearAll()
                                Loader {
                                    anchors.fill: parent
                                    active: notifClearFooter.visible
                                    sourceComponent: notifCardMaterial
                                    onLoaded: item.r = notifClearButton.radius
                                }
                                Rectangle {
                                    anchors.fill: parent
                                    radius: notifClearButton.radius
                                    visible: clrMa.containsMouse
                                    color: pal.btnHover
                                }
                                Text {
                                    id: clrText
                                    anchors.centerIn: parent
                                    text: I18n.tr("Clear All")
                                    color: pal.fg
                                    font.family: root.fontForWeight(Font.Medium, pal.fam)
                                    font.pixelSize: 12
                                    font.weight: Font.Medium
                                }
                                MouseArea { id: clrMa; anchors.fill: parent; hoverEnabled: true; onClicked: notifPop.silkyClearAll() }
                            }
                        }
"""

FLOATING_CARDS = """                    // The notification centre has no shared surface; each card has its own glass.
                    Component {
                        id: notifCardMaterial
                        Item {
                            id: material
                            property real r: 22
                            readonly property bool compositorOwned: surface["silkyOwned"] === true
                            Rectangle {
                                visible: !material.compositorOwned && !notifPopGlass.ctx.liquid
                                anchors.fill: parent
                                radius: material.r
                                color: notifPopGlass.ctx.dark ? Qt.rgba(0.06, 0.06, 0.07, 0.22) : Qt.rgba(0.98, 0.98, 1, 0.28)
                            }
                            GGlass {
                                id: surface
                                property bool silkyRespectClip: true
                                property Item silkyClipViewport: root.notificationClipSupported && !notifPop.morphing ? nfl : null
                                visible: notifPopGlass.ctx.liquid || !silkyWidgetDeck.editing
                                anchors.fill: parent
                                gx: notifPopGlass.ctx
                                cornerR: material.r
                                thickness: 22
                                shadowAmt: 0
                                flatInner: 1
                            }
                            Rectangle {
                                // Keep a light veil for text on top of the Control Center material.
                                visible: material.compositorOwned
                                anchors.fill: parent
                                anchors.margins: 1
                                radius: Math.max(0, material.r - 1)
                                color: notifPopGlass.ctx.dark ? Qt.rgba(0.06, 0.06, 0.08, 0.10) : Qt.rgba(0.99, 0.99, 1, 0.16)
                            }
                            Rectangle {
                                visible: !material.compositorOwned
                                anchors.fill: parent
                                radius: material.r
                                color: "transparent"
                                border.width: 1
                                border.color: notifPopGlass.ctx.dark ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(1, 1, 1, 0.52)
                            }
                        }
                    }
                    Binding {
                        target: notifPopGlass.ctx
                        property: "silkyKind"
                        value: 2
                        when: notifPopGlass.ctx["silkyKind"] !== undefined
                    }
                    Binding {
                        target: notifPopGlass.ctx
                        property: "lightVeil"
                        value: notifPopGlass.ctx.liquid ? 1 : 0
                    }
"""

DOCK_REFERENCE = """    property var hub: null
    property var notificationDock: null
    function notificationDockInset(screen) {
        var dock = notificationDock;
        if (!dock || !screen || !dock.dockEnabled || (dock.monitor && dock.monitor !== screen.name)) return 0;
        return dock.bgHeight + dock.margin;
    }
"""
NOTIFICATION_CLIP_SUPPORT = """    property bool notificationClipSupported: false
    Process {
        running: Quickshell.env("SILKY_DOCK_GLASS_PLUGIN") === "1"
        command: ["hyprctl", "plugin", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                var plugin = text.match(/Plugin silky-dock-glass[^\\n]*\\n[^\\n]*\\n\\s*Version:\\s*(\\d+)\\.(\\d+)\\.(\\d+)/);
                if (!plugin) return;
                root.notificationClipSupported = +plugin[1] > 0 || +plugin[2] > 5
                    || (+plugin[2] === 5 && +plugin[3] >= 2);
            }
        }
    }
"""
NOTIFICATION_CLIP_PROBE = NOTIFICATION_CLIP_SUPPORT
NOTIFICATION_CLIP_SUPPORT = NOTIFICATION_CLIP_PROBE.replace(
    "    property bool notificationClipSupported: false",
    "    property bool notificationClipPlugin: false\n"
    "    readonly property bool notificationClipSupported: notificationClipPlugin && !liquidActive",
    1,
).replace("root.notificationClipSupported =", "root.notificationClipPlugin =", 1)

SHELL_BAR = "    MacBar { id: macBar; hub: sharedHub }"
SHELL_BAR_WITH_DOCK = "    MacBar { id: macBar; hub: sharedHub; notificationDock: macDock }"

# notifications stacked by app: the plan, per-card info, positions, toggles (inside notifPop)
STACK_ANCHOR = '                    readonly property bool opening: ui.pop === "notif"\n'
STACK_V1 = STACK_ANCHOR + '''                    // ── Silky: notifications stacked by app (newest app first), only the 3 newest apps until "more" ──
                    property var silkyOpen: ({})              // app key → its stack is expanded
                    property bool silkyAllApps: false
                    property var silkyItems: ({})             // nid → card delegate
                    property int silkyRev: 0                  // bumped when cards come and go
                    readonly property int silkyMaxApps: 3
                    onOpeningChanged: if (!opening) { silkyOpen = ({}); silkyAllApps = false; }
                    function silkyZh() { return I18n.code().indexOf("zh") === 0; }
                    function silkyLess() { return silkyZh() ? "收起" : "Show less"; }
                    function silkyMore(n) { return silkyZh() ? "还有 " + n + " 个应用的通知" : n + (n > 1 ? " more apps" : " more app"); }
                    function silkyKey(app, nid) { return app ? String(app).toLowerCase() : "#" + nid; }
                    readonly property var silkyPlan: {
                        var c = notifHist.count, groups = [], byKey = {};
                        for (var i = 0; i < c; i++) {
                            var r = notifHist.get(i), k = silkyKey(r.app, r.nid);
                            if (!byKey[k]) { byKey[k] = { key: k, items: [] }; groups.push(byKey[k]); }
                            byKey[k].items.push(r.nid);
                        }
                        return groups;
                    }
                    readonly property int silkyHiddenApps: silkyAllApps ? 0 : Math.max(0, silkyPlan.length - silkyMaxApps)
                    readonly property var silkyInfo: {
                        var m = {}, open = silkyOpen;
                        for (var g = 0; g < silkyPlan.length; g++) {
                            var grp = silkyPlan[g], o = !!open[grp.key], hid = g >= silkyMaxApps && silkyHiddenApps > 0;
                            for (var j = 0; j < grp.items.length; j++)
                                m[grp.items[j]] = { key: grp.key, gi: g, mi: j, n: grp.items.length, open: o, hidden: hid };
                        }
                        return m;
                    }
                    function silkyReg(nid, item) { silkyItems[nid] = item; silkyRev++; }
                    function silkyUnreg(nid, item) { if (silkyItems[nid] === item) { delete silkyItems[nid]; silkyRev++; } }
                    // a card's y: the shown cards before it in display order; a folded card sits under its app's newest
                    function silkyY(nid, rev) {
                        var y = 0;
                        for (var g = 0; g < silkyPlan.length; g++) {
                            var grp = silkyPlan[g], headY = y;
                            for (var j = 0; j < grp.items.length; j++) {
                                var id = grp.items[j], it = silkyItems[id];
                                if (id === nid) return (j === 0 || (it && it.silkyShown)) ? y : headY;
                                if (it && it.height > 0.5) y += it.height + 8;
                            }
                        }
                        return y;
                    }
                    readonly property real silkyCardsH: {
                        var rev = silkyRev, y = 0;
                        for (var g = 0; g < silkyPlan.length; g++)
                            for (var j = 0; j < silkyPlan[g].items.length; j++) {
                                var it = silkyItems[silkyPlan[g].items[j]];
                                if (it && it.height > 0.5) y += it.height + 8;
                            }
                        return Math.max(0, y - 8);
                    }
                    readonly property bool silkyMoreShown: silkyPlan.length > silkyMaxApps && !root.notifClearing
                    readonly property real silkyTotal: silkyCardsH + (silkyMoreShown ? 44 : 0)
                    // soft edges without a shader layer: a card fades by how much of it is still inside the scroll view
                    function silkyEdge(top, h, contentY, viewH) {
                        if (!nfl.silkyOverflow || h <= 1) return 1;
                        var seen = (Math.min(top + h, contentY + viewH) - Math.max(top, contentY)) / h;
                        var t = Math.max(0, Math.min(1, seen));       // the share of the card still in view
                        return 0.12 + 0.88 * t * t;
                    }
                    function silkyToggle(key) { var o = Object.assign({}, silkyOpen); o[key] = !o[key]; silkyOpen = o; }
                    function silkyClearGroup(key) {
                        for (var g = 0; g < silkyPlan.length; g++) {
                            if (silkyPlan[g].key !== key) continue;
                            for (var j = 0; j < silkyPlan[g].items.length; j++) {
                                var it = silkyItems[silkyPlan[g].items[j]];
                                if (it) it.dissolve(1 + j * 55);
                            }
                        }
                    }
'''
STACK_V2 = STACK_ANCHOR + '''                    // ── Silky: notifications stacked by app (newest app first), only the 3 newest apps until "more" ──
                    property var silkyOpen: ({})              // app key → its stack is expanded
                    property bool silkyAllApps: false
                    property var silkyItems: ({})             // nid → card delegate
                    property int silkyRev: 0                  // bumped when cards come and go
                    readonly property int silkyMaxApps: 3
                    onOpeningChanged: if (!opening) { silkyOpen = ({}); silkyAllApps = false; }
                    function silkyZh() { return I18n.code().indexOf("zh") === 0; }
                    function silkyLess() { return silkyZh() ? "收起" : "Show less"; }
                    function silkyMore(n) { return silkyZh() ? "还有 " + n + " 个应用的通知" : n + (n > 1 ? " more apps" : " more app"); }
                    function silkyKey(app, nid) { return app ? String(app).toLowerCase() : "#" + nid; }
                    Connections {
                        target: root
                        function onSilkyStackRequestChanged() { if (root.silkyStackRequest) notifPop.silkyToggle(root.silkyStackRequest); }
                    }
                    readonly property var silkyPlan: {
                        var c = notifHist.count, groups = [], byKey = {};
                        for (var i = 0; i < c; i++) {
                            var r = notifHist.get(i), k = silkyKey(r.app, r.nid);
                            if (!byKey[k]) { byKey[k] = { key: k, items: [] }; groups.push(byKey[k]); }
                            byKey[k].items.push(r.nid);
                        }
                        return groups;
                    }
                    readonly property int silkyHiddenApps: silkyAllApps ? 0 : Math.max(0, silkyPlan.length - silkyMaxApps)
                    readonly property var silkyInfo: {
                        var m = {}, open = silkyOpen;
                        for (var g = 0; g < silkyPlan.length; g++) {
                            var grp = silkyPlan[g], o = !!open[grp.key], hid = g >= silkyMaxApps && silkyHiddenApps > 0;
                            for (var j = 0; j < grp.items.length; j++)
                                m[grp.items[j]] = { key: grp.key, gi: g, mi: j, n: grp.items.length, open: o, hidden: hid };
                        }
                        return m;
                    }
                    function silkyReg(nid, item) { silkyItems[nid] = item; silkyRev++; }
                    function silkyUnreg(nid, item) { if (silkyItems[nid] === item) { delete silkyItems[nid]; silkyRev++; } }
                    // a card's y: the shown cards before it in display order; a folded card sits under its app's newest
                    function silkyY(nid, rev) {
                        var y = 0;
                        for (var g = 0; g < silkyPlan.length; g++) {
                            var grp = silkyPlan[g], headY = y;
                            for (var j = 0; j < grp.items.length; j++) {
                                var id = grp.items[j], it = silkyItems[id];
                                if (id === nid) return (j === 0 || (it && it.silkyShown)) ? y : headY;
                                if (it && it.height > 0.5) y += it.height + 8;
                            }
                        }
                        return y;
                    }
                    readonly property real silkyCardsH: {
                        var rev = silkyRev, y = 0;
                        for (var g = 0; g < silkyPlan.length; g++)
                            for (var j = 0; j < silkyPlan[g].items.length; j++) {
                                var it = silkyItems[silkyPlan[g].items[j]];
                                if (it && it.height > 0.5) y += it.height + 8;
                            }
                        return Math.max(0, y - 8);
                    }
                    readonly property bool silkyMoreShown: silkyPlan.length > silkyMaxApps && !root.notifClearing
                    readonly property real silkyTotal: silkyCardsH + (silkyMoreShown ? 44 : 0)
                    // soft edges without a shader layer: a card fades by how much of it is still inside the scroll view
                    function silkyEdge(top, h, contentY, viewH) {
                        if (!nfl.silkyOverflow || h <= 1) return 1;
                        var seen = (Math.min(top + h, contentY + viewH) - Math.max(top, contentY)) / h;
                        var t = Math.max(0, Math.min(1, seen));       // the share of the card still in view
                        return 0.12 + 0.88 * t * t;
                    }
                    function silkyToggle(key) { var o = Object.assign({}, silkyOpen); o[key] = !o[key]; silkyOpen = o; }
                    function silkyClearGroup(key) {
                        for (var g = 0; g < silkyPlan.length; g++) {
                            if (silkyPlan[g].key !== key) continue;
                            for (var j = 0; j < silkyPlan[g].items.length; j++) {
                                var it = silkyItems[silkyPlan[g].items[j]];
                                if (it) it.dissolve(1 + j * 55);
                            }
                        }
                    }
'''
STACK_V3 = STACK_ANCHOR + '''                    // ── Silky: notifications stacked by app (newest app first), only the 3 newest apps until "more" ──
                    property var silkyOpen: ({})              // app key → its stack is expanded
                    property bool silkyAllApps: false
                    property var silkyItems: ({})             // nid → card delegate
                    property int silkyRev: 0                  // bumped when cards come and go
                    readonly property int silkyMaxApps: 3
                    onOpeningChanged: if (!opening) { silkyOpen = ({}); silkyAllApps = false; }
                    function silkyZh() { return I18n.code().indexOf("zh") === 0; }
                    function silkyLess() { return silkyZh() ? "收起" : "Show less"; }
                    function silkyMore(n) { return silkyZh() ? "还有 " + n + " 个应用的通知" : n + (n > 1 ? " more apps" : " more app"); }
                    function silkyKey(app, nid) { return app ? String(app).toLowerCase() : "#" + nid; }
                    Connections {
                        target: root
                        function onSilkyStackRequestChanged() { if (root.silkyStackRequest) notifPop.silkyToggle(root.silkyStackRequest); }
                    }
                    readonly property var silkyPlan: {
                        var c = notifHist.count, groups = [], byKey = {};
                        for (var i = 0; i < c; i++) {
                            var r = notifHist.get(i), k = silkyKey(r.app, r.nid);
                            if (!byKey[k]) { byKey[k] = { key: k, items: [] }; groups.push(byKey[k]); }
                            byKey[k].items.push(r.nid);
                        }
                        return groups;
                    }
                    readonly property int silkyHiddenApps: silkyAllApps ? 0 : Math.max(0, silkyPlan.length - silkyMaxApps)
                    readonly property var silkyInfo: {
                        var m = {}, open = silkyOpen;
                        for (var g = 0; g < silkyPlan.length; g++) {
                            var grp = silkyPlan[g], o = !!open[grp.key], hid = g >= silkyMaxApps && silkyHiddenApps > 0;
                            for (var j = 0; j < grp.items.length; j++)
                                m[grp.items[j]] = { key: grp.key, gi: g, mi: j, n: grp.items.length, open: o, hidden: hid };
                        }
                        return m;
                    }
                    function silkyReg(nid, item) { silkyItems[nid] = item; silkyRev++; }
                    function silkyUnreg(nid, item) { if (silkyItems[nid] === item) { delete silkyItems[nid]; silkyRev++; } }
                    // the height a card is heading for: layout uses final heights, so every card glides once to a fixed
                    // target instead of chasing its neighbours' animations; Clear All keeps the continuous reflow
                    function silkyH(it) {
                        if (!it) return 0;
                        if (root.notifClearing) return it.height;
                        return it.silkyShown && it.inT > 0.5 ? it.cardH : 0;
                    }
                    // a card's y: the shown cards before it in display order; a folded card sits under its app's newest
                    function silkyY(nid, rev) {
                        var y = 0;
                        for (var g = 0; g < silkyPlan.length; g++) {
                            var grp = silkyPlan[g], headY = y;
                            for (var j = 0; j < grp.items.length; j++) {
                                var id = grp.items[j], it = silkyItems[id];
                                if (id === nid) return (j === 0 || (it && it.silkyShown)) ? y : headY;
                                var h = silkyH(it);
                                if (h > 0.5) y += h + 8;
                            }
                        }
                        return y;
                    }
                    readonly property real silkyCardsH: {
                        var rev = silkyRev, y = 0;
                        for (var g = 0; g < silkyPlan.length; g++)
                            for (var j = 0; j < silkyPlan[g].items.length; j++) {
                                var it = silkyItems[silkyPlan[g].items[j]];
                                var h = silkyH(it);
                                if (h > 0.5) y += h + 8;
                            }
                        return Math.max(0, y - 8);
                    }
                    readonly property bool silkyMoreShown: silkyPlan.length > silkyMaxApps && !root.notifClearing
                    readonly property real silkyTotal: silkyCardsH + (silkyMoreShown ? 44 : 0)
                    // soft edges without a shader layer: a card fades by how much of it is still inside the scroll view
                    function silkyEdge(top, h, contentY, viewH) {
                        if (!nfl.silkyOverflow || h <= 1) return 1;
                        var seen = (Math.min(top + h, contentY + viewH) - Math.max(top, contentY)) / h;
                        var t = Math.max(0, Math.min(1, seen));       // the share of the card still in view
                        return 0.12 + 0.88 * t * t;
                    }
                    function silkyToggle(key) { var o = Object.assign({}, silkyOpen); o[key] = !o[key]; silkyOpen = o; }
                    function silkyClearGroup(key) {
                        for (var g = 0; g < silkyPlan.length; g++) {
                            if (silkyPlan[g].key !== key) continue;
                            for (var j = 0; j < silkyPlan[g].items.length; j++) {
                                var it = silkyItems[silkyPlan[g].items[j]];
                                if (it) it.dissolve(1 + j * 55);
                            }
                        }
                    }
'''
# patches never anchor inside another patch's text, so each one stays recognisable on a repeat run
STACK = STACK_ANCHOR + '''                    // ── Silky: notifications stacked by app (newest app first), only the 3 newest apps until "more" ──
                    property var silkyOpen: ({})              // app key → its stack is expanded
                    property bool silkyAllApps: false
                    property var silkyItems: ({})             // nid → card delegate
                    property int silkyRev: 0                  // bumped when cards come and go
                    readonly property int silkyMaxApps: 3
                    onOpeningChanged: if (!opening) { silkyOpen = ({}); silkyAllApps = false; }
                    function silkyZh() { return I18n.code().indexOf("zh") === 0; }
                    function silkyLess() { return silkyZh() ? "收起" : "Show less"; }
                    function silkyMore(n) { return silkyZh() ? "还有 " + n + " 个应用的通知" : n + (n > 1 ? " more apps" : " more app"); }
                    function silkyKey(app, nid) { return app ? String(app).toLowerCase() : "#" + nid; }
                    Connections {
                        target: root
                        function onSilkyStackRequestChanged() { if (root.silkyStackRequest) notifPop.silkyToggle(root.silkyStackRequest); }
                    }
                    readonly property var silkyPlan: {
                        var c = notifHist.count, groups = [], byKey = {};
                        for (var i = 0; i < c; i++) {
                            var r = notifHist.get(i), k = silkyKey(r.app, r.nid);
                            if (!byKey[k]) { byKey[k] = { key: k, items: [] }; groups.push(byKey[k]); }
                            byKey[k].items.push(r.nid);
                        }
                        return groups;
                    }
                    readonly property int silkyHiddenApps: silkyAllApps ? 0 : Math.max(0, silkyPlan.length - silkyMaxApps)
                    readonly property var silkyInfo: {
                        var m = {}, open = silkyOpen;
                        for (var g = 0; g < silkyPlan.length; g++) {
                            var grp = silkyPlan[g], o = !!open[grp.key], hid = g >= silkyMaxApps && silkyHiddenApps > 0;
                            for (var j = 0; j < grp.items.length; j++)
                                m[grp.items[j]] = { key: grp.key, gi: g, mi: j, n: grp.items.length, open: o, hidden: hid };
                        }
                        return m;
                    }
                    function silkyReg(nid, item) { silkyItems[nid] = item; silkyRev++; }
                    function silkyUnreg(nid, item) { if (silkyItems[nid] === item) { delete silkyItems[nid]; silkyRev++; } }
                    // the height a card is heading for: layout uses final heights, so every card glides once to a fixed
                    // target instead of chasing its neighbours' animations; Clear All keeps the continuous reflow
                    function silkyH(it) {
                        if (!it) return 0;
                        if (root.notifClearing) return it.height;
                        return it.silkyShown && it.inT > 0.5 ? it.silkyFinalH : 0;
                    }
                    // a card's y: the shown cards before it in display order; a folded card sits under its app's newest
                    function silkyY(nid, rev) {
                        var y = 0;
                        for (var g = 0; g < silkyPlan.length; g++) {
                            var grp = silkyPlan[g], headY = y;
                            for (var j = 0; j < grp.items.length; j++) {
                                var id = grp.items[j], it = silkyItems[id];
                                if (id === nid) return (j === 0 || (it && it.silkyShown)) ? y : headY;
                                var h = silkyH(it);
                                if (h > 0.5) y += h + 8;
                            }
                        }
                        return y;
                    }
                    readonly property real silkyCardsH: {
                        var rev = silkyRev, y = 0;
                        for (var g = 0; g < silkyPlan.length; g++)
                            for (var j = 0; j < silkyPlan[g].items.length; j++) {
                                var it = silkyItems[silkyPlan[g].items[j]];
                                var h = silkyH(it);
                                if (h > 0.5) y += h + 8;
                            }
                        return Math.max(0, y - 8);
                    }
                    readonly property bool silkyMoreShown: silkyPlan.length > silkyMaxApps && !root.notifClearing
                    readonly property real silkyTotal: silkyCardsH + (silkyMoreShown ? 44 : 0)
                    // soft edges without a shader layer: a card fades by how much of it is still inside the scroll view
                    function silkyEdge(top, h, contentY, viewH) {
                        if (!nfl.silkyOverflow || h <= 1) return 1;
                        var seen = (Math.min(top + h, contentY + viewH) - Math.max(top, contentY)) / h;
                        var t = Math.max(0, Math.min(1, seen));       // the share of the card still in view
                        return 0.12 + 0.88 * t * t;
                    }
                    function silkyToggle(key) { var o = Object.assign({}, silkyOpen); o[key] = !o[key]; silkyOpen = o; }
                    function silkyClearGroup(key) {
                        for (var g = 0; g < silkyPlan.length; g++) {
                            if (silkyPlan[g].key !== key) continue;
                            for (var j = 0; j < silkyPlan[g].items.length; j++) {
                                var it = silkyItems[silkyPlan[g].items[j]];
                                if (it) it.dissolve(1 + j * 55);
                            }
                        }
                    }
'''

STACK_BEFORE_MOTION = STACK
STACK = STACK_BEFORE_MOTION.replace(
    '                    onOpeningChanged: if (!opening) { silkyOpen = ({}); silkyAllApps = false; }',
    """                    onOpeningChanged: {
                        if (opening && nfl) {
                            nfl.cancelFlick();
                            nfl.contentY = nfl.originY;
                        } else if (!opening) {
                            silkyOpen = ({});
                            silkyAllApps = false;
                        }
                    }
                    property var silkyClearIds: []
                    property real silkyClearProgress: 0
                    property int silkyPressedId: 0
                    function silkyClearAll() { silkyClear(silkyPlan.flatMap(group => group.items)); }
                    function silkyClear(ids) {
                        if (!ids.length || silkyClearIds.length || silkyPressedId) return;
                        silkyClearIds = ids;
                        if (root.reduceMotion) silkyFinishClear();
                        else silkyClearMotion.start();
                    }
                    function silkyFinishClear() {
                        var ids = silkyClearIds;
                        for (var i = 0; i < ids.length; i++) root.notifDelete(ids[i]);
                        silkyClearIds = [];
                        silkyClearProgress = 0;
                    }
                    NumberAnimation {
                        id: silkyClearMotion
                        target: notifPop; property: "silkyClearProgress"
                        from: 0; to: 1; duration: 210; easing.type: Easing.InOutQuad
                        onFinished: notifPop.silkyFinishClear()
                    }
                    function silkyPress(id) {
                        if (silkyPressedId || silkyClearIds.length) return;
                        silkyPressedId = id;
                        if (root.reduceMotion) silkyFinishPress();
                        else silkyPressTimer.start();
                    }
                    function silkyFinishPress() {
                        var id = silkyPressedId;
                        silkyPressedId = 0;
                        if (root.notifIndex(notifHist, id) < 0) return;
                        if (root.notifActivate(id, true) && ui.pop === "notif") ui.pop = "";
                        root.notifDelete(id);
                    }
                    Timer { id: silkyPressTimer; interval: 80; onTriggered: notifPop.silkyFinishPress() }""",
    1,
).replace(
    'if (!nfl.silkyOverflow || h <= 1) return 1;',
    'if (!nfl.silkyOverflow || h <= 1 || (root.notificationClipSupported && !morphing)) return 1;',
    1,
)
STACK = STACK[:STACK.index('                    function silkyClearGroup(key) {')] + """                    function silkyClearGroup(key) {
                        var group = silkyPlan.find(group => group.key === key);
                        if (group) silkyClear(group.items);
                    }
"""


STACK_WITH_GRADIENT = STACK
STACK = STACK_WITH_GRADIENT.replace(
    """                        } else if (!opening) {
                            silkyOpen = ({});""",
    """                        } else if (!opening) {
                            if (silkyClearIds.length) {
                                silkyClearMotion.stop();
                                silkyFinishClear();
                            }
                            silkyOpen = ({});""",
    1,
)
STACK = STACK[:STACK.index("                    property var silkyClearIds:")] + """                    property var silkyClearIds: []
                    property var silkyQueuedClearIds: []
                    property real silkyClearProgress: 0
                    property int silkyPressedId: 0
                    function silkyClearAll() {
                        // Use the history so folded stacks and apps hidden by the list limit are included.
                        var ids = [];
                        for (var i = 0; i < notifHist.count; i++) ids.push(notifHist.get(i).nid);
                        silkyClear(ids);
                    }
                    function silkyClear(ids) {
                        if (silkyClearIds.length) {
                            for (var i = 0; i < ids.length; i++) {
                                var id = ids[i];
                                if (silkyClearIds.indexOf(id) < 0 && silkyQueuedClearIds.indexOf(id) < 0)
                                    silkyQueuedClearIds.push(id);
                            }
                            return;
                        }
                        ids = ids.filter(id => root.notifIndex(notifHist, id) >= 0);
                        if (!ids.length) return;
                        if (ids.indexOf(silkyPressedId) >= 0) {
                            silkyPressTimer.stop();
                            silkyPressedId = 0;
                        }
                        silkyClearIds = ids;
                        if (root.reduceMotion || !opening) silkyFinishClear();
                        else silkyClearMotion.start();
                    }
                    function silkyFinishClear() {
                        var ids = silkyClearIds;
                        var queued = silkyQueuedClearIds;
                        // Remove the whole model in one update when no new notification has arrived.
                        var coversHistory = ids.length === notifHist.count;
                        for (var i = 0; coversHistory && i < notifHist.count; i++)
                            coversHistory = ids.indexOf(notifHist.get(i).nid) >= 0;
                        if (coversHistory) root.notifClear();
                        else for (var j = ids.length - 1; j >= 0; j--) root.notifDelete(ids[j]);
                        silkyClearIds = [];
                        silkyQueuedClearIds = [];
                        silkyClearProgress = 0;
                        if (queued.length) silkyClear(queued);
                    }
                    NumberAnimation {
                        id: silkyClearMotion
                        target: notifPop; property: "silkyClearProgress"
                        from: 0; to: 1; duration: 280; easing.type: Easing.InOutSine
                        onFinished: notifPop.silkyFinishClear()
                    }
""" + STACK[STACK.index("                    function silkyPress(id)"):]


EMPTY_OLD = ("                        // fades in as the list finishes collapsing (no pop at the end of Clear All)\n"
             "                        opacity: notifHist.count === 0 ? 1 : 0\n")
EMPTY_NEW = ("                        // fades in as the list finishes collapsing (no pop at the end of Clear All); hides once the widgets scroll over it\n"
             "                        opacity: notifHist.count === 0 && nfl.contentY < 4 ? 1 : 0\n")

DECK = """                        SilkyWidgetDeck {
                            id: silkyWidgetDeck
                            x: 8; y: notifPop.silkyNotifH + 12
                            Behavior on y { enabled: notifPop.visible && !root.notifClearing; NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
                            opacity: notifPop.merging ? notifPop.chrome : 1
                            theme: pal
                            fam: pal.fam
                            bold: root.fontForWeight(Font.DemiBold, pal.fam)
                            accent: (pal && silkyStatusSummary.sample?.wallpaperAccent?.[pal.dark ? "dark" : "light"]) || (pal ? pal.accent : "#6cb8ff")
                            open: ui.pop === "notif"
                            maxHeight: 100000                 // nfl scrolls; the deck itself never does
                            // which part of the deck is inside nfl, so widgets fade at the edges like the cards
                            viewTop: nfl.contentY - y
                            viewHeight: nfl.silkyOverflow && (!root.notificationClipSupported || notifPop.morphing) ? nfl.height : 0
                            glass: notifCardMaterial
                        }
"""

NFL_OLD = """                    Flickable {
                        id: nfl
                        opacity: notifPop.merging ? 1 : notifPop.contentT
                        x: 12; y: 92
                        width: parent.width - 24
                        height: Math.min(ncol.height, 440)
                        contentHeight: ncol.height
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        Column {
                            id: ncol
                            width: nfl.width
                            spacing: 8
"""
NFL_NEW = """                    Flickable {
                        id: nfl
                        opacity: notifPop.merging ? 1 : notifPop.contentT
                        // Silky: notifications (stacked by app) and the widgets share this one scroll; 8 px of slack on
                        // each side keeps the widgets' edit badges unclipped
                        x: 4; y: 92
                        width: parent.width - 8
                        height: Math.min(contentHeight, notifPop.silkyAvail)
                        contentHeight: notifPop.silkyNotifH + (silkyWidgetDeck.height > 0 ? 12 + silkyWidgetDeck.height : 0)
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        readonly property bool silkyOverflow: contentHeight > height + 1
""" + DECK + """                        Item {
                            id: ncol
                            x: 8
                            width: nfl.width - 16
                            height: notifPop.silkyTotal
                            // "3 more apps" / "Show less" under the newest three apps
                            Item {
                                visible: notifPop.silkyMoreShown
                                y: notifPop.silkyCardsH + 10; width: parent.width; height: 34
                                Behavior on y { enabled: notifPop.visible && !root.notifClearing; NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: silkyMoreText.implicitWidth + 28; height: 28; radius: 14
                                    color: silkyMoreMa.containsMouse ? pal.btnHover : pal.btnOff
                                    Text {
                                        id: silkyMoreText
                                        anchors.centerIn: parent
                                        text: notifPop.silkyAllApps ? notifPop.silkyLess() : notifPop.silkyMore(notifPop.silkyPlan.length - notifPop.silkyMaxApps)
                                        color: pal.fg
                                        font.family: root.fontForWeight(Font.Medium, pal.fam); font.pixelSize: 12; font.weight: Font.Medium
                                    }
                                    MouseArea { id: silkyMoreMa; anchors.fill: parent; hoverEnabled: true; onClicked: notifPop.silkyAllApps = !notifPop.silkyAllApps }
                                }
                            }
"""
NFL_WITHOUT_FADE = NFL_NEW
NFL_NEW = """                    Rectangle {
                        id: notifScrollMask
                        width: 4; height: Math.max(1, nfl.height)
                        visible: false
                        layer.enabled: true
                        gradient: Gradient {
                            GradientStop { position: 0; color: "white" }
                            GradientStop { position: 1 - nfl.silkyClipBottomInset / Math.max(1, nfl.height); color: "white" }
                            GradientStop { position: 1; color: "transparent" }
                        }
                    }
""" + NFL_WITHOUT_FADE.replace(
    "                        readonly property bool silkyOverflow: contentHeight > height + 1\n",
    """                        readonly property bool silkyOverflow: contentHeight > height + 1
                        readonly property real silkyClipBottomInset: !root.liquidActive && silkyOverflow && !atYEnd ? Math.min(40, height / 3) : 0
                        layer.enabled: silkyClipBottomInset > 0
                        layer.effect: MultiEffect {
                            maskEnabled: true
                            maskThresholdMin: 0.5
                            maskSpreadAtMin: 1.0
                            maskSource: notifScrollMask
                        }
""",
)
NFL_WITH_TALL_HEADER = NFL_NEW
NFL_WITH_COMPACT_HEADER = NFL_WITH_TALL_HEADER.replace("x: 4; y: 92", "x: 4; y: notifPop.bodyTop", 1)
NFL_NEW = NFL_WITH_COMPACT_HEADER.replace(DECK, DECK + CLEAR_NOTIFICATIONS, 1)

CARD_OLD = """                                    height: hc.height * inT
                                    cardH: hc.height
                                    opacity: inT
"""
CARD_NEW_V1 = """                                    // Silky: stacked by app (notifPop.silkyInfo), placed by notifPop.silkyY instead of a Column
                                    readonly property var silky: notifPop.silkyInfo[nid] || ({ key: "", gi: 0, mi: 0, n: 1, open: false, hidden: false })
                                    readonly property bool silkyShown: !silky.hidden && (silky.mi === 0 || silky.open)
                                    readonly property bool silkyStacked: silky.mi === 0 && silky.n > 1 && !silky.open
                                    readonly property real silkyHeadH: silky.mi === 0 && silky.n > 1 && silky.open ? 34 : 0
                                    readonly property real silkyStackH: silkyStacked ? (silky.n > 2 ? 14 : 7) : 0
                                    property real silkyT: silkyShown ? 1 : 0
                                    Behavior on silkyT { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
                                    y: notifPop.silkyY(nid, notifPop.silkyRev)
                                    Behavior on y { enabled: notifPop.visible && !root.notifClearing; NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
                                    height: cardH * inT * silkyT
                                    cardH: hc.height + silkyHeadH + silkyStackH
                                    opacity: inT * silkyT * notifPop.silkyEdge(y, height, nfl.contentY, nfl.height)
                                    visible: opacity > 0.01 || flipAnim.running
"""
CARD_NEW_V2 = """                                    // Silky: stacked by app (notifPop.silkyInfo), placed by notifPop.silkyY instead of a Column
                                    readonly property var silky: notifPop.silkyInfo[nid] || ({ key: "", gi: 0, mi: 0, n: 1, open: false, hidden: false })
                                    readonly property bool silkyShown: !silky.hidden && (silky.mi === 0 || silky.open)
                                    readonly property bool silkyStacked: silky.mi === 0 && silky.n > 1 && !silky.open
                                    // the app header and the paper edges grow and shrink instead of popping, so the card never jumps
                                    property real silkyHeadH: silky.mi === 0 && silky.n > 1 && silky.open ? 34 : 0
                                    Behavior on silkyHeadH { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
                                    property real silkyStackH: silkyStacked ? (silky.n > 2 ? 14 : 7) : 0
                                    Behavior on silkyStackH { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
                                    property real silkyT: silkyShown ? 1 : 0
                                    Behavior on silkyT { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
                                    y: notifPop.silkyY(nid, notifPop.silkyRev)
                                    Behavior on y { enabled: notifPop.visible && !root.notifClearing; NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
                                    height: cardH * inT * silkyT
                                    cardH: hc.height + silkyHeadH + silkyStackH
                                    // a folded card shows only once it has mostly slid out from under its app's newest card (cubed),
                                    // and is gone before it slides back: translucent cards never pile up on each other
                                    opacity: inT * silkyT * silkyT * silkyT * notifPop.silkyEdge(y, height, nfl.contentY, nfl.height)
                                    visible: opacity > 0.01 || flipAnim.running
"""
CARD_NEW = """                                    // Silky: stacked by app (notifPop.silkyInfo), placed by notifPop.silkyY instead of a Column
                                    readonly property var silky: notifPop.silkyInfo[nid] || ({ key: "", gi: 0, mi: 0, n: 1, open: false, hidden: false })
                                    readonly property bool silkyShown: !silky.hidden && (silky.mi === 0 || silky.open)
                                    readonly property bool silkyStacked: silky.mi === 0 && silky.n > 1 && !silky.open
                                    // the app header and the paper edges grow and shrink instead of popping, so the card never jumps
                                    readonly property real silkyHeadTarget: silky.mi === 0 && silky.n > 1 && silky.open ? 34 : 0
                                    readonly property real silkyStackTarget: silkyStacked ? (silky.n > 2 ? 14 : 7) : 0
                                    property real silkyHeadH: silkyHeadTarget
                                    Behavior on silkyHeadH { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
                                    property real silkyStackH: silkyStackTarget
                                    Behavior on silkyStackH { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
                                    // the height this card settles at (the layout target; never a value mid-animation)
                                    readonly property real silkyFinalH: hc.height + silkyHeadTarget + silkyStackTarget
                                    property real silkyT: silkyShown ? 1 : 0
                                    Behavior on silkyT { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
                                    y: notifPop.silkyY(nid, notifPop.silkyRev)
                                    Behavior on y { enabled: notifPop.visible && !root.notifClearing; NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
                                    height: cardH * inT * silkyT
                                    cardH: hc.height + silkyHeadH + silkyStackH
                                    // a folded card shows only once it has mostly slid out from under its app's newest card (cubed),
                                    // and is gone before it slides back: translucent cards never pile up on each other
                                    opacity: inT * silkyT * silkyT * silkyT * notifPop.silkyEdge(y, height, nfl.contentY, nfl.height)
                                    visible: opacity > 0.01 || flipAnim.running
"""

CARD_BEFORE_FEATHER = CARD_NEW
CARD_NEW = CARD_BEFORE_FEATHER.replace(
    '                                    opacity: inT * silkyT * silkyT * silkyT * notifPop.silkyEdge(y, height, nfl.contentY, nfl.height)',
    """                                    readonly property real silkyClearT: notifPop.silkyClearIds.includes(nid) ? notifPop.silkyClearProgress : 0
                                    opacity: inT * silkyT * silkyT * silkyT * (1 - silkyClearT) * notifPop.silkyEdge(y, height, nfl.contentY, nfl.height)""",
    1,
)


CARD_WITH_GRADIENT = CARD_NEW
CARD_NEW = CARD_WITH_GRADIENT.replace(
    """                                    readonly property real silkyClearT: notifPop.silkyClearIds.includes(nid) ? notifPop.silkyClearProgress : 0
                                    opacity: inT * silkyT * silkyT * silkyT * (1 - silkyClearT) * notifPop.silkyEdge(y, height, nfl.contentY, nfl.height)""",
    """                                    readonly property bool silkyClearing: notifPop.silkyClearIds.indexOf(nid) >= 0
                                    readonly property bool silkyFeathering: silkyClearing && silkyShown && !root.reduceMotion
                                        && y + height > nfl.contentY && y < nfl.contentY + nfl.height
                                    readonly property real silkyClearT: silkyFeathering ? notifPop.silkyClearProgress : 0
                                    opacity: inT * silkyT * silkyT * silkyT * (1 - silkyClearT) * notifPop.silkyEdge(y, height, nfl.contentY, nfl.height)""",
    1,
)


HC_OLD = """                                Rectangle {
                                    id: hc
                                    readonly property int nid: hcd.nid
"""
HC_NEW_V1 = """                                Item { Component.onCompleted: notifPop.silkyReg(hcd.nid, hcd); Component.onDestruction: notifPop.silkyUnreg(hcd.nid, hcd) }
                                // Silky: the app's header while its stack is open (collapse, clear the app)
                                Item {
                                    visible: hcd.silkyHeadH > 0
                                    width: hcd.width; height: 30
                                    Text {
                                        x: 4; width: parent.width - 120
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: hcd.app
                                        elide: Text.ElideRight
                                        color: pal.fg
                                        font.family: root.fontForWeight(Font.DemiBold, pal.fam); font.pixelSize: 15; font.weight: Font.DemiBold
                                    }
                                    Row {
                                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                        spacing: 6
                                        Rectangle {
                                            width: silkyLessText.implicitWidth + 20; height: 24; radius: 12
                                            color: silkyLessMa.containsMouse ? pal.btnHover : pal.btnOff
                                            Text {
                                                id: silkyLessText
                                                anchors.centerIn: parent
                                                text: notifPop.silkyLess()
                                                color: pal.fg
                                                font.family: root.fontForWeight(Font.Medium, pal.fam); font.pixelSize: 12; font.weight: Font.Medium
                                            }
                                            MouseArea { id: silkyLessMa; anchors.fill: parent; hoverEnabled: true; onClicked: notifPop.silkyToggle(hcd.silky.key) }
                                        }
                                        Rectangle {
                                            width: 24; height: 24; radius: 12
                                            color: silkyClearMa.containsMouse ? pal.btnHover : pal.btnOff
                                            Text { anchors.centerIn: parent; text: "✕"; color: pal.fg; font.pixelSize: 11 }
                                            MouseArea { id: silkyClearMa; anchors.fill: parent; hoverEnabled: true; onClicked: notifPop.silkyClearGroup(hcd.silky.key) }
                                        }
                                    }
                                }
                                // Silky: paper edges peeking out under a folded stack
                                Repeater {
                                    model: hcd.silkyStacked ? (hcd.silky.n > 2 ? 2 : 1) : 0
                                    Rectangle {
                                        required property int index
                                        z: -1 - index
                                        x: 10 * (index + 1); width: hcd.width - 20 * (index + 1)
                                        y: hcd.silkyHeadH + hc.height - 10 + 7 * index
                                        height: 17; radius: 14
                                        color: pal.tile
                                        opacity: 0.9 - 0.3 * index
                                        border.width: 1; border.color: Qt.rgba(pal.tileBorder.r, pal.tileBorder.g, pal.tileBorder.b, pal.tileBorder.a * 0.3)
                                    }
                                }
                                Rectangle {
                                    id: hc
                                    y: hcd.silkyHeadH
                                    readonly property int nid: hcd.nid
"""
HC_NEW = """                                Item { Component.onCompleted: notifPop.silkyReg(hcd.nid, hcd); Component.onDestruction: notifPop.silkyUnreg(hcd.nid, hcd) }
                                // Silky: the app's header while its stack is open (collapse, clear the app)
                                Item {
                                    visible: hcd.silkyHeadH > 0.5
                                    opacity: hcd.silkyHeadH / 34
                                    width: hcd.width; height: 30
                                    Text {
                                        x: 4; width: parent.width - 120
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: hcd.app
                                        elide: Text.ElideRight
                                        color: pal.fg
                                        font.family: root.fontForWeight(Font.DemiBold, pal.fam); font.pixelSize: 15; font.weight: Font.DemiBold
                                    }
                                    Row {
                                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                        spacing: 6
                                        Rectangle {
                                            width: silkyLessText.implicitWidth + 20; height: 24; radius: 12
                                            color: silkyLessMa.containsMouse ? pal.btnHover : pal.btnOff
                                            Text {
                                                id: silkyLessText
                                                anchors.centerIn: parent
                                                text: notifPop.silkyLess()
                                                color: pal.fg
                                                font.family: root.fontForWeight(Font.Medium, pal.fam); font.pixelSize: 12; font.weight: Font.Medium
                                            }
                                            MouseArea { id: silkyLessMa; anchors.fill: parent; hoverEnabled: true; onClicked: notifPop.silkyToggle(hcd.silky.key) }
                                        }
                                        Rectangle {
                                            width: 24; height: 24; radius: 12
                                            color: silkyClearMa.containsMouse ? pal.btnHover : pal.btnOff
                                            Text { anchors.centerIn: parent; text: "✕"; color: pal.fg; font.pixelSize: 11 }
                                            MouseArea { id: silkyClearMa; anchors.fill: parent; hoverEnabled: true; onClicked: notifPop.silkyClearGroup(hcd.silky.key) }
                                        }
                                    }
                                }
                                // Silky: paper edges peeking out under a folded stack
                                Repeater {
                                    model: hcd.silkyStackH > 0.5 ? (hcd.silky.n > 2 ? 2 : 1) : 0
                                    Rectangle {
                                        required property int index
                                        z: -1 - index
                                        x: 10 * (index + 1); width: hcd.width - 20 * (index + 1)
                                        y: hcd.silkyHeadH + hc.height - 10 + 7 * index
                                        height: 17; radius: 14
                                        color: pal.tile
                                        opacity: (0.9 - 0.3 * index) * Math.min(1, hcd.silkyStackH / 7)
                                        border.width: 1; border.color: Qt.rgba(pal.tileBorder.r, pal.tileBorder.g, pal.tileBorder.b, pal.tileBorder.a * 0.3)
                                    }
                                }
                                Rectangle {
                                    id: hc
                                    y: hcd.silkyHeadH
                                    readonly property int nid: hcd.nid
"""

# test hook: open / close an app's stack without a click (qs -c MacShell ipc call silkystack toggle WeChat)
TOGGLE_ANCHOR = "    ListModel { id: notifHist }              // notification centre history, newest first\n"
TOGGLE = TOGGLE_ANCHOR + """    property string silkyStackRequest: ""
    IpcHandler {
        target: "silkystack"
        function toggle(app: string): void { root.silkyStackRequest = ""; root.silkyStackRequest = String(app).toLowerCase(); }
    }
"""
# the scroll block as the previous release wrote it (with the current deck)
NFL_NEW_V1 = NFL_WITHOUT_FADE.replace("                                Behavior on y { enabled: notifPop.visible && !root.notifClearing; NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }\n                                Rectangle {\n                                    anchors.horizontalCenter: parent.horizontalCenter\n                                    width: silkyMoreText", "                                Rectangle {\n                                    anchors.horizontalCenter: parent.horizontalCenter\n                                    width: silkyMoreText", 1)

# each app's newest card draws above its folded cards
Z_OLD = """                                    z: (flipAnim.running || flyDelay.running) ? 10 : 0
"""
Z_NEW = """                                    z: (flipAnim.running || flyDelay.running) ? 10 : (silky.mi === 0 ? 1 : 0)
"""

CLICK_OLD = """                                        onClicked: { root.notifActivate(hc.nid); ui.pop = ""; }
"""
CLICK_STACK_FIRST = """                                        // a folded stack opens first; an open card (or a single one) activates as before
                                        onClicked: { if (hcd.silkyStacked) { notifPop.silkyToggle(hcd.silky.key); return; } root.notifActivate(hc.nid); ui.pop = ""; }
"""
CLICK_ACTIVATE_ONLY = """                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: if (root.notifActivate(hc.nid, true)) ui.pop = ""
"""
CLICK_NEW = """                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            var id = hc.nid;
                                            if (root.notifActivate(id, true)) ui.pop = "";
                                            root.notifDelete(id);
                                        }
"""

CLICK_DISMISS_IMMEDIATELY = CLICK_NEW
CLICK_PRESS_ONLY = """                                        id: silkyCardPress
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: notifPop.silkyPress(hc.nid)
"""
CLICK_NEW = """                                        id: silkyCardPress
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (hcd.silkyStacked) {
                                                if (!notifPop.silkyClearIds.length) notifPop.silkyToggle(hcd.silky.key);
                                                return;
                                            }
                                            notifPop.silkyPress(hc.nid);
                                        }
"""
PRESS_CARD_OLD = """                                    HoverHandler { id: hhov }
                                    MouseArea {
"""
PRESS_CARD_NEW = """                                    HoverHandler { id: hhov }
                                    readonly property bool silkyPressed: (silkyCardPress.pressed && silkyCardPress.containsMouse)
                                        || notifPop.silkyPressedId === nid
                                    scale: silkyPressed && !root.reduceMotion ? 0.985 : 1
                                    Behavior on scale { NumberAnimation { duration: 75; easing.type: Easing.OutCubic } }
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: hc.radius
                                        color: pal.dark ? "#1affffff" : "#14000000"
                                        opacity: hc.silkyPressed ? 1 : 0
                                        visible: opacity > 0
                                        Behavior on opacity { NumberAnimation { duration: root.reduceMotion ? 0 : 75 } }
                                    }
                                    MouseArea {
"""

PRESS_CARD_WITHOUT_DRIFT = PRESS_CARD_NEW
PRESS_CARD_NEW = PRESS_CARD_WITHOUT_DRIFT.replace(
    "                                    Behavior on scale", """                                    transform: Translate {
                                        x: 8 * hcd.silkyClearT
                                        y: -7 * hcd.silkyClearT
                                    }
                                    Behavior on scale""", 1,
)

EXPAND_STACK = """                                    Rectangle {
                                        visible: hcd.silkyStacked
                                        anchors.right: parent.right; anchors.rightMargin: 10
                                        anchors.bottom: parent.bottom; anchors.bottomMargin: 10
                                        width: 24; height: 24; radius: 12
                                        color: expandStackMouse.containsMouse ? pal.btnHover : pal.btnOff
                                        Accessible.role: Accessible.Button
                                        Accessible.name: notifPop.silkyZh() ? "展开通知" : "Expand notifications"
                                        Accessible.onPressAction: notifPop.silkyToggle(hcd.silky.key)
                                        Glyph { anchors.centerIn: parent; width: 12; height: 12; kind: "chevR"; rotation: 90; color: pal.fg }
                                        MouseArea {
                                            id: expandStackMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: notifPop.silkyToggle(hcd.silky.key)
                                        }
                                    }
"""

NOTIFICATION_ACTIVATE_OLD = """    function notifActivate(id) {
        var n = root.notifRefs[id];
        if (n) {
            try {
                for (var i = 0; i < n.actions.length; i++)
                    if (n.actions[i].identifier === "default") { n.actions[i].invoke(); break; }
            } catch (e) {}
        }
        notifToastRemove(id);
    }
"""
NOTIFICATION_ACTIVATE_NEW = """    function notifAppKey(name) {
        return String(name || "").trim().toLowerCase().replace(/\\.desktop$/, "");
    }
    function notifAppEntry(record) {
        var hint = String(record.desktopEntry || "").replace(/\\.desktop$/i, "");
        var entry = hint ? DesktopEntries.byId(hint) : null;
        if (entry) return entry;
        var name = notifAppKey(record.app);
        if (!name) return null;
        entry = DesktopEntries.byId(record.app) || DesktopEntries.byId(name);
        if (entry) return entry;
        var entries = DesktopEntries.applications.values;
        return entries.find(e => notifAppKey(e.name) === name || notifAppKey(e.startupClass) === name) || null;
    }
    function notifOpenApp(record) {
        var entry = notifAppEntry(record);
        var keys = [record.desktopEntry, record.app, entry && entry.id, entry && entry.startupClass]
            .map(notifAppKey).filter(key => key !== "");
        var windows = ToplevelManager.toplevels.values;
        var matches = windows.filter(w => keys.indexOf(notifAppKey(w.appId)) >= 0);
        var target = root.swMru.find(w => matches.indexOf(w) >= 0) || matches[0];
        if (target) {
            Qt.callLater(function () { if (target) target.activate(); });
            return true;
        }
        if (!entry) return false;
        entry.execute();
        return true;
    }
    function notifActivate(id, openApp) {
        var n = root.notifRefs[id];
        var activated = false;
        if (n) {
            try {
                for (var i = 0; i < n.actions.length; i++) {
                    if (n.actions[i].identifier !== "default") continue;
                    n.actions[i].invoke();
                    activated = true;
                    break;
                }
            } catch (e) {}
        }
        if (openApp && !activated) {
            var index = notifIndex(notifHist, id);
            activated = index >= 0 && notifOpenApp(notifHist.get(index));
        }
        notifToastRemove(id);
        return activated;
    }
"""

DEMO_ANCHOR = "    ListModel { id: notifToasts }            // popups currently on screen, newest first\n"
DEMO = DEMO_ANCHOR + """    // Silky: sample notifications for checking the stacked list, without sending real ones
    //   qs -c MacShell ipc call silkynotif demo      adds them      qs -c MacShell ipc call silkynotif undemo   removes them
    IpcHandler {
        target: "silkynotif"
        function demo(): void {
            var zh = I18n.code().indexOf("zh") === 0;
            var rows = [["WeChat", zh ? "示例 · 张三" : "Sample · Alex", zh ? "晚上一起吃饭吗？" : "Dinner tonight?"],
                        ["Mail", zh ? "示例 · 周报" : "Sample · Weekly report", zh ? "本周进展已更新" : "This week's progress is in"],
                        ["WeChat", zh ? "示例 · 李四" : "Sample · Sam", zh ? "文件发你了" : "Sent you the file"],
                        ["Slack", zh ? "示例 · #design" : "Sample · #design", zh ? "新的设计稿" : "New mockups are up"],
                        ["WeChat", zh ? "示例 · 王五" : "Sample · Kim", zh ? "收到" : "Got it"],
                        ["Calendar", zh ? "示例 · 10:00 例会" : "Sample · 10:00 stand-up", zh ? "10 分钟后开始" : "Starts in 10 minutes"],
                        ["Mail", zh ? "示例 · 账单" : "Sample · Invoice", zh ? "11 月账单" : "November invoice"]];
            for (var i = rows.length - 1; i >= 0; i--)
                notifHist.insert(0, { nid: ++root.notifSeq, app: rows[i][0], desktopEntry: "", summary: rows[i][1], body: "[Silky demo] " + rows[i][2],
                                      icon: root.appIconFor(rows[i][0]), urgency: 1, time: Date.now() - i * 90000, timeout: 0 });
        }
        function undemo(): void {
            for (var i = notifHist.count - 1; i >= 0; i--)
                if (String(notifHist.get(i).body).indexOf("[Silky demo]") === 0) notifHist.remove(i);
        }
    }
"""
DEMO_WITHOUT_DESKTOP_ENTRY = DEMO.replace('app: rows[i][0], desktopEntry: "",', 'app: rows[i][0],', 1)

NOTIFICATION_ENTRY_OLD = '            nid: id, app: n.appName || "", summary: n.summary || "", body: n.body || "",\n'
NOTIFICATION_ENTRY_NEW = NOTIFICATION_ENTRY_OLD + '            desktopEntry: n.desktopEntry || "",\n'
NOTIFICATION_CARD_END = """                                        onCloseClicked: hcd.dissolve(1)          // dust away, then removed
                                    }
"""

NOTIFICATION_CARD_FEATHER = """                                        onCloseClicked: notifPop.silkyClear([hc.nid])
                                    }
                                    // Allocate the mask only for a visible card during a clear.
                                    layer.enabled: hcd.silkyClearT > 0 && hcd.opacity > 0.01
                                        && hcd.y + hcd.height > nfl.contentY && hcd.y < nfl.contentY + nfl.height
                                    layer.effect: MultiEffect {
                                        maskEnabled: true
                                        maskThresholdMin: 0.5
                                        maskSpreadAtMin: 1
                                        maskSource: silkyClearMask
                                    }
"""
NOTIFICATION_FEATHER_MASK = """                                Rectangle {
                                    id: silkyClearMask
                                    visible: false
                                    layer.enabled: hc.layer.enabled
                                    width: 4; height: Math.max(1, hc.height)
                                    readonly property real edge: Math.max(0, 1 - hcd.silkyClearT * 1.2)
                                    gradient: Gradient {
                                        GradientStop { position: 0; color: "white" }
                                        GradientStop { position: silkyClearMask.edge; color: "white" }
                                        GradientStop { position: Math.min(1, silkyClearMask.edge + 0.28); color: "transparent" }
                                    }
                                }
"""


FOCUS_OLD = ('            WlrLayershell.keyboardFocus: ((ui.pop === "wifi" || (ui.pop === "cc" && ui.ccPage === "wifi")) '
             '&& ui.wifiPrompt !== "") ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None\n')
FOCUS_NEW = ('            WlrLayershell.keyboardFocus: (ui.pop === "notif" && silkyWidgetDeck.wantsKeyboard) ? WlrKeyboardFocus.OnDemand\n'
             '                : ((ui.pop === "wifi" || (ui.pop === "cc" && ui.ccPage === "wifi")) '
             '&& ui.wifiPrompt !== "") ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None\n')


def strip_deck(text):
    """Remove a deck block left by an earlier version (at any indent), so the current DECK goes in fresh."""
    if DECK in text:
        return text
    match = re.search(r"^( *)SilkyWidgetDeck \{\n", text, re.M)
    if not match:
        return text
    indent = match.group(1)
    end = text.index("\n" + indent + "}\n", match.end()) + len(indent) + 3
    return text[:match.start()] + text[end:]


def float_notification_cards(text):
    if "id: notifCardMaterial" in text:
        start = text.index("                    // The notification centre has no shared surface;")
        end = text.index("                    MouseArea { anchors.fill: parent }", start)
        return text[:start] + FLOATING_CARDS + text[end:]
    if text.count("    property var hub: null\n") != 1:
        raise ValueError("MacBar integration point changed: shared hub")
    text = text.replace("    property var hub: null\n", DOCK_REFERENCE, 1)

    start = text.index("                    PopGlassCtx { id: notifPopGlass;")
    context_end = text.index("\n", start) + 1
    end = text.index("                    MouseArea { anchors.fill: parent }", context_end)
    text = text[:context_end] + FLOATING_CARDS + text[end:]

    start = text.index("                    Item {\n                        id: notifBody\n")
    end = text.index("                Component {\n                    id: menuGlassMaterial", start)
    panel = text[start:end]
    card = """                                    color: pal.tile
                                    border.width: 1; border.color: Qt.rgba(pal.tileBorder.r, pal.tileBorder.g, pal.tileBorder.b, pal.tileBorder.a * 0.4)"""
    card_glass = """                                    color: "transparent"
                                    Loader {
                                        anchors.fill: parent
                                        sourceComponent: notifCardMaterial
                                        onLoaded: item.r = hc.radius
                                    }"""
    if panel.count(card) != 1:
        raise ValueError("MacBar integration point changed: notification card")
    return text[:start] + panel.replace(card, card_glass, 1) + text[end:]


def remove_notification_header(text):
    body = text.index("                        id: notifBody\n")
    start = text.index("\n\n", body) + 2
    end = text.index("                    Text {\n" + EMPTY_NEW, start)
    scroll = text.index("                    Rectangle {\n                        id: notifScrollMask", end)
    empty = text[end:scroll]
    old = "                        x: 0; y: 96; width: parent.width; height: 60\n"
    new = "                        x: 0; y: notifPop.bodyTop; width: parent.width; height: 40\n"
    if new not in empty and empty.count(old) != 1:
        raise ValueError("MacBar integration point changed: empty notification label")
    return text[:start] + empty.replace(old, new, 1) + text[scroll:]


GRADIENT_CARD_END = NOTIFICATION_CARD_FEATHER + EXPAND_STACK + "                                }\n" + NOTIFICATION_FEATHER_MASK
FEATHER_CARD_END = """                                        onCloseClicked: notifPop.silkyClear([hc.nid])
                                    }
                                    // One texture pass, only for cards in the viewport while they clear.
                                    layer.enabled: hcd.silkyFeathering
                                    layer.smooth: true
                                    layer.effect: ShaderEffect {
                                        fragmentShader: Qt.resolvedUrl("silky-notification-feather.frag.qsb")
                                        property real progress: hcd.silkyClearT
                                    }
                                }
"""
FEATHER_CARD_END_WITH_ARROW = FEATHER_CARD_END[:-len("                                }\n")] + EXPAND_STACK + "                                }\n"


def integrate(text):
    text = macshell_notification_center.remove_activation(text)
    text = macshell_notification_center.remove_scroll(text)
    if "id: silkyStatusSummary" not in text:
        raise ValueError("Install the MacShell status integration first: python3 scripts/install-macshell-status.py")
    old_footer = CLEAR_NOTIFICATIONS.replace("notifPop.silkyClearAll()", "root.notifClearAnimated()")
    text = strip_deck(text.replace(old_footer, CLEAR_NOTIFICATIONS, 1))
    # the deck sits inside the scroll block: with an older deck stripped, put the current one back in its place
    for version in (NFL_NEW_V1, NFL_WITHOUT_FADE, NFL_WITH_TALL_HEADER, NFL_WITH_COMPACT_HEADER, NFL_NEW):
        bare = version.replace(DECK, "")
        if bare in text:
            text = text.replace(bare, NFL_NEW, 1)
            break
    if FULL_H_V1 in text:
        text = text.replace(FULL_H_V1, FULL_H_OLD, 1)
    text = text.replace(FULL_H_PREVIOUS, FULL_H_NEW, 1)
    text = text.replace(FULL_H_WITH_DOCK, FULL_H_NEW, 1)
    text = text.replace(FULL_H_WITH_COMPACT_HEADER, FULL_H_NEW, 1)
    for old, new in ((STACK_V1, STACK), (STACK_V2, STACK), (STACK_V3, STACK), (STACK_BEFORE_MOTION, STACK),
                     (STACK_WITH_GRADIENT, STACK), (CARD_WITH_GRADIENT, CARD_NEW),
                     (GRADIENT_CARD_END, FEATHER_CARD_END), (FEATHER_CARD_END_WITH_ARROW, FEATHER_CARD_END),
                     (PRESS_CARD_WITHOUT_DRIFT, PRESS_CARD_NEW),
                     (CARD_NEW_V1, CARD_NEW), (CARD_NEW_V2, CARD_NEW), (CARD_BEFORE_FEATHER, CARD_NEW),
                     (HC_NEW_V1, HC_NEW), (NFL_NEW_V1, NFL_NEW), (NFL_WITHOUT_FADE, NFL_NEW),
                     (NFL_WITH_TALL_HEADER, NFL_NEW), (NFL_WITH_COMPACT_HEADER, NFL_NEW),
                     (CLICK_STACK_FIRST, CLICK_NEW), (CLICK_ACTIVATE_ONLY, CLICK_NEW),
                     (CLICK_DISMISS_IMMEDIATELY, CLICK_NEW), (CLICK_PRESS_ONLY, CLICK_NEW),
                     (NOTIFICATION_CARD_END + EXPAND_STACK + "                                }\n", FEATHER_CARD_END),
                     (DEMO_WITHOUT_DESKTOP_ENTRY, DEMO)):
        if old in text:
            text = text.replace(old, new, 1)
    for before, after in ((FULL_H_OLD, FULL_H_NEW), (STACK_ANCHOR, STACK), (EMPTY_OLD, EMPTY_NEW), (NFL_OLD, NFL_NEW),
                          (CARD_OLD, CARD_NEW), (HC_OLD, HC_NEW), (Z_OLD, Z_NEW), (CLICK_OLD, CLICK_NEW),
                          (TOGGLE_ANCHOR, TOGGLE), (DEMO_ANCHOR, DEMO),
                          (NOTIFICATION_ENTRY_OLD, NOTIFICATION_ENTRY_NEW),
                          (NOTIFICATION_ACTIVATE_OLD, NOTIFICATION_ACTIVATE_NEW),
                          (NOTIFICATION_CARD_END + "                                }\n", FEATHER_CARD_END),
                          (PRESS_CARD_OLD, PRESS_CARD_NEW),
                          (FOCUS_OLD, FOCUS_NEW)):
        if after in text:
            continue
        if text.count(before) != 1:
            raise ValueError(f"MacBar integration point changed: {before.strip().splitlines()[0][:90]}")
        text = text.replace(before, after, 1)
    text = float_notification_cards(text).replace(NOTIFICATION_CLIP_PROBE, NOTIFICATION_CLIP_SUPPORT, 1)
    if NOTIFICATION_CLIP_SUPPORT not in text:
        if text.count(DOCK_REFERENCE) != 1:
            raise ValueError("MacBar integration point changed: notification Dock reference")
        text = text.replace(DOCK_REFERENCE, DOCK_REFERENCE + NOTIFICATION_CLIP_SUPPORT, 1)
    return macshell_notification_center.integrate(remove_notification_header(text))


def fetch_logos(root):
    """Download the AI logos once; on failure the widget shows coloured letter tiles instead."""
    folder = root / "assets/ai-logos"
    folder.mkdir(parents=True, exist_ok=True)
    for name, remote in LOGOS.items():
        target = folder / f"{name}.svg"
        if target.exists():
            continue
        try:
            with urllib.request.urlopen(LOGO_PACKAGE + remote, timeout=15) as response:
                svg = response.read(65536).decode("utf-8")
        except (OSError, UnicodeDecodeError) as error:
            print(f"Logo {name} not downloaded ({error}); the widget uses a letter tile")
            continue
        if not svg.lstrip().startswith("<svg") or re.search(r"<script|<foreignObject|\bon\w+=|href=\"(?!#)", svg, re.I):
            print(f"Logo {name} rejected: not a plain SVG")
            continue
        target.write_text(svg)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("shell_dir", type=Path, nargs="?", default=Path(
        os.environ.get("MACSHELL_DIR", Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
                       / "quickshell/MacShell")))
    args = parser.parse_args()
    root = args.shell_dir
    bar = root / "MacBar.qml"
    shell = root / "shell.qml"
    try:
        if (root / "VERSION").read_text().strip() not in VERSIONS:
            raise ValueError("This integration targets MacShell 0.5.1 to 0.5.3.")
        missing = [name for name in NEEDS if not (root / name).exists()]
        if missing:
            raise ValueError("MacShell is missing " + ", ".join(missing))
        if not shutil.which("python3"):
            raise ValueError("python3 is required for the widget data process")
        original = bar.read_text()
        updated = integrate(original)
        shell_original = shell.read_text()
        if SHELL_BAR_WITH_DOCK in shell_original:
            shell_updated = shell_original
        elif shell_original.count(SHELL_BAR) == 1:
            shell_updated = shell_original.replace(SHELL_BAR, SHELL_BAR_WITH_DOCK, 1)
        else:
            raise ValueError("MacShell integration point changed: MacBar in shell.qml")
    except (OSError, ValueError) as error:
        parser.exit(1, f"{error}\n")
    if args.check:
        print(f"MacShell widgets integration compatible at {root}")
        return

    (root / "assets").mkdir(exist_ok=True)
    (Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "silky").mkdir(parents=True, exist_ok=True)
    changed = False
    for source in sorted(SOURCE.iterdir()):
        if not source.is_file():
            continue
        destination = root / "assets/silky-widgets.py" if source.name == "widgets.py" else root / source.name
        if not destination.exists() or destination.read_bytes() != source.read_bytes():
            with NamedTemporaryFile(dir=destination.parent, delete=False) as tmp:
                tmp.write(source.read_bytes())
            Path(tmp.name).replace(destination)
            changed = True
    fetch_logos(root)
    updates = [(bar, original, updated), (shell, shell_original, shell_updated)]
    marker = root / "SilkyGlassMarker.qml"
    if marker.is_file():
        updates.append((marker, marker.read_text(), (SOURCE.parent / marker.name).read_text()))
    for path, before, after in updates:
        if after == before:
            continue
        backup = path.with_name(f"{path.name}.bak.silky-widgets-{os.urandom(4).hex()}")
        shutil.copy2(path, backup)
        with NamedTemporaryFile(mode="w", dir=root, delete=False) as tmp:
            tmp.write(after)
            os.fchmod(tmp.fileno(), stat.S_IMODE(path.stat().st_mode))
        Path(tmp.name).replace(path)
        print(f"Backup: {backup}")
    if updated == original and changed:
        bar.touch()      # atomic replacement of a child QML file can leave its old watcher behind
    print(f"MacShell widgets installed at {root}")


if __name__ == "__main__":
    main()
