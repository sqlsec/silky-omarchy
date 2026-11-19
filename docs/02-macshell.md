# 02 · MacShell 汉化、实时玻璃与 GPU 优化

简体中文 | [English](en/02-macshell.md)

## 目标

- 为 MacShell 增加简体中文，并补齐菜单、设置和系统操作中的遗漏文本
- 将“关于本机”调整为接近 macOS 的紧凑布局，正确识别 Snapdragon X Elite、Adreno X1-85、内存频率和 Omarchy 完整版本号
- 优化触控屏命中区域、滑动和滚动体验
- 使用真实窗口内容生成实时玻璃，而不是用壁纸或纯色伪装
- 将模糊、折射与合成交给 Vulkan，同时避免无意义的全屏持续捕获
- 使用 Yoga Slim 7 14Q8X9 内屏的原生 90 Hz 模式

## 实现方式

补丁分别针对 MacShell 0.5.1 和 0.5.2，只包含相对上游发生变化的文件：

- `I18n.js` 与 `lang/zh-CN.js`：中文语言注册与完整翻译
- `AboutApp.qml`、`assets/about-info.sh`：关于页布局及硬件识别
- `MacBar.qml`：菜单、控制中心的触控与按需实时捕获；自动对比度改为事件驱动，不再定时截屏
- `MacDock.qml`：Dock 触控、仅捕获相交窗口，并且只为已最小化窗口显示缩略图
- `TouchWindowMove.qml`（新增）及 `AboutApp.qml`、`MacDock.qml`、`ClockApp.qml`、`Installer.qml`：用手指拖动“关于本机”、设置、时钟和安装器窗口
- `shell.qml`：识别 Omarchy 当前壁纸，并降低窗口几何轮询开销
- `MacLock/shell.qml`：锁屏同样读取 Omarchy 当前壁纸（图片或视频）
- `MacBar.qml`：新增 `appearance` IPC，供 macOS Tahoe 主题切换深浅色；电池图标去掉 `%` 并缩窄
- `macshell.lua`：不再绑定 `PRINT`，避免与 Omarchy 截图冲突

实时玻璃仍需要 CPU 完成 Wayland 窗口枚举和捕获调度，无法做到 100% 零 CPU；实际的 Qt Quick 场景图、模糊、折射和合成通过 Vulkan 在 GPU 上执行。GPU 保持 `simple_ondemand` 动态升频，不强制锁定最高频率。

## 版本

本仓库最初基于 MacShell 0.5.1 开发，本机现在运行的是 **MacShell 0.5.2**（Omarchy 4.5.0、Hyprland 0.57.2、Quickshell 0.3.2），0.5.1 补丁里的所有改动都已带到这台机器的 0.5.2 上。各部分对版本的支持：

| 内容 | 0.5.1 | 已带 Silky 改动的 0.5.2 | 全新的 0.5.2 |
| --- | --- | --- | --- |
| `install-macshell-optimizations.sh`（汉化、触控、实时玻璃等完整补丁） | 支持 | 支持（只更新各项调整，不再打补丁） | 支持（使用 0.5.2 专用补丁） |
| `tune-*.py`、`configure-macshell-reload.py` | 支持 | 支持 | 作为安装流程的一部分验证 |
| `install-macshell-status.py`（顶栏监控） | 支持 | 支持 | 支持 |
| `install-macshell-overview.py`（[13 窗口总览](13-window-overview.md)） | 未验证 | 支持 | 未验证 |

0.5.2 补丁基于上游标签 `0.5.2`（提交 `5d17abadd5de192919416990ad2ecf7f31b38b51`）。现有上游 0.5.1 标签与旧补丁基线不同，全新安装建议使用 0.5.2。`--check` 会在临时目录试跑补丁和全部调优步骤。

## 安装

先安装 MacShell 0.5.2，再从本仓库执行：

```bash
./scripts/install-macshell-optimizations.sh --check
./scripts/install-macshell-optimizations.sh
```

脚本会先验证补丁能否干净应用，然后将原文件备份到：

