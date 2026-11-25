#!/usr/bin/env python3
"""Install the Silky Network pane (macOS status dots, Wi-Fi navigation, VPN toggles) into MacShell."""
import json
import os
import pathlib
import re
import sys

assets = pathlib.Path(__file__).resolve().parents[1] / "config/macshell/network"
shell = pathlib.Path(sys.argv[1])
dock = shell / "MacDock.qml"
language = shell / "lang/zh-CN.js"

source = dock.read_text()
pane = (assets / "NetworkPane.qml.inc").read_text().rstrip() + "\n\n"
pane_pattern = r"(?ms)^        // ── Network ──\n        Component \{\n            id: paneNetwork\b.*?(?=^        // ── Battery ──)"
source, pane_count = re.subn(pane_pattern, lambda _: pane, source)
if pane_count != 1:
    raise SystemExit("Network settings: could not find the Network pane")

strings = {
    "Off": "关闭",
    "Cable unplugged": "网线未连接",
    "Connecting…": "正在连接…",
    "Disconnecting…": "正在断开…",
    "Managed by app": "由应用管理",
    "Could not connect VPN": "无法连接 VPN",
    "Could not disconnect VPN": "无法断开 VPN",
    " Mb/s": " Mb/s",
}

translations = language.read_text()
anchor = "var strings = {\n"
if translations.count(anchor) != 1:
    raise SystemExit("Network settings: could not find the Chinese translation dictionary")

additions = []
for key, value in strings.items():
    quoted_key = json.dumps(key, ensure_ascii=False)
    if not re.search(r"(?m)^\s*" + re.escape(quoted_key) + r"\s*:", translations):
        additions.append(f"    {quoted_key}: {json.dumps(value, ensure_ascii=False)},\n")

helper_dest = shell / "assets/silky-network.py"
helper_dest.parent.mkdir(parents=True, exist_ok=True)
helper_dest.write_bytes((assets / "silky-network.py").read_bytes())
os.chmod(helper_dest, 0o755)

if additions:
    language.write_text(translations.replace(anchor, anchor + "".join(additions), 1))
dock.write_text(source)
