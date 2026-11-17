#!/usr/bin/env python3
"""Apply MacShell QML changes only on an explicit reload."""
import sys
from pathlib import Path


path = Path(sys.argv[1])
original = path.read_text()
startup = "    Component.onCompleted: {\n        sharedHub.bar = macBar;"
manual_startup = """    Component.onCompleted: {
        // Rebuild the shell once after all QML changes are ready.
        Quickshell.watchFiles = false;
        sharedHub.bar = macBar;"""
settings_comment = "    // reopen settings even when both the Dock and the Menu Bar are disabled:"
reload_handler = """    IpcHandler {
        target: "macshell"
        function reload(): void {
            Qt.callLater(function () { Quickshell.reload(false); });
        }
    }

"""

updated = original
if manual_startup not in updated:
    if updated.count(startup) != 1:
        raise SystemExit(f"MacShell reload configuration: startup block not found in {path}")
    updated = updated.replace(startup, manual_startup, 1)
if reload_handler not in updated:
    if 'target: "macshell"' in updated or updated.count(settings_comment) != 1:
        raise SystemExit(f"MacShell reload configuration: IPC insertion point unavailable in {path}")
    updated = updated.replace(settings_comment, reload_handler + settings_comment, 1)
if updated != original:
    path.write_text(updated)
