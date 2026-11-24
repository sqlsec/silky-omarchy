#!/usr/bin/env python3
"""Keep MacShell's system menu responsive and run its actions on one click."""

import sys
from pathlib import Path


def replace_once(text, old, new):
    if new in text:
        return text
    if text.count(old) != 1:
        raise ValueError(f"expected one occurrence of {old.strip().splitlines()[0]!r}")
    return text.replace(old, new, 1)


def tune(text):
    text = replace_once(
        text,
        "    property var activeWin: null\n",
        "    property var activeWin: null\n    property var silkySystemMenuModel: null\n",
    )
    text = replace_once(
        text,
        '        if (name === "apple") {\n            m.push(ico(mi("About This Linux"',
        '        if (name === "apple") {\n'
        '            if (silkySystemMenuModel) return silkySystemMenuModel;\n'
        '            m.push(ico(mi("About This Linux"',
    )
    for label, action, icon in (
        ("Restart", 'sh("systemctl reboot")', "m_restart"),
        ("Shut Down", 'sh("systemctl poweroff")', "m_power"),
        ("Log Out", "root.logOut()", "m_logout"),
    ):
        text = replace_once(
            text,
            f'            m.push(ico(mc("{label}\\u2026", function () {{ {action}; }}), "{icon}"));',
            f'            m.push(ico(mi("{label}\\u2026", "", function () {{ {action}; }}), "{icon}"));',
        )
    logout = '            m.push(ico(mi("Log Out\\u2026", "", function () { root.logOut(); }), "m_logout"));'
    text = replace_once(text, logout, logout + "\n            silkySystemMenuModel = m;")
    text = replace_once(
        text,
        '                    if (name === "spot") { spCalm = spReqCalm; spReqCalm = false; }\n'
        '                    menuX = x;',
        '''                    if (name === "apple") {
                        // The system actions are independent of the focused window.
                        menuX = menuDropX = x;
                        menuModel = root.menuModelFor(name);
                        pop = name;
                        return;
                    }
                    if (name === "spot") { spCalm = spReqCalm; spReqCalm = false; }
                    menuX = x;''',
    )
    if "readonly property bool panelTextWhite: darkMode\n" in text:
        text = replace_once(
            text,
            '                    if (pop !== "" && pop !== "spot") toneT.restart();',
            '                    if (pop !== "" && pop !== "spot" && pop !== "apple") toneT.restart();\n'
            '                    else toneT.stop();',
        )
        text = replace_once(
            text,
            '                        if (ui.pop !== "" && ui.pop !== "spot") toneT.restart();',
            '                        if (ui.pop !== "" && ui.pop !== "spot" && ui.pop !== "apple") toneT.restart();',
        )
    text = replace_once(
        text,
        '''                    opacity: ui.isMenu ? 1 : 0
                    visible: opacity > 0
                    scale: root.barPopupScale * (ui.isMenu ? 1 : 0.97)
                    transformOrigin: Item.TopLeft
                    Behavior on opacity { NumberAnimation { duration: 90 } }
                    Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }''',
        '''                    // Retarget one animation so the glass and content reverse together.
                    // Ease in from clear while the compositor prepares the backdrop area.
                    property real reveal: ui.isMenu ? 1 : 0
                    opacity: reveal
                    onOpacityChanged: if (typeof root.pokeGlassMarkers === "function") root.pokeGlassMarkers()
                    visible: reveal > 0
                    enabled: ui.isMenu
                    scale: root.barPopupScale * (0.97 + 0.03 * reveal)
                    transformOrigin: Item.TopLeft
                    Behavior on reveal {
                        enabled: !root.reduceMotion
                        NumberAnimation { duration: ui.isMenu ? 120 : 90; easing.type: Easing.InOutCubic }
                    }''',
    )
    # Older 0.5.1 configurations already keep the inline material instantiated.
    if "                        active: menuPop.visible\n" in text:
        text = replace_once(
            text,
            "                        active: menuPop.visible\n",
            "                        // Keep the material registered across close and reopen.\n",
        )
    return text


if __name__ == "__main__":
    path = Path(sys.argv[1])
    original = path.read_text()
    try:
        updated = tune(original)
    except ValueError as error:
        sys.exit(f"MacShell system menu: {error}")
    if updated != original:
        path.write_text(updated)
