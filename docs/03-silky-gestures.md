# 03 · 触控屏工作区手势与到头回弹

简体中文 | [English](en/03-silky-gestures.md)

## 目标

- 触控板四指滑动切换工作区时，滑到第一个或最后一个工作区会有 macOS 那样的阻尼跟手与回弹，提示已经到头
- 触控屏用三根及以上手指左右滑动，1:1 跟手切换工作区
- 触控屏用一根手指从屏幕左右边缘向内滑动，切换工作区
- 触控屏的两种滑动到头时同样回弹
- 触控屏上用手指移动、缩放浮动窗口：拖标题区域移动，拖边缘和四角缩放，长按窗口任意位置后拖动也能移动

## 为什么需要插件

Hyprland 0.57.2 自带的只有触控板手势和 `gestures.workspace_swipe_touch` 边缘滑动：

- 到头时内部把位移直接归零，没有任何反馈，也没有回弹选项
- 触控屏没有多指手势，Lua 配置里也拿不到触摸事件
- 自带的边缘滑动热区只有 `gaps_out + border_size`（本机 12 px），而且边缘上的点击会被吞掉

所以这部分用一个小的 Hyprland 插件实现：[`plugins/silky-gestures/main.cpp`](../plugins/silky-gestures/main.cpp)。它只监听 Hyprland 的事件总线，切换和动画仍然交给 Hyprland 自己的工作区滑动逻辑，不修改 Hyprland 本体，也不使用函数钩子（钩子只支持 x86_64，本机是 aarch64）。

## 行为

| 手势 | 效果 |
|---|---|
| 触控板四指左右滑动，到头继续滑 | 当前工作区带阻尼跟随，松手回弹 |
| 触控屏三指及以上左右滑动 | 工作区 1:1 跟手，过半或快速甩动则切换，否则回到原位 |
| 触控屏单指从左右边缘 20 px 内向内滑动 | 同上；从左边缘向右滑显示左侧工作区 |
| 触控屏上述滑动到头 | 阻尼跟随，松手回弹 |
| 触控板 / 触控屏四指或五指捏合 | 打开 MacShell 应用程序面板（Launchpad） |
| 触控板 / 触控屏四指或五指张开 | 关闭应用程序面板 |
| 触控板 / 触控屏四指上滑 / 下滑 | MacShell 窗口总览：当前工作区 / 当前应用的所有窗口，跟手（见 [13](13-window-overview.md)） |
| 指针不动、连续点击会改变输入区域的图层（Dock 的“应用程序”图标） | 每次点击都生效 |

细节：

- 第三根手指落下时，前两根手指已经发给应用的触摸会被取消，之后直到所有手指抬起都不再传给应用
- 边缘上的单指轻点、以及沿着边缘上下拖动（例如滚动条），仍然会交还给应用
- 回弹使用 `workspaces` 动画的曲线和速度
- 锁屏时不响应
- 四指 / 五指捏合跟手：插件把进度通过 socket2 事件 `silkylaunchpad>>begin`、`update,<量>`、`end[,cancel]` 发给 MacShell。“量”是 `1 − 缩放比例`（捏合为正，张开为负）。触控板用 libinput 的 pinch 手势（两指、三指捏合不拦截）；触控屏用手指到中心的平均距离，变化超过 6% 就算捏合
- 触控屏四指及以上时，只有横向移动超过 28 px、大于间距变化且大于竖向移动，才当作切换工作区；正好四指上下移动超过 28 px 打开窗口总览（见 [13](13-window-overview.md)）
- 不用 `hl.gesture` 的 pinch：它的函数动作要等抬手才执行，无法跟手
- 排查：每次触控板捏合都会发出 `silkypinch>>手指数`。如果四指捏合没反应，运行 `socat - UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock | grep silky` 后再捏一次，看 libinput 报告了几根手指

- 捏合行程：张开程度缩小约 22% 面板就完全打开（原来 35%），张开约 28% 完全关闭；松手时走过三分之一就完成，否则退回
- 排查：触控板的滑动手势同样会发出 `silkyswipe>>手指数`。捏合没反应而这里出现了 `silkyswipe>>4` 或 `silkyswipe>>3`，说明 libinput 把这次捏合判成了滑动（见下文“触控板四指 / 五指捏合识别”）

