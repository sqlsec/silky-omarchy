#!/usr/bin/env python3
"""Remove Silky's minimize entry points, preserving recovery of existing windows."""
from pathlib import Path
import sys

shell = Path(sys.argv[1])
replacements = {
    "MacBar.qml": [
        ('                    m.push(mi("Minimize", "", function () {\n                        if (aw && root.hub && root.hub.dock) root.hub.dock.minimizeAddress(aw.address);\n                    }));\n', ''),
    ],
    "MacDock.qml": [('            if (event.name === "silkyminimize") root.minimizeAddress(event.data);\n', '')],
    "shell.qml": [
        ('        function minimizeWindow(title) { macDock.minimizeWindow(title); }\n', ''),
        ('        function minimize(address: string): void { macDock.minimizeAddress(address); }\n', ''),
    ],
}
for name, changes in replacements.items():
    path = shell / name
    text = path.read_text()
    for old, new in changes:
        text = text.replace(old, new)
    path.write_text(text)
