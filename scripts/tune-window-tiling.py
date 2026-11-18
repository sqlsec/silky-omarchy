#!/usr/bin/env python3
"""Use the Silky manual tiling action in the MacShell menus when installed."""
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
native = 'hl.dsp.window.float({ action = "toggle" })'
old = "disp('" + native + "')"
new = "disp('(o.silky_toggle_window_floating or " + native + ")')"
if text.count(new) == 2 and old not in text:
    sys.exit(0)
if text.count(old) != 2 or new in text:
    sys.exit(f"Expected two unmodified floating menu actions in {path}")
path.write_text(text.replace(old, new))
