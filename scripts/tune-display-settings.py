#!/usr/bin/env python3
"""Install the Silky Displays pane into a MacShell configuration."""
import json
import pathlib
import re
import sys

assets = pathlib.Path(__file__).resolve().parents[1] / "config/macshell/displays"
shell = pathlib.Path(sys.argv[1])
dock = shell / "MacDock.qml"
language = shell / "lang/zh-CN.js"

source = dock.read_text()
pane = (assets / "DisplaysPane.qml.inc").read_text().rstrip() + "\n\n"
pane_pattern = r"(?ms)^        // ── Displays ──\n        Component \{\n            id: paneDisplays\b.*?(?=^        // ── Notifications ──)"
source, pane_count = re.subn(pane_pattern, lambda _: pane, source)
if pane_count != 1:
    raise SystemExit("Display settings: could not find the Displays pane")

if "SilkyDisplaySettings { id: displaySettings }" not in source:
    logic_pattern = r"(?ms)^    // ═════ Displays:.*?(?=^    Process \{\n        running: true\n        command: \[\"sh\", \"-c\", \"n=\$\(getent)"
    source, logic_count = re.subn(
        logic_pattern, "    SilkyDisplaySettings { id: displaySettings }\n\n", source,
    )
    if logic_count != 1:
        raise SystemExit("Display settings: could not find the monitor controller")
    source = source.replace(
        'import "Fonts.js" as Fonts\n',
        'import "Fonts.js" as Fonts\nimport "DisplayModes.js" as DisplayModes\n',
        1,
    )
    if 'import "DisplayModes.js" as DisplayModes' not in source:
        raise SystemExit("Display settings: could not add the display helper import")

strings = {
    "Built-in display": "内建显示器",
    "External display": "外接显示器",
    "No displays detected.": "未检测到显示器",
    "Arrange…": "排列…",
    "Arrange displays": "排列显示器",
    "Drag the screens to match where they sit on your desk.": "拖动屏幕，让排列与桌面上的实际摆放一致。",
    "Apply": "应用",
    "The connected displays changed. Open Arrange again.": "已连接的显示器发生变化，请重新打开排列。",
    "Keep these display settings?": "保留这些显示设置？",
    "Reverting in %1 s": "%1 秒后自动还原",
    "Scale": "缩放",
    "Larger text": "更大字体",
    "More space": "更多空间",
    "Looks like %1": "等效工作区 %1",
    "Set as main display": "设为主显示器",
    "The Dock is shown on this display.": "程序坞显示在此屏幕上。",
    "Mirrored display": "镜像显示器",
    "This setting would overlap another display.": "此设置会使显示器布局发生重叠。",
    "The display could not apply these settings.": "无法应用这些显示设置。",
    "Could not restore the previous display settings.": "无法恢复之前的显示设置。",
    "Could not restore the saved display settings.": "无法恢复已保存的显示设置。",
    "Could not save display settings.": "无法保存显示设置。",
}

translations = language.read_text()
anchor = "var strings = {\n"
if translations.count(anchor) != 1:
    raise SystemExit("Display settings: could not find the Chinese translation dictionary")

additions = []
for key, value in strings.items():
    quoted_key = json.dumps(key, ensure_ascii=False)
    if not re.search(r"(?m)^\s*" + re.escape(quoted_key) + r"\s*:", translations):
        additions.append(f"    {quoted_key}: {json.dumps(value, ensure_ascii=False)},\n")

for suffix in ("*.qml", "*.js"):
    for asset in assets.glob(suffix):
        (shell / asset.name).write_bytes(asset.read_bytes())
language.write_text(translations.replace(anchor, anchor + "".join(additions), 1))
dock.write_text(source)
