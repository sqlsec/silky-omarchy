#!/usr/bin/env python3
"""Install the macOS-style Trackpad gesture showcase and Touchscreen guide into MacShell."""
from __future__ import annotations

import argparse
from datetime import datetime
import json
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
ASSETS = REPO_ROOT / "config/macshell/trackpad"
OVERVIEW_SRC = REPO_ROOT / "config/macshell/overview/SilkyOverview.qml"
DEFAULT_SHELL = pathlib.Path.home() / ".config/quickshell/MacShell"

TOUCHSCREEN_GLYPH_MARKER = 'gl.kind === "touchscreen"'
TOUCHSCREEN_GLYPH_ANCHOR = """            // about
            Item {
                visible: gl.kind === "about"; anchors.fill: parent"""
TOUCHSCREEN_GLYPH_SNIPPET = """            // touchscreen (rounded display frame with finger contact & ripple arc)
            Item {
                visible: gl.kind === "touchscreen"; anchors.fill: parent
                Rectangle {
                    x: 1.5; y: 3.0; width: 13; height: 10; radius: 2.2
                    color: "transparent"; border.width: 1.4; border.color: "white"
                }
                Rectangle {
                    x: 6.4; y: 6.8; width: 3.2; height: 3.2; radius: 1.6
                    color: "white"
                }
                Canvas {
                    anchors.fill: parent
                    onPaint: {
                        var c = getContext("2d"); c.reset();
                        c.strokeStyle = "white"; c.lineWidth = 1.2; c.lineCap = "round";
                        c.beginPath();
                        c.arc(8.0, 8.4, 3.4, -Math.PI * 0.86, -Math.PI * 0.14, false);
                        c.stroke();
                    }
                }
            }
"""

SIDEBAR_OLD = (
    '            { id: "trackpad",   sec: 6, name: "Trackpad",        wg: "trackpad",   '
    'c1: "#A7A7AD", c2: "#7C7C82", keys: "tap click natural scroll touchpad gestures" },'
)
SIDEBAR_NEW = (
    '            { id: "trackpad",   sec: 6, name: "Trackpad",        wg: "trackpad",   '
    'c1: "#A7A7AD", c2: "#7C7C82", keys: "tap click natural scroll touchpad gestures three finger drag mission control expose launchpad pinch 触控板 手势" },\n'
    '            { id: "touchscreen", sec: 6, name: "Touchscreen",    glyph: "touchscreen", '
    'c1: "#A7A7AD", c2: "#7C7C82", keys: "touch screen finger swipe pinch overview drag resize edge gestures 触控屏 手势" },'
)

LOADER_OLD = "keyboard: paneKeyboard, mouse: paneMouse, trackpad: paneTrackpad,"
LOADER_NEW = "keyboard: paneKeyboard, mouse: paneMouse, trackpad: paneTrackpad, touchscreen: paneTouchscreen,"

CTRL_LINE = "    SilkyTouchscreenController { id: touchscreenCtrl }\n"
CTRL_ANCHORS = (
    "    SilkyDisplaySettings { id: displaySettings }\n",
    '    Process {\n        running: true\n        command: ["sh", "-c", "n=$(getent passwd',
)

RESET_OLD = "            bar.tpNatural = true; bar.tpTap = true; bar.tpDwt = true; bar.tpScroll = 0.7;"
RESET_NEW = (
    "            bar.tpNatural = true; bar.tpTap = true; bar.tpDwt = true; bar.tpScroll = 0.7; "
    "bar.tpClickfinger = true; bar.tpDrag3fg = true; bar.tpTapAndDrag = true; bar.tpWorkspaceSwipe = 4; "
    "bar.tpMissionControl = true; bar.tpAppExpose = true; bar.tpLaunchpadPinch = true;"
)

