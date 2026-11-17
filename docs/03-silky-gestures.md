# 03 · 触控屏工作区手势与到头回弹

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
| 指针不动、连续点击会改变输入区域的图层（Dock 的“应用程序”图标） | 每次点击都生效 |

细节：

- 第三根手指落下时，前两根手指已经发给应用的触摸会被取消，之后直到所有手指抬起都不再传给应用
- 边缘上的单指轻点、以及沿着边缘上下拖动（例如滚动条），仍然会交还给应用
- 回弹使用 `workspaces` 动画的曲线和速度
- 锁屏时不响应
- 四指 / 五指捏合跟手：插件把进度通过 socket2 事件 `silkylaunchpad>>begin`、`update,<量>`、`end[,cancel]` 发给 MacShell。“量”是 `1 − 缩放比例`（捏合为正，张开为负）。触控板用 libinput 的 pinch 手势（两指、三指捏合不拦截）；触控屏用手指到中心的平均距离，变化超过 6% 就算捏合
- 触控屏四指及以上时，只有横向移动超过 28 px 且大于间距变化，才当作切换工作区
- 不用 `hl.gesture` 的 pinch：它的函数动作要等抬手才执行，无法跟手
- 排查：每次触控板捏合都会发出 `silkypinch>>手指数`。如果四指捏合没反应，运行 `socat - UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock | grep silky` 后再捏一次，看 libinput 报告了几根手指

- 捏合行程：张开程度缩小约 25% 面板就完全打开（原来 35%），张开约 30% 完全关闭；松手时走过三分之一就完成，否则退回
- 排查：触控板的滑动手势同样会发出 `silkyswipe>>手指数`。捏合没反应而这里出现了 `silkyswipe>>4`，说明 libinput 把这次捏合判成了滑动（见下文“触控板四指 / 五指捏合识别”）

可调参数是 `main.cpp` 顶部的常量：边缘宽度 `EDGE_PX`、手指数 `MULTI_FINGERS`、甩动速度 `FLICK_PX_PER_SEC`、回弹最大幅度 `RUBBER_LIMIT`、阻尼 `RUBBER_STIFFNESS`，以及捏合的手指数 `PINCH_FINGERS` 和触控屏判定阈值 `PINCH_START`。改完重新运行安装脚本。

## 触控板四指 / 五指捏合识别

触控板上“是捏合还是滑动”由 libinput 决定，插件只能收到结果。libinput 1.32 对三指以上的手势只跟踪最上面和最下面两个触点：

- 整只手捏合时拇指通常比其余手指动得少。其余手指移动超过 8 mm 而拇指不足 2.5 mm 时，libinput 认为拇指是“搁着的”，把它屏蔽并取消手势，剩下的手指被当成三指拖移或滑动
- 两个被跟踪的触点方向相邻（例如一个向下、一个向右下）时，判成滑动

这就是四指、五指捏合经常调不出应用程序面板的原因。[`patches/libinput-1.32.0-multifinger-pinch.patch`](../patches/libinput-1.32.0-multifinger-pinch.patch) 让四指及以上的手势改用全部触点判断：比较“手的张开程度”（各触点到共同中心的平均距离）的变化和这个中心移动的距离。

| 条件 | 结果 |
| --- | --- |
| 张开程度变化 ≥ 2.5 mm，且不小于中心位移的 35% | 捏合 |
| 中心位移 ≥ 3 mm，且张开程度变化小于它的 35% | 滑动 |
| 其他 | 继续等待 |

用模拟轨迹验证：五指捏合（拇指动或不动）、三指加拇指、四指并拢，都在动作的约 30% 处判为捏合；四指左右 / 上下滑动（包括手指略微散开）在约 8–10% 处判为滑动。两指、三指手势不受影响。**真实手指上的效果需要安装后在本机确认**。

补丁需要和 [`libinput-1.32.0-immediate-3fg-release.patch`](../patches/libinput-1.32.0-immediate-3fg-release.patch) 一起打在 libinput 1.32.0 源码上（先 3fg，后 multifinger）。本机已编好的包在 `~/.local/share/silky-omarchy/libinput/`：

```bash
sudo pacman -U ~/.local/share/silky-omarchy/libinput/libinput-1.32.0-1.2-aarch64.pkg.tar.xz
```

