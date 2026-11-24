#!/usr/bin/env python3
"""Install Silky's in-process workspace layout OSD and top-bar indicator into MacShell.

Idempotent and safe to re-run after MacShell updates. Creates timestamped backups
before modifying shell.qml or MacBar.qml.
"""

from __future__ import annotations

import argparse
import datetime
import pathlib
import shutil
import subprocess
import sys

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
DEFAULT_SHELL_DIR = pathlib.Path.home() / ".config/quickshell/MacShell"

QML_FILES = (
    "SilkyWorkspaceLayoutIcon.qml",
    "SilkyWorkspaceLayoutOSD.qml",
)

HUB_ANCHOR = "        property var overview: silkyOverview\n"
HUB_SNIPPET = "        property var workspaceLayout: silkyWorkspaceLayout\n"

SCOPE_ANCHOR = "    FootWindowLayout { id: titlebarControls; light: !macBar.darkMode; language: macBar.language }\n"
SCOPE_SNIPPET = (
    "    SilkyWorkspaceLayoutOSD { id: silkyWorkspaceLayout; bar: macBar; dark: macBar.effDark; "
    "language: macBar.language; glassPlugin: macBar.barGlassPlugin }\n"
)

OSD_STATE_MARKER = "function showLayoutOsd("
OSD_STATE_ANCHOR = "    property real osdValue: 0\n"
OSD_STATE_SNIPPET = """    property string osdLayoutMode: "floating"
    property int osdLayoutPulse: 0
    function showLayoutOsd(mode) {
        osdKind = "layout";
        osdLayoutMode = mode || "floating";
        osdLayoutPulse += 1;
        osdVisible = true;
        osdTimer.restart();
        silkyGlassPoke += 1;
    }
"""

OSD_CONTENT_MARKER = "id: osdLayoutContent"
OSD_GLYPH_ANCHOR = """                    Glyph {
                        x: 20; anchors.verticalCenter: parent.verticalCenter
                        width: 24; height: 24
                        kind: root.osdKind === "brightness" ? "sun" : "speaker"
                        level: root.osdKind === "brightness" ? 3 : (root.osdValue < 0.34 ? 1 : (root.osdValue < 0.67 ? 2 : 3))
                        color: "white"
                    }
                    // segmented level bar: bright segments are filled, the rest are dim
                    Row {
                        id: osdBar"""
