#!/usr/bin/env python3
"""Keep optical Dock icon scaling centered without changing the rotation pivot."""
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
old = "                                    scale: root.dockIconScale(cell.modelData)"
new = ("                                    transform: Scale { origin.x: width / 2; "
       "origin.y: height / 2; xScale: root.dockIconScale(cell.modelData); yScale: xScale }")
if old in text:
    if text.count(old) != 1:
        raise SystemExit("Unexpected number of Dock icon scale bindings")
    path.write_text(text.replace(old, new))
elif new not in text:
    raise SystemExit("Dock icon scale binding not found; leaving file unchanged")
