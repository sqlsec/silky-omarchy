#!/usr/bin/env python3
"""Silky Omarchy Wi-Fi: macOS-style menu-bar list, Option-click details and Settings → Wi-Fi.

Builds on install-macshell-wifi.sh (patches/macshell-wifi-scan.patch + silky-wifi-scan.py), which must be applied first,
and on the Bluetooth Settings components (SBtSpinner, scripts/tune-bluetooth.py).

* SilkyWifi.qml groups the scan into known networks (matched by SSID, not by profile name) and other networks, rates
  security (open / weak / ok), forgets networks, switches Auto-Join and reads link details (silky-wifi-info.py).
* Menu-bar / Control Center list: round badges, "Known Networks", "Other Networks" folded behind a row, a notice for a
  weak or open current network, per-network errors, and a right click on the menu-bar icon for the Option-click details.
* Settings → Wi-Fi: header card with the network in use and "Details…", Known Networks with a ⋯ menu, Other Networks
  with Connect on hover, "Other…" for hidden networks, and sheets for details, password and forgetting.

Usage:
  tune-wifi.py <MacShell dir>      staging mode (install-macshell-optimizations.sh)
  tune-wifi.py --install           back up, apply to ~/.config/quickshell/MacShell, reload MacShell
  tune-wifi.py --check             apply to a temporary copy only
Idempotent: re-running updates the marked blocks to the repository version.
"""
import argparse
import json
import pathlib
import re
import shutil
import subprocess
import tempfile
from datetime import datetime

REPO = pathlib.Path(__file__).resolve().parent.parent
ASSETS = REPO / "config/macshell/wifi"
DEFAULT_SHELL = pathlib.Path.home() / ".config/quickshell/MacShell"
FILES = ("MacBar.qml", "MacDock.qml", "lang/zh-CN.js", "SilkyWifi.qml", "assets/silky-wifi-info.py",
         "assets/silky-wifi-scan.py", "assets/silky-wifi-conn.py")

