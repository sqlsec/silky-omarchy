#!/usr/bin/env python3
"""Install the Silky window overview (four-finger up / down) into a MacShell configuration.

Copies config/macshell/overview/SilkyOverview.qml next to MacShell's shell.qml, places SilkyOverview before
MacBar/MacDock so it sits under them on WlrLayer.Top (eliminating bottom bleed-through while keeping Dock and
Menu Bar interactive), and wires Dock / Menu Bar clicks to dismiss the overview cleanly.
The four-finger gesture itself comes from the silky-gestures Hyprland plugin (scripts/install-silky-gestures.sh).
"""
import argparse
import os
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path

SOURCE_DIR = Path(__file__).resolve().parents[1] / "config/macshell/overview"
SOURCE = SOURCE_DIR / "SilkyOverview.qml"
SHADER = SOURCE_DIR / "silkyround.frag"
QSB_CANDIDATES = ["/usr/lib/qt6/bin/qsb", "qsb6", "qsb"]

SHELL_BAR_ANCHOR = "    MacBar { id: macBar; hub: sharedHub }\n"
SHELL_ABOUT_ANCHOR = "    AboutApp { id: aboutApp; hub: sharedHub }\n"
SHELL_HUB_ANCHOR = "        property var about: aboutApp\n"
SHELL_HUB_LINE = "        property var overview: silkyOverview\n"
OVERVIEW_COMMENT = "    // four fingers up / down on the touchpad: every window of the workspace / of the focused app (silky-gestures plugin)\n"
OVERVIEW_LINE = "    SilkyOverview { id: silkyOverview; hub: sharedHub }\n"
OVERVIEW_BLOCK = OVERVIEW_COMMENT + OVERVIEW_LINE

DOCK_PRESSED_OLD = """                                    onPressed: mouse => {
                                        var mp = ma.mapToItem(ui, mouse.x, mouse.y);"""
DOCK_PRESSED_NEW = """                                    Timer {
                                        id: ovActTimer
                                        property var item: null
                                        property bool forceNew: false
                                        interval: 35
                                        onTriggered: { if (item) { var it = item; item = null; root.activate(it, forceNew); } }
                                    }
                                    onPressed: mouse => {
                                        if (root.hub && root.hub.overview && root.hub.overview.shown) root.hub.overview.releaseKeyboard();
                                        var mp = ma.mapToItem(ui, mouse.x, mouse.y);"""

DOCK_CLICKED_OLD = """                                    onClicked: mouse => {
                                        if (ui.justDragged) return;
                                        if (mouse.button === Qt.RightButton) {
                                            ui.menuCx = cell.mapToItem(ui, cell.width / 2, 0).x;
                                            ui.menuModel = root.menuFor(cell.modelData);
                                            ui.menuCell = cell;
                                            ui.menuItem = cell.modelData;
                                            ui.syncMenu();
                                        } else {
                                            root.activate(cell.modelData, mouse.button === Qt.MiddleButton);
                                        }
                                    }"""
DOCK_CLICKED_NEW = """                                    onClicked: mouse => {
                                        if (ui.justDragged) return;
                                        var ov = root.hub && root.hub.overview && root.hub.overview.shown ? root.hub.overview : null;
                                        if (ov) ov.dismiss(true);
                                        if (mouse.button === Qt.RightButton) {
                                            ui.menuCx = cell.mapToItem(ui, cell.width / 2, 0).x;
                                            ui.menuModel = root.menuFor(cell.modelData);
                                            ui.menuCell = cell;
                                            ui.menuItem = cell.modelData;
                                            ui.syncMenu();
                                        } else if (ov && Date.now() - ov.kbdReleasedAt < 35) {
                                            ovActTimer.item = cell.modelData;
                                            ovActTimer.forceNew = mouse.button === Qt.MiddleButton;
                                            ovActTimer.interval = Math.max(10, 35 - (Date.now() - ov.kbdReleasedAt));
                                            ovActTimer.restart();
                                        } else {
                                            root.activate(cell.modelData, mouse.button === Qt.MiddleButton);
                                        }
                                    }"""

