#!/usr/bin/env python3
"""Silky Omarchy Bluetooth: macOS-style Control Center list and Settings page on a D-Bus backend.

* Backend: config/macshell/bluetooth/SilkyBluetooth.qml (Quickshell.Bluetooth, event driven) replaces MacBar's
  `bluetoothctl` polling. MacBar keeps its old API (btOn, btDevices, connectBt, ...) as aliases and wrappers.
  silky-bt-helper.py runs pair / connect / disconnect / forget, reports BlueZ error names and answers PIN requests.
* Control Center / menu bar list: paired devices only, round device-type badges (accent when connected), no scanning.
* Settings → Bluetooth: macOS header card, discoverable while open, "My Devices" with ⓘ device sheet (rename, connect,
  forget), "Nearby Devices" with named devices only, a spinner while searching, per-device errors, pairing requests.

Usage:
  tune-bluetooth.py <MacShell dir>      staging mode (install-macshell-optimizations.sh)
  tune-bluetooth.py --install           back up, apply to ~/.config/quickshell/MacShell, reload MacShell
  tune-bluetooth.py --check             apply to a temporary copy only
Idempotent: re-running updates the marked blocks to the repository version.
"""
import argparse
import json
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime

REPO = pathlib.Path(__file__).resolve().parent.parent
ASSETS = REPO / "config/macshell/bluetooth"
DEFAULT_SHELL = pathlib.Path.home() / ".config/quickshell/MacShell"
FILES = ("MacBar.qml", "MacDock.qml", "lang/zh-CN.js", "SilkyBluetooth.qml", "SilkyBtIcon.qml",
         "assets/silky-bt-helper.py")

STRINGS = {
    "No paired devices": "没有已配对的设备",
    "My Devices": "我的设备",
    "Nearby Devices": "附近设备",
    "Searching for devices…": "正在搜索设备…",
    "No new devices found": "未发现新设备",
    "Put the device in pairing mode to see it here.": "让设备进入配对模式后，它会显示在这里。",
    "Connect accessories you can use for activities such as streaming music, typing, and gaming.":
        "连接可用于播放音乐、键入文字和玩游戏等活动的配件。",
    "When Bluetooth Settings is open, this computer is discoverable as “%1”.": "“蓝牙”设置打开时，此电脑可被发现为“%1”。",
    "This computer is not discoverable right now.": "此电脑当前不可被发现。",
    "Bluetooth is blocked. Turn off Airplane Mode to use it.": "蓝牙已被禁用。关闭飞行模式后即可使用。",
    "Connected": "已连接",
    "Not Connected": "未连接",
    "Connect": "连接",
    "Disconnect": "断开连接",
    "Connecting…": "正在连接…",
    "Disconnecting…": "正在断开…",
    "Pairing…": "正在配对…",
    "Removing…": "正在移除…",
    "Cancel": "取消",
    "Done": "完成",
    "Pair": "配对",
    "Name": "名称",
    "Address": "地址",
    "Battery %1%": "电量 %1%",
    "Forget This Device…": "忽略此设备…",
    "Forget Device": "忽略设备",
    "This device will be removed from your devices. You will need to pair it again to use it.":
        "此设备将从你的设备中移除。之后需要重新配对才能使用。",
    "Bluetooth Pairing Request": "蓝牙配对请求",
    "Confirm that “%1” shows this code:": "请确认“%1”上显示以下配对码：",
    "Enter the code for “%1”. Try 0000 or 1234 if the device has no screen.":
        "输入“%1”的配对码。若设备没有屏幕，可尝试 0000 或 1234。",
    "Type this code on “%1”, then press Return:": "在“%1”上键入以下配对码，然后按下回车键：",
    "Pairing was rejected. Check the code and try again.": "配对被拒绝。请检查配对码后重试。",
    "Pairing was canceled.": "配对已取消。",
    "The device did not respond. Make sure it is on and nearby.": "设备没有响应。请确认设备已开启并在附近。",
    "The device did not respond.": "设备没有响应。",
    "Bluetooth is not ready yet.": "蓝牙尚未就绪。",
    "The device is no longer available.": "该设备已不可用。",
    "This device has no profile this computer can use.": "此设备没有这台电脑可用的服务。",
    "Could not disconnect the device.": "无法断开设备。",
    "Could not remove the device.": "无法移除设备。",
    "Could not connect to the device.": "无法连接设备。",
}

# keys whose existing MacShell translation differs from the macOS wording
OVERRIDE = ("Nearby Devices",)