STRINGS = {
    "Wi-Fi": "Wi-Fi",
    "Wi-Fi Settings…": "Wi-Fi 设置…",
    "Known Networks": "已知网络",
    "Other Networks": "其他网络",
    "Weak Security Network…": "低安全性的网络…",
    "Insecure Network…": "不安全的网络…",
    "Weak Security": "低安全性",
    "Insecure Network": "不安全的网络",
    "Interface Name": "接口名称",
    "Hardware Address": "硬件地址",
    ": ": "：",
    "IP Address": "IP 地址",
    "Router": "路由器",
    "MAC Address": "MAC 地址",
    "Security": "安全性",
    "None": "无",
    "Personal": "个人级",
    "Enterprise": "企业级",
    "Channel": "频道",
    "Country Code": "国家/地区代码",
    "Noise": "噪声",
    "Tx Rate": "Tx 速率",
    "PHY Mode": "PHY 模式",
    "MCS Index": "MCS 索引",
    "Set up Wi-Fi to wirelessly connect this computer to the internet. Turn on Wi-Fi, then choose a network to join.":
        "设置 Wi-Fi 以将此电脑无线接入互联网。请打开 Wi-Fi，然后选取要加入的网络。",
    "Details…": "详细信息…",
    "No other networks found": "未发现其他网络",
    "Other…": "其他…",
    "Auto-Join": "自动加入",
    "Forget This Network…": "忽略此网络…",
    "Forget": "忽略",
    "Find and join a Wi-Fi network.": "查找并加入 Wi-Fi 网络。",
    "Enter the name of the network and its password, if it has one.": "输入网络名称；如果网络有密码，也一并输入。",
    "The Wi-Fi network “%1” requires a password.": "Wi-Fi 网络“%1”需要密码。",
    "Forget Wi-Fi network “%1”?": "要忽略 Wi-Fi 网络“%1”吗？",
    "This computer will no longer join this network automatically.": "此电脑将不再自动加入此网络。",
    "Network Name": "网络名称",
    "Password (optional)": "密码（可选）",
    "Show password": "显示密码",
    "Connected": "已连接",
    "Connect": "连接",
    "Disconnect": "断开连接",
    "Connecting…": "正在连接…",
    "Cancel": "取消",
    "Proxies": "代理",
    "Hardware": "硬件",
    "Auto-Join": "自动加入",
    "Join this network automatically when it is in range.": "在范围内时自动加入此网络。",
    "Private Wi-Fi Address": "私有 Wi-Fi 地址",
    "Use a different hardware address on this network to reduce tracking.": "在此网络上使用不同的硬件地址以减少跟踪。",
    "System Default": "系统默认",
    "Off": "关闭",
    "Fixed": "固定",
    "Rotating": "轮换",
    "Configure IPv4": "配置 IPv4",
    "Using DHCP": "使用 DHCP",
    "Manually": "手动",
    "Subnet Mask": "子网掩码",
    "DHCP Lease": "DHCP 租期",
    "Expires in %1 h %2 min": "%1 小时 %2 分钟后到期",
    "Renew DHCP Lease": "DHCP 续租",
    "DHCP Client ID (if required)": "DHCP 客户端 ID（如果要求）",
    "DHCP Client ID": "DHCP 客户端 ID",
    "Configure IPv6": "配置 IPv6",
    "Automatically": "自动",
    "Link-Local Only": "仅本地链接",
    "IPv6 Address": "IPv6 地址",
    "DNS Servers": "DNS 服务器",
    "Search Domains": "搜索域",
    "From DHCP": "来自 DHCP",
    "Servers you add replace the ones from DHCP. Remove them all to use DHCP again.": "手动添加的服务器会取代 DHCP 提供的服务器。全部移除后恢复使用 DHCP。",
    "Automatic Proxy Configuration": "自动代理配置",
    "Web Proxy (HTTP)": "网页代理（HTTP）",
    "Secure Web Proxy (HTTPS)": "安全网页代理（HTTPS）",
    "SOCKS Proxy": "SOCKS 代理",
    "Bypass proxy settings for these hosts & domains:": "忽略这些主机与域的代理设置：",
    "Proxies apply to the whole computer, not only this network. Browsers and GTK apps use them; a proxy app may change them again.": "代理设置对整台电脑生效，不只针对此网络。浏览器和 GTK 应用会使用它；代理软件可能会再次改写。",
    "Proxy settings need gsettings (glib2).": "代理设置需要 gsettings（glib2）。",
    "Standard (1500)": "标准（1500）",
    "Custom": "自定",
    "Loading…": "正在载入…",
    "Applying…": "正在应用…",
    "OK": "好",
    "Could not read this network's settings.": "无法读取此网络的设置。",
    "Could not apply the settings.": "无法应用设置。",
    "Could not renew the DHCP lease.": "无法续租 DHCP。",
    "Not Connected": "未连接",
}
# MacShell translates these differently; the macOS 26 wording wins
OVERRIDE = ("Wi-Fi", "Wi-Fi Settings…")

MODEL = """    // Silky WiFi model begin
    // Known / other networks, security level, Auto-Join, forget and link details (SilkyWifi.qml).
    SilkyWifi { id: silkyWifi; bar: root }
    readonly property var wifiModel: silkyWifi
    property string wifiErrorSsid: ""          // network the last join was for: its row shows wifiError
    // Silky WiFi model end
"""


def fail(message):
    raise SystemExit(f"Wi-Fi: {message}")


def swap(source, old, new, what, path):
    if new in source:
        return source
    if source.count(old) != 1:
        fail(f"expected one {what} in {path}")
    return source.replace(old, new, 1)


def between(source, begin, end, fragment, fallback_start, fallback_end, what, path):
    """Replace the marked block (markers included), or the first install's [fallback_start, fallback_end) span."""
    i = source.find(begin)
    if i >= 0:
        i = source.rfind("\n", 0, i) + 1
        j = source.find(end, i)
        if j < 0:
            fail(f"unterminated {what} block in {path}")
        j = source.find("\n", j) + 1
        if fragment.endswith("\n\n") and source[j:j + 1] == "\n":
            j += 1      # the blank line that followed the block is part of the fragment
        return source[:i] + fragment + source[j:]
    if source.count(fallback_start) != 1:
        fail(f"could not find the {what} in {path}")
    i = source.find(fallback_start)
    j = source.find(fallback_end, i)
    if j < 0:
        fail(f"could not find the end of the {what} in {path}")
    return source[:i] + fragment + source[j:]


