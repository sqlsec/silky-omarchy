#!/usr/bin/env python3
"""Tune MacShell's "Normal Blur" appearance and simplify the About window's trim.

With barStyle / dockStyle "blur", Hyprland blurs what is under each MacShell surface and MacShell only draws a tint
on top. MacShell's tints for that style were much heavier than Liquid Glass (dark: Dock and panels 38 %, the menu bar's
dropdown menus 64 %; Liquid Glass uses ~21 % plus a small brightness lift), so the blur read dark and flat. This:

  * lowers the dark tint of the Dock and the panels (GGlass) to Liquid Glass's Glass Opacity x 0.55 (0.21 at the Silky default);
  * lowers the dropdown menus (LGlass) to 0.10 + Glass Opacity x 0.5 (dark) / 0.12 + x 0.45 (light);
  * keeps the fade behind a clear menu bar below the `macbar` layer rule's ignore_alpha (0.05), so Hyprland does not blur a
    dark strip under the bar (it used to peak at 30 %);
  * adds Liquid Glass's soft light from above: a white sheen fading from the top edge, in light and dark mode;
  * removes the About window's two outlines, gives Hyprland sole control of its corners,
    and softens its "More Info..." button.

Usage: tune-native-blur.py <MacShell dir>
"""
from pathlib import Path
import sys

shell = Path(sys.argv[1])


def tune(path, edits):
    text = path.read_text()
    original = text
    for old, new in edits:
        if new in text:
            continue
        alternatives = (old,) if isinstance(old, str) else old
        matches = [candidate for candidate in alternatives if candidate in text]
        if len(matches) != 1 or text.count(matches[0]) != 1:
            raise SystemExit(f"Normal Blur tuning ({path.name}): expected one match for {alternatives[0][:70]!r}")
        text = text.replace(matches[0], new)
    if text != original:
        path.write_text(text)


def sheen(indent, dark_expr):
    """Liquid Glass's lift: brighter at the top, fading downward. Child of the tint rectangle (inherits its radius)."""
    p = " " * indent
    return (
        f"{p}// Silky: Liquid Glass's soft light from above, over the Hyprland blur\n"
        f"{p}Rectangle {{\n"
        f"{p}    anchors.fill: parent\n"
        f"{p}    radius: parent.radius\n"
        f"{p}    gradient: Gradient {{\n"
        f"{p}        GradientStop {{ position: 0.0; color: Qt.rgba(1, 1, 1, ({dark_expr}) ? 0.07 : 0.12) }}\n"
        f"{p}        GradientStop {{ position: 0.5; color: Qt.rgba(1, 1, 1, ({dark_expr}) ? 0.025 : 0.05) }}\n"
        f"{p}        GradientStop {{ position: 1.0; color: Qt.rgba(1, 1, 1, ({dark_expr}) ? 0.015 : 0.03) }}\n"
        f"{p}    }}\n"
        f"{p}}}\n"
    )


tune(shell / "MacBar.qml", [
    # dropdown menus / popovers (LGlass)
    (
        "            color: g.dark ? Qt.rgba(0.12, 0.12, 0.13, 0.30 + g.tint * 0.9) : Qt.rgba(1, 1, 1, 0.30 + g.tint * 0.7)\n"
        "            border.width: 1\n"
        "            border.color: g.dark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.55)\n"
        "        }\n",
        "            color: g.dark ? Qt.rgba(0.12, 0.12, 0.13, 0.10 + g.tint * 0.5) : Qt.rgba(1, 1, 1, 0.12 + g.tint * 0.45)\n"
        "            border.width: 1\n"
        "            border.color: g.dark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.55)\n"
        + sheen(12, "g.dark") +
        "        }\n",
    ),
    # Control Center, notifications, Applications panel, Spotlight (GGlass)
    (
        "            color: gg.gx.dark ? Qt.rgba(0.10, 0.10, 0.11, gg.gx.tint) : Qt.rgba(1, 1, 1, gg.gx.tint * 0.55)\n"
        "            border.width: 1\n"
        "            border.color: gg.gx.dark ? Qt.rgba(0, 0, 0, 0.45) : Qt.rgba(0, 0, 0, 0.12)\n",
        "            color: gg.gx.dark ? Qt.rgba(0.10, 0.10, 0.11, gg.gx.tint * 0.55) : Qt.rgba(1, 1, 1, gg.gx.tint * 0.55)\n"
        "            border.width: 1\n"
        "            border.color: gg.gx.dark ? Qt.rgba(0, 0, 0, 0.45) : Qt.rgba(0, 0, 0, 0.12)\n"
        + sheen(12, "gg.gx.dark"),
    ),
])

