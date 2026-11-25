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

同一配置文件中还包含外接 `BOE 0x0A52`（3840×2400、EDID 连续 60–120 Hz）的 **110 Hz** 自定义 `modeline`。在 Snapdragon X Elite（`x1e80100`，内核 `7.3.0-77-omarchy`）上，设备树 `display-controller@ae01000` 的 `opp-table` 将 DPU 最高核心时钟限制在 `575 MHz`；`msm` 驱动的 `dpu_crtc_mode_valid` 对 `hdisplay <= 5120` 按双 Layer Mixer（2-LM）与 `1.05` 系数计算，EDID 原生 120 Hz（`1176.01 MHz`）需要 `617.4 MHz/LM > 575 MHz` 且超过 DP 1.4 HBR3 4-lane 未压缩带宽上限（`25.92 Gbps`），因而被内核剔除、仅暴露 60 Hz。沿用该面板 EDID 原厂消隐时序（`4000×2450`）设为 `110 Hz`（`1078.00 MHz`），单 LM 时钟 `565.95 MHz <= 575 MHz`、未压缩带宽 `25.87 Gbps <= 25.92 Gbps`，2026-11-23 实机 `hyprctl reload` 后 `DP-1` 稳定点亮在 `3840x2400@110.00Hz` 且无内核报错。回滚时从 `~/.config/hypr/monitors.lua.bak.*` 恢复并执行 `hyprctl reload`。

## 无线局域网扫描与断线恢复

顶栏、控制中心和「系统设置 → 无线局域网」共用扫描逻辑。打开入口时，若列表尚空会先立即读取 NetworkManager 缓存（约 50–100 ms）显示已连接和周边网络，再在后台按需刷新：距离上次扫描 30 秒内直接复用缓存，超过 30 秒或点击「再次扫描」时通过 D-Bus `RequestScan` 触发扫描并轮询 `LastScan`（最长等待 22 秒，覆盖 WCN7850 三频全扫约 16 秒的耗时；若被 NetworkManager 节流则直接返回最新缓存）。列表已有内容时，后台扫描仅在「网络」标题右侧轻量显示「正在搜索…」，不插入空行也不阻塞点击；仅在列表为空或扫描超时时显示居中提示，超时会保留已有列表并提示「无线局域网扫描未完成，请重试」。顶栏状态轮询和面板的列表轮询只读缓存，连接期间会暂停新的列表扫描。设置页会显示连接进度和失败提示。

2026 年 11 月 22 日的本机故障中，wpa_supplicant 先记录到接入点信标丢失，随后 Qualcomm WCN7850 的 `ath12k_wifi7_pci` 报告发送队列清理失败，NetworkManager 也记录了 `ssid-not-found`。MacShell 原先在发出异步扫描请求后立即读取缓存，导致界面可能过早显示「未找到网络」。补丁修复面板这一行为。驱动、固件和接入点哪一方触发了底层故障仍待复现确认。

在仓库根目录运行，依赖 Bash、Python 3、NetworkManager 的 `nmcli`、systemd 的 `busctl` 和 GNU `patch`。在本机 MacShell 0.5.3 上验证。其他版本可先运行预检。

```bash
./scripts/install-macshell-wifi.sh --check
./scripts/install-macshell-wifi.sh
```

安装器将[补丁](../patches/macshell-wifi-scan.patch)与[扫描助手](../config/macshell/silky-wifi-scan.py)应用到 `~/.config/quickshell/MacShell/`，并重载运行中的 MacShell。`silky-macshell-wifi.hook` 在每次 `omarchy update` 后检查并补回兼容的文件。请保留仓库路径。上游代码改到补丁不匹配时，预检会报错并保留现场。验证时打开顶栏 Wi-Fi 和设置页，确认扫描结束后列表更新。可用下面的命令检查当前接口并请求扫描。需要手动解除软阻止并重新扫描时，可运行 `omarchy restart wifi`。

```bash
nmcli -f DEVICE,TYPE,STATE device
nmcli -f IN-USE,SIGNAL,FREQ device wifi list --rescan yes
```

回滚时先移除 `~/.config/omarchy/hooks/post-update.d/silky-macshell-wifi.hook`，将安装时输出的 `~/.local/state/macshell/silky-backup-wifi.*` 中的 `MacBar.qml`、`MacDock.qml` 和 `lang/zh-CN.js` 恢复到对应位置，再移除首次安装新增的 `assets/silky-wifi-scan.py`，并执行 `qs -c MacShell ipc call macshell reload`。更新后使用匹配当时版本的备份。

## 快速连点系统菜单

左上角图标快速连点时，菜单会从当前动画进度反向，文字、玻璃和缩放同步变化。此前每次打开都会查询前台窗口并重建固定菜单项，淡出后还会销毁玻璃组件。逐帧录制捕捉到文字已经出现、合成器玻璃晚一帧跟上的情况。现在系统菜单复用菜单项，顶栏下拉菜单共用一个动画进度，玻璃标记随透明度更新。「减少动态效果」开启时，菜单立即开合。

左上角系统菜单中的「重新启动」「关机」和「退出登录」现在单击即执行。可用模拟命令验证每项在第一次点击时调用对应操作并关闭菜单。

常规安装由 `scripts/install-macshell-optimizations.sh` 应用本项。只更新菜单时，在仓库根目录备份 `~/.config/quickshell/MacShell/MacBar.qml`，运行以下命令：

```bash
python3 scripts/tune-macshell-system-menu.py ~/.config/quickshell/MacShell/MacBar.qml
qs -c MacShell ipc call macshell reload
```

在 MacShell 0.5.3、Hyprland Wayland 会话下，可将菜单放在同时覆盖亮色壁纸和深色窗口的位置，以不同速度连点图标，再点菜单外关闭，观察文字与磨砂是否一起淡入淡出。已在 2× 缩放、90 Hz 的内屏上录制模拟连点，逐帧检查菜单在壁纸和窗口交界处的开合。回滚时恢复备份的 `MacBar.qml` 并重新加载 MacShell。

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

## 顶栏工作区占用指示

顶栏中间的工作区数字区分三种状态：后台有窗口的工作区在数字正下方显示 3 px 指示圆点（与底部 Dock 的运行中圆点一致）；当前工作区只用半透明圆角胶囊与 `DemiBold` 满亮度文字表示，不再叠加圆点，避免同一状态出现两个记号；后台有窗口的工作区提亮文字（约 90% 不透明度、`Medium` 字重），空工作区保持低不透明度淡字、无圆点。此前后台有窗口与空工作区仅靠 `fg2`（约 62%）和 `fg3`（约 34%）区分，在浅色或彩色壁纸上几乎难以分辨。同时修复了鼠标悬停在非当前工作区时背景始终透明的问题。

常规安装由 [install-macshell-optimizations.sh](../scripts/install-macshell-optimizations.sh) 自动调用 [tune-workspace-indicators.py](../scripts/tune-workspace-indicators.py)。单独应用时，先备份 `~/.config/quickshell/MacShell/MacBar.qml`，然后在仓库根目录运行：

```bash
cp -a ~/.config/quickshell/MacShell/MacBar.qml ~/.local/state/macshell/MacBar.qml.bak.workspace-indicators
python3 scripts/tune-workspace-indicators.py ~/.config/quickshell/MacShell/MacBar.qml
qs -c MacShell ipc call macshell reload
```

脚本幂等，适用于 MacShell 0.5.3（Wayland / Hyprland 会话）。实机验证：在 2× 缩放内屏上同时让工作区 1、2 保持有窗口、工作区 3–5 为空，位于工作区 1 时，截屏确认工作区 1 只有胶囊、没有圆点，工作区 2 数字提亮且底部 3 px 圆点居中锐利，空工作区 3–5 无圆点且反差清晰。

数字右侧的布局图标（[`SilkyWorkspaceLayoutIcon.qml`](../config/macshell/SilkyWorkspaceLayoutIcon.qml)）空闲时与后台工作区数字同为约 90% 不透明度，线宽从 1.2 px 加到 1.3 px，浮动布局里后面那个窗口的描边从 45% 提到 60%，不再比相邻数字淡一截。重新运行 [`install-workspace-layout-ui.py`](../scripts/install-workspace-layout-ui.py) 会安装新图标并把旧的 `fg2` 着色换掉。回滚时恢复备份的 `MacBar.qml` 并执行 `qs -c MacShell ipc call macshell reload`。

## 顶栏随壁纸调整对比度

每台显示器独立读取壁纸顶部，**每个控件**单独选用白字或深色字：左侧每个菜单标题、每个工作区数字、每个托盘图标各自判断，右侧固定的状态按钮（蓝牙、音量、输入法、网速、温度、电池、Wi-Fi、搜索、控制中心、时钟、通知）共用一份判断。左右分色壁纸的分界落在工作区中间时，分界左边的数字用一种颜色，右边的用另一种，不再整组共用一种颜色。系统深浅外观仍用于下拉面板。

只有分界正好穿过某个控件的字形时，才在该控件后面画一块和悬停高亮同尺寸的圆角底板（圆角 6 px，限定在顶栏高度内），不透明度按 WCAG 4.5:1 反推、上限 0.56；此时空工作区的淡字从 53% 提到 76%，以免底板换来的对比又被淡字抵消。判断只看控件中间一半（字形所在处），分界只擦过按钮留白时不画底板。共用一份判断的状态区若明暗混杂，底板覆盖整组，这种情况只在分界恰好落在右侧状态区时出现。

此前的做法是左、中、右三组各取一种颜色，混色时在整组后面铺一层水平羽化、并向桌面下垂 24 px 的暗色或亮色蒙层。工作区组居中，左右分色壁纸的分界总落在它下面，白色一侧被 53% 的黑叠成脏灰，后台工作区的淡字也几乎看不见。

在仓库根目录运行以下命令可单独更新顶栏。[完整安装脚本](../scripts/install-macshell-optimizations.sh) 也包含这项调整。旧版（按组取色）安装会被就地升级。

```bash
python3 scripts/tune-macshell-bar-contrast.py ~/.config/quickshell/MacShell
qs -c MacShell ipc call macshell reload
```

