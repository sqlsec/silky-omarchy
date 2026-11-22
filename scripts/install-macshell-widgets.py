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

SOURCE = Path(__file__).resolve().parents[1] / "config/macshell/widgets"
VERSIONS = {"0.5.1", "0.5.2", "0.5.3"}
NEEDS = ["WeatherIcon.qml", "ChinaCalendar.js", "I18n.js"]
# Brand logos for the AI usage widget, from LobeHub's MIT-licensed icon set (the logos are their owners' trademarks,
# so they are fetched at install time instead of being kept in this repository). Pinned for reproducibility.
LOGO_PACKAGE = "https://cdn.jsdelivr.net/npm/@lobehub/icons-static-svg@1.104.0/icons/"
LOGOS = {"claude": "claude-color.svg", "codex": "codex-color.svg", "deepseek": "deepseek-color.svg"}

# ───── MacBar patches ─────
# Earlier releases of this installer wrote FULL_H_V1 and a deck block beside the list; both are migrated.
FULL_H_OLD = ("                    property real fullH: 92 + (notifHist.count === 0 ? 70 : "
              "(root.notifClearing ? Math.max(70, nfl.height) : nfl.height)) + 14\n")
FULL_H_V1 = ("                    readonly property real silkyListH: notifHist.count === 0 ? 70 : "
             "(root.notifClearing ? Math.max(70, nfl.height) : nfl.height)\n"
             "                    // Silky widgets sit under the list (scripts/install-macshell-widgets.py)\n"
             "                    property real fullH: 92 + silkyListH + 14 + (silkyWidgetDeck.height > 0 ? silkyWidgetDeck.height + 6 : 0)\n")
FULL_H_NEW = ("                    // Silky: notifications and widgets scroll together in nfl (scripts/install-macshell-widgets.py)\n"
              "                    readonly property real silkyNotifH: notifHist.count === 0 ? 64 : ncol.height\n"
              "                    readonly property real silkyAvail: Math.max(160, (ui.height - dstY - 12) / ps - 92 - 14)\n"
              "                    property real fullH: 92 + nfl.height + 14\n")

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
                            viewHeight: nfl.silkyOverflow ? nfl.height : 0
                            // the Control Center tile material: the panel's liquid glass again, with the same thin border
                            glass: Component {
                                Item {
                                    property real r: 22
                                    GGlass { anchors.fill: parent; gx: notifPopGlass.ctx; cornerR: parent.r; thickness: 22; shadowAmt: 0; flatInner: 1 }
                                    CornerBorder {
                                        z: 2; anchors.fill: parent; cornerR: parent.r; lineW: 0.8
                                        dark: notifPopGlass.ctx.dark; tint: notifPopGlass.ctx.borderTint; amount: notifPopGlass.ctx.borderAmount
                                    }
                                }
                            }
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
NFL_NEW_V1 = NFL_NEW.replace("                                Behavior on y { enabled: notifPop.visible && !root.notifClearing; NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }\n                                Rectangle {\n                                    anchors.horizontalCenter: parent.horizontalCenter\n                                    width: silkyMoreText", "                                Rectangle {\n                                    anchors.horizontalCenter: parent.horizontalCenter\n                                    width: silkyMoreText", 1)

# each app's newest card draws above its folded cards
Z_OLD = """                                    z: (flipAnim.running || flyDelay.running) ? 10 : 0
"""
Z_NEW = """                                    z: (flipAnim.running || flyDelay.running) ? 10 : (silky.mi === 0 ? 1 : 0)
"""

CLICK_OLD = """                                        onClicked: { root.notifActivate(hc.nid); ui.pop = ""; }
"""
CLICK_NEW = """                                        // a folded stack opens first; an open card (or a single one) activates as before
                                        onClicked: { if (hcd.silkyStacked) { notifPop.silkyToggle(hcd.silky.key); return; } root.notifActivate(hc.nid); ui.pop = ""; }
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
                notifHist.insert(0, { nid: ++root.notifSeq, app: rows[i][0], summary: rows[i][1], body: "[Silky demo] " + rows[i][2],
                                      icon: root.appIconFor(rows[i][0]), urgency: 1, time: Date.now() - i * 90000, timeout: 0 });
        }
        function undemo(): void {
            for (var i = notifHist.count - 1; i >= 0; i--)
                if (String(notifHist.get(i).body).indexOf("[Silky demo]") === 0) notifHist.remove(i);
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


def integrate(text):
    if "id: silkyStatusSummary" not in text:
        raise ValueError("Install the MacShell status integration first: python3 scripts/install-macshell-status.py")
    text = strip_deck(text)
    # the deck sits inside the scroll block: with an older deck stripped, put the current one back in its place
    for version in (NFL_NEW_V1, NFL_NEW):
        bare = version.replace(DECK, "")
        if bare in text:
            text = text.replace(bare, NFL_NEW, 1)
            break
    if FULL_H_V1 in text:
        text = text.replace(FULL_H_V1, FULL_H_OLD, 1)
    for old, new in ((STACK_V1, STACK), (STACK_V2, STACK), (STACK_V3, STACK), (CARD_NEW_V1, CARD_NEW), (CARD_NEW_V2, CARD_NEW),
                     (HC_NEW_V1, HC_NEW), (NFL_NEW_V1, NFL_NEW)):     # earlier releases of the stacked list
        if old in text:
            text = text.replace(old, new, 1)
    for before, after in ((FULL_H_OLD, FULL_H_NEW), (STACK_ANCHOR, STACK), (EMPTY_OLD, EMPTY_NEW), (NFL_OLD, NFL_NEW),
                          (CARD_OLD, CARD_NEW), (HC_OLD, HC_NEW), (Z_OLD, Z_NEW), (CLICK_OLD, CLICK_NEW),
                          (TOGGLE_ANCHOR, TOGGLE), (DEMO_ANCHOR, DEMO),
                          (FOCUS_OLD, FOCUS_NEW)):
        if after in text:
            continue
        if text.count(before) != 1:
            raise ValueError(f"MacBar integration point changed: {before.strip().splitlines()[0][:90]}")
        text = text.replace(before, after, 1)
    return text


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
    if updated != original:
        backup = bar.with_name(f"MacBar.qml.bak.silky-widgets-{os.urandom(4).hex()}")
        shutil.copy2(bar, backup)
        with NamedTemporaryFile(mode="w", dir=root, delete=False) as tmp:
            tmp.write(updated)
            os.fchmod(tmp.fileno(), stat.S_IMODE(bar.stat().st_mode))
        Path(tmp.name).replace(bar)
        print(f"Backup: {backup}")
    elif changed:
        bar.touch()      # atomic replacement of a child QML file can leave its old watcher behind
    print(f"MacShell widgets installed at {root}")


if __name__ == "__main__":
    main()
