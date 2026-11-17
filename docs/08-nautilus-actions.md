# 文件管理器右键菜单

运行 `./scripts/install-nautilus-actions.sh`，然后关闭所有文件窗口并执行 `nautilus -q`，重新打开文件管理器。脚本将扩展安装到 `~/.local/share/nautilus-python/extensions/`，更新时备份已有的不同版本；需要 `nautilus-python` 和 `xdg-terminal-exec`。

- 右键本地文件或文件夹可选择「复制路径」；多选时每行一个路径。
- 右键本地文件夹或文件列表空白处可选择「在终端打开」。终端使用系统默认设置。
- 右键文件或文件夹选择 Nautilus 自带的「压缩…」；右键受支持的压缩包选择「解压到此处」或「解压到…」。可用格式取决于系统的归档支持。
- 远程位置没有本地路径，因此不会显示这两个扩展菜单。

卸载时删除 `~/.local/share/nautilus-python/extensions/silky_actions.py`，退出并重新打开 Nautilus。
