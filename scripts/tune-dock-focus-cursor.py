#!/usr/bin/env python3
"""Keep the pointer on the Dock icon when clicking or restoring windows."""

import argparse
import os
import shutil
import stat
import sys
from pathlib import Path
from tempfile import NamedTemporaryFile

FOCUS_HELPER = """    function silkyFocusAddress(address) {
        var sel = 'window = "address:0x' + address + '"';
        Hyprland.dispatch(
            '(function() '
            + 'local prev = hl.get_config("cursor.no_warps"); '
            + 'if not prev then pcall(hl.config, { cursor = { no_warps = true } }) end; '
            + 'hl.dispatch(hl.dsp.focus({ ' + sel + ' })); '
            + 'if not prev then pcall(hl.config, { cursor = { no_warps = false } }) end; '
            + 'return hl.dsp.window.alter_zorder({ mode = "top", ' + sel + ' }) '
            + 'end)()'
        );
    }

"""

REPLACEMENTS = (
    (
        '        Hyprland.dispatch(\'hl.dsp.focus({ workspace = "\' + o.workspace.id + \'" })\');\n',
        '        Hyprland.dispatch(\n'
        '            \'(function() \'\n'
        '            + \'local prev = hl.get_config("cursor.no_warps"); \'\n'
        '            + \'if not prev then pcall(hl.config, { cursor = { no_warps = true } }) end; \'\n'
        '            + \'local res = hl.dispatch(hl.dsp.focus({ workspace = "\' + o.workspace.id + \'" })); \'\n'
        '            + \'if not prev then pcall(hl.config, { cursor = { no_warps = false } }) end; \'\n'
        '            + \'return res \'\n'
        '            + \'end)()\'\n'
        '        );\n',
    ),
    (
        '            Hyprland.dispatch(\'hl.dsp.focus({ \' + sel + \' })\');\n'
        '            Hyprland.dispatch(\'hl.dsp.window.alter_zorder({ mode = "top", \' + sel + \' })\');\n',
        '            silkyFocusAddress(address);\n',
    ),
    (
        '    function activateToplevel(tl) {\n'
        '        if (isMinimized(tl)) restoreWindow({ tl: tl });\n'
        '        else tl.activate();\n'
        '    }\n',
        FOCUS_HELPER
        + '    function activateToplevel(tl) {\n'
        '        if (isMinimized(tl)) restoreWindow({ tl: tl });\n'
        '        else {\n'
        '            var h = hyprToplevel(tl), address = h ? normalizedAddress(h.address) : "";\n'
        '            if (address) silkyFocusAddress(address);\n'
        '            else tl.activate();\n'
        '        }\n'
        '    }\n',
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
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("dock_path", type=Path, nargs="?", default=dock)
    args = parser.parse_args()

    try:
        original = args.dock_path.read_text()
        updated = integrate(original)
        if args.check:
            print(f"Dock focus cursor fix compatible with {args.dock_path}")
            return
        if updated != original:
            state = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "macshell"
            state.mkdir(parents=True, exist_ok=True)
            with NamedTemporaryFile(prefix="MacDock.qml.bak.focus-cursor-", dir=state, delete=False) as backup:
                backup_path = Path(backup.name)
            shutil.copy2(args.dock_path, backup_path)
            write_atomic(args.dock_path, updated.encode(), stat.S_IMODE(args.dock_path.stat().st_mode))
            print(f"Updated {args.dock_path}; backup: {backup_path}")
    except (OSError, ValueError) as error:
        print(error, file=sys.stderr)
        raise SystemExit(1) from error


if __name__ == "__main__":
    main()
