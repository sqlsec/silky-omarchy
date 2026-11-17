# 13 · 四指上滑 / 下滑：窗口总览

简体中文 | [English](en/13-window-overview.md)

## 目标

和 macOS 一样：

| 手势 | 效果 |
| --- | --- |
| 触控板四指上滑 | 显示当前工作区的所有窗口（调度中心） |
| 触控板四指下滑 | 显示当前应用的所有窗口（应用程序窗口 / App Exposé），包括它在其他工作区上的窗口 |
| 打开后反方向滑 | 回到桌面 |

动画要求：

- **跟手**：手指放在触控板上时，进度只由手指位移决定，往回滑就往回走
- **线性**：每个窗口的位置和大小是“真实位置”和“网格位置”之间的线性插值，没有额外的缓动曲线；松手后也以恒定速度走完
- **可打断、可回退**：松手后的动画进行中再放上四指，从当前进度接手，可以继续、也可以反向
- **过渡自然**：起点那一帧和真实桌面一致（同样的窗口、同样的位置和层叠顺序、同样的壁纸），不闪、不跳

## 实现

分两部分，和四指捏合打开应用程序面板的做法一样：

1. **Hyprland 插件**（[`plugins/silky-gestures/main.cpp`](../plugins/silky-gestures/main.cpp) 的 `CSilkyOverviewGesture`）负责识别手势，把进度通过 socket2 事件发出去
2. **MacShell 组件**（[`config/macshell/overview/SilkyOverview.qml`](../config/macshell/overview/SilkyOverview.qml)）负责画面

### 插件：注册一个原生的四指竖直手势

Hyprland 0.57 的触控板手势表（`g_pTrackpadGestures`）对插件开放。插件往里面加一个 4 指、`vertical` 方向的手势：

```cpp
g_pTrackpadGestures->addGesture(makeUnique<CSilkyOverviewGesture>(), 4, TRACKPAD_GESTURE_DIR_VERTICAL,
                                Input::HL_MODIFIER_NONE, 1.F, false);
```

Hyprland 根据最初约 5 个单位的位移判断这次滑动是横向还是竖向，横向交给已有的四指工作区手势，竖向交给这里，两者不会抢。不用 `hl.gesture` 的 Lua 函数动作：它每次更新都只能启动一个进程去通知 MacShell，跟不上手指。

插件发出的事件：

```text
silkyoverview>>begin,up      四指开始，最初方向向上（down 为向下）
silkyoverview>>update,<位移>  从开始到现在的累计位移，触控板单位，向上为正
silkyoverview>>end           抬手（end,cancel：手势被取消）
```

注意事项：

- Hyprland 每次重载配置都会清空手势表（在 `config.preReload` 和 `config.reloaded` 之间）。插件监听 `reloaded` 重新注册；插件本身是在读取配置的过程中加载的，那时表已经清空、插件已经注册过一次，所以用 `preReload` 做标记，避免第一次 `reloaded` 时重复注册
- 卸载插件前必须把手势从表里删掉，否则 Hyprland 会调用已卸载代码里的虚函数而崩溃
- 配置里如果已经有四指 `vertical` / `up` / `down` / `swipe` 手势，注册会失败，插件会弹出通知说明原因
- 锁屏时不响应

### MacShell：一个数字驱动一切

`SilkyOverview.qml` 里只有一个进度 `p`（0 = 桌面，1 = 总览）：

