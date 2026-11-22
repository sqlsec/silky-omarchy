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

**不限制版本**：安装脚本不再拒绝其他版本的 MacShell。0.5.1 用自己的补丁，其他版本一律用最新的 0.5.2 补丁，然后由补丁检查决定怎么处理：已带 Silky 改动的安装会根据运行时标记识别为“已应用”，只更新各项调整；补丁对不上的全新安装会在改动任何文件之前停下，并报告原因。如果上游已经自带某项调整，调整脚本会识别出来并跳过。例如 0.5.3 的 Dock 收起后本来就会暂停玻璃捕获，`tune-macshell-performance.py` 就不再改这一处。已在本机已带 Silky 改动的 **MacShell 0.5.3** 上验证：`--check` 通过；在隔离的 `HOME` 中完整安装一遍后，所有 QML 文件和现有安装完全一致。全新的 0.5.3 还没有验证。

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

托盘图标统一成和菜单栏其他图标一样的单色线条（跟随深浅色）：按托盘项的 id 或标题换成 `SilkyStatusIcon` 里手绘的图标，目前覆盖 Antigravity（拱形 A 轮廓线条）、Chrome、ChatGPT、Clippy、Netcatty、Remmina、Clash Verge、网易云音乐和微信（id `wechat`，两个叠在一起的对话气泡）。其他应用保持原图标；需要提醒（`NeedsAttention`）时也显示原图标。查托盘 id：`busctl --user get-property <服务> /StatusNotifierItem org.kde.StatusNotifierItem Id`。装完后执行 `qs -c MacShell ipc call macshell reload` 让 MacShell 重新加载。

## 通知中心小组件

