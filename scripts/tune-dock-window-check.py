#!/usr/bin/env python3
"""Check the app's front window in the MacShell Dock context menu, as macOS does.

The window list used to prefix "✓" only when a window was activated, which is
only the case while the app itself has focus, so the mark rarely showed and
shifted that title out of line. The menu now marks the app's most recently
focused window that is not minimized (recentWindow, the same window a Dock
click brings back), draws the check as a path in a left column, and indents
every row of a menu that lists windows so the labels stay aligned.

When tune-dock-window-pick.py has added recentWindow (run it first), the
check uses it; otherwise the window with the lowest Hyprland focusHistoryID.
Usage: tune-dock-window-check.py <MacDock.qml>
"""

import sys
from pathlib import Path

MARK = "silkyFront"

REPLACEMENTS = (
    (
        "menu entries",
        """\
        if (wins.length > 0) {
            for (var i = 0; i < wins.length && i < 8; i++) {
                (function (w) {
                    var t = w.title && w.title.length > 0 ? w.title : item.name;
                    m.push({ kind: "item", label: (w.activated ? "\\u2713  " : "") + t,
                             run: function () { activateToplevel(w); } });
                })(wins[i]);
            }
""",
        """\
        if (wins.length > 0) {
            // Silky: check the app's front window (focused, else the last one used that is not minimized), as macOS does
            var silkyShown = [];
            for (var si = 0; si < wins.length; si++) if (!isMinimized(wins[si])) silkyShown.push(wins[si]);
            var silkyFront = null;
            for (var sj = 0; sj < wins.length; sj++) if (wins[sj].activated) silkyFront = wins[sj];
            if (!silkyFront && silkyShown.length > 0) silkyFront = RECENT(silkyShown);
            for (var i = 0; i < wins.length && i < 8; i++) {
                (function (w) {
                    var t = w.title && w.title.length > 0 ? w.title : item.name;
                    m.push({ kind: "item", label: t, checked: w === silkyFront,
                             run: function () { activateToplevel(w); } });
                })(wins[i]);
            }
""",
    ),
    (
        "menu width",
        "                readonly property real menuW: Math.max(Math.round(168 * root.labelK), Math.min(Math.round(360 * root.labelK), Math.ceil(menuTextW) + Math.round(38 * root.labelK)))\n",
        """\
                // Silky: menus that list windows get a check column on the left, like macOS
                property bool menuChecks: false
                readonly property real menuW: Math.max(Math.round(168 * root.labelK), Math.min(Math.round(360 * root.labelK), Math.ceil(menuTextW) + Math.round(38 * root.labelK) + (menuChecks ? Math.round(11 * root.labelK) : 0)))
""",
    ),
    (
        "menu measuring",
        """\
                function measureMenu() {
                    var w = 0;
                    for (var i = 0; i < menuModel.length; i++) {
                        var e = menuModel[i];
""",
        """\
                function measureMenu() {
                    var w = 0, checks = false;
                    for (var i = 0; i < menuModel.length; i++) {
                        var e = menuModel[i];
                        if (e.checked !== undefined) checks = true;
""",
    ),
    (
        "menu measuring result",
        "                    menuTextW = w;\n",
        "                    menuTextW = w;\n                    menuChecks = checks;\n",
    ),
    (
        "menu row label",
        """\
                                Text {
                                    visible: !mi.isSep
                                    x: Math.round(11 * menu.k)
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 2 * Math.round(11 * menu.k)
""",
        """\
                                // Silky: check mark for the front window, an 8 x 8 pt path with round caps (same colour as the label)
                                Canvas {
                                    id: miCheck
                                    visible: !mi.isSep && mi.modelData.checked === true
                                    readonly property color ink: (!mi.off && mia.containsMouse) ? "white"
                                        : (menu.dark ? Qt.rgba(1, 1, 1, 0.92) : Qt.rgba(0, 0, 0, 0.86))
                                    x: Math.round(8 * menu.k)
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.round(10 * menu.k)
                                    height: width
                                    onInkChanged: requestPaint()
                                    onWidthChanged: requestPaint()
                                    onVisibleChanged: if (visible) requestPaint()
                                    onPaint: {
                                        var c = getContext("2d"), s = width / 10;
                                        c.reset();
                                        c.lineWidth = 1.6 * s;
                                        c.lineCap = "round";
                                        c.lineJoin = "round";
                                        c.strokeStyle = ink;
                                        c.beginPath();
                                        c.moveTo(1.5 * s, 5.4 * s);
                                        c.lineTo(4.0 * s, 8.0 * s);
                                        c.lineTo(8.6 * s, 1.8 * s);
                                        c.stroke();
                                    }
                                }
                                Text {
                                    visible: !mi.isSep
                                    x: Math.round((ui.menuChecks ? 22 : 11) * menu.k)
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - x - Math.round(11 * menu.k)
""",
    ),
)


FALLBACK_ANCHOR = "    function activateToplevel(tl) {\n"
FALLBACK = """\
    // Silky: most recently focused window by Hyprland's focus history (used when recentWindow is not installed)
    function silkyRecentWindow(wins) {
        var best = wins[0], bestHistory = 1e9;
        for (var i = 0; i < wins.length; i++) {
            var h = hyprToplevel(wins[i]), o = h ? (h.lastIpcObject || {}) : {};
            var history = typeof o.focusHistoryID === "number" && o.focusHistoryID >= 0 ? o.focusHistoryID : 1e8;
            if (history < bestHistory) { best = wins[i]; bestHistory = history; }
        }
        return best;
    }
"""


def tune(text):
    if MARK in text:
        return text
    if "function recentWindow(" in text:
        recent = "recentWindow"
    else:
        if text.count(FALLBACK_ANCHOR) != 1:
            raise ValueError("expected one activateToplevel function")
        text = text.replace(FALLBACK_ANCHOR, FALLBACK + FALLBACK_ANCHOR, 1)
        recent = "silkyRecentWindow"
    for label, old, new in REPLACEMENTS:
        new = new.replace("RECENT(", recent + "(")
        if text.count(old) != 1:
            raise ValueError(f"expected one {label}")
        text = text.replace(old, new, 1)
    return text


if __name__ == "__main__":
    try:
        path = Path(sys.argv[1])
        original = path.read_text()
        updated = tune(original)
        if updated != original:
            path.write_text(updated)
    except (IndexError, OSError, ValueError) as error:
        sys.exit(f"MacShell Dock window check: {error}")
