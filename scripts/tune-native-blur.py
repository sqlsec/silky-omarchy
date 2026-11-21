#!/usr/bin/env python3
"""Make MacShell's "Normal Blur" style look like the old Liquid Glass, and quiet the About window's button.

With barStyle / dockStyle "blur", Hyprland blurs what is under each MacShell surface and MacShell only draws a tint
on top. MacShell's tints for that style were much heavier than Liquid Glass (dark: Dock and panels 38 %, the menu bar's
dropdown menus 64 %; Liquid Glass uses ~21 % plus a small brightness lift), so the blur read dark and flat. This:

  * lowers the dark tint of the Dock and the panels (GGlass) to Liquid Glass's Glass Opacity x 0.55 (0.21 at the Silky default);
  * lowers the dropdown menus (LGlass) to 0.10 + Glass Opacity x 0.5 (dark) / 0.12 + x 0.45 (light);
  * keeps the fade behind a clear menu bar below the `macbar` layer rule's ignore_alpha (0.05), so Hyprland does not blur a
    dark strip under the bar (it used to peak at 30 %);
  * adds Liquid Glass's soft light from above: a white sheen fading from the top edge, in light and dark mode;
  * makes About This Mac's "More Info..." button a faint fill instead of a 75 % white slab in light mode.

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
        if text.count(old) != 1:
            raise SystemExit(f"Normal Blur tuning ({path.name}): expected text missing or repeated: {old[:70]!r}")
        text = text.replace(old, new)
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
        "            readonly property color btn: dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.75)\n"
        "            readonly property color btnDown: dark ? Qt.rgba(1, 1, 1, 0.2) : Qt.rgba(1, 1, 1, 0.5)\n",
        "            // Silky: a faint fill like macOS secondary buttons (the light one used to be a 75 % white slab)\n"
        "            readonly property color btn: dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.045)\n"
        "            readonly property color btnDown: dark ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(0, 0, 0, 0.10)\n",
    ),
])