BACKEND = """    // ═════════════ BLUETOOTH ═════════════
    // Silky Bluetooth backend: SilkyBluetooth.qml (BlueZ over D-Bus, event driven; see docs/02-macshell.md#蓝牙面板与设置页).
    // The old names stay as aliases so the rest of MacShell keeps working. The Control Center list shows paired devices
    // only; nearby devices are found in Settings → Bluetooth, which searches while it is open.
    SilkyBluetooth { id: silkyBt }
    readonly property var btBackend: silkyBt
    property alias btOn: silkyBt.on
    property alias btConnected: silkyBt.connectedCount
    property alias btConnectedName: silkyBt.connectedName
    property alias btScanning: silkyBt.scanning
    property alias btDevices: silkyBt.myDevices
    property alias btBusy: silkyBt.busy
    property alias btError: silkyBt.error
    function refreshBt() { silkyBt.schedule(); }
    function scanBt() {}
    function connectBt(mac, connected) { silkyBt.connectDevice(mac, connected); }
    function toggleBt() { silkyBt.toggle(); }
    // Silky Bluetooth backend end
"""


def fail(message):
    raise SystemExit(f"Bluetooth: {message}")


def swap(source, old, new, what, path):
    if new in source:
        return source
    if source.count(old) != 1:
        fail(f"expected one {what} in {path}")
    return source.replace(old, new, 1)


def transform_bar(source, path="MacBar.qml"):
    # 1. backend: replace everything from the BLUETOOTH banner up to the Airplane Mode property (or the previous Silky block)
    start = source.find("    // ═════════════ BLUETOOTH ═════════════\n")
    end = source.find("    readonly property bool airplane: ")
    if start < 0 or end < start:
        fail(f"could not find the Bluetooth backend block in {path}")
    block = source[start:end]
    if "Silky Bluetooth backend end" not in block and "function toggleBt()" not in block:
        fail(f"unexpected Bluetooth backend block in {path}")
    source = source[:start] + BACKEND + source[end:]

    # 2. Control Center / menu bar list: drop the "Devices · Scan" header row (the list no longer scans)
    header = re.compile(
        r"\n                        Item \{\n                            visible: root\.btOn && root\.btDevices\.length > 0\n"
        r"                            width: parent\.width; height: 22\n.*?onClicked: root\.scanBt\(\) \}\n"
        r"                                \}\n                            \}\n                        \}\n", re.S)
    if header.search(source):
        source = header.sub("\n", source, count=1)

    source = swap(source,
                  'text: root.btScanning ? I18n.tr("Searching for devices\\u2026") : I18n.tr("No devices found")',
                  'text: I18n.tr("No paired devices")',
                  "empty-list text", path)

    # 3. rows: device-type badge (accent when connected) instead of the check mark / bare glyph
    source = swap(source,
                  """                                        width: btList.width; height: 38

                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 8
                                            color: root.accent
                                            visible: bma.containsMouse
                                        }

                                        Glyph {
                                            visible: devRow.modelData.connected
                                            x: 9; anchors.verticalCenter: parent.verticalCenter
                                            width: 14; height: 14
                                            kind: "check"
                                            color: bma.containsMouse ? "white" : pp.fg
                                        }
                                        Glyph {
                                            visible: !devRow.modelData.connected
                                            x: 9; anchors.verticalCenter: parent.verticalCenter
                                            width: 14; height: 14
                                            kind: devRow.modelData.icon || "bluetooth"
                                            color: bma.containsMouse ? "white" : pp.fg2
                                        }

                                        Text {
                                            x: 30
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: parent.width - 30 - 100""",
                  """                                        width: btList.width; height: 40

                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 8
                                            color: root.accent
                                            visible: bma.containsMouse
                                        }

                                        // Silky Bluetooth: round device-type badge, accent when connected (white on the hover fill)
                                        SilkyBtIcon {
                                            x: 6; anchors.verticalCenter: parent.verticalCenter
                                            width: 28; height: 28
                                            kind: devRow.modelData.icon || "bluetooth"
                                            active: devRow.modelData.connected && !bma.containsMouse
                                            dark: pp.dark
                                            accent: root.accent
                                            fg: bma.containsMouse ? "white" : pp.fg
                                        }

                                        Text {
                                            x: 42
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: parent.width - 42 - 100""",
                  "device row", path)

    # 4. right column: battery instead of "Connected"; nothing for paired-but-idle devices (every row is paired now)
    source = swap(source,
                  """                                            visible: !devRow.busy && devRow.modelData.connected && !bma.containsMouse
                                            anchors.right: parent.right; anchors.rightMargin: 12
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: I18n.tr("Connected")""",
                  """                                            visible: !devRow.busy && devRow.modelData.connected && !bma.containsMouse && devRow.modelData.bat !== ""
                                            anchors.right: parent.right; anchors.rightMargin: 12
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: devRow.modelData.bat + "%\"""",
                  "connected label", path)
    source = swap(source,
                  "visible: !devRow.busy && !devRow.modelData.connected && !bma.containsMouse && devRow.modelData.paired\n",
                  "visible: false     // Silky Bluetooth: every listed device is paired\n",
                  "paired label", path)
    source = swap(source,
                  "readonly property bool busy: root.btBusy === modelData.mac\n",
                  "readonly property bool busy: root.btBusy === modelData.mac || modelData.busy\n",
                  "row busy state", path)
    return source


