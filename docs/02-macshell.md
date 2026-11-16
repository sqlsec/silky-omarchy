# 02 · MacShell 汉化、实时玻璃与 GPU 优化

## 目标

- 为 MacShell 0.5.1 增加简体中文，并补齐菜单、设置和系统操作中的遗漏文本
- 将“关于本机”调整为接近 macOS 的紧凑布局，正确识别 Snapdragon X Elite、Adreno X1-85、内存频率和 Omarchy 完整版本号
- 优化触控屏命中区域、滑动和滚动体验
- 使用真实窗口内容生成实时玻璃，而不是用壁纸或纯色伪装
- 将模糊、折射与合成交给 Vulkan，同时避免无意义的全屏持续捕获
- 使用 Yoga Slim 7 14Q8X9 内屏的原生 90 Hz 模式

## 实现方式

补丁基于官方 [0-ss/MacShell 0.5.1](https://github.com/0-ss/MacShell/tree/0.5.1)，只包含相对上游发生变化的文件：

- `I18n.js` 与 `lang/zh-CN.js`：中文语言注册与完整翻译
- `AboutApp.qml`、`assets/about-info.sh`：关于页布局及硬件识别
- `MacBar.qml`：菜单、控制中心的触控与按需实时捕获
- `MacDock.qml`：Dock 触控与仅捕获相交窗口
- `shell.qml`：识别 Omarchy 当前壁纸，并降低窗口几何轮询开销

实时玻璃仍需要 CPU 完成 Wayland 窗口枚举和捕获调度，无法做到 100% 零 CPU；实际的 Qt Quick 场景图、模糊、折射和合成通过 Vulkan 在 GPU 上执行。GPU 保持 `simple_ondemand` 动态升频，不强制锁定最高频率。

## 安装

先安装 MacShell 0.5.1，再从本仓库执行：

```bash
./scripts/install-macshell-optimizations.sh --check
./scripts/install-macshell-optimizations.sh
```

脚本会先验证补丁能否干净应用，然后将原文件备份到：

```text
~/.local/state/macshell/silky-backup-YYYYMMDD-HHMMSS/
```

完成后，从 MacShell 设置的“工具”页面重新启动 MacShell。

### 90 Hz 内屏

本机专用显示器配置位于 [`config/hypr/monitor-yoga-slim-7-14q8x9.lua`](../config/hypr/monitor-yoga-slim-7-14q8x9.lua)。将它加入 `~/.config/hypr/monitors.lua`，然后运行：

```bash
hyprctl reload
hyprctl configerrors
hyprctl monitors
```

只有面板确实是 `eDP-1` 且支持 `2944x1840@90` 时才应使用该片段。

## 默认玻璃参数

安装脚本会合并以下值，不会覆盖 Dock 图标、组件排序等其他个人设置：

```json
{
  "glassOpacity": 0.38,
  "glassBlur": 24,
  "glassRealtime": true,
  "glassLive": true
}
```

菜单和控制中心只在可见时捕获，而且只捕获与玻璃区域相交的窗口；Dock 同样只处理其附近窗口。窗口静止或玻璃关闭后，几何轮询会自动降频。

## 验证

```bash
tr '\0' '\n' < /proc/$(pgrep -n -f '^qs -c MacShell$')/environ \
  | grep '^QSG_'

grep -E 'screencopy failure|shader status: 2' \
  /run/user/$(id -u)/quickshell/by-id/*/log.log
```

预期环境包含：

```text
QSG_RHI_BACKEND=vulkan
QSG_RENDER_LOOP=threaded
```

玻璃展开时 Adreno 会按需升频；关闭菜单后捕获停止。日志中不应出现 `screencopy failure` 或着色器状态 `2`。

## 回滚

退出 MacShell，将最近一次 `silky-backup-*` 中的文件复制回原位置，并恢复：

- `~/.config/quickshell/MacShell/`
- `~/.config/macbar/settings.json`
- `~/.config/macdock/settings.json`
- `~/.config/macshell/env`

随后重新启动 MacShell。也可以重新安装官方 MacShell 0.5.1 来恢复所有 QML 文件。