CUR_SCROLL_OLD = "        onCurChanged: flick.contentY = 0"
CUR_SCROLL_NEW = """        onCurChanged: {
            flick.contentY = 0;
            Qt.callLater(function() {
                var pos = prefsWindow.filtered.indexOf(prefsWindow.cur);
                if (pos < 0 || pos >= navCol.children.length) return;
                var row = navCol.children[pos];
                if (!row || row.height <= 0) return;
                if (row.y < navFlick.contentY)
                    navFlick.contentY = Math.max(0, row.y - 8);
                else if (row.y + row.height > navFlick.contentY + navFlick.height)
                    navFlick.contentY = Math.max(0, Math.min(navFlick.contentHeight - navFlick.height, row.y + row.height - navFlick.height + 8));
            });
        }"""

BAR_TABS_SNIPPET = """    property int tpSettingsTab: 0
    property int tsSettingsTab: 0
"""

OPEN_PREFS_OLD = """        if (pane !== undefined && pane !== "") {
            for (var i = 0; i < prefsWindow.panes.length; i++)
                if (prefsWindow.panes[i].id === pane) { prefsWindow.go(i); break; }
        }"""
OPEN_PREFS_NEW = """        if (pane !== undefined && pane !== "") {
            var parts = String(pane).split(":");
            var targetId = parts[0];
            if (parts.length > 1 && bar) {
                var sub = Math.max(0, Math.min(2, parseInt(parts[1], 10) || 0));
                if (targetId === "trackpad") bar.tpSettingsTab = sub;
                else if (targetId === "touchscreen") bar.tsSettingsTab = sub;
            }
            for (var i = 0; i < prefsWindow.panes.length; i++)
                if (prefsWindow.panes[i].id === targetId) { prefsWindow.go(i); break; }
        }"""

BAR_INPUT_OLD = """    property bool tpNatural: true
    property bool tpTap: true
    property bool tpDwt: true
    property real tpScroll: 0.7
    readonly property string inputSig: [kbRepeatRate, kbRepeatDelay, mouseSens, mouseNatural, tpNatural, tpTap, tpDwt, tpScroll].join("|")
    onInputSigChanged: if (settingsReady) inputApplyT.restart()
    Timer { id: inputApplyT; interval: 150; onTriggered: root.applyInput() }
    function applyInput() {
        function b(v) { return v ? "true" : "false"; }
        Quickshell.execDetached(["hyprctl", "eval", "hl.config({ input = { repeat_rate = " + Math.round(kbRepeatRate) + ", repeat_delay = " + Math.round(kbRepeatDelay)
            + ", sensitivity = " + mouseSens.toFixed(2) + ", natural_scroll = " + b(mouseNatural)
            + ", touchpad = { natural_scroll = " + b(tpNatural) + ", tap_to_click = " + b(tpTap) + ", disable_while_typing = " + b(tpDwt)
            + ", scroll_factor = " + tpScroll.toFixed(2) + " } } })"]);
    }"""

BAR_INPUT_NEW = """    property bool tpNatural: true
    property bool tpTap: true
    property bool tpDwt: true
    property real tpScroll: 0.7
    property bool tpClickfinger: true
    property bool tpDrag3fg: true
    property bool tpTapAndDrag: true
    property int tpWorkspaceSwipe: 4
    property bool tpMissionControl: true
    property bool tpAppExpose: true
    property bool tpLaunchpadPinch: true
    readonly property string inputSig: [kbRepeatRate, kbRepeatDelay, mouseSens, mouseNatural, tpNatural, tpTap, tpDwt, tpScroll, tpClickfinger, tpDrag3fg, tpTapAndDrag, tpWorkspaceSwipe].join("|")
    onInputSigChanged: if (settingsReady) inputApplyT.restart()
    Timer { id: inputApplyT; interval: 150; onTriggered: root.applyInput() }
    function applyInput() {
        function b(v) { return v ? "true" : "false"; }
        var dragMode = tpDrag3fg ? 1 : 0;
        var wsFingers = (tpWorkspaceSwipe === 3 && !tpDrag3fg) ? 3 : (tpWorkspaceSwipe === 0 ? 0 : 4);
        var cfgCmd = "hl.config({ input = { repeat_rate = " + Math.round(kbRepeatRate) + ", repeat_delay = " + Math.round(kbRepeatDelay)
            + ", sensitivity = " + mouseSens.toFixed(2) + ", natural_scroll = " + b(mouseNatural)
            + ", touchpad = { natural_scroll = " + b(tpNatural) + ", tap_to_click = " + b(tpTap) + ", disable_while_typing = " + b(tpDwt)
            + ", clickfinger_behavior = " + b(tpClickfinger) + ", tap_and_drag = " + b(tpTapAndDrag) + ", drag_3fg = " + dragMode
            + ", scroll_factor = " + tpScroll.toFixed(2) + " } } })";
        var shCmd = "hyprctl eval '" + cfgCmd + "' >/dev/null 2>&1 || true"
            + "; hyprctl eval 'hl.gesture({ fingers = 3, direction = \\"horizontal\\", action = \\"unset\\" })' >/dev/null 2>&1 || true"
            + "; hyprctl eval 'hl.gesture({ fingers = 4, direction = \\"horizontal\\", action = \\"unset\\" })' >/dev/null 2>&1 || true"
            + (wsFingers > 0 ? "; hyprctl eval 'hl.gesture({ fingers = " + wsFingers + ", direction = \\"horizontal\\", action = \\"workspace\\" })' >/dev/null 2>&1 || true" : "");
        Quickshell.execDetached(["sh", "-c", shCmd]);
    }"""