可调参数是 `main.cpp` 顶部的常量：边缘宽度 `EDGE_PX`、手指数 `MULTI_FINGERS`、甩动速度 `FLICK_PX_PER_SEC`、回弹最大幅度 `RUBBER_LIMIT`、阻尼 `RUBBER_STIFFNESS`，以及捏合的手指数 `PINCH_FINGERS` 和触控屏判定阈值 `PINCH_START`。改完重新运行安装脚本。

## 触控板四指 / 五指捏合识别

触控板手势由 libinput 分类，Hyprland 插件接收已经分类的事件。原版 1.32.0 只用最上、最下两个触点来区分滑动和捏合，可能把近乎不动的拇指排除，剩余三指就会进入三指拖移或三指下滑；并且原版手势分发还有四指上限。早期多指补丁虽然放开了五指分发，但仍受限于 100 ms 的拇指窗口、底部软按钮区与侧压面积过滤（`PALM_TOUCH_SIZE`），且四根手指一字横向排开时 4:1 的算术质心权重会稀释纵向抓拢的半径变化，导致五指捏合迟钝或抢跑为三指下滑。

[多指捏合补丁（1.32.0-1.4）](../patches/libinput-1.32.0-multifinger-pinch.patch) 按真实整手落指几何与时序重新设计：

- **350 ms 整手集结与拇指豁免**：只要 350 ms 内凑齐 4 或 5 个真实槽位且至少有 2 个常规活跃手指，位于底部软按钮区的静止拇指以及因侧贴面积较大触发 `PALM_TOUCH_SIZE` / `PALM_PRESSURE` / `PALM_EDGE` 的拇指或小指均纳入整手几何，且多指期间不会因指群移动较快把拇指降级抑制。
- **对向跨度与径向离散度联合判别**：同时计算全体触点的平均径向半径与「最低拇指 ↔ 上方指群中心」的对向跨度。两者对刚体平移（四指横滑切桌面、四指上下滑窗口总览）严格不变（变化量为 0），而在宽跨度五指纵向抓拢时保留完整收缩量，不被外侧手指横向跨度稀释。
- **3 → 4 → 5 动态升级与抢跑拉回**：前 3 指在 220 ms 内抢跑进入 `3FG_DRAG_OR_SWIPE`、`SWIPE`（如误触发三指下滑）或 `HOLD` 时，第 4/5 指落板会立即取消三指手势并按新触点数重定基线；若 4 指已开始捏合，260 ms 内落板的第 5 指会按当前缩放比例反推校准初始距离并无缝并入 5 指跟踪，进度连续无跳变。
- **抬指收尾与快速轻拍解锁**：第一指抬起即完成整手捏合，避免后续慢抬手指触发滑动；一旦全部手指离板、检测到新手指按下（捏合刚结束立即单指轻点图标），或单个角落残指停留超过 120 ms，立即解除抬指锁定。

| 条件 | 结果 |
| --- | --- |
| 四指：综合张开度或对向跨度折算变化 ≥ 1.5 mm，且 ≥ 中心位移的 34% | 捏合或张开 |
| 五指：综合张开度或对向跨度折算变化 ≥ 1.3 mm，且 ≥ 中心位移的 22% | 捏合或张开 |
| 四指中心移动 ≥ 4 mm（变化 < 22%）或 ≥ 7 mm（变化 < 34%）；五指纯平移 ≥ 9 mm（变化 < 16%） | 滑动 |
| 其他 | 继续等待 |

在 Arch Linux ARM aarch64 上，从仓库根目录运行以下命令。需要 `base-devel`、libinput 的系统运行库和 Arch 原版 `libinput 1.32.0-1` 包（若未全局安装 Meson / Ninja，构建脚本会自动复用 `/var/cache/pacman/pkg/` 中的缓存包）。脚本保留系统包的规则和设备配置，并一并应用[三指拖移即时松开补丁](../patches/libinput-1.32.0-immediate-3fg-release.patch)。

```bash
./scripts/build-silky-libinput.sh
sudo pacman -U ~/.local/share/silky-omarchy/libinput/libinput-1.32.0-1.4-aarch64.pkg.tar.xz
```

安装后注销并重新登录，Hyprland 在启动时载入新 `libinput`。用 `pacman -Q libinput` 确认版本为 `1.32.0-1.4`，再看 Hyprland socket2 的 `silkypinch>>4` 和 `silkypinch>>5`。隔离 C 仿真已验证错峰 `3→5` 指落板（含底部软按钮区与侧贴拇指）、4 mm 微幅纵向抓拢、`4→5` 指中途无缝升级、捏合后残指立即轻拍解锁及四指垂直滑动；物理触控板五指手感需在重新登录新会话后做实机确认。

