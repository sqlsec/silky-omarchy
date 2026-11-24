# 13 · 四指上滑 / 下滑：窗口总览

简体中文 | [English](en/13-window-overview.md)

## 目标

和 macOS 一样：

| 手势 | 效果 |
| --- | --- |
| 触控板 / 触控屏四指上滑 | 显示顶部工作区预览和当前工作区的所有窗口 |
| 触控板 / 触控屏四指下滑 | 显示当前应用的所有窗口（应用程序窗口 / App Exposé），包括它在其他工作区上的窗口 |
| 工作区总览中触控板四指左右滑 | 切换工作区并保持总览打开，也可以点击顶部预览 |
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
silkyoverview>>update,<位移>,<时间>  从开始到现在的累计位移，触控板单位，向上为正；时间是手指在那里的墙钟毫秒（0.8.1 起）
silkyoverview>>end           抬手（end,cancel：手势被取消）
```

注意事项：

- Hyprland 每次重载配置都会清空手势表（在 `config.preReload` 和 `config.reloaded` 之间）。插件监听 `reloaded` 重新注册；插件本身是在读取配置的过程中加载的，那时表已经清空、插件已经注册过一次，所以用 `preReload` 做标记，避免第一次 `reloaded` 时重复注册
- 卸载插件前必须把手势从表里删掉，否则 Hyprland 会调用已卸载代码里的虚函数而崩溃
- 配置里如果已经有四指 `vertical` / `up` / `down` / `swipe` 手势，注册会失败，插件会弹出通知说明原因
- 锁屏时不响应

### 插件：触控屏四指上下滑

触控屏没有 libinput 手势，插件自己跟踪触点（和三指切换工作区、四指捏合同一套代码，见 `checkTouchOverview`）：

- 正好四根手指，四指中心上下移动超过 `OVERVIEW_START_PX`（28 px），且竖直位移大于横向位移的 1.2 倍、大于手指间距的变化，就判定为总览手势；起点扣掉这 28 px，画面不会跳
- 位移换算成触控板单位后发出同样的 `silkyoverview` 事件：屏幕高度的 `OVERVIEW_SPAN`（22%）= 240 单位 = 完全打开，所以 MacShell 不需要第二套参数
- 第一根手指抬起即结束（和捏合一样）；手势中途加减手指不会让画面跳动
- 四指捏合仍然优先，但只有手指间距的变化超过四指中心移动距离的一半才算捏合，四指一起上下滑时手指自然分开一点不会被误判为捏合；四指左右切换工作区也要求横向位移大于竖向位移
- 总览打开后，单指轻点窗口即可选中，四指下滑（或反方向）关闭

### MacShell：一个数字驱动一切

`SilkyOverview.qml` 里只有一个进度 `p`（0 = 桌面，1 = 总览）：

- 手指按住时：`p = 起始进度 ± 位移 / distance`，上滑打开工作区总览，下滑打开应用窗口；限制在 0–1
- 每个窗口是一个窗口捕获（MacShell 自带的 `SafeCapture`，不会在帧未返回时释放捕获，避免 Wayland 连接崩溃），矩形 = `lerp(真实矩形, 网格矩形, p)`。画面保持窗口自身的固定大小，新帧到达时只复制进一张纹理（`ShaderEffectSource`，不做特效处理），再由一个小着色器 [`silkyround.frag`](../config/macshell/overview/silkyround.frag) 按当前大小画出带抗锯齿的圆角——移动、缩放不产生任何额外开销。每次手势开始时批量请求截图，切换工作区后再为当前窗口请求一批截图，停留时不实时推流，原因见下文“流畅度”
- 应用窗口模式下，当前工作区的其他窗口留在原位，透明度 `1 − p`；该应用在其他工作区的窗口在网格位置从 88% 大小、透明度 0 线性长到 100%
- 背景保持桌面静态壁纸原有的亮度和裁切。Omarchy 自己绘制背景时读取当前壁纸链接，其余情况下优先使用 awww 或 swww 当前显示的图片。总览图层放在 `WlrLayer.Top` 且在 `shell.qml` 中声明在 `MacBar` 与 `MacDock` 之前，壁纸直接铺满全屏：底层延伸到 Dock 或菜单栏保留区的真实窗口不会再从上下边缘透出残影，菜单栏与 Dock 自然画在总览上方，其毛玻璃背景也直接模糊干净的壁纸。
- 每个缩略图从第一帧起就带一个和 Hyprland 一样的阴影
- 松手：按手指最后约 90 ms 的速度预判 0.12 秒后的位置，过半就打开，否则关闭；然后以 `max(手指速度, minSpeed)` 的**恒定速度**走到终点
- 动画进行中再次放上四指：停止动画，以当前 `p` 为起点继续跟手
- **收回时始终是实体**：打开时总览在前 12% 的进度里淡入；一旦完全不透明，收回过程中缩略图就一直保持不透明，直到和真实窗口完全重合（同样的位置和层叠顺序，被点的窗口在最上层），然后整层再用 80 ms（`outroMs`）淡出，这时变化的只有截图里没有的 Hyprland 边框、标题栏和阴影。早期版本收回时也是交叉淡化：半透明的总览叠在真实桌面上形成重影；而且快速上滑时淡化起点会被推到 p = 0.5，收回到一半窗口就开始变虚，被选中的窗口要先变虚再变实
- **跟手按时间采样**：插件给每个 `update` 带上手指实际到达那个位置的时间（libinput 的事件时间换算成墙钟毫秒）。socket2 把这些事件成批交给 MacShell（实测一半以上在 1 ms 内连着到，然后 30 ms 以上没有），按到达时间设置进度，画面就一跳一跳的，虽然每帧都准时。现在每一帧按自己的时间、往回 `lagMs`（10 ms）在带时间的手指轨迹上插值取进度，超出最新一个点时按手指速度最多外推 `extrapMs`（16 ms），每帧的步长就跟手指的真实速度一致。松手速度也按这些时间算
- **按时钟走**：松手后的匀速动画按时钟计算位置，而不是按上一帧的耗时累加：以前一帧晚到，下一帧就走两步，是一下可见的顿挫。超过 50 ms 的大卡顿不会让画面跳过去，而是从卡住的地方接着走
- **整层一起淡出**：总览在屏幕上时开启 `layer.enabled`，先拼成一张画面再整体改透明度。QML 的 `opacity` 默认是分别作用到每个子元素上的：每张缩略图各自半透明，叠在下面的窗口会从上面的窗口里透出来（Firefox、Claude 透过 Chrome），淡出那两三帧就是所有窗口混在一起，看起来是最后“闪”了一下。拼成一张后，淡出的画面和下面的真实桌面完全一样，什么都透不出来。录屏逐帧对比：相邻帧的亮度差从 10–20 降到 1 左右

起点无缝的几个细节：

- **窗口常驻、停在屏幕外**：总览图层一直映射着，关闭时以全屏大小停在屏幕左边外面（和 MacShell 的 Spotlight 一样），不接收输入、不拿键盘焦点，Hyprland 也不绘制它；手势开始时只是把它移进来。早期版本在手势开始时才创建窗口，Vulkan 表面、交换链和着色器管线都在 GUI 线程上现建，实测每次滑动都有约 0.5 秒一帧都没有，手指走了三分之一画面才出现，然后一下子“追”上去。现在 `begin` 后约 10 ms 就开始出帧，稳定 90 Hz。另外：启动后先以 1% 透明度把所有效果画一次，预先编译着色器；各效果图层始终开启，手势中途不再分配缓冲；图层规则 `no_anim`，避免 Hyprland 自己的图层淡入叠加在跟手动画上
- **捕获常驻**：当前工作区的窗口一直挂着捕获（不请求新帧，空闲时几乎没有开销），手指一放下就请求一帧新的，所以开始时画面已经在那里。它不受 Dock 设置里“实时窗口捕获”开关的影响（那个开关管的是 Dock 预览）；只在 MacShell 的防崩溃暂停（捕获风暴、正在关闭窗口、游戏模式）时停用。早期版本跟着那个开关走，开关关闭时总览一张画面都没有，每个窗口显示灰色应用图标卡片（每张都在主线程同步查找、渲染图标），就是开始时的闪烁和卡顿
- **等第一帧、交叉淡入**：新帧最多等 60 ms（至少 24 ms，让刷新的帧到达）；这期间手指位移照样计入。画面出现后，总览在接下来 12% 的行程里从完全透明交叉淡入到不透明：真实窗口的 Hyprland 阴影、边框和标题栏（都不在窗口捕获里）是慢慢溶解掉的，不会在一帧里消失
- **层叠顺序**：全屏窗口在最上，其次浮动窗口，同类按最近聚焦排序，和 Hyprland 的实际顺序一致

### 工作区预览与切换

四指上滑后，顶部每张卡片按原有位置和层叠顺序显示该工作区的窗口，空工作区只显示壁纸。高亮边框和标签标出当前工作区。点击卡片或使用已有的 Hyprland 四指左右工作区手势，下方窗口会横向滑出和滑入，总览保持打开。点击缩略图会按目标的方向滑动，触控板四指横滑会跟随手指，松手后继续滑到新工作区或滑回原位。壁纸和顶部预览固定在原位。关闭时停留在选中的工作区。顶部预览和下方窗口共用截图，合成器暂时无法提供截图时显示占位图形。Silky Gestures 0.8.3 发送 Hyprland 原生横滑的进度，切换是否提交仍由 Hyprland 决定。升级后重新安装插件和总览组件，重载 MacShell。

总览打开后：

- 鼠标悬停窗口：蓝色描边，下方显示窗口标题
- 点击 / 轻点窗口（或悬停后回车）：聚焦这个窗口并关闭总览，飞回比普通关闭快一些（`pickSpeed`，完全打开时约 0.3 s，从点击到结束约 0.4 s，以前约 0.75 s），被点的窗口在最上层飞回原位；如果它在其他工作区，先切换工作区，总览整体淡出。总览打开时独占键盘焦点，而 Hyprland 在有图层独占键盘时会拒绝聚焦任何窗口：早期版本点击后聚焦命令被丢掉，原来的窗口仍在最上面。现在先关闭（释放键盘），40 ms 后再发聚焦命令
- 拖动窗口到其他工作区（工作区总览模式）：按住窗口预览移动超过 8 px 即进入拖拽，窗口置顶跟随指针并在靠近顶部工作区预览条时平滑缩小；悬停在目标工作区卡片上时卡片高亮并轻微放大，松手调用 `hl.dsp.window.move({ workspace = "<id>", follow = false, window = "address:0x<addr>" })` 静默移入目标工作区，同时保留总览打开并立即更新网格与顶部缩略图；松手在空白处、原工作区或按 `Esc` 则取消拖拽回到原位
- 点击 Dock 或菜单栏图标：因总览在 `WlrLayer.Top` 中位于 `MacBar` 与 `MacDock` 下方，指针事件直接到达 Dock 与菜单栏；按下时提前释放总览的独占键盘焦点，点击后退出总览并正常执行应用激活、右键菜单、菜单栏弹窗或托盘动作
- 点击空白处（含顶部工作区预览条左右两侧空白）或按 Esc：关闭（拖拽窗口时按 `Esc` 先取消拖拽）
- 有窗口打开、关闭或移动时重新排布

网格排布：保持各窗口的相对大小（统一缩放比例，最大 0.88），按窗口中心从上到下、从左到右分行，尝试所有行数，取缩放比例最大的那种。

### 流畅度

一帧都不能晚，所以动画期间不让 Hyprland 和别的应用做额外的事。这几条都是在这台机器上测出来的（`ipc call overview debug true` 每帧记一行，另外每 4 ms 问一次 Hyprland 的 socket 看它主循环有没有卡住）：

- **键盘在落位后才交还**：总览一出现就独占键盘，直到窗口飞回原位才放开。拿着键盘焦点的应用会不停重绘（光标闪烁、焦点框），每次重绘 Hyprland 都要把全屏总览下面的所有窗口重新合成一遍，只要应用有焦点，大约每 6 帧就掉 1 帧。以前一开始收起就交还键盘，收起时掉帧约 18%；现在约 5%。收回到最后 20%（`handoverAt`，约最后 60 ms）时交还键盘、聚焦被点的窗口（键盘释放是 Wayland 的双缓冲状态，要等总览下一次提交才生效，所以每 50 ms 重发一次，直到它成为活动窗口）。落位时它通常已经是活动窗口、已经提到最上面，淡出立刻开始；还不是就最多等 200 ms。早期版本落位后才交还，实测落位后静止 230 ms 才开始淡出，点击窗口后显得慢
- **不实时推流**：每次请求新的窗口画面都会让 Hyprland 主循环停几十毫秒（所有应用、鼠标指针和总览一起停）。一批请求只停一次，所以每次手势开始时一次性请求所有窗口，那时总览本来就在等第一帧。工作区切换后只刷新一次当前窗口。打开后不再推流：16 个窗口实时推流时大约每秒卡 45–70 ms，只推悬停的那一个窗口也会在它重绘时卡；改成不推流后，总览停着时 Hyprland 一次都不卡。也试过把刷新分散开（每 10 ms 一个、或停着时每 150 ms 轮换一个），结果每个请求各卡一次，更糟
- 结果：打开、收起的掉帧（帧间隔 > 16 ms）都在 5% 左右。Hyprland 偶尔仍会卡 40–70 ms，次数随应用当时在做什么变化很大，和总览没有确定的关系

## 安装

```bash
./scripts/install-silky-gestures.sh                 # 插件（0.7.0 起包含触控板四指上滑 / 下滑，0.8.0 起包含触控屏，0.8.1 起事件带时间）
python3 scripts/install-macshell-overview.py        # 把 SilkyOverview.qml 装进 MacShell 并在 shell.qml 里加一行
qs -c MacShell ipc call macshell reload
```

`install-macshell-overview.py` 会将 `SilkyOverview { id: silkyOverview; hub: sharedHub }` 安装在 `shell.qml` 中 `MacBar` 之前（并在 `sharedHub` 注册 `overview: silkyOverview`，旧版位于 `AboutApp` 之后时会自动迁移），同时为 `MacDock.qml` 和 `MacBar.qml` 写入点击退出总览的钩子。重复运行会先备份并更新 `~/.config/quickshell/MacShell/` 下的 `SilkyOverview.qml`、`silkyround.frag.qsb` 及被修改的 QML 文件（`.bak-overview-<时间>`）。`--check` 只检查不修改。回滚时，将对应的 `.bak-overview-<时间>` 文件复制回原文件名，再执行 `qs -c MacShell ipc call macshell reload`。

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

工作区总览打开后，点击一个有窗口的卡片，再点击空工作区卡片，确认预览高亮和窗口列表同步；同时确认屏幕底边 Dock 后方无底层窗口残影，点击 Dock 或菜单栏图标可正常触发动作并退出总览。拖动窗口到其他工作区可直接在总览中拖拽窗口卡片到顶部目标工作区缩略图验证，也可用 `qs -c MacShell ipc call overview moveWindow <addr> <wsId>` 触发静默移动并确认当前工作区与总览打开状态保持不变；`qs -c MacShell ipc call overview dismiss true` 验证从 Dock / 菜单栏退出总览。切换也可通过 `hyprctl dispatch 'hl.dsp.focus({ workspace = "2" })'` 验证，由 `overview state` 观察 `workspace` 改成目标值且 `p` 仍为 1。动画中 `workspacePosition` 在两个工作区位置之间变化。可用 `qs -c MacShell ipc call overview workspaceSwipe 2 40` 模拟从工作区 1 向 2 滑动 40%，再用 `qs -c MacShell ipc call overview workspaceSwipeEnd` 验证松手滑回原位。实体触控板上，打开后分别四指向左、向右滑，确认仍停在总览，关闭后仍停在选定工作区。

确认插件在发事件：

```bash
socat - UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock | grep silkyoverview
```

四指上下滑时应看到 `begin`、一串 `update`、`end`。

如果手势结束事件丢失，连续 3 秒收不到位移更新后，总览会按取消手势处理。此时也可直接按 `Esc` 关闭总览。装好并重载后，可从关闭状态运行 `qs -c MacShell ipc call overview begin up` 和 `qs -c MacShell ipc call overview update 150`，省略 `end` 来复现中断。约 3 秒后，用 `qs -c MacShell ipc call overview state` 确认 `mode` 为空，再单击 Dock 和菜单栏。正常手势仍在松手时结束。

已在本机验证（内置的 `sim` 每 7 ms 推一次位移，和真实触控板一样）：`begin` 处理只要约 2 ms（早期 258 ms），6 个窗口在开始时都已有画面；画面在约 5% 行程处出现并从透明淡入；移动过程中帧时间基本稳定在 11 ms（90 Hz），最长约 22 ms（偶尔错过一次刷新，原来有 85–100 ms 的卡顿）。真实快速滑动的日志：259 帧中 246 帧按时。用 `qs -c MacShell ipc call overview debug true` 打开逐事件、逐帧日志（`qs log -n -c MacShell | grep overview`），`qs -c MacShell ipc call overview sim up 700` 模拟一次 700 ms 的滑动。

## 已知限制

- 窗口的 Hyprland 边框和标题栏不在窗口捕获里：开始时随交叉淡入溶解掉，总览里的窗口没有标题栏
- 总览背景支持静态壁纸，视频壁纸、桌面图标和小组件不显示
- 应用在其他工作区的窗口如果 Hyprland 不给捕获，会显示应用图标卡片
- 只在当前聚焦的显示器上显示

## 停用

删除 `~/.config/quickshell/MacShell/shell.qml` 里的 `SilkyOverview { … }` 一行（或用 `shell.qml.bak-overview` 恢复）并重载 MacShell。插件发出的事件没人接收时不会产生任何效果；想让四指竖滑完全不被插件占用，可以在 Hyprland 配置里自己定义一个四指 `vertical` 手势，插件会让位。