def transform_bar(source, path="MacBar.qml"):
    if "assets/silky-wifi-scan.py" not in source:
        fail(f"run scripts/install-macshell-wifi.sh first ({path} has no Silky Wi-Fi scan patch)")

    # 1. model object
    if "// Silky WiFi model begin" in source:
        source = between(source, "// Silky WiFi model begin", "// Silky WiFi model end", MODEL, None, None,
                         "Wi-Fi model", path)
    else:
        anchor = '    readonly property string wifiScanError: I18n.tr("Wi-Fi scan did not complete. Try again.")\n'
        source = swap(source, anchor, anchor + MODEL, "wifiScanError property", path)

    # 2. scan results: known networks by SSID, security level, profile UUID / Auto-Join (SilkyWifi.parseScan)
    parse = re.compile(
        r"            var lines = wifiResults\.text\.split\(\"\\n\"\), saved = .*?"
        r"            if \(JSON\.stringify\(arr\) !== JSON\.stringify\(root\.wifiNets\)\) root\.wifiNets = arr;\n", re.S)
    new_parse = ("            var arr = silkyWifi.parseScan(wifiResults.text);     // Silky WiFi\n"
                 "            if (JSON.stringify(arr) !== JSON.stringify(root.wifiNets)) root.wifiNets = arr;\n")
    if new_parse not in source:
        if len(parse.findall(source)) != 1:
            fail(f"could not find the scan parser in {path}")
        source = parse.sub(lambda _m: new_parse, source, count=1)

    # 3. joins remember their network (per-row errors) and can target hidden networks
    source = swap(source,
                  """    function connectWifi(ssid, pw) {
        if (wifiConnProc.running) return;
        wifiError = "";
        wifiBusy = ssid;
        var cmd = ["env", "LC_ALL=C", "nmcli", "--wait", "35", "dev", "wifi", "connect", ssid];
        if (pw && pw !== "") { cmd.push("password"); cmd.push(pw); }
""",
                  """    function connectWifi(ssid, pw, hidden) {
        if (wifiConnProc.running) return;
        wifiError = "";
        wifiBusy = ssid;
        wifiErrorSsid = ssid;
        var cmd = ["env", "LC_ALL=C", "nmcli", "--wait", "35", "dev", "wifi", "connect", ssid];
        if (pw && pw !== "") { cmd.push("password"); cmd.push(pw); }
        if (hidden) { cmd.push("hidden"); cmd.push("yes"); }
""",
                  "connectWifi", path)

    # 4. details flag on each menu bar, set by a right click on the Wi-Fi icon
    flag = '                property bool wifiAdvanced: false   // Silky WiFi: opened with a right click (details)\n'
    # earlier versions: an Alt probe block, or the property alone
    alt = re.compile(r"(?ms)^                // Silky WiFi alt begin\n.*?// Silky WiFi alt end\n")
    source = alt.sub(lambda _m: flag, source, count=1)
    source = re.sub(r"(?m)^                property bool wifiAdvanced: false .*\n", lambda _m: flag, source)
    if flag not in source:
        source = swap(source,
                      '                property string wifiPrompt: ""      // ssid whose password field is open in the Wi-Fi popover\n',
                      '                property string wifiPrompt: ""      // ssid whose password field is open in the Wi-Fi popover\n' + flag,
                      "wifiPrompt property", path)
    # right click opens the details view (macOS Option-click). Alt + click is not offered: Wayland pointer events carry
    # no modifiers and the menu bar never has keyboard focus, so MacShell cannot see Alt.
    button = ('MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton; '
              'onClicked: mouse => { ui.wifiAdvanced = mouse.button === Qt.RightButton; '
              'ui.openPop("wifi", wifiBtn.mapToItem(ui, 0, 0).x); } }')
    old_button = re.compile(r'MouseArea \{ anchors\.fill: parent;[^\n]*?ui\.openPop\("wifi", wifiBtn\.mapToItem\(ui, 0, 0\)\.x\);?[^\n]*?\}( \})?')
    if button not in source:
        if len(old_button.findall(source)) != 1:
            fail(f"could not find the menu-bar Wi-Fi button in {path}")
        source = old_button.sub(lambda _m: button, source, count=1)

    # 5. the list itself
    fragment = (ASSETS / "wifi-list.qml.in").read_text()
    source = between(source, "// Silky WiFi list begin", "// Silky WiFi list end", fragment,
                     "                    Column {\n                        id: wifiCol\n",
                     "                }\n\n                // ═════════ Wi-Fi networks ═════════", "Wi-Fi list", path)
    return source