回滚时重新安装原版，并注销后重新登录。

```bash
sudo pacman -U /var/cache/pacman/pkg/libinput-1.32.0-1-aarch64.pkg.tar.xz
```

## 快速连续点击与 Dock 穿透

应用程序面板打开时，`macspot` 叠层将底部 Dock 胶囊区域从输入遮罩中挖空（[`tune-apps-dock-passthrough.py`](../scripts/tune-apps-dock-passthrough.py) 与 [`tune-apps-panel.py`](../scripts/tune-apps-panel.py)），使 Dock 在面板打开期间保持直接可点：点 Dock「应用程序」图标直接收起或反向，快速连点全程落在同一 `MacDock` 表面而不会因跨层遮罩切换丢点击；点其他 Dock 图标直接启动或切换对应应用并自动收起面板；点面板与 Dock 以外的任意桌面空白仍立即关闭面板。

同时，C++ 插件的 `onMouseButton` 只在指针当前焦点的表面与指针下方实际顶层 `LayerSurface` 不一致（如静止光标下叠层刚刚开合）时才重算指针焦点；焦点已匹配时不注入合成移动事件，避免干扰面板内或 Dock 上的快速轻点。

用[手势插件安装脚本](../scripts/install-silky-gestures.sh)重载 Hyprland 插件，用[应用程序面板恢复脚本](../scripts/restore-silky-apps-panel.py)或[MacShell 优化安装脚本](../scripts/install-macshell-optimizations.sh)同步更新 `MacBar.qml` 与 `MacDock.qml`：

```bash
python3 scripts/restore-silky-apps-panel.py
qs ipc -c MacShell call macshell reload
```

验证时可分别测试：保持光标停在面板外轻点空白关闭、快速连点 Dock「应用程序」图标、面板打开时直接点击其他 Dock 图标、刚打开面板立即快点内部应用图标，以及搜索框点击输入。回滚时恢复 `~/.local/state/silky-omarchy/` 下生成的 `MacBar.qml.before-apps-update.*`、`MacDock.qml.before-apps-update.*` 与版本化插件备份并重载。

## 安装

```bash
./scripts/install-silky-gestures.sh
```

脚本会：

1. 用已安装的 Hyprland 头文件编译插件
2. 安装到 `~/.local/lib/silky-omarchy/silky-gestures-<Hyprland 版本>.so`
3. 把 [`config/hypr/silky-gestures.lua`](../config/hypr/silky-gestures.lua) 复制到 `~/.config/hypr/`，并在 `hyprland.lua` 末尾加入 `require("hypr.silky-gestures")`（先备份）
4. 重新加载配置

只想编译不想启用时加 `--build-only`。

### 系统更新后自动恢复

`./scripts/install-silky-gestures.sh` 会一次性注册 [Omarchy 更新钩子](../hooks/post-update-silky-gestures)。以后执行 `omarchy update`，钩子在系统包更新后执行，已生效的改动会跳过。

- **Hyprland**：按版本号和 ABI 判断是否需要重编译。当前会话与新包 ABI 一致时热加载。ABI 不同时为下一次登录预编译。
- **应用程序面板与 Dock 协同**：[`restore-silky-apps-panel.py`](../scripts/restore-silky-apps-panel.py) 在兼容的 `MacBar.qml` 与 `MacDock.qml`（已验证 MacShell 0.5.2/0.5.3）上自动恢复捏合、临界阻尼动画、Dock 穿透与 `silky-dock-glass` 面板标记，并在写入前备份原文件。新布局不兼容时停止写入并报错提示。
- **libinput**：登记本地 `1.32.0-1.4` 归档摘要。若系统更新用原版 `1.32.0-1`（或旧定制包 `1.1`–`1.3`）覆盖了它，钩子在校验本地归档后自动恢复 `1.32.0-1.4`。上游升级到其他版本时保留新系统包并提示需要适配补丁。

已安装定制 libinput 的机器执行一次手势插件安装即可登记。随后可以单独运行钩子验证，当前版本都就绪时不会重新编译或改写。

```bash
~/.config/omarchy/hooks/post-update.d/silky-gestures.hook
```

要关闭 libinput 自动恢复，在安装回原版之前删除 `${XDG_STATE_HOME:-$HOME/.local/state}/silky-omarchy/libinput-maintained`。要停用整个更新钩子，将 `silky-gestures.hook` 移出 `post-update.d`。MacBar 自动恢复前的备份保存在同一状态目录。