BAR_KEYS_OLD = '"kbRepeatRate", "kbRepeatDelay", "mouseSens", "mouseNatural", "tpNatural", "tpTap", "tpDwt", "tpScroll"]'
BAR_KEYS_NEW = (
    '"kbRepeatRate", "kbRepeatDelay", "mouseSens", "mouseNatural", "tpNatural", "tpTap", "tpDwt", "tpScroll", '
    '"tpClickfinger", "tpDrag3fg", "tpTapAndDrag", "tpWorkspaceSwipe", "tpMissionControl", "tpAppExpose", "tpLaunchpadPinch"]'
)

BAR_PINCH_GUARD_MARKER = "root.tpLaunchpadPinch === false"
BAR_PINCH_OLD = '                        if (event.name !== "silkylaunchpad") return;\n'
BAR_PINCH_NEW = (
    '                        if (event.name !== "silkylaunchpad") return;\n'
    '                        if (root.tpLaunchpadPinch === false && !(ui.pop === "spot" && ui.spMode === "apps") && !ui.lpGesture) return;\n'
)

STRINGS = {
    "Touchscreen": "触控屏",
    "Point & Click": "光标与点按",
    "Scroll & Zoom": "滚动与缩放",
    "More Gestures": "更多手势",
    "Tap with one finger to click": "单指轻点来点按",
    "Secondary click": "辅助点按",
    "Open context menus on files, icons and text": "在文件、图标和文本上打开右键菜单",
    "Click or Tap with Two Fingers": "双指点按或轻点",
    "Click in Bottom Right Corner": "点按右下角",
    "Three Finger Drag": "三指拖移",
    "Move windows, files, selected text and sliders with three fingers": "用三指拖动窗口、文件、选区与滑块",
    "Tap and drag": "轻点并拖移",
    "Double-tap and hold to drag without lifting your finger": "连点两下并在第二次按住以拖移项目",
    "Prevent accidental palm touches while typing": "打字时防止手掌边缘误触",
    "Zoom in or out": "放大或缩小",
    "Pinch with two fingers in browsers, images and documents": "在浏览器、图片和文档中双指捏合或张开",
    "Pinch with two fingers": "双指捏合",
    "Swipe between pages": "轻扫切换页面",
    "Scroll left or right with two fingers to navigate browser history": "在浏览器中用双指左右滚动以前进或后退",
    "Scroll left or right with two fingers": "双指左右滚动",
    "Swipe between full-screen spaces": "轻扫切换空间",
    "1:1 workspace slide with rubber-band bounce at the first and last space": "1:1 跟手切换工作区，滑到首尾带阻尼回弹",
    "Swipe Left or Right with Four Fingers": "四指左右轻扫",
    "Swipe Left or Right with Three Fingers": "三指左右轻扫",
    "Off": "关闭",
    "Mission Control": "调度中心",
    "Show workspace strip and all windows on the current workspace": "显示顶部工作区预览与当前工作区的所有窗口",
    "Swipe Up with Four Fingers": "四指向上轻扫",
    "App Exposé": "App Exposé",
    "Show all open windows of the active application across spaces": "显示当前前台应用在所有工作区的窗口",
    "Swipe Down with Four Fingers": "四指向下轻扫",
    "Pinch with thumb and three or four fingers to open, spread to close": "捏拢拇指和其他三指打开应用面板，张开手指关闭",
    "Hover or click any gesture row to preview its finger motion and live desktop animation.": "将指针悬停或点击任意手势项，即可在上方预览手指动作与桌面联动动画。",
    "Direct touch, floating window controls and multi-finger workspace gestures": "支持直觉点按、浮动窗口触控与多指工作区手势",
    "No built-in touchscreen detected; gesture tutorials remain available for external touch displays": "未检测到内置触控屏，以下手势教程同样适用于外接触控显示器",
    "Window & Tap": "窗口与点按",
    "Scroll & Browse": "滚动与浏览",
    "Workspaces & Multitasking": "工作区与多任务",
    "Move floating windows": "移动浮动窗口",
    "Drag a window's top 44 px bar; stays below the menu bar and snaps at screen edges": "单指拖动浮动窗口顶部 44 px 区域，自动避让菜单栏并在屏幕边缘触发吸附预览",
    "Drag top bar": "拖动顶部",
    "Resize from edges or corners": "边缘与四角缩放",
    "Drag any floating window edge (16 px band) or corner to resize": "单指按住浮动窗口边缘（16 px 热区）或四角拖动以调整大小",
    "Drag edge or corner": "拖边缘或四角",
    "Hold anywhere to move": "长按任意位置移动",
    "Hold one finger still for 0.4 s inside a floating window to pick it up and drag": "在浮动窗口内按住不动 0.4 秒，拾起窗口后即可直接拖动",
    "Hold 0.4 s & drag": "长按 0.4 秒拖动",
    "Context menu": "上下文菜单",
    "Long-press on files, list items or icons to open the context menu": "在文件、列表项或图标上长按以打开右键菜单",
    "Long press": "长按项目",
    "Kinetic touch scrolling": "跟手滑动与惯性滑行",
    "1:1 finger tracking in apps, Folio and WeChat; glides after lift and stops on touch": "单指上下 1:1 滑动浏览应用、Folio 与微信会话，离手惯性滑行，轻触即停",
    "One-finger swipe": "单指滑动",
    "Pinch to zoom": "双指捏合缩放",
    "Spread or pinch two fingers on the screen to zoom pages and images": "双指在屏幕上张开放大、捏合缩小网页与图片",
    "Screen-edge workspace swipe": "屏幕边缘切换空间",
    "Swipe inward from the left or right 20 px screen edge; bounces at the ends": "单指从屏幕左右边缘 20 px 内向内横滑切换工作区，首尾带阻尼回弹",
    "Swipe from screen edge": "左右边缘向内",
    "Three-finger workspace swipe": "三指轻扫切换空间",
    "Swipe left or right with three or more fingers anywhere on the screen": "三指及以上在屏幕任意位置左右滑动，1:1 跟手切换工作区",
    "Swipe with three fingers": "三指左右滑动",
    "Swipe up with four fingers on the screen to view all windows on this workspace": "四指在屏幕上向上滑动，打开顶部工作区预览与当前工作区窗口总览",
    "Swipe down with four fingers on the screen to view windows of the active app": "四指在屏幕上向下滑动，查看当前应用的所有窗口",
    "Pinch in with four or five fingers on the screen to open Applications, spread to close": "四指或五指在屏幕上向心抓拢打开应用面板，向外张开关闭",
    "Tap or hover any row to replay the touch target and desktop gesture guide.": "点击或悬停任意条目，即可在上方重播触控落点与桌面手势演示。",
}


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    if text.count(old) != 1:
        raise SystemExit(f"Trackpad settings: expected one match for {label}")
    return text.replace(old, new, 1)


