# Silky Omarchy

一套受 macOS 启发的 [Omarchy](https://omarchy.org/) Linux 体验优化。每一项都记录了设计思路、配置、验证方法和回滚方式，并提供一键安装脚本。

> 想让 AI 编程助手帮你复现？把 [docs/00-ai-reproduction.md](docs/00-ai-reproduction.md) 交给它：里面按模块列出了效果、关键文件、检索关键词、踩过的坑和验证命令。

## 优化一览

| # | 模块 | 状态 | 内容 |
| --- | --- | --- | --- |
| 01 | 触控板 | ✅ | 自然滚动（触控板和鼠标）、三指拖移、四指横滑切换工作区 |
| 02 | MacShell | ✅ | 简体中文、紧凑的“关于本机”、触控屏拖窗、Vulkan 实时玻璃、消除鼠标卡顿、锁屏壁纸、开机自启修复、电池去 `%`、桌面无图标、截图不重复不发通知 |
| 03 | 触控屏手势 | ✅ | 到头回弹、触控屏三指滑动与边缘单指滑动、触控拖动/缩放浮动窗口（Hyprland 插件） |
| 04 | macOS Tahoe 主题 | ✅ | 深色 / 浅色主题、Apple 系统色、圆角阴影玻璃、MacTahoe 蓝色文件夹图标、Finder 风格 Nautilus、主题联动、浮动窗口圆形红绿灯 |
| 05 | 语音浮条 | ✅ | WowType 语音输入的毛玻璃声波浮条；修复与 Superwhisper 抢右 Alt |
| 06 | 终端 | ✅ | zsh + Oh My Zsh（ys）、历史建议、语法高亮、增强补全，保持快速启动 |
| 07 | 锁屏与开机界面 | 🧪 开机界面待重启验证 | 快捷键、菜单、闲置、合盖都改用 MacLock；开机磁盘解锁界面做成 macOS FileVault 风格 |
| 09 | 候选框毛玻璃 | 🧪 微信内待重启验证 | WowType 候选框圆角毛玻璃皮肤，跟随深色/浅色自动切换；修复微信里候选条重影 |
| 10 | 快捷键 | ✅ | MacShell 与 Omarchy 冲突的键只留 MacShell，Omarchy 的动作挪到空闲键；Super+K 换成可搜索、可直接执行的 macOS 27 风格快捷键面板 |

## 快速开始

前提：Omarchy 4.x（Hyprland 0.57，Lua 配置），并已安装 MacShell 0.5.1。按需运行：

```bash
./scripts/install-macshell-optimizations.sh
./scripts/install-silky-gestures.sh
./scripts/install-macos-theme.sh && omarchy theme set macos-tahoe-dark
./scripts/install-voice-overlay.sh
./scripts/install-zsh.sh
./scripts/install-maclock.sh
./scripts/install-boot-screen.sh
./scripts/install-wowtype-glass.sh
./scripts/install-shortcuts.sh
```

每个脚本都会先备份要修改的文件。装完或升级后可以跑一遍自检，逐项确认菜单栏、Dock、插件、锁屏、语音浮条等都处于预期状态，有问题会给出修复命令：

```bash
./scripts/silky-doctor.sh
```

01 触控板是手动合并的配置片段，见文档。

## 仓库结构

```text
config/hypr/      Hyprland Lua 配置片段（触控板、动画、显示器、截图键、插件加载、语音浮条、快捷键）
config/macshell/  MacShell 玻璃参数与 GPU 环境变量
config/zsh/       ~/.zshrc
patches/          MacShell 0.5.1 + MacLock 的补丁
plugins/          Hyprland C++ 插件 silky-gestures
themes/           Omarchy 主题 macos-tahoe-dark / macos-tahoe-light
hooks/            Omarchy theme-set 钩子
bin/              silky-lock、silky-sleep-lock（MacLock 锁屏入口）
config/omarchy/   Omarchy shell 插件 silky.idle 与菜单覆盖
config/systemd/   用户服务 silky-sleep-lock、silky-ime-theme
plymouth/         开机解锁界面主题与预览图
voice-overlay/    WowType 语音浮条（Quickshell + D-Bus 桥）
keys-panel/       Super+K 快捷键面板 Silky Keys（Quickshell）
wowtype-glass/    WowType 候选框 Silky Glass 皮肤生成器与深浅色切换脚本
scripts/          安装脚本
docs/             逐项说明
```

## 配置原则

- 只修改用户配置（`~/.config`、`~/.local`），不直接修改 `/usr/share/omarchy/`
- 每项优化都提供配置、验证步骤与回滚说明，修改前自动备份
- 第三方依赖固定到具体 commit，结果可复现
- 优先使用 Omarchy 和 Hyprland 的原生能力，减少额外守护进程

## 文档

- [00 · 给 AI 编程助手的复现索引](docs/00-ai-reproduction.md)
- [01 · 触控板手势](docs/01-touchpad-gestures.md)
- [02 · MacShell 汉化、实时玻璃与 GPU 优化](docs/02-macshell.md)
- [03 · 触控屏工作区手势与到头回弹](docs/03-silky-gestures.md)
- [04 · macOS Tahoe 主题（深色 / 浅色）](docs/04-macos-theme.md)
- [05 · WowType 语音输入的声波浮条](docs/05-voice-overlay.md)
- [06 · 终端：zsh + Oh My Zsh](docs/06-terminal.md)
- [07 · 统一 MacLock 锁屏与 macOS 风格开机界面](docs/07-lock-and-boot.md)
- [09 · WowType 候选框：圆角毛玻璃与微信重影修复](docs/09-wowtype-glass.md)
- [10 · 快捷键：MacShell 优先，Super+K 可搜索面板](docs/10-shortcuts.md)