# The bar contrast tuner replaces this fade (barFeather) with SilkyBarContrast; only tune it while it is there.
if "barFeather" in (shell / "MacBar.qml").read_text():
  tune(shell / "MacBar.qml", [
    (
        "                        GradientStop { position: 0.00; color: Qt.rgba(barFeather.c.r, barFeather.c.g, barFeather.c.b, 0.30) }\n"
        "                        GradientStop { position: 0.35; color: Qt.rgba(barFeather.c.r, barFeather.c.g, barFeather.c.b, 0.20) }\n"
        "                        GradientStop { position: 0.65; color: Qt.rgba(barFeather.c.r, barFeather.c.g, barFeather.c.b, 0.08) }\n",
        "                        // Silky: below the macbar layer's ignore_alpha (0.05), so Hyprland does not blur a dark strip under the bar\n"
        "                        GradientStop { position: 0.00; color: Qt.rgba(barFeather.c.r, barFeather.c.g, barFeather.c.b, 0.045) }\n"
        "                        GradientStop { position: 0.35; color: Qt.rgba(barFeather.c.r, barFeather.c.g, barFeather.c.b, 0.03) }\n"
        "                        GradientStop { position: 0.65; color: Qt.rgba(barFeather.c.r, barFeather.c.g, barFeather.c.b, 0.015) }\n",
    ),
  ])

tune(shell / "MacDock.qml", [
    (
        "                        color: root.dockDark ? Qt.rgba(0.10, 0.10, 0.11, root.glassOpacity)\n"
        "                                             : Qt.rgba(1, 1, 1, root.glassOpacity * 0.55)\n"
        "                        border.width: 0      // dark outer border removed\n",
        "                        color: root.dockDark ? Qt.rgba(0.10, 0.10, 0.11, root.glassOpacity * 0.55)\n"
        "                                             : Qt.rgba(1, 1, 1, root.glassOpacity * 0.55)\n"
        "                        border.width: 0      // dark outer border removed\n"
        + sheen(24, "root.dockDark"),
    ),
])

tune(shell / "AboutApp.qml", [
    (
        (
            "            readonly property color bg: dark ? Qt.rgba(0.17, 0.17, 0.18, 0.84) : Qt.rgba(0.88, 0.87, 0.86, 0.88)\n",
            "            // Match the Omarchy system menu's dark and light glass tints (ARGB).\n"
            '            readonly property color bg: dark ? "#8c1c1c1e" : "#adf7f7f9"\n',
        ),
        "            // System menu glass tint at 61% dark and 74% light opacity (ARGB).\n"
        '            readonly property color bg: dark ? "#9c1c1c1e" : "#bdf7f7f9"\n',
    ),
    (
        "            readonly property color btn: dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.75)\n"
        "            readonly property color btnDown: dark ? Qt.rgba(1, 1, 1, 0.2) : Qt.rgba(1, 1, 1, 0.5)\n",
        "            // Silky: a faint fill like macOS secondary buttons (the light one used to be a 75 % white slab)\n"
        "            readonly property color btn: dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.045)\n"
        "            readonly property color btnDown: dark ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(0, 0, 0, 0.10)\n",
    ),
    (
        "                // this window draws its own macOS-style edge: no Hyprland border, and Hyprland's corner rounding\n"
        "                // (also used for its shadow and blur) matches the window's own radius\n",
        "                // Keep the Hyprland border off and align its shadow and blur with the window's radius.\n",
    ),
    (
        "            readonly property color border: dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.18)\n"
        "            readonly property color edgeOuter: Qt.rgba(1, 1, 1, 0.50)     // thin dark line on the outside\n"
        "            readonly property color edgeInner: dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.65)      // soft highlight just inside it\n"
        '            function lightBorder(active, c) { return active ? Qt.darker(c, dark ? 1.12 : 1.22) : "transparent"; }\n',
        "            readonly property color border: dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.18)\n"
        '            function lightBorder(active, c) { return active ? Qt.darker(c, dark ? 1.12 : 1.22) : "transparent"; }\n',
    ),
    (
        "            border.width: 1; border.color: pal.edgeOuter\n"
        "            clip: true\n"
        "\n"
        "            // inner highlight: together with the outer line this is the two-tone edge macOS windows have\n"
        "            Rectangle {\n"
        "                anchors.fill: parent; anchors.margins: 1\n"
        "                radius: frame.radius - 1\n"
        "                color: \"transparent\"\n"
        "                border.width: 1; border.color: pal.edgeInner\n"
        "                z: 50\n"
        "            }\n",
        "            border.width: 0\n"
        "            clip: true\n",
    ),
    (
        "            radius: 18\n"
        "            color: pal.bg\n"
        "            border.width: 0\n",
        "            // Let Hyprland clip the tint and its backdrop to the same rounded outline.\n"
        "            readonly property real cornerRadius: 18\n"
        "            color: pal.bg\n"
        "            border.width: 0\n",
    ),
    (
        'Math.round(frame.radius * win.uiS)',
        'Math.round(frame.cornerRadius * win.uiS)',
    ),
])