def transform_dock(source: str) -> str:
    if TOUCHSCREEN_GLYPH_MARKER not in source:
        if source.count(TOUCHSCREEN_GLYPH_ANCHOR) != 1:
            raise SystemExit("Trackpad settings: could not find SGlyph about anchor in MacDock.qml")
        source = source.replace(TOUCHSCREEN_GLYPH_ANCHOR, TOUCHSCREEN_GLYPH_SNIPPET + TOUCHSCREEN_GLYPH_ANCHOR, 1)

    if 'id: "touchscreen"' not in source:
        source = replace_once(source, SIDEBAR_OLD, SIDEBAR_NEW, "sidebar trackpad entry")

    source = replace_once(source, LOADER_OLD, LOADER_NEW, "paneLoader trackpad mapping")

    if CTRL_LINE not in source:
        placed = False
        for anchor in CTRL_ANCHORS:
            if anchor in source:
                source = source.replace(anchor, anchor + CTRL_LINE, 1)
                placed = True
                break
        if not placed:
            raise SystemExit("Trackpad settings: could not find controller insertion point in MacDock.qml")

    panes_inc = (ASSETS / "TrackpadPanes.qml.inc").read_text().rstrip() + "\n\n"
    pane_pattern = (
        r"(?ms)^        // ── (?:Gesture badge & interactive row helpers for Trackpad / Touchscreen|Trackpad) ──\n"
        r".*?(?=^        // ── Wallpaper ──)"
    )
    source, count = re.subn(pane_pattern, lambda _: panes_inc, source)
    if count != 1:
        raise SystemExit("Trackpad settings: could not replace paneTrackpad block in MacDock.qml")

    source = replace_once(source, RESET_OLD, RESET_NEW, "resetSettings trackpad defaults")
    if "navCol.children[pos]" not in source:
        source = replace_once(source, CUR_SCROLL_OLD, CUR_SCROLL_NEW, "onCurChanged sidebar scroll")
    if "var parts = String(pane).split" not in source:
        source = replace_once(source, OPEN_PREFS_OLD, OPEN_PREFS_NEW, "openPrefs sub-tab routing")
    return source