BAR_PATCHES = [
    (
        "                function openPop(name, x) {\n                    if (pop === name) { pop = \"\"; return; }\n",
        "                function openPop(name, x) {\n                    if (root.hub && root.hub.overview && root.hub.overview.shown) root.hub.overview.dismiss(true);\n                    if (pop === name) { pop = \"\"; return; }\n",
        "openPop overview dismiss",
    ),
    (
        "                    MouseArea { anchors.fill: parent; onClicked: ui.pop = \"\" }\n",
        "                    MouseArea { anchors.fill: parent; onClicked: { ui.pop = \"\"; if (root.hub && root.hub.overview && root.hub.overview.shown) root.hub.overview.dismiss(false); } }\n",
        "barBg blank click overview dismiss",
    ),
    (
        "                                    onClicked: { ui.pop = \"\"; root.focusWorkspace(wsi.modelData); }\n",
        "                                    onClicked: { ui.pop = \"\"; if (root.hub && root.hub.overview && root.hub.overview.shown) root.hub.overview.dismiss(true); root.focusWorkspace(wsi.modelData); }\n",
        "workspace pill overview dismiss",
    ),
    (
        "                                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton\n                                    onClicked: mouse => {\n                                        var p = tray.mapToItem(ui, 0, 0);\n",
        "                                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton\n                                    onPressed: if (root.hub && root.hub.overview && root.hub.overview.shown) root.hub.overview.releaseKeyboard()\n                                    onClicked: mouse => {\n                                        if (root.hub && root.hub.overview && root.hub.overview.shown) root.hub.overview.dismiss(true);\n                                        var p = tray.mapToItem(ui, 0, 0);\n",
        "tray click overview dismiss",
    ),
    (
        "                            MouseArea { anchors.fill: parent; onClicked: { if (root.launcher !== \"\") { ui.pop = \"\"; root.search(); } else ui.openPop(\"spot\", 0); } }\n",
        "                            MouseArea { anchors.fill: parent; onClicked: { if (root.hub && root.hub.overview && root.hub.overview.shown) root.hub.overview.dismiss(true); if (root.launcher !== \"\") { ui.pop = \"\"; root.search(); } else ui.openPop(\"spot\", 0); } }\n",
        "search click overview dismiss",
    ),
]


def backup_file(path: Path, stamp: str):
    if path.is_file():
        backup = path.with_name(f"{path.name}.bak-overview-{stamp}")
        shutil.copy2(path, backup)
        print(f"Backed up {backup}")


def patch_shell(text: str) -> tuple[str, bool]:
    changed = False
    if SHELL_HUB_LINE not in text:
        if SHELL_HUB_ANCHOR not in text:
            sys.exit("shell.qml: sharedHub anchor not found; add `property var overview: silkyOverview` by hand")
        text = text.replace(SHELL_HUB_ANCHOR, SHELL_HUB_ANCHOR + SHELL_HUB_LINE, 1)
        changed = True

    if SHELL_BAR_ANCHOR not in text:
        sys.exit("shell.qml: MacBar line not found; place SilkyOverview before MacBar by hand")

    # Migrate legacy placement (after AboutApp) to before MacBar so silkyoverview sits below MacBar/MacDock on Top.
    bar_idx = text.index(SHELL_BAR_ANCHOR)
    ov_idx = text.find(OVERVIEW_LINE)
    if ov_idx == -1:
        text = text.replace(SHELL_BAR_ANCHOR, OVERVIEW_BLOCK + SHELL_BAR_ANCHOR, 1)
        changed = True
    elif ov_idx > bar_idx:
        if OVERVIEW_BLOCK in text:
            text = text.replace(OVERVIEW_BLOCK, "", 1)
        else:
            text = text.replace(OVERVIEW_LINE, "", 1)
        text = text.replace(SHELL_BAR_ANCHOR, OVERVIEW_BLOCK + SHELL_BAR_ANCHOR, 1)
        changed = True

    return text, changed