[对比度采样器](../config/macshell/menubar/silky-bar-tone.py) 通过 Python 3 和 ImageMagick 读取壁纸文件，按居中填充计算可见区，再按约 2 个逻辑像素一列输出顶栏高度内亮度的 12%、50%、88% 分位数。[`SilkyBarContrast.qml`](../config/macshell/menubar/SilkyBarContrast.qml) 缓存这些列；每个控件的 `SilkyBarContrast.Palette` 按自己的位置读取对应的列并决定颜色，切换颜色有 200 ms 过渡。菜单标题、工作区和托盘这三个 Repeater 委托各自声明一个同名的局部配色（`barMenuPalette`、`barWorkspacePalette`、`bpal`），委托外的引用仍然指向共用配色，因此其他安装脚本的锚点不受影响。

取样只在壁纸、屏幕尺寸、顶栏高度或底色不透明度变化时运行，切换应用导致菜单宽度变化时不再启动 Python 和 ImageMagick。从 MacShell 设置换图片壁纸后，awww 完成设置就立即查询一次当前壁纸，颜色随壁纸过渡切换，不用再等 4 秒的轮询；其他途径换壁纸仍在下一次轮询（约 4 秒）后更新。Omarchy 背景层可见时，按当前 Omarchy 壁纸取样，其余情况使用壁纸服务报告的各屏路径。识别 Omarchy 背景层需要 `jq`。读取失败（例如视频壁纸没有可读的静态帧）时使用白字，不画底板。

实测环境为 MacShell 0.5.3、Hyprland、awww，2944×1840、2× 缩放的内屏。验证：依次把内屏壁纸换成 `split_L-white_R-black_2560x1440.png` 和 `split_L-black_R-white_2560x1440.png`（2560×1440 的左右黑白各半图），截取顶栏，工作区 1–3 与 4–5 应分别是深色字和白字，分界处没有灰色蒙层；再用分界穿过某个数字的图片测试，只有那个数字后面出现圆角底板。

回滚：脚本会打印备份目录，将其中的 `MacBar.qml`、`SilkyBarContrast.qml` 和 `assets/silky-bar-tone.py` 复制回 MacShell 目录（首次安装还要恢复 `shell.qml`，并删除新增的两个文件），再重载 MacShell。

## 顶栏系统监控

MacShell 0.5.1–0.5.3 可单独安装网速、CPU 温度和电池面板。

```bash
python3 scripts/install-macshell-status.py --check
python3 scripts/install-macshell-status.py
```

网速和温度每 1.5 秒采样，面板显示最近约 1 分钟的趋势。顶栏网速只占一行，与温度同为 12 px `DemiBold`：显示当前较忙的方向和对应箭头（如 `↓ 26K/s`），面板里仍同时显示上传和下载，读屏描述也包含两个方向。另一个方向要明显超过（1.5 倍且大于 1 KB/s）才切换，接近持平时箭头不会每次采样都翻转。按钮按 `↓888K/s` 预留宽度，箭头紧贴数字、整体右对齐，空余落在箭头左侧，读数变化时托盘不会移动；超过 100 MB/s 时才临时变宽。同时请求等宽数字（`tnum`），但本机缺少 `Open Runde`，回退的苹方不支持该特性。此前是上下两行 10 px 的上传与下载，高约 22 px，比其他图标高出一截。箭头和数字都跟随顶栏文字颜色，箭头笔画加粗到与 `DemiBold` 数字相当，上传与下载的青、紫配色只留在面板里。温度计图标从 14 px 加到 16 px，笔画加粗并填实液泡，与 Wi-Fi、搜索等实心图标一样重，和数字之间约 3.5 px，温度按两位数预留宽度。网速、温度两个按钮按字形实际可见范围两侧各留约 6 px，扣除箭头和温度计画布自带的空白，与相邻图标的间距和 Wi-Fi、搜索之间一致（约 8–9 px）。切换规则在 [`SilkyStatusButton.qml`](../config/macshell/status/SilkyStatusButton.qml) 的 `lead`。点击网速可查看应用流量排行和本机 IPv4 / IPv6，点击地址可复制。应用排行使用当前用户可见、采样时仍存在的 TCP 套接字，UDP 和 QUIC 不计入。代理转发的流量可能显示在代理进程名下。

点击温度可查看实时 CPU 占用最高的 10 个进程，以及显卡、固态硬盘、无线网卡和风扇等硬件概览。硬件概览下方显示整机 CPU、内存和系统盘（`/`）的占用率。进程占用按相邻两次采样的 CPU 时间增量计算，100% 表示占满一个逻辑核心。点击电池图标可查看供电来源、功率、电压、电量、容量、循环次数和健康度，内容随硬件暴露的字段变化。MacShell 运行时每 3 秒采样一次，面板中部的「整机功耗」曲线保留最近约 5 分钟，关闭面板后继续采样。只有电池供电时才能测到整机功耗：此时电池放电功率就是整机的耗电。接上电源后，Yoga Slim 7x（Snapdragon X，`qcom-battmgr`）既不报告适配器输入功率（USB-C 端口 `voltage_now` 为 0，`2.00 A` 只是 PD 协商值），也不报告整机负载（不充电时电池 `power_now` 为 0），所以接电源期间曲线留空，「供电来源」里的「整机功耗」显示「接电源时不可读」。充电或放电功率改为数值，放在「电池」分组的「充电功率 / 放电功率 / 电池功率」一行。健康度是电池计量芯片给出的满充容量 `energy_full` 除以设计容量 `energy_full_design`。芯片会不定期重新校准满充容量，健康度可能一次跳几个百分点；长期开着充电上限时校准更少、跳得更明显。为了能回看变化，顶栏每 10 分钟检查一次，每天和满充容量变化时向 `~/.local/state/silky/battery-health.csv` 追加一行（时间、型号、满充/设计容量、健康度、循环次数）。Yoga Slim 7 14Q8X9 可在电池面板拖动滑条设置 55%–100% 的充电上限，点「应用」后通过系统授权写入并校验内核回读。右键电池图标可以切换系统提供的电源模式，所选模式由 Omarchy 按外接电源和电池供电分别记忆。左键打开的「电源与电池」面板在「充电上限」下方也有「电源模式」卡片：省电、平衡、高性能三段分段控件，当前模式落在凸起的滑块上，点一下即切换（与右键面板调用同一个 `omarchy-powerprofiles-set autodetect`，同样按供电来源记忆），切换中标题旁显示「正在应用…」，失败时卡片内提示。原先「供电来源」分组里只读的「电源模式」一行随之隐藏，系统不提供可选模式时才保留。右键面板底部还有「显示电量百分比」开关，关掉后电池里只显示电量条，不显示数字；它就是 MacShell 设置里的 `showBatteryPercent`，会保存到 `~/.config/macbar/settings.json`。

托盘图标统一成和菜单栏其他图标一样的单色线条（随右侧壁纸亮度切换）：按托盘项的 id 或标题换成 `SilkyStatusIcon` 里手绘的图标，目前覆盖 Antigravity（拱形 A 轮廓线条）、Chrome、ChatGPT、Clippy、Netcatty、Remmina、Clash Verge、网易云音乐和微信（id `wechat`，两个叠在一起的对话气泡）。其他应用保持原图标；需要提醒（`NeedsAttention`）时也显示原图标。查托盘 id：`busctl --user get-property <服务> /StatusNotifierItem org.kde.StatusNotifierItem Id`。装完后执行 `qs -c MacShell ipc call macshell reload` 让 MacShell 重新加载。

这三个监控面板（以及右键电池的电源模式面板）与控制中心保持同一套动效和材质：宽度收窄到 `356 px`（与通知中心小组件一致；右键电源模式为 `272 px`），打开时以 `OutBack`（520 ms，overshoot 1.5）从顶部 94% 弹性放大到 100% 并伴随失焦变清晰，关闭时以 `OutCubic`（150 ms）快速收起并锁存关闭前的面板内容与水平锚点；面板通过 `PopGlassCtx` 的 `silkyKind: 2` 复用控制中心同款 `silky-dock-glass` 液态玻璃（圆角 26 px），合成器接管时隐藏外层 `MenuBorder` 与不透明底色遮罩，内部信息卡片也去掉描边，仅以柔和半透明底色分层。回退时在 `silky-dock-glass` 未接管的情况下仍自动显示原有底色与 `MenuBorder`。

顶栏温度计平时与顶栏文字同色，CPU 达到 `65 °C` 才显示琥珀橙、`80 °C` 起显示警示红（`barThermalColor`），整条顶栏保持 macOS 式的单色。温度面板强调色按当前最高 CPU 温度分四段着色（[`SilkyStatusFormat.js`](../config/macshell/status/SilkyStatusFormat.js) 的 `thermalColor`），深浅色主题分别配高对比色调，绿色表示状态最佳：`< 50 °C` 翠绿（清凉最佳）、`50–64 °C` 青蓝（日常正常）、`65–79 °C` 琥珀橙（偏高负载）、`≥ 80 °C` 警示红（高温）；尚未采样时保持中性前景色。面板内的 CPU、内存和系统盘占用圆环及进程负载条沿用同一套四段语义色（`loadColor`）：`< 35%` 翠绿、`35–64%` 青蓝、`65–84%` 琥珀橙、`≥ 85%` 警示红。

## 通知中心小组件