```text
~/.local/state/macshell/silky-backup-YYYYMMDD-HHMMSS/
```

完成后，从 MacShell 设置的“工具”页面重新启动 MacShell。

Dock 的「智能」隐藏模式只在当前屏幕的可见窗口与 Dock 重叠时收起，浮动窗口和平铺窗口都适用。窗口移开后 Dock 会自动恢复；收起时，把鼠标移到屏幕底边可以临时唤出。

安装 Silky 快捷键后，MacShell「显示」和「窗口」菜单的浮动／平铺操作与 `Super+T` 一致，窗口留在同一工作区参与分屏。([10 · Super+T](10-shortcuts.md#supert))

### 应用 QML 更新

顶栏和 Dock 共用一个 Quickshell 实例，保存顶栏代码时，自动重载会连带重建 Dock。0.5.1 的 Silky 优化脚本会关闭 QML 文件监听。对正在运行的 0.5.2，可单独应用这项设置：

```bash
python3 scripts/configure-macshell-reload.py "${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/MacShell/shell.qml"
```

之后，完成一组文件修改或安装顶栏系统监控后，运行一次：

```bash
qs ipc -c MacShell call macshell reload
```

### 90 Hz 内屏

本机专用显示器配置位于 [`config/hypr/monitor-yoga-slim-7-14q8x9.lua`](../config/hypr/monitor-yoga-slim-7-14q8x9.lua)。将它加入 `~/.config/hypr/monitors.lua`，然后运行：

```bash
hyprctl reload
hyprctl configerrors
hyprctl monitors
```

只有面板确实是 `eDP-1` 且支持 `2944x1840@90` 时才应使用该片段。

## 按应用切换顶栏菜单

菜单栏跟着前台窗口切换。Chrome 和 Chromium 显示「历史记录」「书签」「标签页」，Firefox 显示「历史记录」「书签」「工具」，Nautilus 显示「前往」。点击历史记录可打开当前浏览器的历史页面或资料库，书签和下载等操作也由当前窗口处理。其他应用使用 MacShell 的通用菜单。

从仓库根目录安装。此功能适用于 MacShell 0.5.3，依赖 Python 3、Git 和 Hyprland 的 Lua 快捷键调度接口。

```bash
python3 scripts/install-macshell-app-menus.py --check
python3 scripts/install-macshell-app-menus.py
qs -c MacShell ipc call macshell reload
```

[应用菜单配置](../config/macshell/app-menus/SilkyAppMenus.js)按窗口的应用 ID 匹配菜单，由 [MacBar 补丁](../config/macshell/app-menus/MacBar.patch)将菜单合入现有顶栏。各项调用应用自己的快捷键，适配范围由应用 ID 和快捷键支持决定。历史记录和书签内容在应用内查看。用 Chrome、Firefox 和 Nautilus 分别切换前台窗口检查分组，再点 Chrome 的「历史记录 → 显示所有历史记录」或 Nautilus 的「前往 → 上级文件夹」验证操作。

安装到 `~/.config/quickshell/MacShell/`。回滚时，用安装器打印的备份目录中的 `MacBar.qml` 替换安装后的文件。若该目录有旧的 `SilkyAppMenus.js`，一并恢复，否则可删除新增的文件。然后再次重载 MacShell。若升级 MacShell 后顶栏恢复为通用菜单，先用 `--check` 核对已安装版本和补丁是否兼容。

## 顶栏系统监控

MacShell 0.5.1–0.5.3 可单独安装网速、CPU 温度和电池面板。

```bash
python3 scripts/install-macshell-status.py --check
python3 scripts/install-macshell-status.py
```

网速和温度每 1.5 秒采样，面板显示最近约 1 分钟的趋势。顶栏网速分两行，上传（↑）在上、下载（↓）在下，和箭头方向一致，顺序由 [`SilkyStatusButton.qml`](../config/macshell/status/SilkyStatusButton.qml) 里 `Repeater` 的 `model` 决定。点击网速可查看应用流量排行和本机 IPv4 / IPv6，点击地址可复制。应用排行使用当前用户可见、采样时仍存在的 TCP 套接字，UDP 和 QUIC 不计入。代理转发的流量可能显示在代理进程名下。

点击温度可查看实时 CPU 占用最高的 10 个进程，以及显卡、固态硬盘、无线网卡和风扇等硬件概览。硬件概览下方显示整机 CPU、内存和系统盘（`/`）的占用率。进程占用按相邻两次采样的 CPU 时间增量计算，100% 表示占满一个逻辑核心。点击电池图标可查看供电来源、功率、电压、电量、容量、循环次数和健康度，内容随硬件暴露的字段变化。MacShell 运行时每 3 秒采样一次，面板中部的「整机功耗」曲线保留最近约 5 分钟，关闭面板后继续采样。只有电池供电时才能测到整机功耗：此时电池放电功率就是整机的耗电。接上电源后，Yoga Slim 7x（Snapdragon X，`qcom-battmgr`）既不报告适配器输入功率（USB-C 端口 `voltage_now` 为 0，`2.00 A` 只是 PD 协商值），也不报告整机负载（不充电时电池 `power_now` 为 0），所以接电源期间曲线留空，「供电来源」里的「整机功耗」显示「接电源时不可读」。充电或放电功率改为数值，放在「电池」分组的「充电功率 / 放电功率 / 电池功率」一行。健康度是电池计量芯片给出的满充容量 `energy_full` 除以设计容量 `energy_full_design`。芯片会不定期重新校准满充容量，健康度可能一次跳几个百分点；长期开着充电上限时校准更少、跳得更明显。为了能回看变化，顶栏每 10 分钟检查一次，每天和满充容量变化时向 `~/.local/state/silky/battery-health.csv` 追加一行（时间、型号、满充/设计容量、健康度、循环次数）。Yoga Slim 7 14Q8X9 可在电池面板拖动滑条设置 55%–100% 的充电上限，点「应用」后通过系统授权写入并校验内核回读。右键电池图标可以切换系统提供的电源模式，所选模式由 Omarchy 按外接电源和电池供电分别记忆。右键面板底部还有「显示电量百分比」开关，关掉后电池里只显示电量条，不显示数字；它就是 MacShell 设置里的 `showBatteryPercent`，会保存到 `~/.config/macbar/settings.json`。

托盘图标统一成和菜单栏其他图标一样的单色线条（跟随深浅色）：按托盘项的 id 换成 `SilkyStatusIcon` 里手绘的图标，目前覆盖 Chrome、ChatGPT、Clippy、Netcatty、Remmina、Clash Verge 和微信（id `wechat`，两个叠在一起的对话气泡）。其他应用保持原图标；需要提醒（`NeedsAttention`）时也显示原图标。查托盘 id：`busctl --user get-property <服务> /StatusNotifierItem org.kde.StatusNotifierItem Id`。装完后执行 `qs -c MacShell ipc call macshell reload` 让 MacShell 重新加载。

## 应用程序面板交互

[`tune-apps-panel.py`](../scripts/tune-apps-panel.py)：应用程序面板的鼠标滚轮每格移动 320 像素，触控板和触摸屏松手后使用平滑减速；玻璃面板与图标一起跟随点击或捏合进度渐显。安装脚本会在现有安装上应用这些调整，滚动距离仍受列表边界限制。触控屏拖动时手指只移动滚动目标，列表按 1.1 倍手指距离、按屏幕帧平滑跟随（和触控板同一套逐帧动画），松手后无论快慢都按同一条减速曲线滑行，不再按触摸事件一跳一跳地移动、慢速松手也不会戛然而止。

### 打开 / 关闭动画

整块面板（玻璃外框和里面的内容）作为一个画面，从 114% 缩小到 100%、从模糊变清晰、从透明变实；每个图标在此之上再叠加一点自己的缩放（外圈先到位）。之前只有图标在缩放，外框只是淡入。实现上外框和内容放进同一个 `appsStage`，只做一次离屏渲染和一次模糊，比原来“外框一层、内容一层再模糊”更省。

关闭（按 Esc、点击面板外、再点 Dock 图标、启动应用）时不再反向放大，也不再走弹簧动画（弹簧先加速、再拖一段慢尾巴，看起来像反弹），而是 0.15 秒的整体淡出：整个面板作为一张画面一起变透明，不模糊、玻璃和内容不分开淡、图标不分先后、尺寸保持 100%。打开和捏合手势松手仍然用弹簧。

入场的明暗顺序和 macOS 一致：浅色的磨砂玻璃先出现（不透明度按 t^1.6：捏合起步时很淡，越往后变深越快），图标和文字再在上面逐渐变实（t^1.8，始终落后玻璃一步）。之前反过来（内容 t^0.55、玻璃 t^1.35），开头几帧是模糊的图标叠在后面的窗口上，比最终的面板更暗，然后才变浅。

另一个原因是玻璃背后的窗口画面：开启实时玻璃（`glassRealtime`）时，只有玻璃正在显示的区域才会抓取窗口画面，所以面板一打开，后面的窗口都要从头开始抓，最初几帧玻璃模糊的是深色占位色（`#1e1e20`）或旧画面，随后才跳成真实的（往往更亮的）窗口。现在面板关闭时，会每 1.5 秒给它将要出现的区域里的窗口各拍一张单帧（不是实时流），打开时直接从当前画面开始。捏合到一半松手关闭、或关闭途中又重新打开时，缩放比例在 0.18 秒内平滑过渡，不会跳变。

动画由一根按真实帧时间推进的弹簧驱动，90 Hz 内屏上实测整个过程平均 11.0 ms / 帧，没有掉帧。另外处理了三处会让它“顿一下”的地方：

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| 刚开始动就跳一下 | 开关后的头几帧最贵（打开约 25 ms，关闭时重建离屏层约 20 ms），弹簧按真实时长推进就会多走一截 | 每次启动或反向后的前 3 帧最多推进一个显示帧；关闭时在收到请求的那一帧就建好离屏层 |
| 登录后第一次打开卡约 200 ms | 着色器、离屏层、图标纹理都在第一帧创建 | Shell 启动 3 秒后以 0.4% 不透明度（低于 8 位色的一个级差，看不见，也不接收输入）预先画一次 |
| 连续点击 Dock 图标时卡 60–70 ms | 指针焦点在 Dock 和全屏面板之间来回切换，每次回到 Dock 都重建图标的悬停标签（一整个玻璃气泡） | 和 macOS 一样：点过图标后，标签在指针移动 4 px 之前不再出现（[`tune-dock-hover-label.py`](../scripts/tune-dock-hover-label.py)） |

连续快速点击 Dock 的“应用程序”图标时，每一次点击都会让弹簧立即反向（速度连续，不会停顿重来）。这依赖 `silky-gestures` 插件在按键按下时重新确定指针下的窗口，见 [03 · 触控屏工作区手势](03-silky-gestures.md#快速连续点击)。

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

## 鼠标指针周期性卡顿

MacShell 0.5.1 的“自动对比度”每 1.2 秒用 `grim` 截取菜单栏背后的画面，菜单打开时每 0.7 秒再截一次。在 Adreno X1-85 上，每次截屏都会让 Hyprland 主线程停顿 60–110 ms（90 Hz 下约 6 帧），表现为什么都不开、鼠标匀速画圈时指针随机顿一下并漂移。Hyprland 日志里对应的是 libinput 的 `event processing lagging behind by …ms`。

补丁删除了这两个定时器，只在菜单栏背后的内容确实可能变化时重新测量：切换工作区、窗口打开/关闭/移动、全屏切换、壁纸或外观变化，以及菜单打开的那一刻。

截图和录屏本身仍会触发同样的停顿，这是 Hyprland 在该 GPU 上的截屏开销，不在本补丁范围内。

## 打开菜单和控制中心时卡顿

原因同上：自动对比度会在菜单打开的瞬间截一次菜单背后的画面，正好落在弹出动画中间；菜单关闭、窗口改标题等任何窗口信息变化后，还会再截一次菜单栏背后的画面。

补丁做了三处调整：

- 深色模式下菜单文字固定为白色，不再为菜单截屏（测量结果本来就用不上）
- 只有窗口出现、关闭、移动或改变大小时才重新测量菜单栏，标题和焦点变化不再触发
- 菜单栏背后只有壁纸时（平时都是如此，菜单栏占用自己的区域），用新增的 `assets/tone-wall.sh` 读取壁纸文件计算亮度，不再截屏；结果按壁纸缓存。只有窗口真的伸到菜单栏下面（浮动窗口、全屏、特殊工作区）或使用视频壁纸时才退回截屏

实测打开控制中心时的停顿从约 76 ms 降到约 19 ms，切换工作区时不再有截屏。剩余的短暂停顿来自实时玻璃对菜单背后窗口的捕获，关闭实时玻璃效果可以进一步消除。

## 重载配置后鼠标设置丢失

MacShell 设置里的鼠标自然滚动、跟踪速度、按键重复和触控板选项是用 `hyprctl eval` 临时写进 Hyprland 的，只在设置变化时写一次。任何一次配置重载（`hyprctl reload`、切换主题、保存配置文件）都会把它们清掉，表现为设置里开着自然滚动，滚轮方向却变回去了。

补丁让 MacBar 在收到 `configreloaded` 事件后重新应用一次这些设置。

## 触控拖动窗口

MacShell 的窗口通过 `startSystemMove()`（即 `xdg_toplevel.move`）拖动。Hyprland 0.57.2 只接受带鼠标按键序列号的移动请求，手指触发的请求会被丢弃，所以触控屏上拖不动。

补丁让原有的拖动处理只响应鼠标和触控板，并新增 `TouchWindowMove.qml` 处理触控屏：手指每移动一次，就通过 Hyprland IPC 把窗口相对移动同样的距离，拖动期间临时关闭该窗口的移动动画，使窗口贴着手指走。可拖动区域与鼠标一致：“关于本机”整个窗口，设置、时钟和安装器的顶部栏。

## 锁屏看不到壁纸

MacLock 只从 MacShell 的 `wallpaperPath` 设置或 `awww query` 读取壁纸。Omarchy 4.x 自己管理桌面壁纸，这两处通常都是空的，锁屏于是只剩纯黑背景。

补丁让 MacLock 在这两处之前先读取 `~/.local/state/omarchy/current/background`：图片作为锁屏背景，视频则作为动态锁屏壁纸（MacShell 自己设置的视频壁纸仍然优先）。

预览锁屏（不会真正锁定）：

```bash
MACLOCK_PREVIEW=1 qs -c MacLock
```

## 重启后菜单栏、Dock 消失，鼠标滚轮方向反了

MacShell 由 `~/.config/hypr/macshell.lua` 在 Hyprland 启动时拉起，`hyprland.lua` 里需要一段 `-- >>> MacShell (added by install.sh) >>>` 块来加载它。这两者丢失后，当前会话里手动启动的 MacShell 一切正常，但重启后菜单栏和 Dock 都不会出现。

鼠标滚轮的自然滚动是 MacShell 设置里的选项，由 MacShell 启动后通过 `hyprctl eval` 写入 Hyprland。MacShell 没有启动，这个设置也就不存在，滚轮方向回到 Linux 默认。

修复：

- 安装脚本会检查并恢复 `macshell.lua` 和 `hyprland.lua` 中的加载块
- [`config/hypr/input-touchpad.lua`](../config/hypr/input-touchpad.lua) 直接在 Hyprland 配置中开启鼠标 `natural_scroll`，从登录起就生效，不再依赖 MacShell

检查：

```bash
grep -n 'hypr.macshell' ~/.config/hypr/hyprland.lua
pgrep -af '^qs -c MacShell'
hyprctl getoption input:natural_scroll
```

## 截图要按两次、还会再弹出一次

Omarchy 把 `PRINT` 绑定到 omasnap，MacShell 的 `macshell.lua` 又把同一个键绑定到自己的区域截图。按一次键两个截图界面同时启动、互相取消：第一次看起来没反应，接着又弹出另一个截图界面。

补丁删掉了 `macshell.lua` 里的 `PRINT` 绑定，这个键只交给 omasnap。MacShell 自己的截图在控制中心里仍然可以用。

## 截图不再发通知

原来每次截图会出现两条通知：omasnap 的“截图已保存并复制”，以及 MacShell 的 “Screenshot saved”。

- Omarchy 默认的截图命令带 `--notify`。[`config/hypr/bindings-screenshot.lua`](../config/hypr/bindings-screenshot.lua) 把 `PRINT` 改为直接运行 `omasnap`：截图照样保存并复制到剪贴板，右下角显示一个和 macOS 一样的浮动预览（7 秒后消失，可拖出或点“编辑”标注），不进通知中心
- MacShell 的 `screenshotNotify` 设为 `false`

## 电池图标

菜单栏电池改成 macOS 26 的样式：更窄的胶囊（电池本体 24 px，按钮 32 px），里面只有数字，没有 `%`。数字通常只有两位，所以不需要更长。右键电池可以开关数字（见上方「顶栏系统监控」）。

电池图标和电池面板用同一套颜色区分供电状态。只有值得注意的状态才上色；最常见的电池供电保持中性色，和 macOS 一致。黄色和橙色都带“警告”含义，在 14 px 的图标上也难以区分，所以不再使用：

| 状态 | 颜色 | 判断条件 |
| --- | --- | --- |
| 正在充电 | 绿色 | 电池状态为 `Charging` |
| 外接电源直接供电（未充电，如已到充电上限） | 当前壁纸的强调色，表示“已连接、稳定”；取不到时为蓝色 | 接着电源但电池不在充电 |
| 电池供电 | 中性色（深色模式白色，浅色模式深灰） | 没有外接电源 |
| 低电量 | 红色 | 电量低于 20%（与 macOS 相同）且不在充电 |

充电优先于低电量：电量低但正在充电时显示绿色。

外接电源直供的颜色取自当前壁纸，换壁纸后跟着变。顶栏采样进程（[`status.py`](../config/macshell/status/status.py) 的 `wallpaper_accent`）解析 Omarchy 的壁纸链接 `~/.local/state/omarchy/current/background`，用 ImageMagick（`magick`）把图缩到 96×96、量化成 16 色，按“面积 × 色度²”选出最鲜明的主色，保留色相，再按深色和浅色菜单栏分别调成亮度 72% 和 38% 的两档（饱和度限制在 50%–85%），随采样数据以 `wallpaperAccent` 发给菜单栏电池和电池面板。结果按壁纸路径和修改时间缓存，换壁纸后约 1.5 秒内更新，只在换图时重新计算一次（6K PNG 约 0.3 秒）。壁纸接近灰色（主色色度低于 0.12）、是视频、或没装 `magick` 时退回原来的蓝色。限制：绿色调壁纸（如 Bliss）取出的颜色会和充电绿接近。验证：接着电源且不在充电时执行 `omarchy-theme-bg-set ~/Pictures/Wallpapers/<另一张>.jpg`，几秒内电池图标和面板强调色应随之变化；macOS Monterey 壁纸取出紫色，Sierra 取出暖橙色。也可以直接查看取色结果：

```bash
python3 -c 'import importlib.util as u; s=u.spec_from_file_location("s", "config/macshell/status/status.py"); m=u.module_from_spec(s); s.loader.exec_module(m); print(m.wallpaper_accent())'
```

部署：重新运行 `python3 scripts/install-macshell-status.py`，它会把旧的蓝色 `indicatorColor` 换成读取 `wallpaperAccent` 的版本，然后重启 MacShell 让新采样脚本生效。回滚：恢复安装脚本打印的 `MacBar.qml.bak.silky-status-*` 备份，并把 `SilkyStatusPanel.qml` 与 `assets/silky-status.py` 换回上一版后重启 MacShell。

面板的「整机功耗」曲线是数据而非状态，固定用紫色。颜色由 [`scripts/install-macshell-status.py`](../scripts/install-macshell-status.py) 写进 `MacBar.qml`（`indicatorColor`），面板颜色在 [`SilkyStatusPanel.qml`](../config/macshell/status/SilkyStatusPanel.qml) 的 `powerState`。重新运行安装脚本会把旧的三色版本替换掉；改动后需重启 MacShell，旧的后台采样进程才会换成新版脚本。验证：插着电源且电池到达充电上限时，图标应为壁纸强调色（取不到时为蓝色）；拔掉电源后变回中性色。只改了 QML 时可用 `qs ipc -c MacShell call macshell reload` 重载。回滚：恢复安装脚本打印的 `MacBar.qml.bak.silky-status-*` 备份并重启 MacShell。

## 桌面不显示图标

MacShell 默认把桌面目录里的文件和文件夹画成桌面图标（`macdock/settings.json` 里的 `desktopIcons`）。安装脚本把它设为 `false`，桌面只显示壁纸。需要时可在 MacShell 设置里重新打开。

## 只保留 MacShell 的 Dock

Omarchy shell 自带一个 Dock（插件 `omarchy.dock`）。MacShell 平时会压住它，但 Omarchy shell 一重启（`omarchy restart shell`、切换插件后）它就会重新出现在屏幕底部，与 MacShell 的 Dock 叠在一起。永久关掉：

```bash
omarchy plugin disable omarchy.dock
```

`scripts/install-maclock.sh` 会顺带执行这一步，因为它需要重启 Omarchy shell。

## “关于本机”变宽、打开时白边闪一下

两个问题都出在 Hyprland 窗口规则上，[`config/hypr/silky-macshell-windows.lua`](../config/hypr/silky-macshell-windows.lua) 一条规则解决：

```lua
o.window("^(org\\.quickshell)$", { float = true, center = true, border_size = 0 })
```

- **变宽**：Omarchy 的浮动工作区模式会把新打开的窗口统一放大到标准尺寸（最多 1100×760，屏幕的 64%×68%），只有“自己带浮动规则”的应用例外。MacShell 的窗口（关于本机、设置、时钟、安装器，class 都是 `org.quickshell`）不在例外名单里，于是被撑宽。用 `o.window(..., { float = true })` 登记后，Omarchy 就不再改它们的尺寸
- **白边闪烁**：这些窗口自己画 macOS 风格的边缘，原本是在窗口出现**之后**用定时器（60 ms 一次）通知 Hyprland 去掉 1 px 边框并重新居中，所以打开动画的前几帧能看到 Hyprland 的白色描边，随后突然消失，窗口还会轻微跳一下。现在在窗口创建时就由规则设好无边框、居中，第一帧起就是最终样子

验证方法：用 `wf-recorder` 以 60 fps 录下打开过程，逐帧查看边缘。

注意：规则只对新创建的窗口生效，修改后需要重启 MacShell 一次。

## 崩溃后出现两个菜单栏、两个 Dock

MacShell 崩溃时有两套机制同时把它拉起来：Quickshell 自带的崩溃处理会弹出报告窗口并**自己重新启动一份**（进程名是不带参数的 `/usr/bin/quickshell`，环境里有 `__QUICKSHELL_CRASH_*`），而 `macshell-start` 也会再启动一份。两份各画一套菜单栏和 Dock。

- `~/.config/macshell/env` 加 `QS_DISABLE_CRASH_HANDLER=1`：不弹崩溃窗口、不自行重启，只由 `macshell-start` 安静地重启；崩溃信息仍在 `~/.local/state/macshell/MacShell.log` 和系统核心转储里
- `macshell-start` 改用 `qs -n -c MacShell`：已有 MacShell 在运行时新启动的直接退出（退出码 0，守护脚本随之安静结束），保证永远只有一份

## Omarchy 菜单里显示 “system.lock”

覆盖菜单项时只写 `action` 会丢掉原来的 `icon` 和 `label`，菜单里就直接显示 id。覆盖时把三者都写上：`"system.lock": {"icon":"󰌾","label":"锁屏","action":"silky-lock"}`。图标是 Nerd Font 私有区字符（这里是 Material Design 的锁 U+F033E，与菜单里其他图标同一套），在终端或脚本里复制时很容易被吞掉变成空字符串，菜单里就只剩文字；写入时用转义（如 Python 的 `"\U000F033E"`）更稳妥，写完可以用 `od -c` 确认。

## 玻璃面板边缘“错位”

菜单栏弹出的面板（日历、控制中心等）边缘会出现一条和背景对不上的深色宽带，看起来像背景偏移了。原因是 Liquid Glass 着色器的边缘折射太强：弹出面板把折射强度放大到基准的 1.6 倍（`liquidglass.frag` 里再乘 1.35），斜面宽 26 px，边缘会把面板外 50–60 px 的背景“折”进来——面板旁边正好有窗口边缘时，就是那条错位的暗带。

补丁把 `MacBar.qml` 里两处弹出面板玻璃的倍数从 1.6 降到 0.6、斜面上限从 26 px 降到 18 px：边缘仍有玻璃厚度和高光，但只偏折约 18 px，与 Apple Liquid Glass 的克制程度接近。Dock 的玻璃不受影响。

日历还需要单独处理：它以右上角为缩放原点，旧代码却从未缩放的左上角截取背景，因此菜单栏尺寸或显示缩放变化后，面板里的壁纸会横向错位。日历现在按实际屏幕矩形取样，并把固定的 42 px 模糊改为最多 18 px、降低染色与折射、把饱和度收回到 1.05。这样仍保留轻微玻璃质感，但底色和面板外的壁纸连续，不再像另贴了一张经过重调色的模糊图。

## 控制中心

[`tune-control-center-glass.py`](../scripts/tune-control-center-glass.py)：分组后的控制中心和菜单栏下拉菜单共用同一套玻璃材质（同一块底板、渐变和描边，以后调一处两边都变）。MacShell 0.5.2 把控制中心固定成深色，浅色外观下也是黑的；现在跟随外观，浅色下是浅色玻璃。

[`tune-display-controls.py`](../scripts/tune-display-controls.py)：控制中心新增「显示」页，入口和「声音」一样（左边点名称进页面，右边直接拖滑条）。页面里有亮度滑条，以及「夜览」和「外观」（深色 / 浅色）两个开关。

## Dock 图标与设置窗口

- [`tune-dock-icons.py`](../scripts/tune-dock-icons.py)：Dock 图标的光学缩放以图标中心为基准，悬停放大时不会往一边偏；旋转（抖动）的支点不变。
- [`tune-settings-scroll.py`](../scripts/tune-settings-scroll.py)：设置窗口左侧导航列表原来滚轮一格只动几像素。现在每格 140 px，多格累加后逐帧平滑过去；触控板的像素级滚动仍交给列表自己处理，保留原生惯性。

## 焦点切换时玻璃背景跟着刷新

[`tune-glass-stacking.py`](../scripts/tune-glass-stacking.py)：玻璃背后窗口的“指纹”原来只看位置和大小，点击切换浮动窗口的前后顺序时，玻璃里还是旧的叠放顺序。现在把焦点顺序（`focusHistoryID`）也算进去，切换焦点时立即刷新；窗口改标题（终端、浏览器标签页、播放器）依然不会唤醒 60 Hz 刷新。

## 窗口最小化

Silky 不再提供窗口最小化入口（[`disable-minimize.py`](../scripts/disable-minimize.py)）：标题栏仅保留关闭和最大化，MacShell 菜单及客户端请求转发也已关闭。Dock 仍保留恢复先前已最小化窗口的能力。
