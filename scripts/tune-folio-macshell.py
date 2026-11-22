#!/usr/bin/env python3
"""Connect Folio's window controls and folder shortcuts to MacShell."""

import argparse
import os
import shutil
from datetime import datetime
from pathlib import Path
from tempfile import NamedTemporaryFile


def replace_once(content, before, after, path):
    if after in content:
        return content
    if content.count(before) != 1:
        raise SystemExit(f"Unsupported MacShell window activation in {path}")
    return content.replace(before, after, 1)


def tune_dock(text, path):
    changes = [
        (
            "    property var minimizeFx: null",
            """    property var minimizeFx: null
    FolioMinimizeFx { id: folioEffect }

    property var folioSnapshots: ({})

    function setFolioSnapshot(address, value) {
        var next = Object.assign({}, folioSnapshots);
        if (value) next[address] = value;
        else delete next[address];
        folioSnapshots = next;
        rebuild();
    }

    function folioDockTarget(screenName, address) {
        var panel = trashProbes[screenName];
        return panel ? panel.folioCellRect(address) : null;
    }""",
        ),
        (
            """    function minimizeAddress(address) {
        var h = hyprByAddress(address), o = h ? h.lastIpcObject : null;
        if (!h || !h.wayland || !o || !o.workspace || String(o.workspace.name || "") === "special:minimized") return;
        var screenName = monitorNameFor(o), rect = windowRect(o);
        var job = { screen: screenName, tl: h.wayland, win: rect, targetFn: function() { return root.targetRect(screenName); }, reverse: false,
                    before: function() { root.rememberAndMinimize(h); }, after: function() { minimizedDebounce.restart(); } };
        if (minimizeFx) minimizeFx.play(job); else { job.before(); job.after(); }
    }""",
            """    function minimizeAddress(address, snapshot) {
        var h = hyprByAddress(address), o = h ? h.lastIpcObject : null;
        if (!h || !h.wayland || !o || !o.workspace || String(o.workspace.name || "") === "special:minimized") return;
        var screenName = monitorNameFor(o), rect = windowRect(o);
        var key = normalizedAddress(address), folio = h.wayland.appId === "folio";
        var record = folio ? { tl: h.wayland, win: rect, image: snapshot || "", pending: true } : null;
        if (folioSnapshots[key]?.pending) return;
        if (record) setFolioSnapshot(key, record);
        var job = { screen: screenName, tl: h.wayland, win: rect, reverse: false,
                    image: record?.image || "",
                    targetFn: function() { return root.folioDockTarget(screenName, key); },
                    before: function() { root.rememberAndMinimize(h); },
                    after: function() {
                        if (record && root.folioSnapshots[key] === record) {
                            root.setFolioSnapshot(key, Object.assign({}, record, { pending: false }));
                        }
                        minimizedDebounce.restart();
                    } };
        if (job.image) folioEffect.play(job);
        else if (minimizeFx && !folio) {
            job.targetFn = function() { return root.targetRect(screenName); };
            minimizeFx.play(job);
        } else { job.before(); job.after(); }
    }""",
        ),
        (
            """        var workspace = restoreWorkspace(o), screenName = monitorNameFor(o), rect = windowRect(o);
        if (!(workspace >= 1)) return;""",
            """        var workspace = restoreWorkspace(o), screenName = monitorNameFor(o), rect = windowRect(o);
        if (!(workspace >= 1) || restoringWindows[address]) return;
        var record = folioSnapshots[address];
        if (record?.tl !== item.tl) record = null;""",
        ),
        (
            """        if (minimizeFx) minimizeFx.play(job); else { job.before(); job.after(); }
    }
    function restoreAddress(address)""",
            """        if (record?.image) {
            job.image = record.image;
            job.win = record.win;
            job.targetFn = function() { return root.folioDockTarget(screenName, address); };
            job.after = function() {
                showReal();
                root.setFolioSnapshot(address, null);
            };
            folioEffect.play(job);
        } else if (minimizeFx && item.tl.appId !== "folio") minimizeFx.play(job);
        else { job.before(); job.after(); }
    }
    function restoreAddress(address)""",
        ),
        (
            """        var winItems = [], liveWins = [];
        if (showThumbs) {""",
            """        var winItems = [], liveWins = [];
        var snapshots = Object.assign({}, folioSnapshots);
        for (var key in snapshots) if (!tls.includes(snapshots[key].tl)) delete snapshots[key];
        if (Object.keys(snapshots).length !== Object.keys(folioSnapshots).length) folioSnapshots = snapshots;
        {""",
        ),
        (
            """                if (!isMinimized(tl)) continue;
                var address = addressOf(tl);
                if (restoringWindows[address]) continue;
                // live capture off: a preview cell is only an app icon, so a pinned app (its icon is already in the Dock) gets none; unpinned apps keep theirs
                if (!windowCapture && seen[keyOf(appOf(tl))]) continue;""",
            """                var address = addressOf(tl), folio = tl.appId === "folio";
                var record = folio ? snapshots[address] : null;
                if (!folio && !showThumbs) continue;
                if (!isMinimized(tl) && !record?.pending) continue;
                if (!folio && (restoringWindows[address] || (!windowCapture && seen[keyOf(appOf(tl))]))) continue;""",
        ),
        (
            """                if (winAge(tl) < 200) { if (!youngWin.running) youngWin.start(); continue; }""",
            """                if (!folio && winAge(tl) < 200) { if (!youngWin.running) youngWin.start(); continue; }""",
        ),
        (
            """                winItems.push({ kind: "win", key: "win:" + wid, tl: tl, address: address,""",
            """                winItems.push({ kind: "win", key: "win:" + wid, tl: tl, address: address,
                                folio: folio, image: record?.image || "", held: !!(record?.pending || restoringWindows[address]),""",
        ),
        (
            """        // [apps…] | [windows…] | Apps (Spotlight's application list) | Trash
        list.push({ kind: "sep", key: "sep:win" });
        for (var wj = 0; wj < winItems.length; wj++) list.push(winItems[wj]);
        if (winItems.length > 0) list.push({ kind: "sep", key: "sep:trash" });
        if (!appsPlaced) list.push(appsItem);""",
            """        // [apps…] | [minimized windows…] [Trash]
        if (!appsPlaced) list.push(appsItem);
        if (winItems.length > 0 || showTrash) list.push({ kind: "sep", key: "sep:win" });
        for (var wj = 0; wj < winItems.length; wj++) list.push(winItems[wj]);""",
        ),
        (
            """            sig.push(it.kind + ":" + (it.key || "") + ":" + it.running + ":" + (it.icon || "") + (it.leaving ? ":L" : ""));""",
            """            sig.push(it.kind + ":" + (it.key || "") + ":" + it.running + ":" + (it.icon || "")
                     + (it.leaving ? ":L" : "") + (it.held ? ":H" : "") + (it.image || ""));""",
        ),
        (
            """                function publishDockTarget() {""",
            """                function folioCellRect(address) {
                    if (!win.visible || Math.abs(dock.y - (ui.height - root.margin - dock.height)) > 1) return null;
                    row.forceLayout();
                    for (var i = 0; i < rep.count; i++) {
                        var cell = rep.itemAt(i);
                        if (!cell?.modelData?.folio || cell.modelData.address !== address || cell.leavingCell) continue;
                        var icon = cell.iconImg, p = icon.mapToItem(ui, 0, 0);
                        return { x: win.modelData.x + p.x,
                                 y: win.modelData.y + win.modelData.height - win.height + p.y,
                                 width: icon.width, height: icon.height };
                    }
                    return null;
                }

                function publishDockTarget() {""",
        ),
        (
            """readonly property bool tucked: wantsHide && !revealed && !menuOpen && !dragging && !tearing""",
            """readonly property bool tucked: wantsHide && !revealed && !menuOpen && !dragging && !tearing
                    && folioEffect.job?.screen !== win.modelData.name""",
        ),
        (
            """                                readonly property bool useThumb: thumbWin !== null
                                readonly property bool thumbReady: useThumb && (sv.hasContent === undefined || sv.hasContent === true)""",
            """                                readonly property bool useThumb: thumbWin !== null && !modelData.folio
                                readonly property bool thumbReady: useThumb && (sv.hasContent === undefined || sv.hasContent === true)
                                readonly property bool folioThumbReady: folioThumbnail.status === Image.Ready""",
        ),
        (
            """                                property real appear: modelData.fresh ? 0 : 1""",
            """                                property real appear: modelData.fresh && !modelData.folio ? 0 : 1""",
        ),
        (
            """                                enabled: !leavingCell""",
            """                                enabled: !leavingCell && !modelData.held""",
        ),
        (
            """                                    visible: !cell.isSep && !cell.thumbReady""",
            """                                    visible: !cell.isSep && !cell.thumbReady && !cell.folioThumbReady && !cell.modelData.held""",
        ),
        (
            """                                        want: (root.hub && !root.hub.windowCapture) ? null : cell.heldTl""",
            """                                        want: (!cell.useThumb || (root.hub && !root.hub.windowCapture)) ? null : cell.heldTl""",
        ),
        (
            """                                // small app icon in the corner, so you can tell which app the window belongs to""",
            """                                Image {
                                    id: folioThumbnail
                                    anchors.fill: img
                                    source: cell.modelData.image || ""
                                    visible: cell.folioThumbReady && !cell.modelData.held
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                    smooth: true
                                    mipmap: true
                                }

                                // small app icon in the corner, so you can tell which app the window belongs to""",
        ),
        (
            """                                    visible: cell.thumbReady
                                    width: img.width * 0.46""",
            """                                    visible: (cell.thumbReady || cell.folioThumbReady) && !cell.modelData.held
                                    width: img.width * 0.46""",
        ),
    ]
    for before, after in changes:
        text = replace_once(text, before, after, path)
    return text