- 手指按住时：`p = 起始进度 ± 位移 / distance`，上滑打开工作区总览，下滑打开应用窗口；限制在 0–1
- 每个窗口是一个窗口捕获（MacShell 自带的 `SafeCapture`，不会在帧未返回时释放捕获，避免 Wayland 连接崩溃），矩形 = `lerp(真实矩形, 网格矩形, p)`。画面保持窗口自身的固定大小，新帧到达时只复制进一张纹理（`ShaderEffectSource`，不做特效处理），再由一个小着色器 [`silkyround.frag`](../config/macshell/overview/silkyround.frag) 按当前大小画出带抗锯齿的圆角——移动、缩放不产生任何额外开销。手势过程中只用开始时拿到的那一帧，总览完全打开、停稳后才开始实时刷新
- 应用窗口模式下，当前工作区的其他窗口留在原位，透明度 `1 − p`；该应用在其他工作区的窗口在网格位置从 88% 大小、透明度 0 线性长到 100%
- 背景是当前壁纸（和桌面同一张，同样的裁切）加一层压暗 `0.22·p`，不做模糊：全屏模糊每帧重算，在这块 GPU 上比一帧 90 Hz 的时间还长；菜单栏的保留区不覆盖，菜单栏保持原样
- 每个缩略图从第一帧起就带一个和 Hyprland 一样的阴影
- 松手：按手指最后约 90 ms 的速度预判 0.12 秒后的位置，过半就打开，否则关闭；然后以 `max(手指速度, minSpeed)` 的**恒定速度**走到终点
- 动画进行中再次放上四指：停止动画，以当前 `p` 为起点继续跟手

起点无缝的几个细节：

- **窗口常驻、停在屏幕外**：总览图层一直映射着，关闭时以全屏大小停在屏幕左边外面（和 MacShell 的 Spotlight 一样），不接收输入、不拿键盘焦点，Hyprland 也不绘制它；手势开始时只是把它移进来。早期版本在手势开始时才创建窗口，Vulkan 表面、交换链和着色器管线都在 GUI 线程上现建，实测每次滑动都有约 0.5 秒一帧都没有，手指走了三分之一画面才出现，然后一下子“追”上去。现在 `begin` 后约 10 ms 就开始出帧，稳定 90 Hz。另外：启动后先以 1% 透明度把所有效果画一次，预先编译着色器；各效果图层始终开启，手势中途不再分配缓冲；图层规则 `no_anim`，避免 Hyprland 自己的图层淡入叠加在跟手动画上
- **捕获常驻**：当前工作区的窗口一直挂着捕获（不请求新帧，空闲时几乎没有开销），手指一放下就请求一帧新的，所以开始时画面已经在那里。它不受 Dock 设置里“实时窗口捕获”开关的影响（那个开关管的是 Dock 预览）；只在 MacShell 的防崩溃暂停（捕获风暴、正在关闭窗口、游戏模式）时停用。早期版本跟着那个开关走，开关关闭时总览一张画面都没有，每个窗口显示灰色应用图标卡片（每张都在主线程同步查找、渲染图标），就是开始时的闪烁和卡顿
- **等第一帧、交叉淡入**：新帧最多等 60 ms（至少 24 ms，让刷新的帧到达）；这期间手指位移照样计入。画面出现后，总览在接下来 12% 的行程里从完全透明交叉淡入到不透明：真实窗口的 Hyprland 阴影、边框和标题栏（都不在窗口捕获里）是慢慢溶解掉的，不会在一帧里消失
- **层叠顺序**：全屏窗口在最上，其次浮动窗口，同类按最近聚焦排序，和 Hyprland 的实际顺序一致
- **Dock**：Dock 是总览图层下面的另一个图层，直接盖住会在第一帧突然消失。Dock 显示时，在它的位置留一个圆角洞，随进度在前 35% 内逐渐合上，所以 Dock 是淡出的；Dock 自动隐藏时不留洞（留了会透出后面的真实窗口）

总览打开后：

- 鼠标悬停窗口：蓝色描边，下方显示窗口标题
- 点击窗口（或悬停后回车）：聚焦这个窗口并关闭总览，被点的窗口在最上层飞回原位；如果它在其他工作区，先切换工作区，总览整体淡出
- 点击空白处或按 Esc：关闭
- 有窗口打开、关闭或移动时重新排布

