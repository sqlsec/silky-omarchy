#!/usr/bin/env python3
"""Make a Dock click land on a window the user can see.

* Clicking an app that is not frontmost brings up its most recently focused window, not the first one
  in the compositor's list (Claude Desktop used to show a stray Chromium window first).
* Before focusing, Hyprland is asked to float a tiled window that floating peers cover on a floating
  workspace (o.silky_reveal_window in config/hypr/silky-shortcuts.lua); otherwise it stays hidden behind them.

Run after tune-dock-focus-cursor.py, which adds silkyFocusAddress.
"""

import argparse
import os
import shutil
import stat
import sys
from pathlib import Path
from tempfile import NamedTemporaryFile

REPLACEMENTS = (
    (
        "            + 'if not prev then pcall(hl.config, { cursor = { no_warps = true } }) end; '\n"
        "            + 'hl.dispatch(hl.dsp.focus({ ' + sel + ' })); '\n",
        "            + 'if not prev then pcall(hl.config, { cursor = { no_warps = true } }) end; '\n"
        "            + 'if o and o.silky_reveal_window then pcall(o.silky_reveal_window, \"0x' + address + '\") end; '\n"
        "            + 'hl.dispatch(hl.dsp.focus({ ' + sel + ' })); '\n",
    ),
    (
        "        function onRawEvent(event) {\n"
        "            tickDebounce.restart();\n",
        "        function onRawEvent(event) {\n"
        "            tickDebounce.restart();\n"
        "            if (event.name === \"activewindowv2\") root.noteFocused(event.data);\n",
    ),
    (
        "            var idx = -1;\n"
        "            for (var i = 0; i < wins.length; i++) if (wins[i].activated) idx = i;\n"
        "            activateToplevel(wins[(idx + 1) % wins.length]);\n",
        "            var idx = -1;\n"
        "            for (var i = 0; i < wins.length; i++) if (wins[i].activated) idx = i;\n"
        "            activateToplevel(idx >= 0 ? wins[(idx + 1) % wins.length] : recentWindow(wins));\n",
    ),
    (
        "    function activateToplevel(tl) {\n",
        "    // Focus order seen by the Dock (address -> sequence), so a click restores the window used last.\n"
        "    property var focusOrder: ({})\n"
        "    property int focusSeq: 0\n"
        "    function noteFocused(address) {\n"
        "        var key = normalizedAddress(address);\n"
        "        if (!key || key === \"0\") return;\n"
        "        focusSeq++;\n"
        "        focusOrder[key] = focusSeq;\n"
        "    }\n"
        "    function recentWindow(wins) {\n"
        "        var best = wins[0], bestSeq = -1, bestHistory = 1e9;\n"
        "        for (var i = 0; i < wins.length; i++) {\n"
        "            var h = hyprToplevel(wins[i]);\n"
        "            if (!h) continue;\n"
        "            var seq = focusOrder[normalizedAddress(h.address)] || 0;\n"
        "            var o = h.lastIpcObject || {};\n"
        "            var history = typeof o.focusHistoryID === \"number\" && o.focusHistoryID >= 0 ? o.focusHistoryID : 1e8;\n"
        "            if (seq > bestSeq || (seq === bestSeq && history < bestHistory)) { best = wins[i]; bestSeq = seq; bestHistory = history; }\n"
        "        }\n"
        "        return best;\n"
        "    }\n"
        "    function activateToplevel(tl) {\n",
    ),
)


def integrate(text):
    for original, updated in REPLACEMENTS:
        if text.count(updated) == 1:
            continue
        if text.count(original) != 1:
            raise ValueError(f"MacDock.qml code changed near {original.strip().splitlines()[0]}")
        text = text.replace(original, updated, 1)
    return text


def write_atomic(path, contents, mode):
    with NamedTemporaryFile(dir=path.parent, delete=False) as temporary:
        temp_path = Path(temporary.name)
        try:
            temporary.write(contents)
            temporary.flush()
            os.fchmod(temporary.fileno(), mode)
            temp_path.replace(path)
        finally:
            temp_path.unlink(missing_ok=True)


def main():
    config_home = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    dock = config_home / "quickshell/MacShell/MacDock.qml"
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true")
    parser.add_argument("dock_path", type=Path, nargs="?", default=dock)
    args = parser.parse_args()

    try:
        original = args.dock_path.read_text()
        updated = integrate(original)
        if args.check:
            print(f"Dock window pick fix compatible with {args.dock_path}")
            return
        if updated != original:
            state = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "macshell"
            state.mkdir(parents=True, exist_ok=True)
            with NamedTemporaryFile(prefix="MacDock.qml.bak.window-pick-", dir=state, delete=False) as backup:
                backup_path = Path(backup.name)
            shutil.copy2(args.dock_path, backup_path)
            write_atomic(args.dock_path, updated.encode(), stat.S_IMODE(args.dock_path.stat().st_mode))
            print(f"Updated {args.dock_path}; backup: {backup_path}")
    except (OSError, ValueError) as error:
        print(error, file=sys.stderr)
        raise SystemExit(1) from error


if __name__ == "__main__":
    main()