点顶栏铃铛打开的「通知系统」面板里，通知列表下面是一组 macOS 风格的小组件。每个都有小（172×172）、中（356×172）、大（356×356）三种尺寸，两个小组件并排正好是一个中组件的宽度。小组件的强调色取自当前壁纸（和[电池图标](#电池图标)同一个 `wallpaperAccent`），换壁纸后跟着变。

| 小组件 | 小 | 中 | 大 | 数据来源 |
| --- | --- | --- | --- | --- |
| 天气 | 城市、气温、天气、最高 / 最低 | 加体感、湿度、风速和未来 6 小时 | 再加 6 天预报和温度区间条 | [Open-Meteo](https://open-meteo.com/)，无需密钥，15 分钟刷新 |
| 股市 | 第一只代码的走势、价格和涨跌 | 3 只 | 6 只 | A 股、港股、美股用腾讯行情（`qt.gtimg.cn`），其他市场（东京、欧洲、全球指数、加密货币、期货）用 Yahoo Finance，每分钟刷新 |
| 屏幕使用时间 | 今天总时长和前 3 个应用 | 加按小时分布、和昨天对比 | 再加本周 7 天和前 6 个应用 | 本机记录，见下文 |
| 电池 | 本机和设备的圆环（最多 4 个） | 4 个圆环带名称 | 设备列表 | UPower：本机电池、蓝牙鼠标 / 键盘 / 耳机等 |
| 日历 | 星期、日期、农历或节日 | 加本月月历 | 带农历、节日和调休「休 / 班」的整月 | 本地日期和 [`ChinaCalendar.js`](../config/macshell/calendar/ChinaCalendar.js) |
| 系统 | CPU、内存、磁盘进度条 | 三个圆环和用量 | 再加最近 5 分钟 CPU 曲线、运行时间、负载 | `/proc`、`statvfs("/")` |
| AI 用量 | Claude、Codex、DeepSeek 各一行：主数字、说明，Codex 的额度条在说明同一行、主数字下方 | 三栏，结构相同：图标和名称、主数字、说明、两行明细 | 再加每小时 tokens（Claude、Codex 叠加）和 Codex 5 小时 / 本周额度条与重置时间 | 见下文「AI 用量」 |

小组件卡片和控制中心的方块用同一种材质：在面板的液态玻璃上再叠一层同样的玻璃（`GGlass`，玻璃上下文 `notifPopGlass.ctx`）和细边框（`CornerBorder`），再加一层很淡的深色，所以比面板本身深一点。玻璃关闭时退回深色半透明底。天气卡只在上半部叠一层很淡的天色（晴、阴、雨、夜），文字跟随面板深浅色；中、大尺寸里天气描述和最高 / 最低温合成一行，不再和逐小时预报重叠。

股票颜色默认中文界面红涨绿跌、英文界面绿涨红跌，可在右键菜单里切换。走势图在交易时段画当天分时线，虚线为昨收；取不到分时数据时改画近一月日线。关注列表最多 12 项，每项可以是：

| 输入 | 解析为 | 行情来源 |
| --- | --- | --- |
| `sh000001`、`hkHSI`、`usIXIC` 等带前缀代码 | 原样使用 | 腾讯 |
| 6 位数字，如 `600519` | `6` / `9` 开头为沪市，`0` / `3` 为深市，`4` / `8` 为北交所 | 腾讯 |
| 4–5 位数字，如 `00700` | 港股 | 腾讯 |
| 1–5 个字母，如 `AAPL` | 美股 | 腾讯 |
| 含 `^ . = -` 的代码，如 `^N225`、`^GDAXI`、`7203.T`、`SAP.DE`、`BTC-USD`、`GC=F` | Yahoo 代码 | Yahoo Finance |
| 名称，如 `茅台`、`英伟达`、`toyota` | 先查腾讯搜索（中文名），再查 Yahoo 搜索 | 解析出的来源 |

解析结果在数据进程运行期间缓存；查不到的条目在菜单里只显示原文，下一轮再试。在右键菜单里上下拖动某一行（或左侧的 ≡）可以调整顺序，小组件按这个顺序显示，小尺寸显示第一项。

### 通知按应用堆叠、和小组件一起滚动

通知很多时，通知区和小组件之间原来是两个各自滚动、边缘硬切的区域，衔接生硬。现在：

- **按应用堆叠**（同 macOS）：同一应用的通知叠成一摞，只显示最新一条，下面露出一到两层「纸边」。点一下展开这一摞，其他卡片平滑让位；展开后上方出现应用名、「收起」和「✕」（清除这个应用的全部通知，逐张化为尘埃）。单条通知点击仍是打开。
- **只显示最近 3 个应用**：更早的应用收进「还有 N 个应用的通知」，点开后可「收起」。关闭面板时恢复折叠。
- **一个滚动区**：通知和小组件在同一个滚动区里，不再各自滚动；面板高度不超过屏幕。滚到边缘的卡片和小组件按露出的比例淡出（露出 70% 时约 55% 不透明），而不是被硬切一半。「没有通知」在小组件滚上来时隐藏。

实现：安装脚本把 `MacBar.qml` 里通知列表的 `Column` 换成按 `notifPop.silkyPlan`（按应用分组、按最新通知排序）手动布局的 `Item`，每张卡片的位置由 `silkyY()` 计算并带 420 ms 动画；小组件 `SilkyWidgetDeck` 移进通知的 `Flickable`（`nfl`），面板高度改为 `92 + nfl.height + 14`。淡出不用着色器遮罩：液态玻璃放进离屏图层会发白，所以改为每张卡片按自身在视口里的比例设置不透明度。

展开 / 收起时不再重影。最初的版本里，被折叠的卡片和最新那张叠在同一位置、按同样节奏淡入淡出，而且每张卡片的目标位置取自邻居「正在动画中」的高度，目标一直在变、动画反复重启，于是多张半透明卡片叠在一起。现在：布局只用每张卡片的最终高度（`silkyFinalH`，含应用标题和纸边的最终值），每张卡片只朝一个固定目标滑动一次；折叠卡片的不透明度是过渡进度的三次方，滑出最新那张之后才显现，收起时在滑回之前就消失；每个应用最新那张始终画在它的折叠卡片上面；应用标题、纸边、「还有 N 个应用」按钮和小组件区都以同样的 420 ms 曲线移动。「全部清除」仍按动画中的高度连续收拢。

用示例通知检查（不发真实通知，只加到列表里，`undemo` 只删除带 `[Silky demo]` 标记的条目）：

```bash
qs -c MacShell ipc call silkynotif demo      # 微信 3 条、邮件 2 条、Slack、日历
qs -c MacShell ipc call notifications open
qs -c MacShell ipc call silkystack toggle wechat   # 不用点击，展开 / 收起某个应用的一摞
qs -c MacShell ipc call silkynotif undemo
```

实机验证：示例通知显示为微信、邮件两摞（带纸边）、Slack 单条和「还有 1 个应用的通知」，下面接小组件，底部卡片淡出。用 `silkystack toggle` 逐帧截图检查了展开和收起：折叠卡片在最新那张下面不可见，收起时不再残留重影。清除一个应用和「还有 N 个应用」的展开需要在面板里点击确认。面板在浅色窗口上方时玻璃会整体变亮，这是玻璃半透明的正常表现。

### 安装

需要 MacShell 0.5.1–0.5.3，并且已安装[顶栏系统监控](#顶栏系统监控)（取壁纸强调色）和农历日历（`ChinaCalendar.js`）。

```bash
python3 scripts/install-macshell-widgets.py --check
python3 scripts/install-macshell-widgets.py
qs -c MacShell ipc call macshell reload
```

安装脚本把 [`config/macshell/widgets/`](../config/macshell/widgets/) 下的 QML 复制到 `~/.config/quickshell/MacShell/`，把 [`widgets.py`](../config/macshell/widgets/widgets.py) 复制成 `assets/silky-widgets.py`，并给 `MacBar.qml` 打三处补丁：面板高度加上小组件区、在通知列表下放 `SilkyWidgetDeck`、右键菜单编辑天气城市或股票代码时让弹层窗口接收键盘（`WlrKeyboardFocus.OnDemand`）。改 `MacBar.qml` 前会备份为 `MacBar.qml.bak.silky-widgets-*`，重复运行不会再改。

### 使用

- 在任意小组件上点右键，弹出菜单：切换「小 / 中 / 大」，移除小组件。天气的菜单里可以填城市（中文、英文都可以，留空按 IP 定位），回车或点别处保存，下方显示当前定位到的城市；股市的菜单里列出关注的代码（显示解析出的名称），点「−」删除，在输入框里输入代码或名称后回车添加，并可切换红涨绿跌 / 绿涨红跌。菜单本身也是磨砂玻璃（同一个液态玻璃材质加一层半透明底）。打开菜单时面板会临时接收键盘输入，按 `Esc` 关闭。
- 点面板底部「编辑小组件」进入编辑：小组件会轻微晃动，点一下按「小 → 中 → 大」切换尺寸，拖动调整顺序，点左上角「−」删除。
- 编辑时下方是「添加小组件」：选类型和尺寸，预览就是实际效果，点预览或「＋ 添加小组件」加入。城市和股票代码在右键菜单里设置。
- 布局和设置保存在 `~/.config/silky/widgets.json`，可以直接编辑，MacShell 会自动读取。

### 屏幕使用时间怎么算

数据进程每 5 秒通过 Hyprland 套接字读一次当前聚焦窗口的 `class`，把这段时间记到该应用和当前小时上。以下时间不计：连续 2 分钟没有键鼠操作（Quickshell `IdleMonitor`，视频播放器等发出的空闲抑制视为在用）、锁屏（`hyprlock` / `swaylock` / `gtklock` 在运行）、休眠。记录按天保存在 `~/.local/state/silky/screen-time/YYYY-MM-DD.json`，每分钟写一次，保留 30 天。应用名和图标按 `class` 匹配桌面入口（`DesktopEntries.heuristicLookup`），匹配不到时显示 `class`。只从安装后开始统计，MacShell 没运行时也不统计。

### AI 用量

「AI 用量」小组件显示今天（本地时间）的用量，按 30 秒刷新。三家用同一种结构：白色圆角底上的官方 logo（品牌色：Claude `#D97757`、Codex `#7A6CFF`、DeepSeek `#4D6BFE`）、一个主数字、一行说明、两行明细。主数字分别是 Claude 今日 tokens、Codex 5 小时额度剩余、DeepSeek 今日消费；明细分别是请求数和输出 tokens、本周剩余和重置时间、余额。

- **Claude Code**：读取 `~/.claude/projects/**/*.jsonl`（设置了 `CLAUDE_CONFIG_DIR` 时读它下面的 `projects`，也会读 `~/.config/claude/projects`），把今天每条回复的 `usage` 加起来，按消息 ID 和请求 ID 去重。tokens 合计包括输入、输出、缓存读取和缓存写入，其中缓存读取通常占绝大部分，所以大尺寸里单独列出输出和缓存。Claude Code 只在请求因额度用完被拒时，才在日志里记下 `rate_limit_info`（类型和重置时间）；小组件读到尚未到重置时间的这类记录时，Claude 一栏改为「5 小时剩余 0%」「已达上限」和重置时间。平时的额度百分比只能通过 Anthropic 的 OAuth 用量接口查询，需要 Claude Code 命令行的登录凭据；Claude 桌面应用自己管理登录，本机没有这份凭据，所以目前不显示。
- **Codex**：读取 `~/.codex/sessions` 和 `~/.codex/archived_sessions` 里今天改动过的会话，tokens 取每个会话今天的 `total_token_usage` 增量；5 小时和每周额度取最新一条 `token_count` 事件里的 `rate_limits`，和 Codex 应用一样显示「剩余」百分比（100 − `used_percent`）。Codex 只在回复后写入额度，所以如果记录里的重置时间（`resets_at`）已经过了，就按该窗口已重置处理，显示剩余 100%、「窗口已重置」；之前直接显示旧记录，会出现「5h 12% · 0 分钟后重置」而 Codex 应用里是剩余 100% 的情况。重置时间显示为钟点（当天）或日期加钟点。
- **DeepSeek**：DeepSeek 没有账号授权登录，需要在右键菜单里粘贴 API Key（在 [DeepSeek 开放平台](https://platform.deepseek.com/api_keys) 创建），回车保存。Key 通过标准输入交给数据进程，写到 `~/.config/silky/ai-keys.json`（权限 `0600`），不进 `widgets.json`，也不出现在进程参数里。数据进程每 10 分钟调用一次 [`GET /user/balance`](https://api-docs.deepseek.com/api/get-user-balance)，以当天第一次读到的余额为基准，「今日消费」= 基准 − 当前余额；余额变多（充值）时重设基准。在右键菜单里点「删除 Key」会删掉 Key 和基准。

日志按增量读取（只读新追加的行），第一次扫描约 0.1 秒，之后约 1 毫秒。AI 用量小组件不放在面板上时，这些文件和接口都不会被读取。

logo 来自 [LobeHub Icons](https://github.com/lobehub/lobe-icons) 的 npm 包 `@lobehub/icons-static-svg`（MIT 许可，固定 1.104.0 版）：`claude-color.svg`、`codex-color.svg`、`deepseek-color.svg`。logo 本身是各公司的商标，所以不放进仓库，由安装脚本在首次安装时从 jsDelivr 下载到 `~/.config/quickshell/MacShell/assets/ai-logos/`，只接受不含脚本和外链的纯 SVG。下载失败时小组件用品牌色字母方块代替；之后重新运行安装脚本会补下载。

### 离屏预览

[`scripts/preview-macshell-widgets.sh`](../scripts/preview-macshell-widgets.sh) 用一份真实数据快照（天气取缓存，没有 DeepSeek Key 时用示例余额），在 `QT_QPA_PLATFORM=offscreen` 下把小组件渲染成 PNG，不在屏幕上显示任何东西，也不改面板布局。脚本会打印 QML 报错（`TypeError`、`ReferenceError`、属性冲突等）。

```bash
scripts/preview-macshell-widgets.sh /tmp/widgets.png              # 默认：AI 小 / 中 / 大、天气中 / 大、股市小
scripts/preview-macshell-widgets.sh /tmp/ai.png ai:small ai:large
SILKY_PREVIEW_LANG=en scripts/preview-macshell-widgets.sh /tmp/en.png
```

预览用的面板配色、玻璃材质是近似值（没有液态玻璃），只用来检查排版和数据。


### 实现与限制

- 数据进程 `assets/silky-widgets.py` 由 `SilkyWidgetDeck` 启动，常驻运行（屏幕使用时间需要持续记录），每 5 秒输出一行 JSON；退出后 5 秒自动重启。天气和股市只在对应小组件放在面板上时才联网，天气结果缓存在 `~/.cache/silky/widgets-weather.json`，离线时显示上次结果。
- 面板关着时数据不送进 QML，打开时才刷新界面。
- 走代理时 IP 定位会定到代理出口（例如显示 Los Angeles），这时请在编辑面板里填城市。
- 腾讯行情和 Yahoo Finance 都是公开网页接口，不保证稳定；美股盘前盘后显示的是上一交易日收盘。Yahoo 的价格以交易所本币显示，不做换算。
- 面板高度不超过屏幕，小组件多时可以在小组件区内滚动。

### 验证

```bash
# 数据进程：约 15 秒后应看到天气、股票、屏幕时间和系统数据
(sleep 14; echo refresh) | timeout 16 python3 -I config/macshell/widgets/widgets.py | tail -1 | python3 -m json.tool | head -40
# 打开通知面板
qs -c MacShell ipc call notifications open
```

实机验证（Yoga Slim 7x，MacShell 0.5.3，Quickshell 0.3.2）：面板中通知下方显示小组件，强调色为 Monterey 壁纸的紫色；编辑模式的晃动、「−」、提示和添加面板正常显示；用户在面板里调整过顺序和尺寸。股市和天气的右键菜单（通过临时代码直接打开）显示正常，股票代码在数据进程里实测解析：`600519`、`00700`、`AAPL`、`^N225`、`7203.T`、`SAP.DE`、`BTC-USD`、`GC=F`、`茅台`、`英伟达`、`toyota` 都能取到价格和分时线。面板截图确认卡片已换成液态玻璃加细边框，天气改为南京后正常显示。AI 用量的数据在数据进程里实测（当天 Claude Code 约 3172 万 tokens、217 次请求，Codex 约 627 万 tokens、5 小时额度 12%、每周 37%）。AI 用量的小 / 中 / 大三种尺寸用离屏预览检查过中英文排版，Codex 额度和 Codex 应用一致（5 小时剩余 100%、本周剩余 63%）。股票拖动排序、菜单里的文字输入和 DeepSeek Key 还需要在面板里实际操作确认。

```bash
# AI 用量（在仓库根目录运行）
python3 -I -c 'import importlib.util as u; s=u.spec_from_file_location("w", "config/macshell/widgets/widgets.py"); m=u.module_from_spec(s); s.loader.exec_module(m); r=m.AiUsage().summary(); print(r["claude"] and r["claude"]["tokens"], r["codex"] and (r["codex"]["tokens"], r["codex"]["primary"]))'
# 代码解析与行情（在仓库根目录运行）
python3 -I -c 'import importlib.util as u; s=u.spec_from_file_location("w", "config/macshell/widgets/widgets.py"); m=u.module_from_spec(s); s.loader.exec_module(m); [print(q["entry"], q.get("symbol"), q["name"], q.get("price")) for q in m.stocks(["600519", "^N225", "SAP.DE", "茅台"])]'
```

### 回滚

恢复安装脚本打印的 `MacBar.qml.bak.silky-widgets-*`，删除 `~/.config/quickshell/MacShell/` 下的 `SilkyWidget*.qml`、`SilkyW*.qml`、`SilkyWidgetsFormat.js` 和 `assets/silky-widgets.py`，然后执行 `qs -c MacShell ipc call macshell reload`。数据文件 `~/.config/silky/widgets.json`、`~/.config/silky/ai-keys.json`、`~/.local/state/silky/screen-time/`、`~/.local/state/silky/deepseek-balance.json` 和 `~/.cache/silky/widgets-weather.json` 可以按需删除。

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

## 改用 Hyprland 模糊（普通模糊）

**效果**：菜单栏的下拉菜单、控制中心、通知中心、应用程序面板、Spotlight 和 Dock 都改用 MacShell 的「普通模糊」样式（`barStyle` / `dockStyle` 为 `"blur"`）。模糊由 Hyprland 在合成时完成，拖动窗口经过 Dock 或打开的面板时，玻璃和窗口在同一帧移动，不再慢半拍。颜色按原来 Liquid Glass 的算法调：背景模糊保持原亮度，深色外观下只叠约 21% 的着色和一层由亮到淡的白色光泽。浅色外观下是白色半透明底加同样的光泽。两种外观随系统切换。代价是没有斜面折射和色散。

**原因**：Liquid Glass 不靠合成器模糊。MacShell 自己抓取玻璃后面每个窗口的画面，在 QML 里模糊、折射后再画出来，窗口位置靠每 33 ms 轮询一次 Hyprland 得到。所以玻璃总比真实窗口落后约 50–90 ms，而且窗口一动 MacShell 就要逐帧重画。菜单栏的 `glassRealtime` 为 `false` 时，菜单背后只是定时截图，根本不是实时的。

**性能对比**：同一台机器（Snapdragon X Elite、Adreno X1-85、2944×1840 @ 90 Hz），用 `hyprctl` 把一个 700×300 的浮动窗口沿 Dock 来回拖 192 步（约 3.1 秒），各测两次。MacShell 的帧时间来自 `QT_LOGGING_RULES="qt.scenegraph.time.renderloop=true"`，GPU 时间来自 `/proc/<pid>/fdinfo` 的 `drm-engine-gpu`：

| 指标 | Liquid Glass | 普通模糊 |
| --- | --- | --- |
| MacShell 重绘 | 90–106 帧/秒 | 约 1 帧/秒（拖动时不用重画） |
| MacShell 帧耗时 | 平均 9–11 ms，p95 22 ms，最长 23 ms | 不到 1 ms |
| MacShell CPU | 23–28% | 0.6% |
| MacShell GPU | 7.2–7.5% | 0% |
| Hyprland CPU | 21% | 24–25% |
| Hyprland GPU | 53% | 61% |

90 Hz 下每帧只有 11.1 ms。Liquid Glass 的 p95 是 22 ms，也就是说拖动时有相当一部分帧赶不上，玻璃会跳帧。改用普通模糊后，MacShell 在拖动期间几乎不工作，模糊交给 Hyprland 在同一帧完成。Hyprland 自己多了约 8 个百分点的 GPU 时间，两者加起来 GPU 总量基本持平，但省掉了 MacShell 的 CPU 和那 50–90 ms 的延迟。

**安装**：从仓库根目录运行（可重复执行）：

```bash
./scripts/install-native-blur.sh
```

脚本会安装 [`config/hypr/silky-native-blur.lua`](../config/hypr/silky-native-blur.lua)，并在 `~/.config/hypr/hyprland.lua` 里 `require` 它。这个文件给 `macbar`（下拉菜单、控制中心、通知）、`macswitch`（窗口切换）、`macwall`（壁纸选择）和 `macosd`（音量 / 亮度提示）图层打开模糊。`macdock`、`macspot`、`macbarbg` 已经由 MacShell 的安装块覆盖。脚本还会把 `~/.config/macbar/settings.json` 的 `barStyle` 和 `~/.config/macdock/settings.json` 的 `dockStyle` 设为 `"blur"`，原文件备份为 `settings.json.bak.<时间>`。之后从「设置 > 工具 > 重新启动」重启 MacShell。`install-macshell-optimizations.sh` 现在也默认使用普通模糊。

[`tune-native-blur.py`](../scripts/tune-native-blur.py) 调整普通模糊的着色（`install-native-blur.sh` 和 `install-macshell-optimizations.sh` 都会调用，前者先把改动的 QML 备份到 `~/.local/state/macshell/silky-backup-native-blur-<时间>/`；也可以单独运行 `python3 scripts/tune-native-blur.py ~/.config/quickshell/MacShell`）：

- Dock 和各面板（`GGlass`）的深色着色从「玻璃不透明度」的 100% 降到 55%，和 Liquid Glass 着色器的 `tintMix` 相同（默认约 21%）。
- 下拉菜单（`LGlass`）从 0.30 + 0.9 × 不透明度降到 0.10 + 0.5 ×（深色）或 0.12 + 0.45 ×（浅色）。
- 菜单栏透明时背后那条渐变（`barFeather`）原来最深 30%，现在最高 4.5%。它在 `macbar` 图层上，高于 `ignore_alpha` 就会被 Hyprland 模糊成一条深色带，压到 0.05 以下后菜单栏几乎完全透明，只剩极淡的一层。
- 三者都加上从上往下变淡的白色光泽，深色 7% → 1.5%，浅色 12% → 3%。
- 顺带把「关于本机」的「更多信息…」按钮从浅色下 75% 的白色块改成 4.5% 的淡灰底（深色下 8% 白），和 macOS 的次要按钮一致。

深色主题的 Hyprland 模糊原来把亮度压到 82%（`decoration:blur:brightness = 0.82`），模糊后的背景先整体变暗，再叠着色，看起来比 Liquid Glass 深很多（Liquid Glass 自己模糊，不经过这一步）。现在深色主题和浅色主题一样用 `1.0`，见 [04](04-macos-theme.md)。

**限制**：模糊强度由 Hyprland 全局的 `decoration:blur`（本机 `size = 7`、`passes = 3`、`vibrancy = 0.45`）决定，MacShell 的「模糊」滑块对普通模糊不起作用。需要 `decoration:blur:enabled = true`。桌面小组件（`MacWidgets`）和设置窗口里的玻璃开关、滑块仍是 Liquid Glass，本机没有启用桌面小组件，设置窗口里的玻璃只在设置打开时运行。

**验证**：Hyprland 0.57.2、MacShell 0.5.3 实机验证：`hyprctl configerrors` 为空。浅色和深色外观下截图检查过 Dock、控制中心和应用程序面板，背后的窗口和壁纸都被模糊。上面的拖动测试中 MacShell 不再逐帧重画。

**回滚**：把两个 `settings.json` 的 `barStyle` / `dockStyle` 改回 `"liquid"`，或用 `.bak.<时间>` 恢复。从 `hyprland.lua` 删掉 `require("hypr.silky-native-blur")` 一行。想恢复深色模糊的压暗，把 `~/.config/omarchy/themes/macos-tahoe-dark/hyprland.lua` 和 `~/.local/state/omarchy/current/theme/hyprland.lua` 里的 `brightness` 改回 `0.82`。然后运行 `hyprctl reload`。着色调整可从安装脚本备份目录（`~/.local/state/macshell/silky-backup-*/MacShell/`）恢复 `MacBar.qml`、`MacDock.qml` 和 `AboutApp.qml`。最后重启 MacShell。

## Dock 玻璃跟随深浅色

[`tune-dock-follow-appearance.py`](../scripts/tune-dock-follow-appearance.py)：MacDock 原来把 `dockDark` 写死为 `true`，Dock 玻璃固定深色——dockglass.frag 的 `dark` 着色、普通模糊的备用矩形、启动预览条和边缘高光都不随外观变，深浅切换只影响右键菜单、悬停标签和指示点。现在 `dockDark` 跟随 `darkMode`：菜单栏的外观一变（主题切换 hook、Dock 设置里的「外观」、「自动」模式和 `color-scheme` 监听都会同步它），Dock 玻璃就在浅色 / 深色之间整体切换。

- **安装**：`install-macshell-optimizations.sh` 会自动应用。单独应用：`python3 scripts/tune-dock-follow-appearance.py ~/.config/quickshell/MacShell`，然后重载 MacShell（设置 > 工具 > 重新启动，或 `qs -c MacShell ipc call macshell reload`）。
- **验证**：浅色外观下 Dock 玻璃应为白色半透明着色，深色下回到原来的深色。Hyprland 0.57.2、MacShell 0.5.3 实机验证：浅色外观重载后截图，Dock 玻璃变亮，与壁纸和浅色模式一致。
- **回滚**：从 `~/.local/state/silky-omarchy/backup-dock-appearance-<时间>/MacDock.qml` 恢复（安装脚本场景用 `~/.local/state/macshell/silky-backup-*/MacShell/`），重载 MacShell。

## Dock 液态玻璃插件（原型）

Hyprland 在全屏时会隐藏 Dock 图层，图层仍可能处于已映射状态。插件 0.2.2 使用和合成器相同的可见性判断，避免在全屏窗口上留下只有玻璃的 Dock 轮廓。用 `./scripts/install-dock-glass-plugin.sh` 更新，进入真正全屏检查 Dock 完全隐藏，再退出确认玻璃恢复。安装器备份同版本的旧插件文件。

**效果**：Dock 与 MacShell 菜单栏浮层（左上角苹果菜单、应用下拉菜单、Wi-Fi、蓝牙、音量、电池/状态、控制中心、通知中心及通知横幅）以及其他浮层（Spotlight / 应用面板 `macspot`、窗口切换器 `macswitch`、壁纸选择 `macwall`、音量/亮度浮窗 `macosd`）统一改由 Hyprland 插件在合成同一帧时画出 Liquid Glass 的斜面折射、色散和边缘高光，拖动窗口经过时同帧跟随、没有延迟，MacShell 也不再逐帧抓取窗口。顶部菜单栏细条本身（`macbarbg`）保持原生模糊不变。需要 MacShell 处于普通模糊样式（`barStyle` / `dockStyle` 为 `"blur"`）。

插件 0.4.0 的关键改进（升级为 macOS 26/27 光学液态玻璃，并新增控制中心独立悬浮气泡材质）：
- 新增第 3 种材质 `kind = 2`（`cc_*` 控制中心悬浮气泡），在 [`SilkyGlassMarker.qml`](../config/macshell/SilkyGlassMarker.qml) 里把单层最多上报矩形数从 16 提升到 24，支持无外框大底板的悬浮气泡模式。
- 着色器升级为更贴近 macOS 26/27 的物理光学模型：**Convex Squircle 曲面高度场 $h(u)=(1-(1-u)^4)^{1/4}$ + 真实 Snell 定律向内折射（折射率 1.50）**。平坦区偏移严格为 0（穿过玻璃的窗口边框与外部严格对齐成一条直线），凸面倒角区把视线向玻璃内部弯折，自然把玻璃下方的按钮或色彩倒映到弧形边缘上，不再把外部壁纸向内拽造成错位；同时搭配边缘自适应模糊、细微色散与 360° 精细高光描边，Dock、下拉菜单、通知中心、Spotlight 和控制中心同步受益。
- [`dock-glass.conf`](../config/silky-omarchy/dock-glass.conf) 支持三组热调前缀：无前缀（Dock，`kind = 0`）、`menu_`（菜单/通知/Spotlight，`kind = 1`）、`cc_`（控制中心独立气泡，`kind = 2`）。

插件 0.3.0 的基础能力：
- 覆盖图层扩展到 `macdock`、`macbar`、`macspot`、`macosd`、`macswitch`、`macwall`（排除 `macbarbg`）。插件成功加载时，[`config/hypr/silky-dock-glass.lua`](../config/hypr/silky-dock-glass.lua) 自动关闭这些图层的 Hyprland 原生模糊，避免控制中心、通知中心内层半透明卡片出现双重模糊；插件未加载时自动保留原生模糊回退。
- 按单矩形分别做 `requiresFullDamage` 损伤判断和 `glBlitFramebuffer` 背景拷贝，多个弹窗相距较远时不再合并成覆盖全屏的大外包框。
- [`SilkyGlassMarker.qml`](../config/macshell/SilkyGlassMarker.qml) 支持 `poke` 立即触发轮询（弹窗打开同帧上报，不再等 120 ms 定时器），并把标记像素统一放进独立子容器以消除 Qt `stackAfter` 警告；当大面板包住内层卡片时，内层卡片自动保留自身 Qt 半透明叠层，不重复折射。

**为什么能做到无延迟**：macOS 的 Liquid Glass 由合成器 WindowServer 在合成一帧时直接读取刚画好的下层像素，所以没有延迟。Wayland 不允许客户端读取自己下面的画面，MacShell 只能截取窗口、轮询位置，再交给合成器显示，至少慢 1–2 帧。所以要做到无延迟，只能在合成器里实现：[`plugins/silky-dock-glass`](../plugins/silky-dock-glass/main.cpp) 是一个 Hyprland 插件，做法如下：

1. Hyprland 0.57 在 aarch64 上不支持函数钩子，插件只用公开的渲染阶段事件：在 `RENDER_POST_WINDOWS`（窗口已排进渲染队列，Top 层还没有）插入一个渲染元素。
2. 这个元素执行时，帧缓冲里正好是这一帧 Dock 下面的画面。插件把 Dock 输入区域附近的一段以半分辨率复制出来（`glBlitFramebuffer`），生成 mipmap。注意 Hyprland 只绑定绘制帧缓冲，读取帧缓冲必须手动绑到同一个，否则读到的是上一帧的旧缓冲（会把 Dock 图标自己折射进去）。
3. 着色器移植自 MacShell 的 `dockglass.frag`：圆角矩形斜面、按 Snell 定律折射、边缘色散、从 mipmap 采样的模糊、自适应着色和边缘高光。默认值按 macOS 27 的 Dock 调过：模糊只有 6 px、着色 10%（深色外观 22%，与 macOS 的深色玻璃一样略深），透明度高，能看清背后的内容；边缘弯折带宽 14 px、折射强度 20：只有这条窄带有透镜效果，中间是只模糊不变形的平面玻璃。边缘的折射保持背景连续：位移在玻璃边缘和斜面内侧都是 0，在斜面中间最大，方向朝外，所以边缘附近的内容被拉伸到整个斜面上，像透镜一样；位移的变化率小于 1，画面不会折返。最初照搬 `dockglass.frag`：按 Snell 定律在斜面上折射，位移在最外缘最大（约 50 px），边缘两侧的像素显示相距 50 px 的内容，于是玻璃边缘处画面跳变，玻璃外紧挨着的一条背景又被压扁着在斜面里出现一次（例如壁纸的斜线进入 Dock 时出现重复的亮带）。只把方向改成向外也只是换了一边重复。`thickness` 控制拉伸强度（峰值位移为它的 0.32 倍，最多为斜面宽度的 30%），负值向另一侧拉伸。

对照方法：把参数全部设为中性（`blur`、`tint`、`thickness`、`dispersion`、`magnify`、`lift`、`rim` 为 0，`saturation` 为 1）时，Dock 下的画面和卸载插件时逐像素一致，说明采样位置正确，剩下的观感差别都来自光学效果。拿壁纸原图对照时，斜线穿过 Dock 会弯成 S 形，原因是整块玻璃的纵向放大（`magnify` 0.04）加上上下边缘方向相反的拉伸。默认值因此改为 `magnify = 0`、`thickness = 20`（原为 0.04 和 52），斜线基本保持笔直，只在边缘有轻微弯曲。斜面深度不超过 Dock 半高的 80%：之前斜面最深约 46 px，而 Dock 只有约 70 px 高，上下两条斜面在中线重叠，中线处“最近的边”从上沿换成下沿，位移从“向上拉”突然变成“向下拉”，Dock 中间出现一条横向撕裂，看起来像上下分层（叠在窗口上时最明显）。现在中线附近没有位移，是完整的平面玻璃。之后又发现窗口滑过时 Dock 中部也在变形：`bezel` 原来还要乘 1.45，即使有上限也占到半高的 80%，上下两条弯折带合起来覆盖了 Dock 的大部分。现在 `bezel` 就是弯折带的实际宽度（默认 14 px，最多半高的 60%），中间约六成高度不再变形。同时把色彩上的改动减到最小（`saturation` 1.05、`lift` 0.015、`dispersion` 0.06，原为 1.15、0.03、0.10），玻璃下的壁纸颜色和周围基本一致。之后 Hyprland 照常在上面画 Dock 图层（图标）。
4. Dock 放大图标时形状每帧都变。MacDock 把玻璃的位置、尺寸、圆角和深浅色写进自己图层最底一行的 45 个像素里（每个像素 alpha 为 1–4 / 255，表示 2 bit，肉眼看不见）。插件的顶点着色器直接从 Hyprland 即将绘制的同一个缓冲里解码，所以形状和折射总在同一帧。
5. 复制的背景必须全部来自这一帧：只要玻璃折射范围内有变化，插件就把整块玻璃区域加进这一帧的损伤区域（不是整个屏幕，整屏重绘会让 Hyprland 重新模糊所有表面）。

**性能**（实机，Snapdragon X Elite、2944×1840 @ 90 Hz，和[上一节](#改用-hyprland-模糊普通模糊)同样的拖动测试，每种 3 次取平均）：

| 拖动窗口经过 Dock | MacShell CPU | MacShell GPU | Hyprland CPU | Hyprland GPU | 延迟 |
| --- | --- | --- | --- | --- | --- |
| MacShell Liquid Glass（旧） | 23–28% | 7% | 21% | 53% | 50–90 ms |
| 普通模糊 | 约 1% | 0% | 24% | 54% | 0 |
| 插件 Liquid Glass | 约 1% | 0% | 25% | 63% | 0 |

画面静止时（只有别处的窗口在更新），插件只多约 1 个百分点的 Hyprland GPU（45.4% 对 44.4%）。原型最初请求整屏损伤，拖动时 GPU 为 78%，静止时也多 18 个百分点；改为只损伤玻璃区域后降到上表的数值。半分辨率复制和只在边缘做色散对 GPU 没有可测的影响，保留是因为更省显存。和旧 Liquid Glass 相比，GPU 总量相当（旧方案 MacShell 7% + Hyprland 53%），但 MacShell 的 CPU 从 25% 左右降到 1%，并且没有延迟。

**安装**：先用 `install-native-blur.sh` 切到普通模糊，再从仓库根目录运行：

```bash
./scripts/install-dock-glass-plugin.sh
```

脚本按已安装的 Hyprland 头文件编译插件，装到 `~/.local/lib/silky-omarchy/silky-dock-glass-<版本>.so`，安装 [`config/hypr/silky-dock-glass.lua`](../config/hypr/silky-dock-glass.lua) 并在 `hyprland.lua` 里 `require`（登录时自动加载），立即加载插件。它还会运行 [`tune-dock-glass-plugin.py`](../scripts/tune-dock-glass-plugin.py)（MacDock 写隐藏标记、不再画自己的着色），并在 `~/.config/macshell/env` 里加上 `export SILKY_DOCK_GLASS_PLUGIN=1`。改动的 `MacDock.qml` 和 `env` 备份在 `~/.local/state/macshell/silky-backup-dock-glass-<时间>/`。之后从「设置 > 工具 > 重新启动」重启 MacShell。Hyprland 更新后要重跑脚本。依赖 `g++`、`make`、`pkg-config` 和 Hyprland 头文件。

**调参**：安装脚本在 `~/.config/silky-omarchy/dock-glass.conf` 不存在时放一份带注释的[默认配置](../config/silky-omarchy/dock-glass.conf)，以后不会覆盖。每行一个 `键 = 值`：不带前缀的键控制 Dock（`blur`、`tint`、`tint_dark`、`bezel`、`thickness`、`dispersion`、`magnify`、`saturation`、`lift`、`rim`），加 `menu_` 前缀的键控制菜单栏与各浮层，加 `cc_` 前缀的键控制控制中心独立悬浮气泡。保存后插件在 1 秒内重新读取，不用重载 Hyprland。删掉某行即恢复默认值。

**限制**：

- 顶部菜单栏细条（`macbarbg`）、Dock 右键菜单与悬停标签仍保持原生模糊。
- 玻璃参数不跟随 MacShell 的玻璃滑块，改在 `~/.config/silky-omarchy/dock-glass.conf` 里调（见上方「调参」）。
- 依赖 Hyprland 0.57 的内部渲染接口（渲染阶段事件、渲染元素、`requiresFullDamage`），升级 Hyprland 后可能需要改代码。
- 设置了 `SILKY_DOCK_GLASS_PLUGIN=1` 但插件没加载时，已接管图层没有插件底板（需重跑安装脚本或关闭该环境变量）。
- 只在单显示器、无旋转、缩放 2 的内屏上验证过。

**验证**：实机验证（Hyprland 0.57.2、MacShell 0.5.3、插件 0.4.0）：`hyprctl configerrors` 为空，`hyprctl plugin list` 显示 `silky-dock-glass` 0.4.0；`MacShell.log` 重载后无 QML 报错或 `stackAfter` 警告；实机截取控制中心独立气泡与 Dock 确认边缘凸透镜折射、细微色散、360° 镜面高光环、纯白激活态圆钮与顶部菜单栏细条（`macbarbg`）均正常。

**回滚**：从 `hyprland.lua` 删掉 `require("hypr.silky-dock-glass")`，运行 `hyprctl plugin unload ~/.local/lib/silky-omarchy/silky-dock-glass-<版本>.so` 并 `hyprctl reload`。从备份目录 `~/.local/state/macshell/silky-backup-dock-glass-<时间>/` 恢复 `MacDock.qml`、`MacBar.qml` 和 `~/.config/macshell/env`（或删掉 `SILKY_DOCK_GLASS_PLUGIN=1` 一行），然后重启 MacShell，所有浮层回到普通模糊。

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

## 90 Hz 下拖动窗口卡顿

在 Snapdragon X Elite（Adreno X1-85）、Hyprland 0.57.2、2944×1840 @ 90 Hz 的内屏上，多个窗口重叠时拖动 foot，实时背景模糊让合成器隔一个刷新周期才送显一次。用模拟鼠标拖动浮动窗口，通过 Wayland `wp_presentation` 记录送显时间，foot 从约 45 FPS 提升到 89.6 FPS，帧间隔的第 95 百分位从 22.25 ms 降到 11.13 ms。重载安装后的配置，GTK（Zenity）和 XWayland（XTerm）测试窗口分别测得 89.9 和 89.4 FPS，两者的第 95 百分位帧间隔均为 11.13 ms。

在 [`silky-native-blur.lua`](../config/hypr/silky-native-blur.lua) 中启用这项优化后，浮动窗口的磨砂复用预先模糊的桌面背景，背景主要取自壁纸。Hyprland 使用着色器混合模糊，模糊遍数从 3 降到 2。MacShell 的面板和菜单从实际画面取背景，Dock 折射插件和窗口动画照常运行。[Hyprland 模糊选项](https://wiki.hypr.land/0.57.0/configuring/core/config-options/#blur)

从仓库根目录更新用户配置中的模块，先为已安装的模块留一份备份：

```bash
hypr_dir="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
if [ -f "$hypr_dir/silky-native-blur.lua" ]; then
  cp -a "$hypr_dir/silky-native-blur.lua" "$hypr_dir/silky-native-blur.lua.bak.$(date +%Y%m%d-%H%M%S)"
fi
install -m 644 config/hypr/silky-native-blur.lua "$hypr_dir/silky-native-blur.lua"
```

在 `hyprland.lua` 的 `require("hypr.silky-native-blur")` 前加 `silky_cached_window_blur = true`，然后运行 `hyprctl reload`。`hyprctl configerrors` 应为空，`hyprctl getoption render:use_shader_blur_blend` 应为 `true`。拖动浮动窗口跨过其他窗口，检查窗口跟手程度和磨砂；用 `hyprctl monitors` 核对屏幕模式。回滚时删除这行开关并重新加载，主题原有的模糊参数会恢复。无需重启应用或重新登录。

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

## 截图遮挡档位与右键取消

按 `PrtSc` 进入 Omasnap 截图选择界面。右键退出，拖框时第一次右键取消当前拖动，再点一次退出。

按 `D` 可直接开始画遮挡。点工具栏的盾牌图标或按 `Shift+D`，模式和档位会显示在同一排工具栏内。选定后自动收起，点回截图可直接开始操作。模糊和马赛克各有轻、中、强三档，滚轮也可以调档。模糊参考 MacShell 的预模糊和淡色玻璃层，对选区做近似高斯滤波，轻微降低饱和度并抬高暗部。边缘从选区内部镜像取样。马赛克用分块平均色。切换模式时会记住各自的档位，初次打开默认为中档模糊。按 `V` 选中已有遮挡，也可以当场更换模式和档位，并可撤销。需要完全盖住敏感内容时，选「涂黑」。

[右键与旧磨砂补丁](../patches/omasnap-1.26.2-zh-frost.patch)和[遮挡档位补丁](../patches/omasnap-1.26.2-zh-redaction-levels.patch)、[工具栏补丁](../patches/omasnap-1.26.2-zh-inline-redaction.patch)和[玻璃模糊补丁](../patches/omasnap-1.26.2-zh-glass-blur.patch)适用于 Omasnap 1.26.2 中文源码（上游提交 `6150151`，含 `i18n/omasnap_zh_CN.ts`）。旧磨砂图层仍能按原样重新打开。选中后可以改用新模式。构建依赖 Qt 6、LayerShellQt、Wayland、libdeflate 和 Qt Linguist 的 `lrelease`。从 Silky Omarchy 仓库根目录运行：

```bash
src="$HOME/.local/src/omasnap-zh"
(
  set -e
  frost="$PWD/patches/omasnap-1.26.2-zh-frost.patch"
  levels="$PWD/patches/omasnap-1.26.2-zh-redaction-levels.patch"
  inline="$PWD/patches/omasnap-1.26.2-zh-inline-redaction.patch"
  glass="$PWD/patches/omasnap-1.26.2-zh-glass-blur.patch"
  if ! git -C "$src" apply --reverse --check "$glass" 2>/dev/null; then
    if ! git -C "$src" apply --reverse --check "$inline" 2>/dev/null; then
      if ! git -C "$src" apply --reverse --check "$levels" 2>/dev/null; then
        git -C "$src" apply --reverse --check "$frost" 2>/dev/null ||
          git -C "$src" apply "$frost"
        git -C "$src" apply "$levels"
      fi
      git -C "$src" apply "$inline"
    fi
    git -C "$src" apply "$glass"
  fi
  "$src/bin/test"
)
```

测试通过后，备份旧程序并替换本机中文版。下一次启动生效。

```bash
cp -an "$HOME/.local/bin/omasnap" "$HOME/.local/bin/omasnap.pre-glass-blur"
install -m 755 "$src/build/omasnap" "$HOME/.local/bin/omasnap"
```

离屏测试覆盖档位渲染、选中后调整、撤销、重新打开和工具栏内联选项的自动收起。使用临时深色列表对比了三档模糊的边缘和颜色过渡。已在 Hyprland 实测右键退出。回滚最新改动时，恢复 `~/.local/bin/omasnap.pre-glass-blur`，并对玻璃模糊补丁执行 `git apply -R`。

## 独立截图贴图

截图标注后按 `P` 或 `Ctrl+P`，也可以点预览上的图钉把它变成正式贴图。本机的 `Shift+PrtSc` 直接贴出剪贴板里的图片。正式贴图按原比例显示完整图片，大图初始适配到可用屏幕范围。新贴图出现在鼠标附近，可直接拖走。

右键菜单提供复制、保存到截图目录、编辑、显示文件夹、不透明度和关闭。滚轮放大缩小，`Alt` 加滚轮按 1% 微调，`Ctrl` 加滚轮调不透明度。中键恢复原始大小，大图仍会适配屏幕。双击或按 `Esc` 关闭，`Shift` 加拖动可将 PNG 拖到其他应用。

右键菜单和不透明度子菜单使用圆角玻璃面板、细描边和高对比文字。日间与夜间配色读取 MacShell 使用的系统 `color-scheme`。已打开的菜单也会跟随变化，背景虚化由 Hyprland 的弹出菜单模糊提供。

[贴图补丁](../patches/omasnap-1.26.2-zh-standalone-pin.patch)和[玻璃菜单补丁](../patches/omasnap-1.26.2-zh-pin-glass-menu.patch)适用于本机 Omasnap 1.26.2 中文源码，使用上节的构建依赖。缩放和置顶依赖 Hyprland。以下命令从 Silky Omarchy 仓库根目录运行。

```bash
src="$HOME/.local/src/omasnap-zh"
patch="$PWD/patches/omasnap-1.26.2-zh-standalone-pin.patch"
(
  set -e
  glass="$PWD/patches/omasnap-1.26.2-zh-pin-glass-menu.patch"
  if ! git -C "$src" apply --reverse --check "$glass" 2>/dev/null; then
    git -C "$src" apply --reverse --check "$patch" 2>/dev/null ||
      git -C "$src" apply "$patch"
    git -C "$src" apply "$glass"
  fi
  "$src/bin/test"
  cp -an "$HOME/.local/bin/omasnap" "$HOME/.local/bin/omasnap.pre-pin-glass-menu"
  install -m 755 "$src/build/omasnap" "$HOME/.local/bin/omasnap"
)
```

下次新建贴图时生效。离屏测试覆盖预览转为正式贴图、缩放、恢复大小、不透明度和右键菜单。已在 Hyprland 0.57.2 实测竖图完整显示、滚轮缩放、中键恢复和右键菜单。在独立的设置会话内实测了打开菜单时的日夜切换。回滚玻璃菜单时恢复 `~/.local/bin/omasnap.pre-pin-glass-menu`，并用 `git apply -R` 撤回玻璃菜单补丁。

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

## 打开窗口时壁纸闪现与「关于本机」实时磨砂

[窗口配置](../config/hypr/silky-macshell-windows.lua)关闭 Hyprland 的 `windowsIn` 和 `fadeIn`，让新窗口直接以完整尺寸和不透明度显示，同时为 Firefox 系浏览器（`firefox-based-browser` 标签）关闭合成器模糊（`no_blur`）。配套的 [GTK3 CSD 样式](../config/gtk-3.0/silky-csd.css) 去掉 `window.csd decoration` 的透明阴影外边距（由 `~/.config/gtk-3.0/gtk.css` 引入），避免 Firefox 等 GTK3 CSD 窗口在首帧先闪出一圈虚化光晕和约 26 px 的偏移。窗口关闭、工作区切换和 Dock 最小化保留各自的动画。[模糊规则](../config/hypr/silky-native-blur.lua)给「关于本机」单独关闭 `xray`，让面板实时取样其下方窗口。此前它使用了浮动窗口的壁纸缓存。

从仓库根目录运行 `./scripts/install-macshell-optimizations.sh`，再运行 `hyprctl reload`。在 Hyprland 0.57.2 的 Wayland 会话中，前后逐帧对比打开重叠测试窗口与 Firefox，检查底层窗口是否透过开场淡入露出以及 Firefox 首帧是否严丝合缝。把「关于本机」叠放在不同颜色的测试窗口上，磨砂底色应随下方窗口变化。回滚时从安装器的 `~/.local/state/macshell/silky-backup-*/settings/` 恢复这两个 Lua 文件及 `gtk3.css`（或移除 `~/.config/gtk-3.0/gtk.css` 中的 `@import url("silky-csd.css");`）并重载 Hyprland。

## “关于本机”里 Edge 版本像降级

切到 Edge 渠道后，Omarchy 从 `omarchy` 包（如 `4.5.0-3`）换成 `omarchy-dev` 包。后者的版本号由 master 分支的 `git describe` 生成，例如 `4.0.0.r8103.ge4635a4`：`4.0.0` 只是 master 上能找到的最近一个 tag，`r8103` 是之后的提交数，`ge4635a4` 是提交哈希。正式版的 tag 不在 master 上，所以“关于本机”原样显示这个版本号时，比 4.5.0 更新的构建看起来反而像降级了。

现在只要装的是 `omarchy-dev`，这一行就改成显示渠道和短提交，例如 `Edge · e4635a4`，后面跟着小号淡色的包构建日期 `11-20 构建`，样式和“12 核”“8448 MT/s”这类辅助信息一致。渠道读取 `omarchy-channel-current`，`dev` 显示为 `Dev`，其余都显示为 `Edge`。构建日期取自 `/var/lib/pacman/local/omarchy-dev-*/desc` 的 `%BUILDDATE%`，按本地时区格式化为 `月-日`。稳定版和 RC 仍显示原来的版本号。英文界面显示 `11-20 build`。

**实现**：[`scripts/tune-about-version.py`](../scripts/tune-about-version.py) 修改三个文件：`assets/about-info.sh` 额外输出 `osver` 和 `osbuilddate`；`AboutApp.qml` 把日期放进辅助文字；`lang/zh-CN.js` 增加 `"%1 build"` 的翻译。脚本可以重复执行，`install-macshell-optimizations.sh` 每次都会运行它。

**安装**：在仓库根目录运行 `scripts/install-macshell-optimizations.sh`。安装脚本会备份这三个文件，任何 MacShell 版本都可以运行（见[版本](#版本)）。只想单独应用这一项时，先手动备份三个文件，再直接运行调整脚本：

```bash
python3 scripts/tune-about-version.py ~/.config/quickshell/MacShell
qs -c MacShell ipc call macshell reload
```

**验证**（MacShell 0.5.3、`omarchy-dev 4.0.0.r8103.ge4635a4-1`、Edge 渠道，已实机验证）：

```bash
sh ~/.config/quickshell/MacShell/assets/about-info.sh | grep -E '^os(ver|build)'
qs -c MacShell ipc call about open
```

`about-info.sh` 输出的最后一条 `osver=` 应为 `Edge · e4635a4`，同时还应有 `osbuilddate=11-20`。“关于本机”的 Omarchy 一行应显示 `Edge · e4635a4`，后面跟着小号淡色的 `11-20 构建`。稳定版 / RC 渠道的显示还没有实机测过。按脚本逻辑，没有 `omarchy-dev` 时会显示原版本号。

**回滚**：从备份目录（安装脚本的 `~/.local/state/macshell/silky-backup-*/MacShell/`，或手动备份的位置）恢复 `AboutApp.qml`、`assets/about-info.sh` 和 `lang/zh-CN.js`，然后运行 `qs -c MacShell ipc call macshell reload`。

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

[`tune-control-center-glass.py`](../scripts/tune-control-center-glass.py)：默认采用类似 macOS 26/27 的独立悬浮液态玻璃气泡样式（`ccStyle: "tiles"`），Wi-Fi / 蓝牙 / 专注模式 / 显示器 / 声音等控件均以全圆角胶囊或正圆独立悬浮在桌面上，通过 `silky-dock-glass` 的 `kind = 2`（`cc_*`）材质渲染清透边缘折射与 360° 亮边，开启态 1×1 圆钮切换为纯白实心底且自动隐藏底层重复描边；仍可在 MacShell 设置（或 `~/.config/macbar/settings.json` 把 `ccStyle` 设为 `"macos"`）随时切回统一的毛玻璃大底板模式。深浅外观跟随系统切换。

[`tune-display-controls.py`](../scripts/tune-display-controls.py)：控制中心新增「显示」页，入口和「声音」一样（左边点名称进页面，右边直接拖滑条）。页面里有亮度滑条，以及「夜览」和「外观」（深色 / 浅色）两个开关。

## Dock 图标与设置窗口

MacShell 的 Dock 图标采用 Silky 的深紫玻璃圆角底和银紫色 M 字标记，方便在 52 px 的默认尺寸下辨认。MacShell 的窗口切换器和设置页也使用这枚[图标](../config/icons/macshell-logo.png)。

从仓库根目录运行 `./scripts/install-macshell-optimizations.sh` 会将图标安装到 `~/.config/quickshell/MacShell/assets/macshell-logo.png`。运行 `qs -c MacShell ipc call macshell reload` 后打开 MacShell 的设置，在 Dock 右侧检查 MacShell 图标。要恢复原图，从安装器打印的备份目录复制 `MacShell/assets/macshell-logo.png` 回原位，再重载 MacShell。

- [`tune-dock-icons.py`](../scripts/tune-dock-icons.py)：Dock 图标的光学缩放以图标中心为基准，悬停放大时不会往一边偏；旋转（抖动）的支点不变。
- [`tune-settings-scroll.py`](../scripts/tune-settings-scroll.py)：设置窗口左侧导航列表原来滚轮一格只动几像素。现在每格 140 px，多格累加后逐帧平滑过去；触控板的像素级滚动仍交给列表自己处理，保留原生惯性。

### Dock 中文件打不开

Omarchy 移除 Nautilus 并将目录默认应用切换为 Folio 后，旧的 Dock 固定项仍会尝试启动 Nautilus。残留的桌面入口仍能显示「文件」图标，Dock 会在等待窗口时反复跳动。

从仓库根目录运行 `./scripts/install-macshell-optimizations.sh`。如果 Nautilus 已卸载，且 Folio 已安装并设为目录默认应用，[迁移脚本](../scripts/migrate-macshell-files.py)会将 `~/.config/macdock/pinned.json` 中的 Nautilus 固定项换成 Folio，保留其他图标顺序。脚本也会移除旧的 Silky Nautilus 中文快捷键覆盖，让 Hyprland 恢复系统的文件快捷键，并将旧的 Silky 桌面入口归档为备份，避免它继续出现在应用面板。

只修复这三个设置时可运行 `python3 scripts/migrate-macshell-files.py`。更新后执行 `hyprctl reload` 和 `qs -c MacShell ipc call macshell reload`。点击 Dock 中文件图标应打开 Folio，再点击应激活已有窗口。也可用 `Super+Shift+F` 验证快捷键。若已重新安装 Nautilus 并要恢复旧设置，将脚本打印的 `.bak.folio.*` 文件复制回原位，再重载 Hyprland 和 MacShell。

## 焦点切换时玻璃背景跟着刷新

[`tune-glass-stacking.py`](../scripts/tune-glass-stacking.py)：玻璃背后窗口的“指纹”原来只看位置和大小，点击切换浮动窗口的前后顺序时，玻璃里还是旧的叠放顺序。现在把焦点顺序（`focusHistoryID`）也算进去，切换焦点时立即刷新；窗口改标题（终端、浏览器标签页、播放器）依然不会唤醒 60 Hz 刷新。

### 文件右键菜单的常用目录

启用 Folio 定制后，在 Dock 右键点「文件」，可直接打开主文件夹、桌面、文档、下载或图片。菜单读取系统的用户目录设置。如果某个快捷目录配置成主文件夹，会优先使用现有的同名目录，避免重复指向主文件夹。使用 Folio 安装脚本或 MacShell 优化安装脚本更新菜单以后，重载 MacShell 即可验证。回滚时恢复安装器备份的 `MacDock.qml` 和 `lang/zh-CN.js`，再重载 MacShell。

## 窗口最小化

点 Folio 左上角的黄灯，窗口会沿类似「神奇效果」的弧形轮廓收拢到 Dock 分隔线和废纸篓之间，留下独立的窗口缩略图。点击缩略图，原窗口会从同一位置放大回来。动画时长设为 480 ms。Folio 异步抓取一张尺寸受限的窗口画面，文件保存在 Wayland 会话的运行目录，关闭该窗口后清理。MacShell 通过渲染线程驱动网格变形，并将叠层限制在窗口到缩略图的范围内。原窗口在叠层就绪后才移入隐藏工作区，移走时禁用 Hyprland 的窗口动画，避免交接时叠加两套效果。Dock 缩略图占位和间距在 180 ms 内线性展开，恢复窗口时线性收回。先前已最小化的 Folio 窗口也会有可点击的恢复项。

旧版曲线让上下沿分段启动，下沿过早缩到目标宽度，尾段还会把窗口画面压暗。新版让各行从起步到落点持续移动，下沿先收拢，窗口全程保持原亮度，并在缩略图或真实窗口接手时短暂保留叠层。用同一组起点和落点按 90 Hz 对着色器轨迹采样，上沿单帧最大位移由约 45 降至 13 个逻辑像素。

收起时，MacShell 先在原位置提交原尺寸快照，等待画面送出后才把真实窗口移入隐藏工作区，确认移走后再开始变形。[Folio 的 Hyprland 规则](../config/hypr/silky-folio.lua)关闭收起叠层自身的淡入，避免交接时闪过桌面或瞬间变暗。

在仓库根目录运行 `./scripts/install-folio-macos.sh`，再运行 `qs -c MacShell ipc call macshell reload` 并重开 Folio。[缩放组件](../config/macshell/FolioMinimizeFx.qml)安装到 `~/.config/quickshell/MacShell/`。验证时分别在浮动和全屏状态下点黄灯，再点 Dock 缩略图，窗口应回到原工作区和原状态。回滚时先恢复已最小化的窗口，再用安装器报告的备份恢复 MacShell 配置及 Folio 二进制，然后重载 MacShell。

其他应用的通用最小化入口由 [`disable-minimize.py`](../scripts/disable-minimize.py) 管理。
