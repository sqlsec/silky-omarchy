#!/usr/bin/env python3
"""Update the glass backdrop when window focus changes stacking order."""
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
s = path.read_text()
old = '''                     + (c.mapped ? 1 : 0) + (c.hidden ? 1 : 0) + ";";'''
new = '''                     + (c.mapped ? 1 : 0) + (c.hidden ? 1 : 0) + "," + c.focusHistoryID + ";";'''
if new not in s:
    if old not in s:
        raise SystemExit("Glass stacking tuning: fingerprint not found")
    s = s.replace(old, new, 1)
s = s.replace('''            // fingerprint the GEOMETRY only: a window retitling itself (a terminal, a browser tab, a player) is no
            // reason to wake the 60 Hz path — that kept it hot (and the main thread busy) the whole time.''', '''            // Track geometry and focus order: the latter determines the stack of floating windows in glass.
            // Window titles are excluded so retitling does not wake the 60 Hz path.''')
if s != path.read_text():
    path.write_text(s)