点顶栏铃铛打开的「通知系统」面板里，通知列表下面是一组 macOS 风格的小组件。每个都有小（172×172）、中（356×172）、大（356×356）三种尺寸，两个小组件并排正好是一个中组件的宽度。小组件的强调色取自当前壁纸（和[电池图标](#电池图标)同一个 `wallpaperAccent`），换壁纸后跟着变。

| 小组件 | 小 | 中 | 大 | 数据来源 |
| --- | --- | --- | --- | --- |
| 天气 | 城市、气温、天气、最高 / 最低 | 加体感、湿度、风速和未来 6 小时 | 再加 6 天预报和温度区间条 | [Open-Meteo](https://open-meteo.com/)，无需密钥，15 分钟刷新 |
| 股市 | 第一只代码的走势、价格和涨跌 | 3 只 | 6 只 | A 股、港股、美股用腾讯行情（`qt.gtimg.cn`），其他市场（东京、欧洲、全球指数、加密货币、期货）用 Yahoo Finance，每分钟刷新 |
| 屏幕使用时间 | 今天总时长和前 3 个应用 | 加按小时分布、和昨天对比 | 再加本周 7 天和前 6 个应用 | 本机记录，见下文 |
| 电池 | 本机和设备的圆环（最多 4 个） | 4 个圆环带名称 | 设备列表 | UPower：本机电池、蓝牙鼠标 / 键盘 / 耳机等 |
| 日历 | 星期、日期、农历或节日 | 加本月月历 | 带农历、节日和调休「休 / 班」的整月 | 本地日期和 [`ChinaCalendar.js`](../config/macshell/calendar/ChinaCalendar.js) |
| 系统 | CPU、内存、磁盘进度条（按负载四段着色） | 三个圆环和用量（按负载四段着色） | 再加最近 5 分钟 CPU 曲线、运行时间、负载 | `/proc`、`statvfs("/")` |
| AI 用量 | Claude、Codex、Antigravity 各一行：左侧图标，右侧上排名称、下排并列 `5h` 与 `周` 两个剩余百分比和迷你进度条（各自按剩余额度四段着色；当周额度为 `0%` 时 `5h` 数值与进度条自动置灰弱化） | 三栏，结构相同：图标和名称、主数字、说明、两行明细 | 再加每小时 tokens（Claude、Codex 叠加）和 Codex 5 小时 / 本周额度条与重置时间 | 见下文「AI 用量」 |

通知和小组件各自是一张独立的玻璃卡片。每次打开面板都从列表顶部显示。有通知时，「全部清除」居中放在通知列表和小组件之间，随列表滚动。勿扰入口在控制中心的专注模式。卡片沿用控制中心的模糊、折射和细亮边，接近 Wi‑Fi 面板的通透度。卡片只额外叠一层轻着色，深色外观为 10%，浅色外观为 16%，便于辨认文字。天气卡上半部叠一层淡淡的天色，中、大尺寸把天气描述和最高、最低温合成一行。

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

- **按应用堆叠**（同 macOS）：同一应用的通知叠成一摞，只显示最新一条，下面露出一到两层「纸边」（不额外放置右下角下拉箭头按钮）。点击堆叠中的卡片默认先展开这一摞；展开后上方出现应用名、「收起」和「✕」（清除这个应用的全部通知）。点击单条通知或已展开的通知正文时卡片会轻微收缩，随后执行应用提供的默认动作并移除这一条。点击卡片的关闭按钮、应用的「✕」或「全部清除」时，对应卡片会羽化消失。没有默认动作时，优先切到匹配的应用窗口，也可通过匹配的桌面入口启动应用。开启减少动态效果时，点击和清除均立即执行。
- **只显示最近 3 个应用**：更早的应用收进「还有 N 个应用的通知」，点开后可「收起」。关闭面板时恢复折叠。
- **一个滚动区**：通知和小组件一起滚动，内容区在当前屏幕的 Dock 上方结束。还有内容时，底边会渐隐。滚到末尾可完整看到最后一个小组件和「编辑小组件」。「没有通知」在小组件滚上来时隐藏。

实现：通知列表按 `notifPop.silkyPlan` 分组，用 `silkyY()` 计算带动画的位置。通知和 `SilkyWidgetDeck` 共用 `Flickable`，可用高度根据当前屏幕的 Dock 高度和底部边距计算。普通模糊模式下，silky-dock-glass 0.5.2 起将玻璃裁切在滚动区内，让部分露出的卡片也保留模糊和折射，并和内容一起在底部渐隐。较早版本及 MacShell 自带液态玻璃按卡片可见比例淡出。

展开 / 收起时不再重影。最初的版本里，被折叠的卡片和最新那张叠在同一位置、按同样节奏淡入淡出，而且每张卡片的目标位置取自邻居「正在动画中」的高度，目标一直在变、动画反复重启，于是多张半透明卡片叠在一起。现在：布局只用每张卡片的最终高度（`silkyFinalH`，含应用标题和纸边的最终值），每张卡片只朝一个固定目标滑动一次；折叠卡片的不透明度是过渡进度的三次方，滑出最新那张之后才显现，收起时在滑回之前就消失；每个应用最新那张始终画在它的折叠卡片上面；应用标题、纸边、「还有 N 个应用」按钮和小组件区都以同样的 420 ms 曲线移动。清除动画只给视口内受影响的卡片加羽化遮罩，结束后列表和小组件平滑补位。

用示例通知检查（不发真实通知，只加到列表里，`undemo` 只删除带 `[Silky demo]` 标记的条目）：

```bash
qs -c MacShell ipc call silkynotif demo      # 微信 3 条、邮件 2 条、Slack、日历
qs -c MacShell ipc call notifications open
qs -c MacShell ipc call silkystack toggle wechat   # 不用点击，展开 / 收起某个应用的一摞
qs -c MacShell ipc call silkynotif undemo
```

实机验证：示例通知显示为微信、邮件两摞（带纸边）、Slack 单条和「还有 1 个应用的通知」，下面接小组件，底部卡片淡出。用 `silkystack toggle` 逐帧截图检查了展开和收起：折叠卡片在最新那张下面不可见，收起时不再残留重影。清除一个应用和「还有 N 个应用」的展开需要在面板里点击确认。面板在浅色窗口上方时玻璃会整体变亮，这是玻璃半透明的正常表现。

### 通知中心滚动速度

滚轮每格平滑移动 160 个逻辑像素，连续滚动时步长会累加。触控板保留像素级输入和系统滚动方向，细粒度移动增至 2.2 倍，并在每帧快速追随。触屏保持原生 `Flickable`，手指一旦开始拖动便补足起始位移，松手后减速更缓。到达边界时停止，重新打开面板回到顶部；开启减少动态效果时，滚轮和触控板立即移动到目标位置。[Qt Flickable](https://doc.qt.io/qt-6/qml-qtquick-flickable.html)

与下方微信和横幅修复共用 `python3 scripts/macshell_notification_center.py --install`，由同一个用户服务在更新后恢复。用示例通知验证三种输入，分别检查从卡片滑到小组件、触顶触底，以及重新打开面板。Wayland 会把部分滚轮刻度与触控板报告为同一种设备，脚本根据整格角度和最近是否在连续滑动来判别。

### 微信通知跳转与横幅

在通知中心点击微信正文时，MacShell 会先尝试调用微信提供的默认动作（兼容已失效或不含 `actions` 的通知对象，避免 `TypeError` 中断跳转）。微信缩到托盘时，如果默认动作没有显示窗口，MacShell 会从托盘恢复微信；找到微信主窗口后由 Hyprland 聚焦并置顶（`alter_zorder` `top`），避免浮动布局下被其他窗口遮挡。通知如果没有会话动作，会打开微信主窗口。原先的窗口查找在微信缩到托盘后找不到主窗口，普通激活请求也会受到防抢焦点规则限制。 托盘恢复使用 [Quickshell 的托盘激活接口](https://quickshell.org/docs/v0.3.2/types/Quickshell.Services.SystemTray/SystemTrayItem/)。

通知中心打开时，已有横幅立即收起，通知记录留在列表里。此时到达的所有通知（含紧急通知）直接进入列表。关上面板后，新通知恢复按平时的设置显示横幅。多个显示器共用通知中心状态，其他屏幕上的菜单不会提前恢复横幅。通知卡片（含横幅与通知中心列表）左侧的应用图标改为相对整张卡片垂直居中（`NotifBody` 图标容器由固定 `y: 15` 改为 `anchors.verticalCenter: parent.verticalCenter`），多行通知不再偏在顶部。

从仓库根目录运行 `python3 scripts/macshell_notification_center.py --install`。脚本备份并更新 `~/.config/quickshell/MacShell/MacBar.qml`，随后重载 MacShell。它将维护脚本安装到 `~/.local/libexec/silky-macshell-notifications`，启用同名 systemd 用户路径单元和服务。系统更新或 MacShell 自身更新覆盖文件时，路径单元会重新应用修复。用户服务启动时也会检查。可用 `--check` 检查新版本的结构是否兼容，安装脚本遇到未知结构时会保留原文件并报错。

MacShell 0.5.3 上可关闭微信主窗口使其缩回托盘，然后点击微信通知测试。打开通知中心前发送一条测试通知，打开后再发一条紧急通知，确认两条各出现一次。关闭面板后再发通知，确认横幅恢复。查看更新后自动恢复的记录可运行 `journalctl --user -u silky-macshell-notifications.service`。

回滚时，先运行 `systemctl --user disable --now silky-macshell-notifications.path silky-macshell-notifications.service`。如果首次安装后没有其他 MacBar 修改，恢复首次安装时打印的 `~/.local/state/macshell/MacBar.qml.bak.notifications-*`，再运行 `qs -c MacShell ipc call macshell reload`。有后续改动时，先将备份与当前文件对照，只撤销需要回滚的通知中心改动。

### 通知横幅入场清晰度

MacShell 0.5.3 的横幅会在滑入时对文字和图标做高斯模糊，随着约 770 ms 的动画才逐渐变清晰。新横幅不再创建前景模糊图层，也不在弹出时截屏取色。文字和图标从显露时起就清晰，背景保留玻璃效果。

滑入和淡出分别为 350 ms 和 230 ms。每张卡片的高度和间距随同一段动画变化，连发通知与应用撤回通知时，下面的卡片会随之滑动补位。「减少动态效果」开启时跳过这些动画。

从仓库根目录运行 `python3 scripts/macshell_notification_center.py --install` 即可应用。安装器备份 `~/.config/quickshell/MacShell/MacBar.qml` 并重载 MacShell，更新后的自动恢复与回滚沿用[通知中心修复](#微信通知跳转与横幅)。在 MacShell 0.5.3、Hyprland Wayland 会话下，用 `notify-send` 先发一条中英文测试通知，再连发三条并撤回中间一条，检查入场文字、玻璃背景和剩余卡片补位。实机在 2× 缩放、90 Hz 内屏上对比录制了单条通知和连发撤回场景。调整后测试样本的录屏帧间隔中位数为 11 ms。

### 清除通知的羽化动效

旧版「全部清除」使用了当前 Qt QML 不支持的 `flatMap()`。新版直接按通知历史收集条目，折叠的通知和未展开的应用也会清除，动画开始后到达的新通知会保留。单条、按应用和全部清除共用 280 毫秒的羽化动效。可见卡片轻微向右上漂移，柔边逐步扫过卡片内容。只有视口内的卡片临时使用一层 GPU 纹理，每像素取样一次。开启减少动态效果时立即清除。

按下方步骤重新安装并重载 MacShell。用示例数据分别点单条「✕」和「全部清除」，确认单条操作只移除选中的通知，全部清除后面板显示「无通知」。回退时恢复安装脚本生成的 `MacBar.qml.bak.silky-widgets-*` 到 `MacBar.qml`，再重载。

### 安装

需要 MacShell 0.5.1–0.5.3，并且已安装[顶栏系统监控](#顶栏系统监控)（取壁纸强调色）和农历日历（`ChinaCalendar.js`）。

```bash
python3 scripts/install-macshell-widgets.py --check
python3 scripts/install-macshell-widgets.py
qs -c MacShell ipc call macshell reload
```

安装脚本将 [小组件文件](../config/macshell/widgets/) 复制到 `~/.config/quickshell/MacShell/`。它更新 `MacBar.qml`，在 `shell.qml` 把当前 Dock 传给菜单栏，并在玻璃插件已安装时更新 `SilkyGlassMarker.qml`。改动前备份文件为 `*.bak.silky-widgets-*`。边缘实时模糊需要从仓库根目录运行 `bash scripts/install-dock-glass-plugin.sh` 更新到 0.5.2 或更新版本。重载后滚动到「屏幕使用时间」仅部分露出，检查玻璃模糊和 Dock 间距。关掉面板再打开，确认回到顶部。用示例通知检查按压与单条清除效果。要回退本次更新，恢复对应备份的 `MacBar.qml` 和 `SilkyGlassMarker.qml`，若此前更新了插件也恢复先前备份的插件并重新加载。

### 使用

- 在任意小组件上点右键，弹出菜单：切换「小 / 中 / 大」，移除小组件。天气的菜单里可以填城市（中文、英文都可以，留空按 IP 定位），回车或点别处保存，下方显示当前定位到的城市；股市的菜单里列出关注的代码（显示解析出的名称），点「−」删除，在输入框里输入代码或名称后回车添加，并可切换红涨绿跌 / 绿涨红跌。菜单本身也是磨砂玻璃（同一个液态玻璃材质加一层半透明底）。打开菜单时面板会临时接收键盘输入，按 `Esc` 关闭。
- 点面板底部「编辑小组件」进入编辑：小组件会轻微晃动，点一下按「小 → 中 → 大」切换尺寸，拖动调整顺序，点左上角「−」删除。
- 编辑时下方是「添加小组件」：选类型和尺寸，预览就是实际效果，点预览或「＋ 添加小组件」加入。城市和股票代码在右键菜单里设置。
- 布局和设置保存在 `~/.config/silky/widgets.json`，可以直接编辑，MacShell 会自动读取。

### 屏幕使用时间怎么算

数据进程每 5 秒通过 Hyprland 套接字读一次当前聚焦窗口的 `class`，把这段时间记到该应用和当前小时上。以下时间不计：连续 2 分钟没有键鼠操作（Quickshell `IdleMonitor`，视频播放器等发出的空闲抑制视为在用）、锁屏（`hyprlock` / `swaylock` / `gtklock` 在运行）、休眠。记录按天保存在 `~/.local/state/silky/screen-time/YYYY-MM-DD.json`，每分钟写一次，保留 30 天。应用名和图标按 `class` 匹配桌面入口（`DesktopEntries.heuristicLookup`），匹配不到时显示 `class`。只从安装后开始统计，MacShell 没运行时也不统计。

### AI 用量

「AI 用量」小组件显示 Claude、Codex 和 Antigravity 中 Gemini 模型组的剩余额度。Claude 也可以回退显示 Claude Code 本地 tokens。

- **Claude**：读取桌面端 `~/.config/Claude/plan-usage-history.json` 的最新记录，把已用百分比换算为剩余百分比。每周额度耗尽时，优先显示每周剩余 0%，进度条只留底轨。30 分钟内没有桌面记录时，回退到 Claude Code 日志中仍有效的耗尽状态（启动与跨天时会扫描近 7 天会话日志末尾以保留跨天的 5 小时 / 每周限额）或当日 tokens。额度窗口见 [Claude 用量上限](https://support.claude.com/en/articles/11647753-how-do-usage-and-length-limits-work)。
- **Codex**：读取 `~/.codex/sessions` 和 `~/.codex/archived_sessions` 里今天改动过的会话，tokens 取每个会话今天的 `total_token_usage` 增量；5 小时和每周额度取最新一条带有效窗口且 `limit_id` 为 `codex`（或省略）的 `token_count` 事件里的 `rate_limits`（忽略随后写入的 `limit_id: "premium"` 等 `primary`/`secondary` 为空的记录，避免额度用尽后覆盖成 `—`），和 Codex 应用一样显示「剩余」百分比（100 − `used_percent`）。Codex 只在回复后写入额度，所以如果记录里的重置时间（`resets_at`）已经过了，就按该窗口已重置处理，显示剩余 100%、「窗口已重置」；之前直接显示旧记录，会出现「5h 12% · 0 分钟后重置」而 Codex 应用里是剩余 100% 的情况。重置时间显示为钟点（当天）或日期加钟点。
- **Antigravity** 每 15 秒从已登录的桌面应用本地服务读取 Gemini 模型组的配额。小卡片显示 5 小时剩余百分比和进度条；中、大卡片同时显示每周剩余百分比及 5 小时重置时间。应用未运行或配额不可用时显示「—」。模型分组与额度窗口见 [Google Antigravity 配额文档](https://antigravity.google/docs/cli/commands/usage)。

Claude Code 和 Codex 日志每 15 秒按增量读取。数据进程只在面板上放置「AI 用量」小组件时扫描日志和读取 Antigravity 额度；每次打开通知中心时会立刻触发一次 `refresh-ai` 刷新并在数据变化后即时推送到界面，避免等待后台轮询周期。

logo 来自 [LobeHub Icons](https://github.com/lobehub/lobe-icons) 的 npm 包 `@lobehub/icons-static-svg`（MIT 许可，固定 1.104.0 版）：`claude-color.svg`、`codex-color.svg`、`antigravity-color.svg`。logo 本身是各公司的商标，所以不放进仓库，由安装脚本在首次安装时从 jsDelivr 下载到 `~/.config/quickshell/MacShell/assets/ai-logos/`，只接受不含脚本和外链的纯 SVG。下载失败时小组件用品牌色字母方块代替；之后重新运行安装脚本会补下载。

### 离屏预览

[`scripts/preview-macshell-widgets.sh`](../scripts/preview-macshell-widgets.sh) 用一份真实数据快照（天气取缓存），在 `QT_QPA_PLATFORM=offscreen` 下把小组件渲染成 PNG，不在屏幕上显示任何东西，也不改面板布局。脚本会打印 QML 报错（`TypeError`、`ReferenceError`、属性冲突等）。

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

实机验证（Yoga Slim 7x，MacShell 0.5.3，Quickshell 0.3.2）：面板中通知下方显示小组件，强调色为 Monterey 壁纸的紫色；编辑模式的晃动、「−」、提示和添加面板正常显示；用户在面板里调整过顺序和尺寸。股市和天气的右键菜单（通过临时代码直接打开）显示正常，股票代码在数据进程里实测解析：`600519`、`00700`、`AAPL`、`^N225`、`7203.T`、`SAP.DE`、`BTC-USD`、`GC=F`、`茅台`、`英伟达`、`toyota` 都能取到价格和分时线。面板截图确认卡片已换成液态玻璃加细边框，天气改为南京后正常显示。AI 用量的数据在数据进程里实测（当天 Claude Code 约 3172 万 tokens、217 次请求，Codex 约 627 万 tokens、5 小时额度 12%、每周 37%）。AI 用量的小 / 中 / 大三种尺寸用离屏预览检查过中英文排版，Codex 额度和 Codex 应用一致（5 小时剩余 100%、本周剩余 63%）。股票拖动排序和菜单里的文字输入 还需要在面板里实际操作确认。

```bash
# AI 用量（在仓库根目录运行）
python3 -I -c 'import importlib.util as u; s=u.spec_from_file_location("w", "config/macshell/widgets/widgets.py"); m=u.module_from_spec(s); s.loader.exec_module(m); r=m.AiUsage().summary(); print(r["claude"] and r["claude"]["tokens"], r["codex"] and (r["codex"]["tokens"], r["codex"]["primary"]))'
# 代码解析与行情（在仓库根目录运行）
python3 -I -c 'import importlib.util as u; s=u.spec_from_file_location("w", "config/macshell/widgets/widgets.py"); m=u.module_from_spec(s); s.loader.exec_module(m); [print(q["entry"], q.get("symbol"), q["name"], q.get("price")) for q in m.stocks(["600519", "^N225", "SAP.DE", "茅台"])]'
```

### 回滚

彻底停用时，恢复首次安装前备份的 `MacBar.qml`、`shell.qml` 和当时已安装的 `SilkyGlassMarker.qml`。删除 `~/.config/quickshell/MacShell/` 下的 `SilkyWidget*.qml`、`SilkyW*.qml`、`SilkyWidgetsFormat.js` 和 `assets/silky-widgets.py` 后重载 MacShell。保留 `~/.config/silky/widgets.json` 可在再次安装时沿用布局。

## 应用程序面板交互

[`tune-apps-panel.py`](../scripts/tune-apps-panel.py) 与 [`tune-apps-dock-passthrough.py`](../scripts/tune-apps-dock-passthrough.py)：应用程序面板的鼠标滚轮每格移动 320 像素；触控板双指滚动紧贴手指（平滑系数提高到 65），并在收到 Wayland `axis_stop` 零增量抬指信号时 0 ms 无缝切入指数惯性滑行，消除原先 50 ms 超时定时器带来的松手粘滞感；触摸屏拖动在列表内保持流畅跟手，滑行中点按屏幕立即刹停且不误触图标，越过上下边界支持手机式轻微拉出与回弹（`DragOverBounds`）。关闭 `appsFlick.synchronousDrag` 并为应用图标加入 18 px 位移容差的按下—松开即刻触发，避免触控板快速滑过轻点时被 `Flickable` 误判为拖拽而吞掉点击。

### 打开 / 关闭动画与 Dock 协同

早期版本同时叠加了欠阻尼弹簧（`z = 0.97` 带硬钳位截断）、面板 `114% → 100%` 缩放与单独的 180 ms `zoomMix` 动画、外圈先动的逐图标 `112%` 果冻缩放，以及每帧重算的 32 px `MultiEffect` 全面板高斯模糊，快速反向或松手时会出现肉眼可见的缩放回弹和撞墙顿挫。

重构为 **macOS Tahoe 现代克制风格**：

- **统一临界阻尼无回弹弹簧（`ζ = 1.0`）**：打开（`ω = 28`）与关闭（`ω = 33`）共用同一套按真实帧时间解析步进的临界阻尼方程，并将松手注入速度限制在单调不越界区间内，数学上严格单调收敛、零超调、零回弹，中途连续点击或捏合反向时速度平滑衔接。
- **克制单一缩放与渲染减负**：整块 `appsStage` 仅做 `1.06× → 1.00×` 微幅中心缩放，玻璃（`t^0.85`）与内容（`t`）协调淡入淡出；移除逐图标错峰缩放、移除每帧 32 px `MultiEffect` 离屏模糊及隐藏的双倍全量图标 `Repeater`，毛玻璃直接由 `silky-dock-glass` 合成器插件或单层玻璃负责。
- **后台分批渐进预热**：启动 3 秒静默预热及面板空闲期间，每 20 ms 按行（每次 `appCols` 个槽位）渐进实例化离屏图标，消除首次打开动画结束后的集中实例化卡顿。
- **Dock 直接可点**：面板打开时从 `spotWin` 输入遮罩中精准挖空底部 Dock 胶囊矩形，点击 Dock「应用程序」图标立即丝滑收起或反向，点击其他 Dock 图标直接启动/切换对应应用并自动收起面板，点击其余桌面空白立即关闭面板。

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| 开合或中途反向出现回弹、果冻感 | 欠阻尼弹簧硬截断 + `zoomMix` 与 `t` 双动画相乘非单调 + 逐图标错峰缩放 | 改为单一临界阻尼弹簧（`ζ = 1.0`）与 `1.06× → 1.00×` 整体微幅缩放，移除 `zoomMix`、`tileReveal` 和动态 `MultiEffect` 模糊 |
| 登录后首次打开或打开后 ~650 ms 微卡 | 第一帧集中创建着色器，随后一次性实例化全部离屏图标 | 启动 3 秒后以 0.4% 不透明度静默建好管线，并以 20 ms 分批渐进预热全部图标槽位 |
| 快速点击面板图标或连点 Dock 图标漏响应 | `synchronousDrag` 抢夺微动轻点；全屏 `Overlay` 遮罩遮住 Dock 引发跨层焦点来回切换 | 关闭 `synchronousDrag` 并用 18 px 容差松手即触发；挖空 Dock 胶囊遮罩让点击直达 `MacDock`（详见 [03 · 快速连续点击与 Dock 穿透](03-silky-gestures.md#快速连续点击与-dock-穿透)） |

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
- 菜单栏透明时背后那条渐变（`barFeather`）原来最深 30%，现在最高 4.5%。它在 `macbar` 图层上，高于 `ignore_alpha` 就会被 Hyprland 模糊成一条深色带，压到 0.05 以下后菜单栏几乎完全透明，只剩极淡的一层。[顶栏对比度调整](#顶栏随壁纸调整对比度)会把这条渐变换成 `SilkyBarContrast`，之后脚本跳过这一项，不再因为找不到 `barFeather` 让完整安装的预检失败。
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

插件 0.5.4 的边缘折射与深色底边高光修复：
- **消除深色底部的假白/暖黄高亮带与虚化断层**：此前在黑底白字窗口（如终端、网页或文档）上方打开电池/状态等玻璃面板时，着色器最外缘（`t -> 0`）仍保留 `0.45` 的基础厚度系数和高达 `10.0` 的斜面导数，同时将边缘模糊半径骤降到 `0.55×`、色散拉开到 `±9%`，导致最底边 1–2 px 强行把上方十几像素外的白色文字低模糊折射并色散成暖黄/白色亮边，叠加对称底边高光（`abs(g.y)` 与 `dOpp`）后在纯黑背景上显得突兀。[`plugins/silky-dock-glass/main.cpp`](../plugins/silky-dock-glass/main.cpp) 现让折射光程在最外唇随 `h * smoothstep(0.0, 0.28, u)` 自然收敛回 `0`（斜率上限收紧为 `1 / 0.24`），边缘模糊保持在 `0.86×`–`1.0×` 连续过渡，色散按 `0.45 * lipFade` 克制衰减，并收敛深色模式下底边的镜面高光与加性白光（保留顶部受光与精致 1 px 轮廓线）。已在本机 Hyprland 0.57.2、2× 缩放下编译热加载并截图核对 Dock，无报错、无边缘亮带；电池弹窗在黑底白字上的实际观感可点击顶栏电池图标复核。回滚时用 `~/.local/lib/silky-omarchy/silky-dock-glass-<版本>.so.bak.<时间>` 覆盖并通过 `hyprctl plugin unload` / `load` 切回。

插件 0.5.3 的大面积面板性能优化：
- **大面板自动 8-tap 降采样**：[`plugins/silky-dock-glass/main.cpp`](../plugins/silky-dock-glass/main.cpp) 对逻辑面积超过 `160000 px²`（约 `400×400` 逻辑像素，如应用程序面板、壁纸选择器、展开的 Spotlight）的玻璃自动改用 8-tap 黄金角 Mipmap 圆盘采样并关闭边缘 3× 色散采样，同时保留相同的 Convex Squircle 折射与 360° 高光描边，片元纹理采样量降低 60%–86.7%；Dock、控制中心气泡与常规下拉菜单保持原有 20-tap + 色散不变。
- **跳过空离屏 FBO**：[`tune-dock-glass-plugin.py`](../scripts/tune-dock-glass-plugin.py) 将应用程序面板的 `appsGlassLayer.layer.enabled` 绑定为 `!appsGlass.silkyOwned`，插件接管期间不再为透明底板维护约 2K 分辨率的离屏纹理。
- **静止休眠轮询**：[`SilkyGlassMarker.qml`](../config/macshell/SilkyGlassMarker.qml) 仅在玻璃几何或透明度变化期间以屏幕刷新率运行 `FrameAnimation`，连续 12 帧无变化后自动回退到 120 ms 兜底定时器，并在 `poke`、面板开关（`onPopChanged` / `onLpChanged` / `onVisibleChanged`）及滚动视图 `contentY` 变化时立刻唤醒。实机 90 Hz（2944×1840 @ 2×）下静止打开应用程序面板 3 秒，MacShell CPU 占用从约 11.6% 降至 5.3%–6.0%，背景静止时 Hyprland GPU 耗时从 1538 ms 降至 259 ms，连续开关 8 次 Hyprland GPU 耗时由 2844 ms 降至 1950 ms（背景无额外动画时）。

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

脚本按已安装的 Hyprland 头文件编译插件，装到 `~/.local/lib/silky-omarchy/silky-dock-glass-<版本>.so`，安装 [`config/hypr/silky-dock-glass.lua`](../config/hypr/silky-dock-glass.lua) 并在 `hyprland.lua` 里 `require`（登录时自动加载），立即加载插件。它还会运行 [`tune-dock-glass-plugin.py`](../scripts/tune-dock-glass-plugin.py)（MacDock 写隐藏标记、不再画自己的着色），并在 `~/.config/macshell/env` 里加上 `export SILKY_DOCK_GLASS_PLUGIN=1`。改动的 `MacDock.qml`、`DockGlassPanel.qml` 和 `env` 备份在 `~/.local/state/macshell/silky-backup-dock-glass-<时间>/`。之后从「设置 > 工具 > 重新启动」重启 MacShell。Hyprland 更新后要重跑脚本。依赖 `g++`、`make`、`pkg-config` 和 Hyprland 头文件。

**调参**：安装脚本在 `~/.config/silky-omarchy/dock-glass.conf` 不存在时放一份带注释的[默认配置](../config/silky-omarchy/dock-glass.conf)，以后不会覆盖。每行一个 `键 = 值`：不带前缀的键控制 Dock（`blur`、`tint`、`tint_dark`、`bezel`、`thickness`、`dispersion`、`magnify`、`saturation`、`lift`、`rim`），加 `menu_` 前缀的键控制菜单栏与各浮层，加 `cc_` 前缀的键控制控制中心独立气泡和通知中心独立卡片。保存后插件在 1 秒内重新读取，不用重载 Hyprland。删掉某行即恢复默认值。

### Dock 右键菜单的液态玻璃

Hyprland 插件接管 Dock 时，应用右键菜单和 Dock 共用实时折射、模糊、深浅色着色和边缘高光，读取 `dock-glass.conf` 中同一组无前缀参数。菜单采用插件支持的圆角轮廓。停用插件时恢复原来的带尖角气泡。

从仓库根目录运行 `./scripts/install-dock-glass-plugin.sh` 后重载 MacShell。右键点击 Dock 应用，在窗口和壁纸的交界处检查菜单能否显示背后的折射和模糊，并点击菜单外部确认收起。要单独回滚菜单，恢复安装前备份中的 `MacDock.qml` 和 `DockGlassPanel.qml`，再重载 MacShell。

### 菜单和面板沿用控制中心的玻璃

菜单和面板的默认折射、色散及边缘高光与控制中心气泡一致，面内多保留少量模糊和着色，让设置项和通知文字在复杂背景上易读。合成器接管菜单、Wi‑Fi、蓝牙、音量和通知中心的底板时，这些弹层只显示合成器的细亮边，下拉菜单也会隐藏原有的深色罩层。安装通知小组件后，通知中心使用控制中心材质的独立卡片。

从仓库根目录重跑上面的插件安装脚本。已有调参文件时，可先备份它，再从新版默认配置更新 `menu_*` 行或删除对应的旧覆盖值。已安装通知小组件时，重跑 `python3 scripts/install-macshell-widgets.py`，再重载 MacShell。用同一张壁纸查看菜单、Wi‑Fi 和通知中心，观察文字背后的颜色过渡与边缘的细亮线。回退这次外观改动时，恢复先前的 `dock-glass.conf`、`MacBar.qml` 和 `SilkyWidget.qml`，再重载 MacShell。

**限制**：

- 顶部菜单栏细条（`macbarbg`）与 Dock 悬停标签仍使用原有材质。
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

在 [`silky-native-blur.lua`](../config/hypr/silky-native-blur.lua) 中启用这项优化后，Hyprland 使用着色器混合模糊并将模糊遍数从 3 降到 2，同时默认对普通窗口关闭合成器模糊（`no_blur = true`），仅对真正带半透明磨砂表面的窗口白名单（Folio、Obsidian、Nautilus、「关于本机」与「系统设置」）保留实时背景模糊。配套在 [`silky-macos.lua`](../config/hypr/silky-macos.lua) 中关闭 `hyprbars` 标题栏的实时模糊（`bar_blur = false`）并改用实色底，减少多窗口叠放时的合成开销。MacShell 的面板和菜单照常从实际画面取背景，Dock 折射插件和窗口动画照常运行。[Hyprland 模糊选项](https://wiki.hypr.land/0.57.0/configuring/core/config-options/#blur)

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

## 截图选区避免误触滚动截图

原来的「滚动截图」是选区下方自动出现的按钮。部分选区会让它盖在工具栏上，鼠标按下时优先进入滚动模式。现在圈选后直接使用复制、保存和标注工具。要截长图，圈选前按 `S`，或圈选后按 `Shift+S` 沿用当前区域。按 `?` 可在截图界面查看快捷键。

[滚动截图快捷键补丁](../patches/omasnap-1.26.2-zh-scroll-shortcut.patch)适用于已配置的 Omasnap 1.26.2 中文源码（`6150151`），构建依赖同上。从 Silky Omarchy 仓库根目录运行。更新在下一次打开截图时生效。

```bash
src="$HOME/.local/src/omasnap-zh"
patch="$PWD/patches/omasnap-1.26.2-zh-scroll-shortcut.patch"
(
  set -e
  if ! git -C "$src" apply -R --check "$patch" 2>/dev/null; then
    git -C "$src" apply "$patch"
  fi
  "$src/bin/test"
  cp -an "$HOME/.local/bin/omasnap" "$HOME/.local/bin/omasnap.pre-scroll-shortcut"
  install -m 755 "$src/build/omasnap" "$HOME/.local/bin/omasnap"
)
```

按 `PrtSc` 圈选后，选区底边显示常规工具栏。离屏测试覆盖点击原按钮位置及用 `Shift+S` 打开当前区域的滚动面板。在 Hyprland 0.57.2 的 2 倍缩放会话中，也用模拟键盘输入验证了已安装版本进入滚动面板。回滚时恢复 `~/.local/bin/omasnap.pre-scroll-shortcut` 到 `~/.local/bin/omasnap`，并用 `git -C "$src" apply -R "$patch"` 撤销源码补丁。

## 独立截图贴图

截图标注后按 `P` 或 `Ctrl+P`、点击临时预览上的图钉，或用本机的 `Shift+PrtSc` 贴出剪贴板图片，都会把新贴图加入所在屏幕工作区的右下角。每块屏幕有一叠贴图，可在其工作区之间切换时继续使用。堆叠状态显示完整图片的缩略图，点击后向上展开。点选一张展开的卡片可将原比例图片移到工作区中央。也可以按住任意可见卡片直接拖出，或拖动已取出的图片继续摆放。

拖动取出图片右下角的斜线手柄可等比缩放。右键选「收回右下角」或「销毁贴图」，贴图聚焦时也可以按 `Esc` 销毁。原有的滚轮缩放、`Alt` 加滚轮 1% 微调、`Ctrl` 加滚轮调不透明度、中键恢复原始大小、双击关闭和 `Shift` 加拖动导出 PNG 仍可用。原图超过可用工作区时会等比适配。

右键菜单和不透明度子菜单使用圆角玻璃面板、细描边和高对比文字。日间与夜间配色读取 MacShell 使用的系统 `color-scheme`。已打开的菜单也会跟随变化，背景虚化由 Hyprland 的弹出菜单模糊提供。

[贴图补丁](../patches/omasnap-1.26.2-zh-standalone-pin.patch)、[玻璃菜单补丁](../patches/omasnap-1.26.2-zh-pin-glass-menu.patch)和[卡片堆叠补丁](../patches/omasnap-1.26.2-zh-pin-stack.patch)适用于 Omasnap 1.26.2 中文源码。C++ 界面处理缩略图和输入，Hyprland 播放窗口位移动画并处理原生窗口拖动。每次堆叠操作只批量提交一次窗口位置和层级，闲置时无需逐帧重绘。使用上节的构建依赖，从 Silky Omarchy 仓库根目录运行。

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
  stack="$PWD/patches/omasnap-1.26.2-zh-pin-stack.patch"
  git -C "$src" apply --reverse --check "$stack" 2>/dev/null ||
    git -C "$src" apply "$stack"
  "$src/bin/test"
  cp -an "$HOME/.local/bin/omasnap" "$HOME/.local/bin/omasnap.pre-pin-stack"
  install -m 755 "$src/build/omasnap" "$HOME/.local/bin/omasnap"
)
```

下次新建贴图时生效。用不同尺寸的三张图片检查右下角叠放、展开、点击居中、直接拖出和等比缩放，再分别用右键和 `Esc` 检查收回与销毁。离屏测试覆盖拖动手柄的等比缩放。隔离的 Hyprland 0.57.2 会话通过上述操作，并验证了剪贴板贴图和临时预览转贴图。展开时逐帧采样确认有连续的中间位置。回滚时恢复 `~/.local/bin/omasnap.pre-pin-stack` 到 `~/.local/bin/omasnap`，并执行 `git -C "$src" apply -R "$PWD/patches/omasnap-1.26.2-zh-pin-stack.patch"`。

## 电池图标

菜单栏电池改成 macOS 26 的样式：更窄的胶囊（电池本体 24 px，按钮 32 px），里面只有数字，没有 `%`。数字通常只有两位，所以不需要更长。右键电池可以开关数字（见上方「顶栏系统监控」）。外框与电池正极帽保持与顶栏文字同色（深色顶栏为白色，浅色顶栏为深色），仅内部电量填充条随供电状态着色。

顶栏电池与 macOS 一样保持单色：正在充电时填充条为绿色，电池供电且电量不高于 35% 时为琥珀橙，低于 20% 时为红色，其余时候（包括接着电源但未充电、电量充裕）与顶栏文字同色。电量数字在填充条上方时自动取反色。外框和正极帽用 45% 不透明度的文字色，电量接近满格时不再是顶栏里最黑的一块。电量数字从 9 px 加到 10 px；按钮从 32 px 加宽到 37 px，两侧各留 5 px；正极帽离电池本体 0.5 px（2× 屏上 1 个设备像素），读起来是一个整体。这样整条顶栏只有需要注意的状态才带颜色。

电源面板与通知中心电池小组件仍用下面这套四段语义色（绿色表示状态最佳），与温度面板、负载和 AI 额度保持同一设计语言：

| 状态 | 颜色（深色 / 浅色） | 判断条件 |
| --- | --- | --- |
| 正在充电 / 外接电源直供 / 电量充裕 | 翠绿 `#30d158` / `#1c8241` | 充电中、接电源直供（面板副标签显示「电源直供」），或电池供电且电量 `> 65%` |
| 电池供电 · 正常 | 青蓝 `#64d2ff` / `#0071a4` | 电池供电且电量 `36%–65%` |
| 电池供电 · 偏低 | 琥珀橙 `#ff9f0a` / `#b85d00` | 电池供电且电量 `20%–35%` |
| 低电量 | 警示红 `#ff453a` / `#c92a22` | 电量低于 `20%`（与 macOS 相同）且不在充电 |

充电优先于低电量：电量低但正在充电时显示绿色。`status.py` 中的 `wallpaperAccent` 仍保留给通知中心小组件（如「屏幕使用时间」）使用。

（以下为较早的方案，顶栏电池已不再使用壁纸强调色。）外接电源直供的颜色曾取自当前壁纸，换壁纸后跟着变。顶栏采样进程（[`status.py`](../config/macshell/status/status.py) 的 `wallpaper_accent`）解析 Omarchy 的壁纸链接 `~/.local/state/omarchy/current/background`，用 ImageMagick（`magick`）把图缩到 96×96、量化成 16 色，按“面积 × 色度²”选出最鲜明的主色，保留色相，再按深色和浅色菜单栏分别调成亮度 72% 和 38% 的两档（饱和度限制在 50%–85%），随采样数据以 `wallpaperAccent` 发给菜单栏电池和电池面板。结果按壁纸路径和修改时间缓存，换壁纸后约 1.5 秒内更新，只在换图时重新计算一次（6K PNG 约 0.3 秒）。壁纸接近灰色（主色色度低于 0.12）、是视频、或没装 `magick` 时退回原来的蓝色。限制：绿色调壁纸（如 Bliss）取出的颜色会和充电绿接近。验证：接着电源且不在充电时执行 `omarchy-theme-bg-set ~/Pictures/Wallpapers/<另一张>.jpg`，几秒内电池图标和面板强调色应随之变化；macOS Monterey 壁纸取出紫色，Sierra 取出暖橙色。也可以直接查看取色结果：

```bash
python3 -c 'import importlib.util as u; s=u.spec_from_file_location("s", "config/macshell/status/status.py"); m=u.module_from_spec(s); s.loader.exec_module(m); print(m.wallpaper_accent())'
```

部署：重新运行 `python3 scripts/install-macshell-status.py`，它会把旧的蓝色 `indicatorColor` 换成读取 `wallpaperAccent` 的版本，然后重启 MacShell 让新采样脚本生效。回滚：恢复安装脚本打印的 `MacBar.qml.bak.silky-status-*` 备份，并把 `SilkyStatusPanel.qml` 与 `assets/silky-status.py` 换回上一版后重启 MacShell。

面板的「整机功耗」曲线是数据而非状态，固定用紫色。颜色由 [`scripts/install-macshell-status.py`](../scripts/install-macshell-status.py) 写进 `MacBar.qml`（`indicatorColor`），面板颜色在 [`SilkyStatusPanel.qml`](../config/macshell/status/SilkyStatusPanel.qml) 的 `powerState`。重新运行安装脚本会把旧的三色版本替换掉；改动后需重启 MacShell，旧的后台采样进程才会换成新版脚本。验证：插着电源且电池到达充电上限时，顶栏图标应与顶栏文字同色；拔掉电源并放电到 35% 以下变为琥珀橙，充电时为绿色。只改了 QML 时可用 `qs ipc -c MacShell call macshell reload` 重载。回滚：恢复安装脚本打印的 `MacBar.qml.bak.silky-status-*` 备份并重启 MacShell。

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

## 打开窗口时壁纸闪现

[窗口配置](../config/hypr/silky-macshell-windows.lua)关闭 Hyprland 的 `windowsIn` 和 `fadeIn`，让新窗口直接以完整尺寸和不透明度显示，同时为 Firefox 系浏览器（`firefox-based-browser` 标签）以及应用「关于」弹窗（`AppAbout`，标题以 `关于 ` / `About ` 开头）关闭合成器模糊（`no_blur`），并把 `AppAbout` 的窗口圆角对齐卡片自身的 `18 px`，避免透明圆角外缘被模糊出浅色光晕。配套的 [GTK3 CSD 样式](../config/gtk-3.0/silky-csd.css) 去掉 `window.csd decoration` 的透明阴影外边距（由 `~/.config/gtk-3.0/gtk.css` 引入），避免 Firefox 等 GTK3 CSD 窗口在首帧先闪出一圈虚化光晕和约 26 px 的偏移。窗口关闭、工作区切换和 Dock 最小化保留各自的动画。

从仓库根目录运行 `./scripts/install-macshell-optimizations.sh`，再运行 `hyprctl reload`。在 Hyprland 0.57.2 的 Wayland 会话中，前后逐帧对比打开重叠测试窗口与 Firefox，检查底层窗口是否透过开场淡入露出以及 Firefox 首帧是否严丝合缝。回滚时从安装器的 `~/.local/state/macshell/silky-backup-*/settings/` 恢复 `silky-macshell-windows.lua` 和 `gtk3.css`（或移除 `~/.config/gtk-3.0/gtk.css` 中的 `@import url("silky-csd.css");`）并重载 Hyprland。

### 关于本机的外缘

「关于本机」采用 [Omarchy 系统菜单](11-menu-glass.md) 的磨砂色调，底色不透明度为深色 61%、浅色 74%（「系统设置」侧栏则压暗至深色 80%、浅色 82%，避免在浅色窗口前过透发灰）。加载 `silky-dock-glass` 0.5.1 插件后，[`silky-dock-glass.lua`](../config/hypr/silky-dock-glass.lua) 会关闭「关于本机」的 Hyprland 多遍原生模糊，改由插件在 `RENDER_PRE_WINDOW` 阶段对窗口下方画面做**半分辨率拷贝 + 硬件 Mipmap + 单遍 8-tap 黄金角圆盘采样**（支持在 `~/.config/silky-omarchy/dock-glass.conf` 中用 `win_blur`、`win_saturation`、`win_contrast`、`win_brightness` 热调参），并与 Dock 液态玻璃双向联动扩伤，避免静止或重叠时局部损伤导致黑块闪烁；保留真实实时背景与无描边 18 px 超椭圆圆角的同时大幅降低合成器 CPU 开销，插件未加载时自动回退到 Hyprland 原生实时模糊。

安装器会部署 [窗口规则](../config/hypr/silky-macshell-windows.lua) 和 [普通模糊调整脚本](../scripts/tune-native-blur.py) 的改动。手动更新时，先备份 `~/.config/hypr/silky-macshell-windows.lua` 和 MacShell 目录里的 `AboutApp.qml`、`MacBar.qml`、`MacDock.qml`，然后在仓库根目录执行下列命令。从左上角菜单打开「关于本机」，在有文字的窗口和高饱和壁纸上查看背景与圆角。回滚时恢复备份，再重载 Hyprland 和 MacShell。

```bash
python3 scripts/tune-native-blur.py "${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/MacShell"
install -m 644 config/hypr/silky-macshell-windows.lua ~/.config/hypr/
hyprctl reload
hyprctl configerrors
qs -c MacShell ipc call macshell reload
```

### 触控板切换工作区时的磨砂残影

`silky-dock-glass` 0.5.6 修复了四指横滑时「关于本机」的磨砂留在原位的问题。[C++ 渲染插件](../plugins/silky-dock-glass/main.cpp)原先使用窗口的静态位置。现在它在提交绘制时读取 Hyprland 同一帧的工作区偏移、浮动窗口偏移与透明度，并用动效中的位置计算采样和重绘区域。窗口完全滑出屏幕时跳过磨砂绘制，经过屏幕边缘时复用同尺寸的半分辨率纹理。

已在 ARM64、Hyprland 0.57.2 和 90 Hz 屏幕上通过合成器手势接口验证暂停、取消、完成和反向滑动。窗口完全离屏时，采样期间的 19 个合成帧里，磨砂绘制从 19 次降到 0 次。用触控板复测时，从左上角菜单打开「关于本机」，四指横滑并在中途停住，再返回或松手完成切换。磨砂应随窗口移动，并从原位置消失。

已经启用插件时，在仓库根目录运行以下命令。安装器会在同一目录保存覆盖前的插件副本，文件名以 `.so.bak.时间戳` 结尾。回滚时先卸载插件，将该备份恢复到原路径，再加载插件和重载 Hyprland。

```bash
bash scripts/install-dock-glass-plugin.sh --build-only
plugin="$HOME/.local/lib/silky-omarchy/silky-dock-glass-$(pkg-config --modversion hyprland).so"
hyprctl plugin unload "$plugin"
hyprctl plugin load "$plugin"
hyprctl reload
hyprctl configerrors
```

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

## Dock 和菜单栏同时卡住

MacShell 的进程还在时，Dock 和菜单栏可能同时停止响应，连 `qs -c MacShell kill` 也可能等不到回复。[启动脚本的响应检测](../config/macshell/watchdog.py) 在 MacShell 第一次回应 IPC 后启用。每次探测最多等 3 秒，连续三次失败就结束这个实例，由原启动脚本重启。MacLock 和其他应用进程独立运行。故障记录写入 `~/.local/state/macshell/MacShell.log`。

在仓库根目录运行 `scripts/install-macshell-optimizations.sh` 安装。它使用系统 Python 3 和 Linux 的 pidfd 来定位本次启动的进程。新启动脚本从下次重新登录或重新启动启动脚本时生效。恢复安装备份中 `settings/macshell-start` 到 `~/.local/bin/macshell-start` 后重新登录可停用检测。可用 `qs -c MacShell ipc show` 检查当前实例能否响应，自动恢复时日志会有 `macshell-watchdog` 记录。

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

「系统设置」打开时在 Dock 显示独立的齿轮图标，沿用当前图标主题的 `preferences-system`，本机使用 MacTahoe。其他 MacShell 窗口仍可显示紫色 [M 图标](../config/icons/macshell-logo.png)。设置窗口采用随界面缩放的 18 px 圆角和无描边样式。左侧导航使用压暗后的磨砂底色（深色 80% `#cc1c1c1e`、浅色 82% `#d1f7f7f9`，贴近 Folio 侧栏通透度，避免在白底窗口上方过透发灰），右侧正文保持实色。可把设置叠在浅色或有文字的窗口上，查看磨砂是否只在侧栏可见且文字对比清晰。

从仓库根目录运行 `./scripts/install-macshell-optimizations.sh` 即可应用。单独更新时，先备份 `~/.config/quickshell/MacShell/MacDock.qml`，再用 Python 3 对它运行 [设置调整脚本](../scripts/tune-macshell-settings.py)。执行 `hyprctl reload`、`hyprctl configerrors` 和 `qs -c MacShell ipc call macshell reload`，然后按 `Super+Z` 打开设置。已在 MacShell 0.5.3、Hyprland 0.57.2 和 2× 缩放的深色会话中检查 Dock 齿轮图标和紫色壁纸上的圆角。回滚时恢复备份的 `MacDock.qml`（完整安装器备份位于其打印目录下的 `MacShell/MacDock.qml`），重新加载 Hyprland 和 MacShell。

- [`tune-dock-hover-label.py`](../scripts/tune-dock-hover-label.py)：点击 Dock 图标后隐藏悬停标签，直到指针移动超过 4 px。脚本按 `muteX`、`muteY` 和 `cell.tipMuted` 等标记判断是否已应用，所以在按下处理附近自行加入其他属性或 `Timer` 后，重复运行完整安装仍能通过预检。
- [`tune-wallpaper-picker.py`](../scripts/tune-wallpaper-picker.py)：设置里的「墙纸」网格按整行停靠（`GridView.SnapToRow`），最下面一行的名称不会被切掉一半；名称去掉下划线和末尾的分辨率（`solid_black_2560x1440` 显示为 `solid black`），过长时在末尾省略，当前墙纸标题同样处理；收藏按钮改成 24 px 浅色圆底、细描边加深色星形（已收藏为金色实心星），在纯黑和纯白缩略图上都清晰。搜索仍按原文件名匹配。验证：`qs -c MacShell ipc call settings pane wallpaper` 打开墙纸页，滚动网格后应停在整行，名称可读。悬停时收藏按钮的观感尚未在实机上用鼠标检查。回滚：恢复备份的 `MacDock.qml` 并重载 MacShell。
- [`tune-dock-icons.py`](../scripts/tune-dock-icons.py)：Dock 图标的光学缩放以图标中心为基准，悬停放大时不会往一边偏；旋转（抖动）的支点不变。
- [`tune-settings-scroll.py`](../scripts/tune-settings-scroll.py)：设置窗口左侧导航列表原来滚轮一格只动几像素。现在每格 140 px，多格累加后逐帧平滑过去；触控板的像素级滚动仍交给列表自己处理，保留原生惯性。
- [`tune-network-settings.py`](../scripts/tune-network-settings.py)：修复「系统设置 → 网络」状态点始终发灰的问题（原 `paneNetwork` 里状态圆点挂在 `SRow` 内部 `slot` 中，`parent.up` 取不到 `SRow` 的 `up` 属性而恒为假），并按 macOS「网络」页重组版式：
  - 主要网络服务（Wi-Fi、以太网）和 VPN 分组显示，每行左侧配圆角渐变图标，副标题行把 8 px 状态圆点放在状态文字前面（已连接绿 `#30D158`、连接/断开中琥珀黄 `#FF9F0A`、网线未插红 `#FF453A`、关闭或未连接弱灰）。
  - 点击「Wi-Fi」行直接跳转到左侧「Wi-Fi」板块并保留顶部 `<` 返回栈，右侧显示 `›` 指示箭头。
  - VPN 分组由 [`silky-network.py`](../config/macshell/network/silky-network.py) 汇总 NetworkManager 托管的 `vpn` / `wireguard` 配置（含未连接项）、Tailscale 与外部守护进程接管的 TUN 设备：NetworkManager VPN / WireGuard 与 Tailscale 在右侧提供实时开关（`nmcli connection up/down uuid ...` / `tailscale up/down`），切换失败时在副标题行报错；外部应用接管的虚拟网卡（如 Clash Verge 的 `Meta`、ZeroTier 的 `zt*`，`nmcli dev` 状态为 `connected (externally)`）标出应用来源并显示「由应用管理」，不放无法生效的假开关。
  - 安装与验证：随 `./scripts/install-macshell-optimizations.sh` 一并安装，也可备份 `~/.config/quickshell/MacShell/{MacDock.qml,lang/zh-CN.js}` 后单独执行 `python3 scripts/tune-network-settings.py ~/.config/quickshell/MacShell` 并运行 `qs -c MacShell ipc call macshell reload`。运行 `qs -c MacShell ipc call settings pane network` 验证绿点、Wi-Fi 跳转与 VPN 展示（已在本机 MacShell 0.5.3 深色模式实机验证；NM VPN 开关与浅色模式待有配置时实机复查）。回滚：恢复备份的 `MacDock.qml`、`lang/zh-CN.js`，删除 `assets/silky-network.py` 并重载 MacShell。

### Dock 中文件打不开

Omarchy 移除 Nautilus 并将目录默认应用切换为 Folio 后，旧的 Dock 固定项仍会尝试启动 Nautilus。残留的桌面入口仍能显示「文件」图标，Dock 会在等待窗口时反复跳动。

从仓库根目录运行 `./scripts/install-macshell-optimizations.sh`。如果 Nautilus 已卸载，且 Folio 已安装并设为目录默认应用，[迁移脚本](../scripts/migrate-macshell-files.py)会将 `~/.config/macdock/pinned.json` 中的 Nautilus 固定项换成 Folio，保留其他图标顺序。脚本也会移除旧的 Silky Nautilus 中文快捷键覆盖，让 Hyprland 恢复系统的文件快捷键，并将旧的 Silky 桌面入口归档为备份，避免它继续出现在应用面板。

只修复这三个设置时可运行 `python3 scripts/migrate-macshell-files.py`。更新后执行 `hyprctl reload` 和 `qs -c MacShell ipc call macshell reload`。点击 Dock 中文件图标应打开 Folio，再点击应激活已有窗口。也可用 `Super+Shift+F` 验证快捷键。若已重新安装 Nautilus 并要恢复旧设置，将脚本打印的 `.bak.folio.*` 文件复制回原位，再重载 Hyprland 和 MacShell。

## 焦点切换时玻璃背景跟着刷新

[`tune-glass-stacking.py`](../scripts/tune-glass-stacking.py)：玻璃背后窗口的“指纹”原来只看位置和大小，点击切换浮动窗口的前后顺序时，玻璃里还是旧的叠放顺序。现在把焦点顺序（`focusHistoryID`）也算进去，切换焦点时立即刷新；窗口改标题（终端、浏览器标签页、播放器）依然不会唤醒 60 Hz 刷新。

### 文件右键菜单的常用目录

启用 Folio 定制后，在 Dock 右键点「文件」，可直接打开主文件夹、桌面、文档、下载或图片。菜单读取系统的用户目录设置。如果某个快捷目录配置成主文件夹，会优先使用现有的同名目录，避免重复指向主文件夹。使用 Folio 安装脚本或 MacShell 优化安装脚本更新菜单以后，重载 MacShell 即可验证。回滚时恢复安装器备份的 `MacDock.qml` 和 `lang/zh-CN.js`，再重载 MacShell。

### 单击清倒废纸篓

右键点击 MacShell Dock 上的废纸篓，选择「清倒废纸篓」即执行。废纸篓为空时，此项置灰。

常规优化安装会应用此项。只更新菜单时，备份 `~/.config/quickshell/MacShell/MacDock.qml`，在仓库根目录运行以下命令。可用模拟回调检查首次点击是否关闭菜单并发起清倒。回滚时恢复备份后重载 MacShell。

```bash
python3 scripts/tune-dock-trash.py ~/.config/quickshell/MacShell/MacDock.qml
qs ipc -c MacShell call macshell reload
```

## 窗口最小化

点 Folio、Foot 及其他带 Silky 标题栏窗口（[silky-macos.lua](../config/hypr/silky-macos.lua)）的黄灯，以及 Obsidian 标题栏黄灯、微信最小化按钮（[touch-scroll.c](../plugins/wechat-wayland/touch-scroll.c)）或按 `Super+M`（[silky-shortcuts.lua](../config/hypr/silky-shortcuts.lua)），窗口都会沿类似「神奇效果」的弧形轮廓收拢到 Dock 分隔线和废纸篓之间，留下独立的窗口缩略图与右下角应用小徽标。点击缩略图（或对应的 Dock 应用图标），原窗口会从同一位置放大回来。动画时长设为 300 ms。

Folio 自身异步抓取一张尺寸受限的窗口画面并保存在 Wayland 会话运行目录，关闭后清理；其余窗口由 MacShell 的 [缩放组件](../config/macshell/FolioMinimizeFx.qml) 在最小化瞬间通过单次 `ScreencopyView` + `grabToImage` 抓取一张尺寸受限的内存快照（无磁盘 I/O，抓完即断开捕获源，在关闭 Dock 实时窗口预览 `windowCapture: false` 时也同样显示缩略图且零常驻开销），窗口恢复或关闭后自动释放。MacShell 通过渲染线程驱动网格变形，并将叠层限制在窗口到缩略图的范围内。原窗口在叠层就绪后才移入隐藏工作区，移走时禁用 Hyprland 的窗口动画，避免交接时叠加两套效果。Dock 缩略图占位和间距在 180 ms 内线性展开，恢复窗口时线性收回。MacShell 不可用时，所有入口均自动回退到 `omarchy-hyprland-window-minimize`。

旧版曲线让上下沿分段启动，下沿过早缩到目标宽度，尾段还会把窗口画面压暗。新版让各行从起步到落点持续移动，下沿先收拢，窗口全程保持原亮度，并在缩略图或真实窗口接手时短暂保留叠层。用同一组起点和落点按 90 Hz 对着色器轨迹采样，上沿单帧最大位移由约 45 降至 13 个逻辑像素。

收起时，MacShell 先在原位置提交原尺寸快照，等待画面送出后才把真实窗口移入隐藏工作区，确认移走后再开始变形（等待送显期间主动调用 `window.update()`，避免静态叠层只提交一帧导致卡住并触发 320 ms 超时跳过动画）。[Folio 的 Hyprland 规则](../config/hypr/silky-folio.lua)关闭收起叠层自身的淡入，避免交接时闪过桌面或瞬间变暗。

在仓库根目录运行 `python3 scripts/tune-folio-macshell.py ~/.config/quickshell/MacShell --backup`（或 `./scripts/install-folio-macos.sh`），更新微信适配器可运行 `./scripts/install-wechat-touch-scroll.sh`，随后执行 `hyprctl reload` 和 `qs -c MacShell ipc call macshell reload`（微信需重开生效）。若希望系统更新后自动保持这套配置，可将 [post-update-silky-minimize](../hooks/post-update-silky-minimize) 安装到 `~/.config/omarchy/hooks/post-update.d/silky-minimize.hook`：它会在每次 Omarchy 更新后检查并恢复 MacShell 与 Hyprland 最小化入口，并在系统升级了 `/usr/bin/folio` 或依赖库时发出桌面提醒。验证时分别对 Folio、Foot 和其他浮动窗口点黄灯或按 `Super+M`，确认收起动画流畅、Dock 出现窗口缩略图与右下角图标，再点击缩略图确认反向弹出回到原工作区和原状态。回滚时先恢复已最小化的窗口，删掉该 post-update hook，再用安装器报告的备份恢复 MacShell、Hyprland 配置及微信适配器，然后重载 Hyprland 与 MacShell。

其他应用的通用最小化入口由 [`disable-minimize.py`](../scripts/disable-minimize.py) 管理。

## 合成器玻璃与后台采集 C++ 优化

- **`silky-dock-glass`（`0.5.5`）渲染与回读优化**（[`plugins/silky-dock-glass/main.cpp`](../plugins/silky-dock-glass/main.cpp)）：监听每个玻璃层 `CWLSurfaceResource::m_events.commit` 及纹理/几何变化，仅在 surface 实际提交更新时发起 PBO 标记行回读；无 damage 相交且无 commit 更新的帧直接跳过 GL 状态查询与重绘；将 backdrop 纹理与 mipmap 缩小为实际玻璃区包围盒（64 px 桶对齐，并收紧 `REACH = 48`、`CPU_MARGIN = 24`），在 `ensureGL()` 一次性缓存全部 uniform 位置，并在 blit 后解绑 `g_gl.fbo` 颜色附件；新增 `hyprctl silkyglass` 查询实时帧数、跳过数与回读次数。实机双高刷屏（90 Hz + 110 Hz）下，约 81.7%–85.8% 的帧被跳过，回读次数减少 99.7%，空闲堆增长速率下降约 90%。
- **顶栏状态采集 C++ 化**（[`plugins/silky-status/main.cpp`](../plugins/silky-status/main.cpp)）：[`scripts/install-macshell-status.py`](../scripts/install-macshell-status.py) 优先编译安装原生 `assets/silky-status`（缺少 `g++` 时自动回退为调用 `silky-status.py` 的包装脚本）。常驻 `bar` 与重度 `/proc` 扫描的 `thermal` 模式由 C++ 原生执行（常驻 RSS 由约 17 MB 降至 3.7 MB），低频按需模式（`network`、`power`、`profiles`、`set-charge-limit`）自动透传给同目录的 `silky-status.py`。
- **多显示器小组件后端去重**（[`SilkyWidgetsFormat.js`](../config/macshell/widgets/SilkyWidgetsFormat.js)、[`SilkyWidgetDeck.qml`](../config/macshell/widgets/SilkyWidgetDeck.qml)）：通过 `.pragma library` 单例协调器在所有屏幕间共享唯一一个 `silky-widgets.py` 后台进程，副屏热插拔时自动移交宿主，双屏下省去一套完整的 Python 进程（约 105 MB RSS 与一半重复扫描开销）。