## 触控屏移动、缩放浮动窗口

Hyprland 0.57 只接受带鼠标按键序列号的 `xdg_toplevel.move` / `resize` 请求，手指发起的请求会被丢弃，所以浮动窗口在触控屏上拖不动（之前只给 MacShell 的“关于本机”等窗口单独做了 `TouchWindowMove.qml`）。插件在合成器层面接管：

| 手指按下的位置 | 行为 |
| --- | --- |
| 浮动窗口顶部 44 px（Omarchy 标题栏、应用自己的标题栏或工具栏） | 移动超过 10 px 后开始移动窗口 |
| 窗口边缘内外各 8 px（共 16 px）；四角沿两边各 16 px | 移动超过 10 px 后开始缩放，角块同时改宽高 |
| 窗口其他位置 | 按住不动 0.4 秒后可拖动移动；在此之前就移动了，则当作应用自己的拖动（滚动、选择文字） |

**所有触摸都立即交给应用**，和没有插件时完全一样；只有当它确定是窗口操作（标题区或边缘拖过阈值、或按住不动 0.4 秒）时，才给应用发一个标准的触摸取消（`wl_touch.cancel`），然后接管去移动或缩放窗口。所以轻点、滚动、按下高亮都和原来一样，没有延迟。按下后又加一根手指（比如双指缩放）时，插件不再关注这次触摸。

