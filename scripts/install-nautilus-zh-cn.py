#!/usr/bin/env python3
"""Install Simplified Chinese UI overrides for Nautilus on Omarchy."""

import os
import re
import shutil
import subprocess
from datetime import datetime
from pathlib import Path
from urllib.parse import unquote, urlsplit


HOME = Path.home()
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME") or HOME / ".config")
DATA = Path(os.environ.get("XDG_DATA_HOME") or HOME / ".local/share")
APP_ID = "org.gnome.Nautilus"
LAUNCH = (
    "/usr/bin/env -u LC_ALL LC_MESSAGES=zh_CN.UTF-8 "
    "LC_TIME=zh_CN.UTF-8 LANGUAGE=zh_CN /usr/bin/nautilus"
)
BACKUP_SUFFIX = ".bak." + datetime.now().strftime("%Y%m%d%H%M%S%f")


def update(path, content):
    if path.exists():
        if path.read_text() == content:
            return
        backup = path.with_name(path.name + BACKUP_SUFFIX)
        shutil.copy2(path, backup)
        print(f"备份 {backup}")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)
    print(f"更新 {path}")


def localize_bookmarks(path):
    if not path.is_file():
        return
    translations = {
        "Downloads": "下载",
        "Documents": "文档",
        "Projects": "项目",
        "Music": "音乐",
        "Pictures": "图片",
        "Videos": "视频",
        "Desktop": "桌面",
    }
    lines = []
    for line in path.read_text().splitlines(keepends=True):
        uri, _, label = line.rstrip("\n").partition(" ")
        location = urlsplit(uri)
        folder = Path(unquote(location.path))
        if (
            location.scheme == "file"
            and not location.netloc
            and folder.parent == HOME
            and folder.name in translations
            and label in ("", folder.name)
        ):
            line = f"{uri} {translations[folder.name]}" + ("\n" if line.endswith("\n") else "")
        lines.append(line)
    update(path, "".join(lines))


def localize_extensions():
    extensions = DATA / "nautilus-python/extensions"
    labels = {
        "localsend.py": {
            '"Send via LocalSend"': '"通过 LocalSend 发送"',
            '"Send selected via LocalSend"': '"通过 LocalSend 发送所选项目"',
        },
        "transcode.py": {
            '"Transcode"': '"转码"',
            'f"Transcode {len(paths)} items"': 'f"转码 {len(paths)} 个项目"',
        },
    }
    for filename, translations in labels.items():
        path = extensions / filename
        if not path.is_file():
            continue
        content = path.read_text()
        for english, chinese in translations.items():
            content = content.replace(english, chinese)
        compile(content, str(path), "exec")
        update(path, content)


def main():
    locales = subprocess.check_output(["locale", "-a"], text=True).splitlines()
    if not any(name.lower().replace("-", "") == "zh_cn.utf8" for name in locales):
        raise SystemExit("请先生成 zh_CN.UTF-8 locale，再运行此脚本。")
    stock_desktop = Path(f"/usr/share/applications/{APP_ID}.desktop")
    catalog = Path("/usr/share/locale/zh_CN/LC_MESSAGES/nautilus.mo")
    if not (stock_desktop.is_file() and catalog.is_file() and os.access("/usr/bin/nautilus", os.X_OK)):
        raise SystemExit("需要安装带简体中文翻译的 Nautilus。")

    desktop = DATA / "applications" / stock_desktop.name
    content = (desktop if desktop.is_file() else stock_desktop).read_text()
    content = re.sub(r"(?m)^(Name(?:\[en(?:_[^\]]+)?\])?=)Files$", r"\g<1>文件", content)
    content = re.sub(r"(?m)^(Name(?:\[en(?:_[^\]]+)?\])?=)New Window$", r"\g<1>新建窗口", content)
    content = re.sub(r"(?m)^Exec=(?:/usr/bin/)?nautilus(?= |$)", f"Exec={LAUNCH}", content)
    update(desktop, content)

    service = DATA / "dbus-1/services" / f"{APP_ID}.service"
    update(service, f"[D-BUS Service]\nName={APP_ID}\nExec={LAUNCH} --gapplication-service\n")

    bindings = CONFIG / "hypr/bindings.lua"
    if bindings.is_file():
        start = "-- >>> Silky Nautilus zh_CN >>>"
        end = "-- <<< Silky Nautilus zh_CN <<<"
        command = f"setsid uwsm-app -- {LAUNCH} --new-window"
        block = (
            f'{start}\n'
            f'o.rebind("SUPER + SHIFT + F", "文件管理器", [[{command}]])\n'
            f'o.rebind("SUPER + ALT + SHIFT + F", "在当前目录打开文件管理器", '
            f'[[{command} "$(omarchy-cmd-terminal-cwd)"]])\n'
            f'{end}\n'
        )
        content = bindings.read_text()
        pattern = re.escape(start) + r"[^\n]*\n.*?" + re.escape(end) + r"[^\n]*\n?"
        if re.search(pattern, content, re.DOTALL):
            content = re.sub(pattern, lambda _: block, content, flags=re.DOTALL)
        else:
            content = content.rstrip("\n") + "\n\n" + block
        update(bindings, content)

    for version in ("gtk-3.0", "gtk-4.0"):
        localize_bookmarks(CONFIG / version / "bookmarks")
    localize_extensions()
    print("安装完成。关闭文件管理器窗口后执行 nautilus --quit，再从应用菜单或快捷键打开。")


if __name__ == "__main__":
    main()