def tune_handoffs(text, path):
    changes = [
        (
            "    property var folioSnapshots: ({})",
            """    property var folioSnapshots: ({})
    readonly property int folioSlotMs: 180""",
        ),
        (
            """                function folioCellRect(address) {""",
            """                readonly property real folioSpacing: {
                    if (!folioEffect.job) return root.spacing;
                    var occupied = 0, withheld = 0;
                    for (var i = 0; i < rep.count; i++) {
                        var cell = rep.itemAt(i);
                        if (!cell || !cell.visible || cell.width <= 0) continue;
                        occupied++;
                        if (cell.modelData.folio) withheld += root.spacing * (1 - cell.appear);
                    }
                    // Row inserts its spacing at the first nonzero width. Ramp
                    // that gap along with the slot instead of adding it in one frame.
                    return Math.max(0, root.spacing - withheld / Math.max(1, occupied - 1));
                }

                function folioCellRect(address) {""",
        ),
        (
            """                        id: row
                        spacing: root.spacing""",
            """                        id: row
                        spacing: ui.folioSpacing""",
        ),
        (
            "    function rememberAndMinimize(h) {",
            "    function rememberAndMinimize(h, instantMove) {",
        ),
        (
            """        Hyprland.dispatch('hl.dsp.window.move({ workspace = "special:minimized", follow = false, window = "address:0x' + address + '" })');""",
            """        if (instantMove)
            Hyprland.dispatch('hl.dsp.window.set_prop({ prop = "no_anim", value = "1", window = "address:0x' + address + '" })');
        Hyprland.dispatch('hl.dsp.window.move({ workspace = "special:minimized", follow = false, window = "address:0x' + address + '" })');""",
        ),
        (
            """                    before: function() { root.rememberAndMinimize(h); },
                    after: function() {
                        if (record && root.folioSnapshots[key] === record) {""",
            """                    before: function() { root.rememberAndMinimize(h, !!job.image); },
                    after: function() {
                        if (job.image)
                            Hyprland.dispatch('hl.dsp.window.set_prop({ prop = "no_anim", value = "unset", window = "address:0x' + key + '" })');
                        if (record && root.folioSnapshots[key] === record) {""",
        ),
        (
            """                        var icon = cell.iconImg, p = icon.mapToItem(ui, 0, 0);
                        return { x: win.modelData.x + p.x,
                                 y: win.modelData.y + win.modelData.height - win.height + p.y,
                                 width: icon.width, height: icon.height };""",
            """                        var icon = cell.iconImg, p = icon.mapToItem(ui, 0, 0), size = icon.width;
                        if (cell.appear < 1 && !cell.retractFolio) {
                            // Aim at the final center while the placeholder and its neighbours
                            // are still sliding. The lamp can start before the Dock finishes.
                            var width = root.iconSize * cell.s;
                            var total = 0, before = 0;
                            for (var j = 0; j < rep.count; j++) {
                                var other = rep.itemAt(j);
                                if (!other) continue;
                                var w = other.modelData.folio && !other.leavingCell && !other.retractFolio
                                    ? root.iconSize * other.s : other.width;
                                if (w <= 0) continue;
                                total += w + root.spacing;
                                if (j < i) before += w + root.spacing;
                            }
                            size = Math.max(1, Math.round(width * 0.99));
                            p = Qt.point((ui.width - Math.max(0, total - root.spacing)) / 2
                                    + before + (width - size) / 2,
                                cell.mapToItem(ui, 0, cell.height).y - size);
                        }
                        return { x: win.modelData.x + p.x,
                                 y: win.modelData.y + win.modelData.height - win.height + p.y,
                                 width: size, height: size };""",
        ),
        (
            """                    targetFn: function() { return root.folioDockTarget(screenName, key); },""",
            """                    targetFn: function() { return root.folioDockTarget(screenName, key); },
                    parked: function() { return root.isMinimized(h.wayland); },""",
        ),
        (
            """                                property real appear: modelData.fresh && !modelData.folio ? 0 : 1
                                Behavior on appear { NumberAnimation { duration: cell.leavingCell ? root.leaveMs : 320; easing.type: cell.leavingCell ? Easing.InOutCubic : Easing.OutCubic } }
                                Component.onCompleted: { heldTl = thumbWin; Qt.callLater(function () { cell.appear = cell.leavingCell ? 0 : 1; cell.bounceStep(); }); }
                                onLeavingCellChanged: appear = leavingCell ? 0 : 1""",
            """                                readonly property bool retractFolio: modelData.folio === true
                                    && root.restoringWindows[modelData.address] === true
                                property real appear: modelData.fresh ? 0 : 1
                                Behavior on appear {
                                    NumberAnimation {
                                        duration: cell.modelData.folio ? root.folioSlotMs : (cell.leavingCell ? root.leaveMs : 320)
                                        easing.type: cell.modelData.folio ? Easing.Linear
                                            : (cell.leavingCell ? Easing.InOutCubic : Easing.OutCubic)
                                    }
                                }
                                function syncAppearance() { appear = leavingCell || retractFolio ? 0 : 1; }
                                Component.onCompleted: { heldTl = thumbWin; Qt.callLater(function () { cell.syncAppearance(); cell.bounceStep(); }); }
                                onLeavingCellChanged: syncAppearance()
                                onRetractFolioChanged: syncAppearance()""",
        ),
    ]
    for before, after in changes:
        text = replace_once(text, before, after, path)
    return text


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("shell", type=Path)
    parser.add_argument("--backup", action="store_true")
    args = parser.parse_args()

    dock = args.shell / "MacDock.qml"
    shell = args.shell / "shell.qml"
    changes = {}
    content = dock.read_text()
    updated = replace_once(content, "    function activate(item, forceNew) {", """    function activateToplevel(tl) {
        if (isMinimized(tl)) restoreWindow({ tl: tl });
        else tl.activate();
    }

    function activate(item, forceNew) {""", dock)
    updated = replace_once(updated, "            wins[(idx + 1) % wins.length].activate();",
                           "            activateToplevel(wins[(idx + 1) % wins.length]);", dock)
    updated = replace_once(updated, "run: function () { w.activate(); }",
                           "run: function () { activateToplevel(w); }", dock)
    if "    FolioMinimizeFx { id: folioEffect }" not in updated:
        updated = tune_dock(updated, dock)
    updated = tune_handoffs(updated, dock)
    updated = replace_once(updated, "import QtQuick\n", "import QtQuick\nimport QtCore as Core\n", dock)
    updated = replace_once(updated, """        if (item.entry) {
            m.push({ kind: "item", label: item.pinned""", """        if (item.key === "folio") {
            const paths = Core.StandardPaths;
            const home = paths.writableLocation(paths.HomeLocation);
            const folders = [
                ["Open Home Folder", paths.HomeLocation, ""],
                ["Desktop", paths.DesktopLocation, "Desktop"],
                ["Documents", paths.DocumentsLocation, "Documents"],
                ["Downloads", paths.DownloadLocation, "Downloads"],
                ["Pictures", paths.PicturesLocation, "Pictures"]
            ];
            for (const [label, location, fallback] of folders) {
                let url = paths.writableLocation(location);
                // XDG uses the home directory for disabled locations. Prefer
                // an existing conventional folder to another Home shortcut.
                if (fallback && (!url.toString() || url.toString() === home.toString()))
                    url = paths.locate(paths.HomeLocation, fallback, paths.LocateDirectory);
                const destination = url.toString();
                if (!destination) continue;
                m.push({ kind: "item", label: I18n.tr(label),
                         run: function () { Quickshell.execDetached(["gtk-launch", "folio.desktop", destination]); } });
            }
            m.push({ kind: "sep" });
        }
        if (item.entry) {
            m.push({ kind: "item", label: item.pinned""", dock)
    if updated != content:
        changes[dock] = updated

    chinese = args.shell / "lang/zh-CN.js"
    if chinese.exists():
        content = chinese.read_text()
        if '"Documents":' not in content:
            changes[chinese] = replace_once(content, '    "Downloads": "下载",',
                                            '    "Documents": "文档",\n    "Downloads": "下载",', chinese)

    content = shell.read_text()
    needle = "        function restore(address: string): void { macDock.restoreAddress(address); }"
    old_ipc = """        function minimizeFolio(address: string): bool {
            const client = macDock.hyprByAddress(address);
            if (!macDock.dockEnabled || !client || !client.wayland
                    || client.wayland.appId !== "folio"
                    || !(client.lastIpcObject?.workspace?.id >= 1)) return false;
            macDock.minimizeAddress(address);
            return true;
        }
"""
    new_ipc = """        function minimizeFolio(address: string): bool {
            return minimizeFolioSnapshot(address, "");
        }
        function minimizeFolioSnapshot(address: string, snapshot: string): bool {
            const client = macDock.hyprByAddress(address);
            if (!macDock.dockEnabled || !client || !client.wayland
                    || client.wayland.appId !== "folio"
                    || !(client.lastIpcObject?.workspace?.id >= 1)) return false;
            const runtime = Quickshell.env("XDG_RUNTIME_DIR");
            const name = snapshot.slice(runtime.length + 1);
            const image = runtime && snapshot.startsWith(runtime + "/")
                && /^silky-folio-[A-Za-z0-9]+[.]png$/.test(name)
                ? "file://" + snapshot : "";
            macDock.minimizeAddress(address, image);
            return true;
        }
"""
    if old_ipc in content:
        updated = replace_once(content, old_ipc + needle, new_ipc + needle, shell)
    else:
        updated = replace_once(content, needle, new_ipc + needle, shell)
    old_minimize = """        function minimizeFoot(address: string): bool {
            const client = macDock.hyprByAddress(address);
            if (!macDock.dockEnabled || client?.wayland?.appId !== "foot"
                    || !(client.lastIpcObject?.workspace?.id >= 1)) return false;
            macDock.minimizeAddress(address);
            return true;
        }
"""
    minimize = """        function minimizeFoot(address: string): bool {
            const client = macDock.hyprByAddress(address);
            const state = client?.lastIpcObject;
            if (!macDock.dockEnabled || !titlebarControls.fullscreenApps.includes(client?.wayland?.appId)
                    || !(state?.workspace?.id >= 1) || state.fullscreen >= 2) return false;
            macDock.minimizeAddress(address);
            return true;
        }
"""
    anchor = "        function minimizeFolio(address: string): bool {"
    if old_minimize in updated:
        updated = replace_once(updated, old_minimize, minimize, shell)
    else:
        updated = replace_once(updated, anchor, minimize + anchor, shell)
    if "    FolioSnapPreview {}" not in updated:
        updated = replace_once(updated, "    MacDock {", "    FolioSnapPreview {}\n    MacDock {", shell)
    layout = "    FootWindowLayout { id: titlebarControls; light: !macBar.darkMode; language: macBar.language }"
    for old_layout in (
        "    FootWindowLayout { light: !macBar.darkMode }",
        "    FootWindowLayout { light: !macBar.darkMode; language: macBar.language }",
    ):
        if old_layout in updated:
            updated = replace_once(updated, old_layout, layout, shell)
            break
    else:
        updated = replace_once(updated, "    FolioSnapPreview {}",
                               "    FolioSnapPreview {}\n" + layout, shell)
    if updated != content:
        changes[shell] = updated

    assets = Path(__file__).resolve().parents[1] / "config/macshell"
    for name in ("FolioMinimizeFx.qml", "FolioSnapPreview.qml", "FootWindowLayout.qml", "folio-genie.vert.qsb"):
        target = args.shell / name
        content = (assets / name).read_bytes()
        if not target.exists() or target.read_bytes() != content:
            changes[target] = content

    stamp = datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    for path, updated in changes.items():
        if args.backup and path.exists():
            backup = path.with_name(f"{path.name}.bak.folio.{stamp}")
            shutil.copy2(path, backup)
            print(f"Backed up {path} to {backup}")
        with NamedTemporaryFile(mode="wb", dir=path.parent, delete=False) as stream:
            temporary = Path(stream.name)
            try:
                stream.write(updated.encode("utf-8") if isinstance(updated, str) else updated)
                stream.close()
                if path.exists():
                    shutil.copymode(path, temporary)
                else:
                    temporary.chmod(0o644)
                os.replace(temporary, path)
            finally:
                temporary.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