def replace_marked(source, begin, end, fragment, fallback_start, fallback_end, what, path):
    i = source.find(begin)
    if i >= 0:
        # include the indentation before the marker
        i = source.rfind("\n", 0, i) + 1
        j = source.find(end, i)
        if j < 0:
            fail(f"unterminated {what} block in {path}")
        j = source.find("\n", j) + 1
        if source[j:j + 1] == "\n":
            j += 1
        return source[:i] + fragment + source[j:]
    i = source.find(fallback_start)
    j = source.find(fallback_end, i + 1)
    if i < 0 or j < 0 or source.count(fallback_start) != 1:
        fail(f"could not find the {what} in {path}")
    return source[:i] + fragment + source[j:]


def transform_dock(source, path="MacDock.qml"):
    # each block is followed by one blank line in MacDock.qml
    components = (ASSETS / "settings-components.qml.in").read_text().rstrip("\n") + "\n\n"
    pane = (ASSETS / "settings-pane.qml.in").read_text().rstrip("\n") + "\n\n"
    anchor = "    // Light / Dark appearance thumbnail\n"
    if "// Silky Bluetooth components begin" in source:
        source = replace_marked(source, "// Silky Bluetooth components begin", "// Silky Bluetooth components end",
                                components, None, None, "settings components", path)
    elif source.count(anchor) == 1:
        source = source.replace(anchor, components + anchor, 1)
    else:
        fail(f"could not find where to add the settings components in {path}")
    return replace_marked(source, "// Silky Bluetooth pane begin", "// Silky Bluetooth pane end", pane,
                          "        // ── Bluetooth ──", "        // ── Network ──", "Bluetooth pane", path)


def transform_translations(text):
    anchor = "var strings = {\n"
    if text.count(anchor) != 1:
        fail("could not find the Chinese translation dictionary")
    additions = []
    for key, value in STRINGS.items():
        quoted = json.dumps(key, ensure_ascii=False)
        line = f"    {quoted}: {json.dumps(value, ensure_ascii=False)},\n"
        existing = re.search(r"(?m)^\s*" + re.escape(quoted) + r"\s*:.*\n", text)
        if existing:
            if existing.group(0) != line and key in OVERRIDE:
                text = text.replace(existing.group(0), line, 1)
            continue
        additions.append(line)
    if additions:
        text = text.replace(anchor, anchor + "".join(additions), 1)
    return text


def apply_to_dir(shell):
    bar, dock, lang = shell / "MacBar.qml", shell / "MacDock.qml", shell / "lang/zh-CN.js"
    for required in (bar, dock):
        if not required.is_file():
            fail(f"missing {required}")
    outputs = {
        bar: transform_bar(bar.read_text(), bar),
        dock: transform_dock(dock.read_text(), dock),
    }
    if lang.is_file():
        outputs[lang] = transform_translations(lang.read_text())
    outputs[shell / "SilkyBluetooth.qml"] = (ASSETS / "SilkyBluetooth.qml").read_text()
    outputs[shell / "SilkyBtIcon.qml"] = (ASSETS / "SilkyBtIcon.qml").read_text()
    outputs[shell / "assets/silky-bt-helper.py"] = (ASSETS / "silky-bt-helper.py").read_text()
    changed = []
    for path, content in outputs.items():
        if not path.is_file() or path.read_text() != content:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
            changed.append(str(path.relative_to(shell)))
    helper = shell / "assets/silky-bt-helper.py"
    helper.chmod(0o755)
    return changed


def copy_tree(src, dst):
    for rel in FILES:
        if (src / rel).is_file():
            (dst / rel).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src / rel, dst / rel)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("shell_dir", nargs="?")
    parser.add_argument("--install", action="store_true")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    target = pathlib.Path(args.shell_dir) if args.shell_dir else DEFAULT_SHELL

    if args.check or args.install:
        with tempfile.TemporaryDirectory() as tmp:
            probe = pathlib.Path(tmp) / "MacShell"
            copy_tree(target, probe)
            pending = apply_to_dir(probe)
        if args.check:
            print(f"Bluetooth preflight OK ({len(pending)} file(s) would change).")
            return
        if not pending:
            print("Bluetooth already up to date.")
            return
        stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        backup = pathlib.Path.home() / ".local/state/silky-omarchy" / f"bluetooth-backup-{stamp}"
        copy_tree(target, backup)
        changed = apply_to_dir(target)
        subprocess.run(["qs", "-c", "MacShell", "ipc", "call", "macshell", "reload"], check=False)
        print(f"Installed ({', '.join(changed)}). Backup: {backup}")
        return

    apply_to_dir(target)


if __name__ == "__main__":
    main()