def transform_dock(source, path="MacDock.qml"):
    if "component SBtSpinner" not in source:
        fail(f"run scripts/tune-bluetooth.py first ({path} has no SBtSpinner)")
    components = (ASSETS / "settings-components.qml.in").read_text().rstrip("\n") + "\n\n"
    anchor = "    // Light / Dark appearance thumbnail\n"
    if "// Silky WiFi components begin" in source:
        source = between(source, "// Silky WiFi components begin", "// Silky WiFi components end", components, None, None,
                         "Wi-Fi components", path)
    elif source.count(anchor) == 1:
        source = source.replace(anchor, components + anchor, 1)
    else:
        fail(f"could not find where to add the Wi-Fi components in {path}")
    fragment = (ASSETS / "settings-pane.qml.in").read_text().rstrip("\n") + "\n\n"
    include = "                // @include network-details.qml.in\n"
    if fragment.count(include) != 1:
        fail("settings-pane.qml.in has no network-details include")
    fragment = fragment.replace(include, (ASSETS / "network-details.qml.in").read_text())
    if "// Silky WiFi pane begin" in source:
        return between(source, "// Silky WiFi pane begin", "// Silky WiFi pane end", fragment, None, None,
                       "Wi-Fi pane", path)
    start = "        // ── Wi-Fi ──\n"
    if source.count(start) != 1:
        fail(f"could not find the Wi-Fi pane in {path}")
    i = source.find(start)
    ends = [j for j in (source.find("        // Silky Bluetooth pane begin", i), source.find("        // ── Bluetooth ──", i))
            if j > i]
    if not ends:
        fail(f"could not find the end of the Wi-Fi pane in {path}")
    return source[:i] + fragment + source[min(ends):]


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
            if key in OVERRIDE and existing.group(0) != line:
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
        shell / "SilkyWifi.qml": (ASSETS / "SilkyWifi.qml").read_text(),
        shell / "assets/silky-wifi-info.py": (ASSETS / "silky-wifi-info.py").read_text(),
        shell / "assets/silky-wifi-conn.py": (ASSETS / "silky-wifi-conn.py").read_text(),
        shell / "assets/silky-wifi-scan.py": (REPO / "config/macshell/silky-wifi-scan.py").read_text(),
    }
    if lang.is_file():
        outputs[lang] = transform_translations(lang.read_text())
    changed = []
    for path, content in outputs.items():
        if not path.is_file() or path.read_text() != content:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
            changed.append(str(path.relative_to(shell)))
    for helper in ("silky-wifi-info.py", "silky-wifi-conn.py"):
        (shell / "assets" / helper).chmod(0o755)
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
            print(f"Wi-Fi preflight OK ({len(pending)} file(s) would change).")
            return
        if not pending:
            print("Wi-Fi already up to date.")
            return
        stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        backup = pathlib.Path.home() / ".local/state/silky-omarchy" / f"wifi-backup-{stamp}"
        copy_tree(target, backup)
        changed = apply_to_dir(target)
        subprocess.run(["qs", "-c", "MacShell", "ipc", "call", "macshell", "reload"], check=False)
        print(f"Installed ({', '.join(changed)}). Backup: {backup}")
        return

    apply_to_dir(target)


if __name__ == "__main__":
    main()