OSD_GLYPH_REPLACE = """                    Glyph {
                        visible: root.osdKind !== "layout"
                        x: 20; anchors.verticalCenter: parent.verticalCenter
                        width: 24; height: 24
                        kind: root.osdKind === "brightness" ? "sun" : "speaker"
                        level: root.osdKind === "brightness" ? 3 : (root.osdValue < 0.34 ? 1 : (root.osdValue < 0.67 ? 2 : 3))
                        color: "white"
                    }
                    // Silky: workspace layout content sharing the exact volume / brightness Liquid Glass capsule
                    Item {
                        id: osdLayoutContent
                        visible: root.osdKind === "layout"
                        anchors.fill: parent
                        readonly property var layoutSvc: root.hub ? root.hub.workspaceLayout : null
                        readonly property int modeIdx: layoutSvc ? layoutSvc.modeIndex(root.osdLayoutMode) : 0
                        Connections {
                            target: root
                            function onOsdLayoutPulseChanged() {
                                if (root.osdKind === "layout") layoutSwitchAnim.restart();
                            }
                        }
                        ParallelAnimation {
                            id: layoutSwitchAnim
                            NumberAnimation { target: osdLayoutIcon; property: "scale"; from: 0.78; to: 1.0; duration: 210; easing.type: Easing.OutBack; easing.overshoot: 1.3 }
                            NumberAnimation { target: osdLayoutLabel; property: "opacity"; from: 0.30; to: 1.0; duration: 170; easing.type: Easing.OutCubic }
                            NumberAnimation { target: osdLayoutLabel; property: "y"; from: 5; to: 0; duration: 170; easing.type: Easing.OutCubic }
                        }
                        SilkyWorkspaceLayoutIcon {
                            id: osdLayoutIcon
                            x: 20; anchors.verticalCenter: parent.verticalCenter
                            width: 24; height: 24
                            mode: root.osdLayoutMode
                            color: "white"
                            strokeWidth: 2.0
                            transformOrigin: Item.Center
                        }
                        Item {
                            x: 62; width: parent.width - 62 - 24; height: 36
                            anchors.verticalCenter: parent.verticalCenter
                            Item {
                                width: parent.width; height: 20; clip: true
                                Text {
                                    id: osdLayoutLabel
                                    text: osdLayoutContent.layoutSvc ? osdLayoutContent.layoutSvc.modeLabel(root.osdLayoutMode) : root.osdLayoutMode
                                    color: "white"
                                    font.family: root.fontForWeight(Font.DemiBold, root.fontFamily)
                                    font.pixelSize: 15
                                    font.weight: Font.DemiBold
                                }
                            }
                            Item {
                                id: osdLayoutTrack
                                anchors.left: parent.left; anchors.right: parent.right
                                anchors.bottom: parent.bottom; anchors.bottomMargin: 2
                                height: 4
                                readonly property real gap: 6
                                readonly property real segW: (width - gap * 2) / 3
                                Row {
                                    anchors.fill: parent; spacing: osdLayoutTrack.gap
                                    Repeater {
                                        model: 3
                                        Rectangle { width: osdLayoutTrack.segW; height: 4; radius: 2; color: "white"; opacity: 0.28 }
                                    }
                                }
                                Rectangle {
                                    width: osdLayoutTrack.segW; height: 4; radius: 2
                                    x: osdLayoutContent.modeIdx * (osdLayoutTrack.segW + osdLayoutTrack.gap)
                                    color: "white"; opacity: 0.96
                                    Behavior on x { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                                }
                            }
                        }
                    }
                    // segmented level bar: bright segments are filled, the rest are dim
                    Row {
                        id: osdBar
                        visible: root.osdKind !== "layout\""""

WS_BUTTON_MARKER = "id: wsLayoutBtn"
# The idle layout glyph used fg2 and read lighter than the occupied workspace numbers next to it.
WS_ICON_OLD = "wsLayoutMa.containsMouse ? bpal.fg : bpal.fg2"
WS_ICON_NEW = "wsLayoutMa.containsMouse ? bpal.fg : Qt.rgba(bpal.fg.r, bpal.fg.g, bpal.fg.b, 0.90)"
WS_ANCHOR = """                        WheelHandler {
                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad"""
WS_SNIPPET = """                        // Silky: current workspace layout indicator & click/right-click switcher
                        Item {
                            id: wsLayoutBtn
                            visible: root.hub && root.hub.workspaceLayout
                            readonly property var layoutSvc: root.hub ? root.hub.workspaceLayout : null
                            readonly property string mode: (layoutSvc && layoutSvc.modes && layoutSvc.modes[String(wsRow.activeId)]) ? layoutSvc.modes[String(wsRow.activeId)] : "floating"
                            readonly property bool nonDefault: mode !== "floating"
                            width: 24; height: 28
                            Rectangle {
                                anchors.centerIn: parent
                                width: 20; height: 20; radius: 6
                                color: wsLayoutBtn.nonDefault ? bpal.hover : (wsLayoutMa.containsMouse ? bpal.hover : "transparent")
                                opacity: wsLayoutBtn.nonDefault || wsLayoutMa.containsMouse ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 140 } }
                            }
                            SilkyWorkspaceLayoutIcon {
                                anchors.centerIn: parent
                                width: 14; height: 14
                                mode: wsLayoutBtn.mode
                                color: wsLayoutBtn.nonDefault || wsLayoutMa.containsMouse ? bpal.fg : Qt.rgba(bpal.fg.r, bpal.fg.g, bpal.fg.b, 0.90)
                            }
                            MouseArea {
                                id: wsLayoutMa
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onClicked: mouse => {
                                    ui.pop = "";
                                    if (!wsLayoutBtn.layoutSvc) return;
                                    if (mouse.button === Qt.RightButton) {
                                        var pos = wsLayoutBtn.mapToItem(null, wsLayoutBtn.width / 2, wsLayoutBtn.height);
                                        wsLayoutBtn.layoutSvc.openMenu(wsRow.activeId, perScreen.modelData.name, pos.x, root.barH + 6);
                                    } else {
                                        wsLayoutBtn.layoutSvc.cycleWorkspace(wsRow.activeId);
                                    }
                                }
                            }
                        }
"""


