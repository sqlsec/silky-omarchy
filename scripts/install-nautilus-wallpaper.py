#!/usr/bin/env python3
"""Install the user-session Wallpaper portal backend for Omarchy."""

import os
import re
import shlex
import shutil
import subprocess
from datetime import datetime
from pathlib import Path


HOME = Path.home()
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME") or HOME / ".config")
DATA = Path(os.environ.get("XDG_DATA_HOME") or HOME / ".local/share")
SOURCE = Path(__file__).resolve().parents[1] / "nautilus/wallpaper_portal.py"
PORTAL_ID = "org.freedesktop.impl.portal.desktop.silky_wallpaper"
WALLPAPER = "org.freedesktop.impl.portal.Wallpaper"
UNIT = "silky-wallpaper-portal.service"
BACKUP_SUFFIX = ".bak." + datetime.now().strftime("%Y%m%d%H%M%S%f")


def install(path, content):
    if path.is_file():
        if path.read_text() == content:
            return
        backup = path.with_name(path.name + BACKUP_SUFFIX)
        shutil.copy2(path, backup)
        print(f"备份 {backup}")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)
    print(f"更新 {path}")


def configure_backend(content):
    lines = content.splitlines(keepends=True)
    preferred = next((i for i, line in enumerate(lines) if line.strip() == "[preferred]"), None)
    if preferred is None:
        raise SystemExit("Hyprland 的 Portal 配置缺少 [preferred] 段，请检查配置文件。")
    setting = f"{WALLPAPER}=silky-wallpaper\n"
    key = re.compile(r"^\s*" + re.escape(WALLPAPER) + r"\s*=")
    for index in range(preferred + 1, len(lines)):
        if lines[index].lstrip().startswith("["):
            break
        if key.match(lines[index]):
            lines[index] = setting
            return "".join(lines)
    lines[preferred] = lines[preferred].rstrip("\n") + "\n"
    lines.insert(preferred + 1, setting)
    return "".join(lines)


def main():
    if not shutil.which("omarchy") or not shutil.which("systemctl"):
        raise SystemExit("需要 Omarchy 和 systemd 用户会话。")
    try:
        subprocess.run(
            ["/usr/bin/python3", "-c", "import runpy, sys; runpy.run_path(sys.argv[1])", str(SOURCE)],
            check=True,
        )
    except subprocess.CalledProcessError as error:
        raise SystemExit("请确认已安装 Python GObject 和 GTK 4。") from error
    if not Path(f"/usr/share/dbus-1/interfaces/{WALLPAPER}.xml").is_file():
        raise SystemExit("需要安装带 Wallpaper 接口定义的 xdg-desktop-portal。")

    portal_conf = CONFIG / "xdg-desktop-portal/hyprland-portals.conf"
    stock = Path("/usr/share/xdg-desktop-portal/hyprland-portals.conf")
    fallback = CONFIG / "xdg-desktop-portal/portals.conf"
    source_conf = next((path for path in (portal_conf, fallback, stock) if path.is_file()), None)
    if source_conf is None:
        raise SystemExit("找不到 Hyprland 的 Portal 配置，请检查 xdg-desktop-portal-hyprland。")
    configuration = configure_backend(source_conf.read_text())

    backend = DATA / "silky-omarchy/wallpaper_portal.py"
    escaped = str(backend).replace("\\", "\\\\").replace('"', '\\"').replace("%", "%%").replace("$", "$$")
    install(backend, SOURCE.read_text())
    install(
        CONFIG / "systemd/user" / UNIT,
        f"[Unit]\nDescription=Silky Omarchy Wallpaper Portal\nPartOf=graphical-session.target\n\n"
        f"[Service]\nType=dbus\nBusName={PORTAL_ID}\nExecStart=/usr/bin/python3 \"{escaped}\"\n",
    )
    install(
        DATA / "dbus-1/services" / f"{PORTAL_ID}.service",
        "[D-BUS Service]\n"
        f"Name={PORTAL_ID}\nExec=/usr/bin/python3 {shlex.quote(str(backend))}\nSystemdService={UNIT}\n",
    )
    install(
        DATA / "xdg-desktop-portal/portals/silky-wallpaper.portal",
        f"[portal]\nDBusName={PORTAL_ID}\nInterfaces={WALLPAPER};\n",
    )
    install(portal_conf, configuration)
    subprocess.run(["systemctl", "--user", "daemon-reload"], check=True)
    subprocess.run(
        ["gdbus", "call", "--session", "--dest", "org.freedesktop.DBus", "--object-path",
         "/org/freedesktop/DBus", "--method", "org.freedesktop.DBus.ReloadConfig"],
        check=True,
    )
    subprocess.run(["systemctl", "--user", "try-restart", UNIT], check=True)
    subprocess.run(["systemctl", "--user", "restart", "xdg-desktop-portal.service"], check=True)
    print("安装完成。在文件管理器中右键单张图片，选择「设置为背景…」。")


if __name__ == "__main__":
    main()
