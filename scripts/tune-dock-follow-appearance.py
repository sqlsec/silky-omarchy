#!/usr/bin/env python3
"""Make the Dock glass follow the system Light / Dark appearance.

MacDock pins `dockDark` to `true`, so the Dock keeps one fixed dark look: the
dockglass.frag shader always receives dark = 1 and the fallback / preview
surfaces always use the dark tints, however the theme switcher (or the Menu
Bar's own Appearance setting) flips the rest of the shell. Everything else
(Dock right-click menu, hover labels, indicator dots) already follows
`root.darkMode`, which the Menu Bar keeps in step with the macOS Tahoe theme
hook. This changes the single pin so the whole Dock renders the light glass in
light mode and the dark glass in dark mode, and follows the "auto" mode.

Usage: tune-dock-follow-appearance.py <MacShell dir>
"""
from pathlib import Path
import sys

shell = Path(sys.argv[1])

path = shell / "MacDock.qml"
text = path.read_text()
original = text

old = (
    "    // the dock keeps one fixed look (dark): switching the system between Light and Dark does not change its colours\n"
    "    readonly property bool dockDark: true\n"
)
new = (
    "    // Silky: the Dock follows the Light / Dark appearance. darkMode is kept in step with the Menu Bar\n"
    "    // (theme hook, the bar's own Appearance setting and \"auto\"), and every dockDark tint / shader uniform reads it.\n"
    "    readonly property bool dockDark: darkMode\n"
)

if new in text:
    sys.exit(0)  # already tuned
if text.count(old) != 1:
    raise SystemExit(f"Dock appearance tuning: expected text missing or repeated in {path}")
path.write_text(text.replace(old, new, 1))
print(f"tuned {path}: dockDark now follows darkMode")