安装后注销并重新登录（Hyprland 启动时加载 libinput）。回退到只有三指拖移补丁的版本：

```bash
sudo pacman -U ~/.local/share/silky-omarchy/libinput/libinput-1.32.0-1.1-aarch64.pkg.tar.xz
```

## 快速连续点击

Hyprland 只在指针移动时才确定指针下面是哪个窗口。MacShell 的 Spotlight / 应用程序面板是一个全屏图层：打开时接收整个屏幕的输入，关闭后不接收任何输入。指针不动、快速连点 Dock 的“应用程序”图标时，第二次点击（落在面板上，关闭它）之后的所有点击仍被送到已经关闭的面板图层，什么都不发生，直到鼠标动一下。

插件监听鼠标按键：按下时如果没有其他按键被按住、指针没有被锁定、并且当前指针焦点是图层表面（或为空），就先让 Hyprland 重新确定指针下的表面（`simulateMouseMovement`），再处理这次点击。焦点在普通窗口上时不做任何事。

用虚拟鼠标实测（指针停在图标上不动）：每秒 6–9 次连点 8、9、11 次，每一次点击都切换了面板，最终状态与点击次数的奇偶一致；修复前只有前两次有效。

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

### Hyprland 更新之后

插件和 Hyprland 版本绑定。文件名里带版本号，所以更新 Hyprland 后旧文件不会被加载，手势只是暂时失效，不会报错；重新登录后再运行一次安装脚本即可。

## 触控屏移动、缩放浮动窗口

Hyprland 0.57 只接受带鼠标按键序列号的 `xdg_toplevel.move` / `resize` 请求，手指发起的请求会被丢弃，所以浮动窗口在触控屏上拖不动（之前只给 MacShell 的“关于本机”等窗口单独做了 `TouchWindowMove.qml`）。插件在合成器层面接管：

| 手指按下的位置 | 行为 |
| --- | --- |
| 浮动窗口顶部 44 px（Omarchy 标题栏、应用自己的标题栏或工具栏） | 移动超过 10 px 后开始移动窗口 |
| 窗口边缘内外各 8 px（共 16 px）；四角沿两边各 16 px | 移动超过 10 px 后开始缩放，角块同时改宽高 |
| 窗口其他位置 | 按住不动 0.4 秒后可拖动移动；在此之前就移动了，则当作应用自己的拖动（滚动、选择文字） |

**所有触摸都立即交给应用**，和没有插件时完全一样；只有当它确定是窗口操作（标题区或边缘拖过阈值、或按住不动 0.4 秒）时，才给应用发一个标准的触摸取消（`wl_touch.cancel`），然后接管去移动或缩放窗口。所以轻点、滚动、按下高亮都和原来一样，没有延迟。按下后又加一根手指（比如双指缩放）时，插件不再关注这次触摸。

> 早期版本是先把按下事件扣住、松手时再补发给应用。补发的“按下”和真正的“抬起”落在同一个 `wl_touch.frame` 里，Chromium / Electron 应用（Claude、Chrome、VS Code）会直接丢掉这种点击，表现为窗口里很多地方点了没反应。现在不再扣留；屏幕边缘的工作区滑动仍需要扣留，它补发按下后会立即发送一个 frame，与抬起分开。

移动和缩放走的是 Hyprland 鼠标拖动的同一条路径（`g_layoutManager->beginDragTarget` → `moveMouse` → `endDragTarget`），吸附等行为与鼠标一致。开始拖动前会把指针移到手指位置，因为布局从指针位置读取拖动起点。

只处理浮动窗口；平铺窗口和铺满整个屏幕的窗口照常交给应用。屏幕左右边缘 20 px 的工作区滑动优先。

### 浮动窗口不能拖到菜单栏下面

菜单栏占用屏幕顶部的保留区（`monitor.reserved` 的 top，这台机器上 21 px）。Hyprland 只让平铺窗口避开它，浮动窗口可以被直接拖进菜单栏下面。插件监听 Hyprland 的拖动控制器（`g_layoutManager->dragController()->m_events.motion / ended`，鼠标和触控都走这里）：每一步拖动后，如果窗口顶端（含标题栏）高过保留区下沿 + 4 px，就把它放回下沿以下；从上边缘缩放时上边停在那里、下边不动。拖动结束后（`doLater`）再检查一次。

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
