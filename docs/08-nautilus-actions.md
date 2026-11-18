# 08 · 文件管理器右键菜单

简体中文 | [English](en/08-nautilus-actions.md)

运行 `./scripts/install-nautilus-actions.sh`，然后关闭所有文件窗口并执行 `nautilus -q`，重新打开文件管理器。脚本将扩展安装到 `~/.local/share/nautilus-python/extensions/`，更新时备份已有的不同版本；需要 `nautilus-python` 和 `xdg-terminal-exec`。

- 右键本地文件或文件夹可选择「复制路径」；多选时每行一个路径。
- 右键本地文件夹或文件列表空白处可选择「在终端打开」。终端使用系统默认设置。
- 右键文件或文件夹选择 Nautilus 自带的「压缩…」；右键受支持的压缩包选择「解压到此处」或「解压到…」。可用格式取决于系统的归档支持。
- 远程位置没有本地路径，因此不会显示这两个扩展菜单。

卸载时删除 `~/.local/share/nautilus-python/extensions/silky_actions.py`，退出并重新打开 Nautilus。

## 简体中文界面

在仓库根目录运行以下命令。需要 Python 3、带简体中文翻译的 Nautilus，以及已生成的 `zh_CN.UTF-8` locale（可用 `locale -a` 检查）。这一配置使用 Nautilus 自带的菜单和日期翻译，并将常用侧栏书签和已安装的 LocalSend、转码菜单项改成中文。书签仍指向原路径。目录名、脚本文件名和卷标按原名显示。

```bash
./scripts/install-nautilus-zh-cn.py
nautilus --quit
```

通过应用菜单的「文件」或 `Super+Shift+F` 重新打开，检查侧栏和右键菜单。也可以在终端按 `Super+Alt+Shift+F` 检查当前目录入口。仅 Nautilus 的启动入口使用中文 locale，从终端直接运行 `nautilus` 启动新进程时会沿用该终端的语言。

[安装脚本](../scripts/install-nautilus-zh-cn.py) 写入用户级 `applications/org.gnome.Nautilus.desktop` 和 `dbus-1/services/org.gnome.Nautilus.service`，并更新 `~/.config/hypr/bindings.lua` 和现有 GTK 书签。运行中的 D-Bus 若尚未识别服务覆盖，可以用 `gdbus call --session --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus --method org.freedesktop.DBus.ReloadConfig` 刷新。

回滚时，按脚本打印的 `.bak.*` 路径恢复原文件。若原先没有用户级 Nautilus 的 `.desktop` 或 `.service` 文件，移除本次生成的覆盖文件即可。然后运行 `hyprctl reload`、刷新 D-Bus，退出并重新打开 Nautilus。