def backup_file(path: pathlib.Path, stamp: str) -> pathlib.Path:
    backup = path.with_name(f"{path.name}.bak.ws-layout.{stamp}")
    shutil.copy2(path, backup)
    return backup


def patch_text(path: pathlib.Path, checks: list[tuple[str, str, str, str]], check_only: bool, stamp: str) -> bool:
    text = path.read_text(encoding="utf-8")
    updated = text
    for mode, marker, anchor, snippet in checks:
        if marker in updated:
            continue
        if anchor not in updated:
            raise SystemExit(f"Anchor not found in {path}: {anchor.splitlines()[0]!r}")
        if mode == "before":
            updated = updated.replace(anchor, snippet + anchor, 1)
        elif mode == "replace":
            updated = updated.replace(anchor, snippet, 1)
        else:
            updated = updated.replace(anchor, anchor + snippet, 1)
    if updated == text:
        return False
    if check_only:
        return True
    backup = backup_file(path, stamp)
    path.write_text(updated, encoding="utf-8")
    print(f"Updated {path} (backup: {backup})")
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("shell_dir", nargs="?", type=pathlib.Path, default=DEFAULT_SHELL_DIR)
    parser.add_argument("--check", action="store_true", help="Check whether files are installed without modifying them")
    parser.add_argument("--no-reload", action="store_true", help="Skip reloading MacShell")
    args = parser.parse_args()

    shell_dir: pathlib.Path = args.shell_dir
    shell_qml = shell_dir / "shell.qml"
    bar_qml = shell_dir / "MacBar.qml"
    if not shell_qml.is_file() or not bar_qml.is_file():
        raise SystemExit(f"MacShell not found in {shell_dir}")

    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    changed = False

    for name in QML_FILES:
        src = REPO_ROOT / "config/macshell" / name
        dst = shell_dir / name
        same = dst.is_file() and dst.read_bytes() == src.read_bytes()
        if not same:
            changed = True
            if not args.check:
                if dst.is_file():
                    backup_file(dst, stamp)
                shutil.copy2(src, dst)
                print(f"Installed {dst}")

    if patch_text(
        shell_qml,
        [
            ("after", "property var workspaceLayout:", HUB_ANCHOR, HUB_SNIPPET),
            ("after", "SilkyWorkspaceLayoutOSD {", SCOPE_ANCHOR, SCOPE_SNIPPET),
        ],
        args.check,
        stamp,
    ):
        changed = True

    ws_snippet, icon_old, icon_new = WS_SNIPPET, WS_ICON_OLD, WS_ICON_NEW
    bar_text = bar_qml.read_text(encoding="utf-8")
    if "id: barContrast" in bar_text:
        ws_snippet = ws_snippet.replace("bpal.", "barWorkspacePalette.")
        icon_old = icon_old.replace("bpal.", "barWorkspacePalette.")
        icon_new = icon_new.replace("bpal.", "barWorkspacePalette.")
    icon_upgrade = [("replace", icon_new, icon_old, icon_new)] if icon_old in bar_text else []
    if patch_text(
        bar_qml,
        [
            ("before", WS_BUTTON_MARKER, WS_ANCHOR, ws_snippet),
            *icon_upgrade,
            ("after", OSD_STATE_MARKER, OSD_STATE_ANCHOR, OSD_STATE_SNIPPET),
            ("replace", OSD_CONTENT_MARKER, OSD_GLYPH_ANCHOR, OSD_GLYPH_REPLACE),
        ],
        args.check,
        stamp,
    ):
        changed = True

    if args.check:
        if changed:
            print("Workspace layout UI needs install/update.")
            return 1
        print("Workspace layout UI is up to date.")
        return 0

    if changed and not args.no_reload and shutil.which("qs"):
        subprocess.run(["qs", "-c", "MacShell", "ipc", "call", "macshell", "reload"], check=False)
        print("Reloaded MacShell.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
