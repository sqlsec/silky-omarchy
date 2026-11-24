#!/usr/bin/env python3
"""Group WPS Office windows under one MacShell Dock icon."""

import argparse
from pathlib import Path
import shutil
from tempfile import NamedTemporaryFile


def tune_dock(source):
    # Other Dock tuners may add their own window classification to appOf.
    app_filter = '        if (/^(wps|et|wpp|wpspdf|wpsoffice)$/.test(component) && (tl.title || "").toLowerCase() === component) return "";'
    changes = [
        (
            '    function lookup(appId) {',
            r'''    function dockAppId(appId) {
        if (!/^(wps|et|wpp|wpspdf|wpsoffice|wps-office-(wps|et|wpp|pdf))$/i.test(appId)) return appId;
        return DesktopEntries.byId("wps-office-prometheus") ? "wps-office-prometheus" : appId;
    }

    function lookup(appId) {
        appId = dockAppId(appId);''',
        ),
        (
            '    function appOf(tl) { return (tl.appId === "org.quickshell" && tl.title === "Clock") ? "macshell-clock" : tl.appId; }',
            r'''    function appOf(tl) {
        var id = tl.appId || "";
        var component = id.toLowerCase();
        // WPS menus and its selection toolbar use the component class as their title.
''' + app_filter + '''
        return (id === "org.quickshell" && tl.title === "Clock") ? "macshell-clock" : id;
    }''',
        ),
        (
            'if (id.toLowerCase() === item.key)',
            'if (dockAppId(id).toLowerCase() === item.key)',
        ),
        (
            'if (!have[id.toLowerCase()])',
            'if (!have[dockAppId(id).toLowerCase()])',
        ),
        (
            r'DesktopEntries.byId(String(pinned[p]).replace(/\.desktop$/, ""))',
            r'DesktopEntries.byId(dockAppId(String(pinned[p]).replace(/\.desktop$/, "")))',
        ),
        (
            'if (!tl.appId || tl.title === "macshell Settings")',
            'if (!appOf(tl) || tl.title === "macshell Settings")',
        ),
    ]
    for before, after in changes:
        if after in source or (app_filter in after and app_filter in source):
            continue
        if source.count(before) != 1:
            raise SystemExit(f"Unsupported MacDock.qml: expected one match for {before!r}")
        source = source.replace(before, after, 1)
    return source


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("dock", type=Path)
    parser.add_argument("--backup", action="store_true")
    args = parser.parse_args()

    original = args.dock.read_text()
    updated = tune_dock(original)
    if updated == original:
        return
    with NamedTemporaryFile(
        mode="w", dir=args.dock.parent, prefix="MacDock.qml.bak.wps-", delete=False
    ) as temporary:
        temporary.write(updated)
        staged = Path(temporary.name)
    try:
        shutil.copymode(args.dock, staged)
        if args.backup:
            backup = staged.with_name(staged.name + ".original")
            shutil.copy2(args.dock, backup)
            print(backup)
        staged.replace(args.dock)
    finally:
        staged.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