网格排布：保持各窗口的相对大小（统一缩放比例，最大 0.88），按窗口中心从上到下、从左到右分行，尝试所有行数，取缩放比例最大的那种。

## 安装

```bash
./scripts/install-silky-gestures.sh                 # 插件（0.7.0 起包含四指上滑 / 下滑）
python3 scripts/install-macshell-overview.py        # 把 SilkyOverview.qml 装进 MacShell 并在 shell.qml 里加一行
qs -c MacShell ipc call macshell reload
```

`install-macshell-overview.py` 会把 `shell.qml` 备份为 `shell.qml.bak-overview`，只在 `AboutApp { … }` 那一行后面加一行 `SilkyOverview { id: silkyOverview; hub: sharedHub }`。重复运行只会更新 QML 文件。`--check` 只检查不修改。

## 调整

`SilkyOverview.qml` 开头的常量：

| 常量 | 默认 | 含义 |
| --- | --- | --- |
| `distance` | 240 | 完整打开 / 关闭需要的手指位移（触控板单位，libinput 约 11.7 单位 / mm，240 ≈ 20 mm，本机触控板高 77 mm），越小越灵敏 |
| `minSpeed` | 2.4 | 松手后的最低速度（进度 / 秒），完整走一遍约 0.4 秒 |
| `maxSpeed` | 10 | 松手后的最高速度 |
| `project` | 0.12 | 松手时按手指速度预判多少秒后的位置来决定打开还是关闭 |
| `primeMs` | 60 | 等第一帧画面的最长时间 |
| `fadeIn` | 0.12 | 开始时交叉淡入占的行程 |
| `dim` | 0.22 | 完全打开时壁纸压暗的程度 |
| `maxScale` | 0.88 | 网格里窗口的最大缩放比例 |

改完重新运行 `install-macshell-overview.py` 并重载 MacShell。

## 验证

不用触控板也能走完整条路径（与手势用的是同一套函数）：

```bash
qs -c MacShell ipc call overview begin up     # 或 down
qs -c MacShell ipc call overview update 120   # 走到一半
qs -c MacShell ipc call overview state        # {"mode":"workspace","p":0.5,...}
qs -c MacShell ipc call overview end          # 松手
qs -c MacShell ipc call overview toggle workspace   # 或 app：直接打开 / 关闭
```

确认插件在发事件：

```bash
socat - UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock | grep silkyoverview
```

四指上下滑时应看到 `begin`、一串 `update`、`end`。

已在本机验证（内置的 `sim` 每 7 ms 推一次位移，和真实触控板一样）：`begin` 处理只要约 2 ms（早期 258 ms），6 个窗口在开始时都已有画面；画面在约 5% 行程处出现并从透明淡入；移动过程中帧时间基本稳定在 11 ms（90 Hz），最长约 22 ms（偶尔错过一次刷新，原来有 85–100 ms 的卡顿）。真实快速滑动的日志：259 帧中 246 帧按时。用 `qs -c MacShell ipc call overview debug true` 打开逐事件、逐帧日志（`qs log -n -c MacShell | grep overview`），`qs -c MacShell ipc call overview sim up 700` 模拟一次 700 ms 的滑动。

## 已知限制

- 窗口的 Hyprland 边框和标题栏不在窗口捕获里：开始时随交叉淡入溶解掉，总览里的窗口没有标题栏
- MacShell 的桌面图标、小组件在总览里不显示（被壁纸盖住）
- 应用在其他工作区的窗口如果 Hyprland 不给捕获，会显示应用图标卡片
- 只在当前聚焦的显示器上显示

## 停用

删除 `~/.config/quickshell/MacShell/shell.qml` 里的 `SilkyOverview { … }` 一行（或用 `shell.qml.bak-overview` 恢复）并重载 MacShell。插件发出的事件没人接收时不会产生任何效果；想让四指竖滑完全不被插件占用，可以在 Hyprland 配置里自己定义一个四指 `vertical` 手势，插件会让位。