def transform_bar(source: str) -> str:
    if "property bool tpClickfinger:" not in source:
        source = replace_once(source, BAR_INPUT_OLD, BAR_INPUT_NEW, "MacBar input properties & applyInput")
    if "property int tpSettingsTab:" not in source:
        source = replace_once(
            source,
            "    property bool tpLaunchpadPinch: true\n",
            "    property bool tpLaunchpadPinch: true\n" + BAR_TABS_SNIPPET,
            "MacBar tab memory properties",
        )
    if '"tpClickfinger"' not in source:
        source = replace_once(source, BAR_KEYS_OLD, BAR_KEYS_NEW, "MacBar settingKeys list")
    if BAR_PINCH_GUARD_MARKER not in source and BAR_PINCH_OLD in source:
        source = replace_once(source, BAR_PINCH_OLD, BAR_PINCH_NEW, "MacBar silkylaunchpad guard")
    return source


def transform_translations(translations: str) -> str:
    anchor = "var strings = {\n"
    if translations.count(anchor) != 1:
        raise SystemExit("Trackpad settings: could not find Chinese translation dictionary")
    additions = []
    for key, value in STRINGS.items():
        quoted_key = json.dumps(key, ensure_ascii=False)
        if not re.search(r"(?m)^\s*" + re.escape(quoted_key) + r"\s*:", translations):
            additions.append(f"    {quoted_key}: {json.dumps(value, ensure_ascii=False)},\n")
    if not additions:
        return translations
    return translations.replace(anchor, anchor + "".join(additions), 1)