Folio 的文件区由应用处理触摸。触屏滑动可以滚动，长按可以打开文件菜单。拖动 Folio 顶部仍可移动窗口。见 [Folio 的 Finder 外观](04-macos-theme.md#folio-的-finder-外观)。

> 早期版本是先把按下事件扣住、松手时再补发给应用。补发的“按下”和真正的“抬起”落在同一个 `wl_touch.frame` 里，Chromium / Electron 应用（Claude、Chrome、VS Code）会直接丢掉这种点击，表现为窗口里很多地方点了没反应。现在不再扣留；屏幕边缘的工作区滑动仍需要扣留，它补发按下后会立即发送一个 frame，与抬起分开。

移动和缩放走的是 Hyprland 鼠标拖动的同一条路径（`g_layoutManager->beginDragTarget` → `moveMouse` → `endDragTarget`），吸附等行为与鼠标一致。开始拖动前会把指针移到手指位置，因为布局从指针位置读取拖动起点。

只处理浮动窗口；平铺窗口和铺满整个屏幕的窗口照常交给应用。屏幕左右边缘 20 px 的工作区滑动优先。手指按在窗口上方的 shell 图层上（MacShell 的应用程序 / Spotlight 面板、菜单栏、Dock、弹出菜单等 top / overlay 层，按各自的输入区域判断）时，插件不接管，触摸只交给这个图层，不会拖动它后面的窗口。

### 浮动窗口不能越过菜单栏

菜单栏占用屏幕顶部的保留区（`monitor.reserved` 的 top，如 23 px）。Hyprland 只让平铺窗口避开它，浮动窗口不仅可能被拖进菜单栏下面，在多屏重排、工作区切换、退出全屏或新开窗口时也可能越过顶栏（尤其是 `foot` 等由 `hyprbars` 在 `window.at.y` 上方绘制 30 px 标题栏的窗口）。

插件（0.8.4 起）在合成器层同时做两类防护：
- **拖动过程**：监听 `g_layoutManager->dragController()->m_events.motion / ended`（鼠标和触控都走这里），每一步拖动后若窗口顶端（含 `hyprbars` 标题栏，`RESERVED_EXTENTS`）高过保留区下沿 + 4 px，就放回下沿以下；从上边缘缩放时上边停在那里、下边不动；拖动结束后（`doLater`）复检一次。
- **非拖动生命周期与多屏兜底**：监听 `window.openLate`、`window.floating`、`window.fullscreen`、`window.moveToWorkspace`、`workspace.moveToMonitor`、`monitor.added / removed / layoutChanged`、`layer.opened`、`config.reloaded` 以及插件加载时，跳过全屏和隐藏窗口，对真正越过 `monitor.y + reserved.top` 的浮动窗口自动拉回顶栏下方（必要时收窄高度避免超出工作区），而紧贴顶栏下沿的半屏／四角吸附窗口不会被误推偏。
- **Lua 精确高度接口**：向 Lua 暴露 `hl.plugin.silky_gestures.window_top_inset(address)`，返回窗口客户端顶边到外框顶边（含 `hyprbars`）的真实高度，供 [`silky-workspaces.lua`](../config/hypr/silky-workspaces.lua) 与 [`silky-shortcuts.lua`](../config/hypr/silky-shortcuts.lua) 使用。

### 带标题栏的窗口（终端）与 Omarchy 的标题栏

Omarchy 的标题栏插件（`omarchy-hyprland-titlebars`）自己也处理标题栏上的触摸拖动，但有两个问题：

- 它判断“这次触摸是否属于我”时看的是**鼠标指针**的位置（`inputIsValid()` 里的 `getMouseCoordsInternal()`），触摸不会移动指针，所以多数时候它直接忽略手指，单指拖标题栏没有反应
- 它真的接手时，是为平铺工作区设计的：开始拖动时把窗口设为浮动并钉住，**松手时再改回平铺**（`handleUpEvent` 里 `if (m_bTouchEv) floatWindow(TOGGLE_ACTION_DISABLE)`），也不取消钉住

所以标题栏上的拖动由本插件自己处理（与其他窗口的标题区一样）；同时记下窗口原来是否钉住，松手后（`doLater`，下一帧之前）如果 Omarchy 标题栏碰巧也接手、把窗口改成了平铺，就恢复浮动、放回松手位置，原来没钉住的取消钉住。

### 应用自身不支持触摸的地方

用诊断日志确认过：触摸事件都正确送到了窗口。Claude 桌面版的终端面板是网页终端组件（xterm.js），只响应鼠标滚轮和触控板滚动，不响应触摸拖动滚动——卸载本插件后同样如此，属于应用本身的限制。

### 不让应用收到“没按下就移动”的触摸事件

插件会暂扣某些手指的按下事件。如果之后这根手指的移动或抬起又被放给应用，应用会收到一个它从没见过按下的触摸点；Qt 程序（MacShell / Quickshell）会因此崩溃（`QEventPoint::device()` 空指针，崩溃在 `QQuickDeliveryAgentPrivate::deliverUpdatedPoints`）。第一版就踩到了：拖窗口时第二根手指落下又被暂扣，第一根抬起后状态被清空，第二根的后续事件漏给了应用。

现在所有触摸事件外面包了一层：插件记下每一根被暂扣按下事件的手指 ID，这根手指之后的移动、抬起一律暂扣，直到它抬起；只有插件主动把它交还应用（补发按下事件）时才放行。无论手势状态怎样重置，都不会漏出不成对的事件。卸载插件时如果还有被暂扣的手指，会先向应用发送触摸取消。

重新安装插件时请不要触摸屏幕：重载瞬间正在按着的手指可能产生不成对的事件。

已在 Yoga Slim 7 14Q8X9 的触控屏上实测：标题区拖动、边缘/四角缩放、长按拖动、轻点按钮和滚动都正常。

调整参数在 `main.cpp` 开头：`TITLE_PX`、`RESIZE_PX`、`CORNER_PX`、`HOLD_MS`。

### 原生拖拽吸附预览（`0.8.5`）

[`plugins/silky-gestures/snap-preview.hpp`](../plugins/silky-gestures/snap-preview.hpp) 在 Hyprland `RENDER_POST_WINDOWS` 阶段直接使用 `CRectPassElement` 和 `CBorderPassElement` 绘制半屏/四角拖拽吸附的蓝色圆角预览框（65 ms 淡入、45 ms 淡出、90 ms 同屏平滑过渡），通过 Lua 接口 `hl.plugin.silky_gestures.snap_preview(output, x, y, w, h)` 与 `snap_preview_hide()` 供 [`config/hypr/silky-folio.lua`](../config/hypr/silky-folio.lua) 调用，避免经 socket2 唤醒 MacShell 的全屏透明 Vulkan 层。插件未加载时自动回退到 [`FolioSnapPreview.qml`](../config/macshell/FolioSnapPreview.qml)。

## 验证

```bash
hyprctl plugin list
```

应列出 `silky-gestures`。

## 停用

```bash
hyprctl plugin unload ~/.local/lib/silky-omarchy/silky-gestures-$(pkg-config --modversion hyprland).so
```

要永久停用，删除 `~/.config/hypr/hyprland.lua` 里的 `require("hypr.silky-gestures")` 一行。

## 风险

这是运行在合成器进程内的原生代码，如果有缺陷可能导致 Hyprland 崩溃，届时所有打开的应用都会随之关闭。加载、卸载和重载配置已在嵌套的 Hyprland 实例中验证；手势本身只能在真机上用手指验证。
