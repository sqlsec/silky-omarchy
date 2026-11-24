#!/usr/bin/env python3
"""Give Settings a Dock icon and the system menu's glass sidebar."""
from pathlib import Path
import sys


path = Path(sys.argv[1])
original = path.read_text()
text = original

edits = [
    (
        (
            '            // Keep the sidebar frosted but readable over text-heavy windows.\n'
            '            readonly property color sidebarGlass: dark ? Qt.rgba(0.17, 0.17, 0.18, 0.96) : Qt.rgba(0.94, 0.94, 0.96, 0.97)\n',
            "            // Match the Omarchy system menu's dark and light glass tints (ARGB).\n"
            '            readonly property color sidebarGlass: dark ? "#8c1c1c1e" : "#adf7f7f9"\n',
            "            // System menu glass tint at 61% dark and 74% light opacity (ARGB).\n"
            '            readonly property color sidebarGlass: dark ? "#9c1c1c1e" : "#bdf7f7f9"\n',
        ),
        "            // Darker frosted sidebar tint at 80% dark and 82% light opacity (ARGB).\n"
        '            readonly property color sidebarGlass: dark ? "#cc1c1c1e" : "#d1f7f7f9"\n',
    ),
    (
        '                // the window draws its own macOS-style edge: no Hyprland border, and Hyprland\'s rounding (used for its\n'
        "                // shadow and the blur behind the sidebar) matches the window's own corner radius\n",
        "                // Match About: scale the compositor's rounded outline with the UI.\n",
    ),
    ("Math.round(frame.radius * root.uiS)", "Math.round(frame.cornerRadius * root.uiS)"),
    (
        '            readonly property color windowBorder: dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.22)\n'
        '            // two-tone macOS window edge: a thin dark line outside, a soft highlight just inside it\n'
        '            readonly property color edgeOuter: Qt.rgba(1, 1, 1, 0.50)\n'
        '            readonly property color edgeInner: dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.65)\n'
        '            readonly property color sep:',
        '            // Separators inside the Settings window.\n'
        '            readonly property color sep:',
    ),
    (
        '''            radius: 12
            color: "transparent"        // the sidebar is translucent (blur of what is behind the window), the pages are opaque
            border.width: 1
            border.color: pal.edgeOuter

            // inner highlight (on top of everything, never takes the mouse)
            Rectangle {
                anchors.fill: parent; anchors.margins: 1
                radius: frame.radius - 1
                color: "transparent"
                border.width: 1; border.color: pal.edgeInner
                z: 900
            }
''',
        '''            // Paint the full window; Hyprland clips the frame and shadow together.
            readonly property real cornerRadius: 18
            color: "transparent"
            border.width: 0
''',
    ),
    (
        'Rectangle { anchors.fill: parent; radius: frame.radius; color: Qt.rgba(0, 0, 0, pal.dark ? 0.45 : 0.25) }',
        'Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, pal.dark ? 0.45 : 0.25) }',
    ),
    (
        '''            // opaque page area: from the sidebar's right edge to the window edge (rounded on the right only)
            Rectangle {
                x: sidebar.x + sidebar.width; y: 1
                width: parent.width - x - 1; height: parent.height - 2
                radius: 11
                color: pal.contentSolid
                Rectangle { anchors.left: parent.left; width: 12; height: parent.height; color: parent.color }
            }''',
        '''            // The opaque page reaches the compositor's rounded window outline.
            Rectangle {
                x: sidebar.x + sidebar.width
                width: parent.width - x; height: parent.height
                color: pal.contentSolid
            }''',
    ),
    (
        '''                x: sidebar.floating ? 8 : 1; y: sidebar.floating ? 8 : 1
                width: sidebar.floating ? 224 : 232
                height: parent.height - (sidebar.floating ? 16 : 2)
                radius: sidebar.floating ? 18 : 11
                // frosted: a translucent pane over Hyprland's blur of what's behind the window (no Liquid Glass shader)''',
        '''                x: sidebar.floating ? 8 : 0; y: sidebar.floating ? 8 : 0
                width: sidebar.floating ? 224 : 233
                height: parent.height - (sidebar.floating ? 16 : 0)
                radius: sidebar.floating ? 18 : 0
                // Keep the sidebar's translucent tint over the backdrop.''',
    ),
    (
        '''                // translucent fill, drawn as ONE layer so the rounded body and the square right edge don't add up to a darker band:
                // both shapes are opaque inside the layer, and the layer carries the translucency
                Item {
                    visible: !sidebar.floating
                    anchors.fill: parent
                    z: -1
                    layer.enabled: true
                    opacity: pal.sidebarGlass.a
                    Rectangle { anchors.fill: parent; radius: sidebar.radius; color: Qt.rgba(pal.sidebarGlass.r, pal.sidebarGlass.g, pal.sidebarGlass.b, 1) }
                    Rectangle { anchors.right: parent.right; width: 14; height: parent.height; color: Qt.rgba(pal.sidebarGlass.r, pal.sidebarGlass.g, pal.sidebarGlass.b, 1) }
                }''',
        '''                Rectangle {
                    visible: !sidebar.floating
                    anchors.fill: parent
                    z: -1
                    color: pal.sidebarGlass
                }''',
    ),
    (
        '        return (id === "org.quickshell" && tl.title === "Clock") ? "macshell-clock" : id;',
        '        if (id === "org.quickshell" && tl.title === "macshell Settings") return "macshell-settings";\n'
        '        return (id === "org.quickshell" && tl.title === "Clock") ? "macshell-clock" : id;',
    ),
    (
        '''            var e2 = lookup(extras[x].appId);
            var own = isShellApp(extras[x].appId);
            list.push({ kind: "app", key: extras[x].key, appId: e2 ? e2.id : extras[x].appId,
                        name: own ? "MacShell" : (e2 ? e2.name : extras[x].appId),
                        icon: own ? logoPath : (e2 ? e2.icon : extras[x].appId.toLowerCase()),''',
        '''            var settings = extras[x].appId === "macshell-settings";
            var e2 = lookup(extras[x].appId);
            var own = isShellApp(extras[x].appId);
            list.push({ kind: "app", key: extras[x].key, appId: e2 ? e2.id : extras[x].appId,
                        name: settings ? I18n.tr("System Settings") : (own ? "MacShell" : (e2 ? e2.name : extras[x].appId)),
                        icon: settings ? "preferences-system" : (own ? logoPath : (e2 ? e2.icon : extras[x].appId.toLowerCase())),''',
    ),
    (
        '        appId = dockAppId(appId);\n        if (!appId) return null;',
        '        appId = dockAppId(appId);\n        if (!appId || appId === "macshell-settings") return null;',
    ),
    (
        '        registerSettingsRule(false);\n        rebuild();',
        '        registerSettingsRule(true);\n        rebuild();',
    ),
    (
        (
            'match = { title = "^(macshell Settings)$" }, float = true, center = true, border_size = 0 })',
            'match = { class = "^org[.]quickshell$", initial_title = "^macshell Settings$" }, '
            'float = true, center = true, border_size = 0, no_blur = true, rounding = 18 })',
        ),
        'match = { class = "^org[.]quickshell$", initial_title = "^macshell Settings$" }, '
        'float = true, center = true, border_size = 0, no_blur = false, xray = false, rounding = 18 })',
    ),
]

for before, after in edits:
    if after in text:
        continue
    alternatives = (before,) if isinstance(before, str) else before
    matches = [candidate for candidate in alternatives if candidate in text]
    if len(matches) != 1 or text.count(matches[0]) != 1:
        raise SystemExit(f"Settings tuning ({path}): expected one match for {alternatives[0][:90]!r}")
    text = text.replace(matches[0], after)

if text != original:
    path.write_text(text)