def apply_to_dir(shell: pathlib.Path, sync_overview: bool = False) -> list[str]:
    dock_path = shell / "MacDock.qml"
    bar_path = shell / "MacBar.qml"
    lang_path = shell / "lang/zh-CN.js"

    for required in (dock_path, bar_path, lang_path):
        if not required.is_file():
            raise SystemExit(f"Trackpad settings: missing {required}")

    new_dock = transform_dock(dock_path.read_text())
    new_bar = transform_bar(bar_path.read_text())
    new_lang = transform_translations(lang_path.read_text())

    changed: list[str] = []

    for asset in sorted(ASSETS.glob("*.qml")):
        dest = shell / asset.name
        data = asset.read_bytes()
        if not dest.is_file() or dest.read_bytes() != data:
            dest.write_bytes(data)
            changed.append(asset.name)

    if sync_overview and OVERVIEW_SRC.is_file() and (shell / "SilkyOverview.qml").is_file():
        ov_dest = shell / "SilkyOverview.qml"
        ov_data = OVERVIEW_SRC.read_bytes()
        if ov_dest.read_bytes() != ov_data:
            ov_dest.write_bytes(ov_data)
            changed.append("SilkyOverview.qml")

    for path, content in ((dock_path, new_dock), (bar_path, new_bar), (lang_path, new_lang)):
        if path.read_text() != content:
            path.write_text(content)
            changed.append(str(path.relative_to(shell)))

    return changed


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("shell_dir", nargs="?", help="Target MacShell directory (used by staging installers)")
    parser.add_argument("--install", action="store_true", help="Backup, install into live MacShell and reload")
    parser.add_argument("--check", action="store_true", help="Validate anchors on a temporary copy without modifying files")
    args = parser.parse_args()

    target = pathlib.Path(args.shell_dir) if args.shell_dir else DEFAULT_SHELL

    if args.check:
        with tempfile.TemporaryDirectory() as tmp:
            stage = pathlib.Path(tmp) / "MacShell"
            stage.mkdir()
            (stage / "lang").mkdir()
            shutil.copy2(target / "MacDock.qml", stage / "MacDock.qml")
            shutil.copy2(target / "MacBar.qml", stage / "MacBar.qml")
            shutil.copy2(target / "lang/zh-CN.js", stage / "lang/zh-CN.js")
            if (target / "SilkyOverview.qml").is_file():
                shutil.copy2(target / "SilkyOverview.qml", stage / "SilkyOverview.qml")
            apply_to_dir(stage, sync_overview=True)
        print("Trackpad & Touchscreen settings preflight OK.")
        return

    if args.install:
        with tempfile.TemporaryDirectory() as tmp:
            probe = pathlib.Path(tmp) / "MacShell"
            probe.mkdir()
            (probe / "lang").mkdir()
            for rel in ("MacDock.qml", "MacBar.qml", "lang/zh-CN.js", "SilkyOverview.qml",
                        "SilkyGestureStage.qml", "SilkyTouchscreenController.qml",
                        "SilkyGestureBadge.qml", "SilkyGestureRow.qml"):
                src = target / rel
                if src.is_file():
                    dst = probe / rel
                    dst.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(src, dst)
            pending = apply_to_dir(probe, sync_overview=True)
        if not pending:
            print("Trackpad & Touchscreen settings already up to date.")
            return
        stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        backup_root = pathlib.Path.home() / ".local/state/silky-omarchy" / f"trackpad-backup-{stamp}"
        backup_root.mkdir(parents=True, exist_ok=True)
        for rel in ("MacDock.qml", "MacBar.qml", "lang/zh-CN.js", "SilkyOverview.qml",
                    "SilkyGestureStage.qml", "SilkyTouchscreenController.qml",
                    "SilkyGestureBadge.qml", "SilkyGestureRow.qml"):
            src = target / rel
            if src.is_file():
                dst = backup_root / rel
                dst.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(src, dst)
        changed = apply_to_dir(target, sync_overview=True)
        subprocess.run(["qs", "-c", "MacShell", "ipc", "call", "macshell", "reload"], check=False)
        print(f"Installed ({len(changed)} updated). Backup: {backup_root}")
        return

    # Staging mode (called by install-macshell-optimizations.sh)
    apply_to_dir(target, sync_overview=False)


if __name__ == "__main__":
    main()