def patch_dock(text: str) -> tuple[str, bool]:
    changed = False
    if "root.hub.overview.releaseKeyboard()" not in text:
        if DOCK_PRESSED_OLD not in text:
            sys.exit("MacDock.qml: icon MouseArea onPressed anchor not found")
        text = text.replace(DOCK_PRESSED_OLD, DOCK_PRESSED_NEW, 1)
        changed = True
    if "ovActTimer.restart()" not in text:
        if DOCK_CLICKED_OLD not in text:
            sys.exit("MacDock.qml: icon MouseArea onClicked anchor not found")
        text = text.replace(DOCK_CLICKED_OLD, DOCK_CLICKED_NEW, 1)
        changed = True
    return text, changed


def patch_bar(text: str) -> tuple[str, bool]:
    changed = False
    for old, new, label in BAR_PATCHES:
        if new in text:
            continue
        if old not in text:
            sys.exit(f"MacBar.qml: anchor not found for {label}")
        text = text.replace(old, new, 1)
        changed = True
    return text, changed


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--config", default=os.path.join(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config")),
                                                         "quickshell/MacShell"), help="MacShell config directory")
    parser.add_argument("--check", action="store_true", help="only report whether it can be installed")
    args = parser.parse_args()

    target = Path(args.config)
    shell = target / "shell.qml"
    dock = target / "MacDock.qml"
    bar = target / "MacBar.qml"
    if not shell.is_file() or not (target / "SafeCapture.qml").is_file():
        sys.exit(f"MacShell not found (or too old: no SafeCapture.qml) in {target}")

    shell_text = shell.read_text()
    new_shell, shell_changed = patch_shell(shell_text)
    new_dock, dock_changed = (patch_dock(dock.read_text()) if dock.is_file() else ("", False))
    new_bar, bar_changed = (patch_bar(bar.read_text()) if bar.is_file() else ("", False))

    if args.check:
        parts = []
        if shell_changed: parts.append("shell.qml")
        if dock_changed: parts.append("MacDock.qml")
        if bar_changed: parts.append("MacBar.qml")
        if parts:
            print("will update SilkyOverview.qml and patch " + ", ".join(parts))
        else:
            print("already installed (will refresh SilkyOverview.qml)")
        return

    qml = target / SOURCE.name
    out = target / "silkyround.frag.qsb"
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    for path in (qml, out):
        backup_file(path, stamp)

    shutil.copyfile(SOURCE, qml)
    # the rounded-corner shader: compiled here when Qt's shader baker is available, otherwise the prebuilt copy
    qsb = next((c for c in QSB_CANDIDATES if shutil.which(c)), None)
    if qsb:
        subprocess.run([qsb, "--qt6", "-o", str(out), str(SHADER)], check=True)
    else:
        shutil.copyfile(SHADER.with_name("silkyround.frag.qsb"), out)

    if shell_changed:
        if not shell.with_name("shell.qml.bak-overview").is_file():
            shutil.copyfile(shell, shell.with_name("shell.qml.bak-overview"))
        backup_file(shell, stamp)
        tmp = shell.with_name("shell.qml.new")
        tmp.write_text(new_shell)
        os.replace(tmp, shell)

    if dock_changed:
        backup_file(dock, stamp)
        tmp = dock.with_name("MacDock.qml.new")
        tmp.write_text(new_dock)
        os.replace(tmp, dock)

    if bar_changed:
        backup_file(bar, stamp)
        tmp = bar.with_name("MacBar.qml.new")
        tmp.write_text(new_bar)
        os.replace(tmp, bar)

    patched = [name for name, ch in (("shell.qml", shell_changed), ("MacDock.qml", dock_changed), ("MacBar.qml", bar_changed)) if ch]
    suffix = (" and patched " + ", ".join(patched)) if patched else ""
    print(f"Installed {qml}{suffix}")
    print("Apply with: qs -c MacShell ipc call macshell reload")


if __name__ == "__main__":
    main()
