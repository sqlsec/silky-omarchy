# 01 · 触控板手势

简体中文 | [English](en/01-touchpad-gestures.md)

## 目标

- 双指滚动：使用 macOS 式自然滚动，内容跟随手指方向移动
- 三指移动：像 macOS 的“三指拖移”一样拖动窗口、文件、选中文本和滑块
- 四指左右滑动：以整页跟手动画切换当前显示器上的工作区
- 四指上滑 / 下滑：窗口总览（当前工作区 / 当前应用的所有窗口），触控屏四指上下滑同样可用，由 silky-gestures 插件和 MacShell 实现，见 [13](13-window-overview.md)
- 滑到工作区边缘时回弹，不自动创建新的空工作区

## 为什么这样分配

三指拖移和工作区切换如果使用相同的手指数，会发生手势竞争。将拖移固定为三指、工作区固定为四指，既接近 macOS 的使用习惯，也能由 Hyprland 和 libinput 原生完成，无需安装额外的手势守护程序。

## 配置

将 [`config/hypr/input-touchpad.lua`](../config/hypr/input-touchpad.lua) 的内容加入 `~/.config/hypr/input.lua`，再将 [`config/hypr/looknfeel-workspaces.lua`](../config/hypr/looknfeel-workspaces.lua) 的内容加入 `~/.config/hypr/looknfeel.lua`。

关键设置：

```lua
hl.config({
  input = {
    touchpad = {
      natural_scroll = true,
      drag_3fg = 1,
    },
  },
  gestures = {
    workspace_swipe_create_new = false,
    workspace_swipe_use_r = false,
  },
})

hl.gesture({ fingers = 4, direction = "horizontal", action = "workspace" })
```

`touchpad.natural_scroll = true` 改变触控板滚动方向：双指向上移动时，页面内容也会向上移动。外层的 `input.natural_scroll = true` 让鼠标滚轮也用同样的方向。它原本由 MacShell 启动后临时写入，MacShell 没启动时就会失效，所以直接写进 Hyprland 配置。`drag_3fg = 1` 表示使用三指拖移；值 `2` 会改用四指，与四指工作区手势冲突，因此不要使用。

### 工作区过渡动画

Omarchy 默认关闭 `workspaces` 动画。如果只添加触控板手势，工作区仍会生硬地直接切换。下面的覆盖会启用整页水平滑动，并在松手后使用快起慢收的缓动完成切换或回弹：

```lua
hl.curve("silkyWorkspaceEaseOut", {
  type = "bezier",
  points = { { 0.16, 1.0 }, { 0.30, 1.0 } },
})

hl.animation({
  leaf = "workspaces",
  enabled = true,
  speed = 4.0,
  bezier = "silkyWorkspaceEaseOut",
  style = "slide",
})
```

`speed = 4.0` 表示松手后的动画最长约为 400ms；拖动过程中仍由手指实时控制进度。

### 微信会话列表触屏滚动

微信 4.x 是静态链接 Qt 的闭源无边框自绘应用，右上角的最小化（`—`）、最大化（`□`）、关闭（`×`）按钮直接绘制在应用内部，因此沿用其自带按钮，不额外叠加系统标题栏。此前本机依赖针对 `wechat-bin 4.1.13.26` ARM64 的二进制补丁和校验哈希才能在原生 Wayland 下运行；升级到 `4.1.13.29` 后哈希失效、启动器自动回退到 XWayland（`QT_QPA_PLATFORM=xcb`），导致顶部栏无法直接用鼠标拖动、消息列表与会话内容区的触屏拖动滚动全部失效，且最小化按钮无响应。

更新后的 Wayland 适配库 [plugins/wechat-wayland/touch-scroll.c](../plugins/wechat-wayland/touch-scroll.c) 与启动器 [bin/wechat-wayland-touch](../bin/wechat-wayland-touch) 从协议层解决了这些问题，不再依赖特定版本的二进制补丁：

- **空 `wl_touch.frame` 过滤**：微信内置的 `QWaylandInputDevice::Touch::touch_frame()` 在触控点列表为空时会直接解引用导致崩溃（例如 `silky-gestures` 接管手势发送 `touch_cancel` 后紧跟空 `touch_frame`）。适配库通过 `LD_AUDIT` 拦截 `wl_touch`，仅在当前帧实际转发过 `down` / `motion` / `up` 时才向下游转发 `frame`，从而在任意版本下稳定运行原生 Wayland。
- **顶部栏拖动与自带按钮**：原生 Wayland 下，顶部栏直接通过 `xdg_toplevel.move` 支持鼠标拖动；关闭按钮隐藏到系统托盘。由于微信的 `xdg_toplevel` 无返回值请求走 `wl_proxy_marshal_array`，且 Omarchy 全局规则默认对所有窗口启用了 `suppress_event = "maximize"`、Hyprland 默认忽略 `set_minimized`，适配库同时拦截 `wl_proxy_marshal_array` 与 `wl_proxy_marshal_array_flags`：仅当微信窗口内最近 500 ms 有用户鼠标点击或触屏轻点时才转发按钮请求，既让右上角最小化（opcode 13，调用 MacShell 神奇效果或 `omarchy-hyprland-window-minimize`）、最大化/还原（opcode 9 / 10，经 `hyprctl eval` 仅作用于当前活动微信窗口）正常工作，又拦截微信从托盘或启动器重开时 Qt 自动发出的 `set_maximized`，避免每次点开被强行最大化。
- **消息列表与会话内容触屏滚动**：顶部栏下方（`y >= 54` 逻辑像素）单指按下时先暂存 `touch_down` 而不立刻透传给微信，避免微信在按下瞬间就误点开手指下的会话或消息；纵向移动满 6 px 直接丢弃暂存的按下事件并进入 1:1 零延迟滚动（`WL_POINTER_AXIS_SOURCE_FINGER`），同时覆盖左侧消息列表和右侧会话内容区；原地轻点松手或横向拖动超过 6 px 时再补发完整的按下事件，正常切换会话、点击按钮或拖选文字。松手后按最近 90 ms 的真实离手速度，通过主线程 `wl_surface_frame` VSync 回调驱动指数衰减惯性滑行（不自行提交 `wl_surface.commit`，滚到边界自动停止）；惯性滑行中手指一碰屏幕立即刹停且屏蔽当次轻点。触控板和鼠标滚轮仍走各自路径。设置 `WECHAT_TOUCH_SCROLL_SCALE`（默认 `1.0`）可微调滚动比例，设置 `WECHAT_TOUCH_SCROLL=0` 可单独关闭触屏滚动转换而保留空帧防护与最小化转发，`WECHAT_WAYLAND=0` 可临时回退到 XWayland。

从仓库根目录运行安装脚本即可编译适配库、安装启动器与用户桌面入口并重载 Hyprland：

```bash
./scripts/install-wechat-touch-scroll.sh
```

需要 GCC 或兼容的 C 编译器、`pkg-config`、Wayland 客户端开发文件和 Hyprland Lua 配置。脚本会写入 `~/.local/share/wechat-wayland/touch-scroll.so`、`~/.local/bin/wechat-wayland-touch`、`~/.local/share/applications/wechat.desktop` 与 `~/.config/hypr/silky-wechat-glass.lua`，覆盖前自动备份。完全退出微信后从应用启动器重新打开生效。

验证：

- 运行 `hyprctl clients -j | jq -c '.[] | select(.class=="wechat") | {title, xwayland}'`，确认主窗口 `xwayland` 为 `false`，且 `/proc/$(pgrep -x wechat | head -n 1)/maps` 已加载 `touch-scroll.so`。
- 实机上已确认微信 `4.1.13.29` ARM64 直接以原生 Wayland 启动并加载新库；隔离单元测试覆盖了空 `touch_frame` 丢弃、`touch_cancel` 后空帧过滤、正常轻点转发、标题栏下方纵向滑动转连续滚动与标题栏内不误触发滚动。实体触屏在消息列表与会话内容区的连续滚动手感、以及主窗口登录后的拖动与最小化/最大化按钮操作待在桌面交互中复核。

回滚时退出微信，从安装器报告的 `*.bak.*` 恢复 `~/.local/share/wechat-wayland/` 下的 `touch-scroll.c` 和 `touch-scroll.so`、`~/.local/bin/wechat-wayland-touch`、`~/.local/share/applications/wechat.desktop` 以及 `~/.config/hypr/silky-wechat-glass.lua`，执行 `hyprctl reload` 后重新打开微信。


## 应用与验证

```bash
hyprctl reload
hyprctl configerrors
hyprctl getoption input:touchpad:natural_scroll
hyprctl getoption input:natural_scroll
hyprctl getoption input:touchpad:drag_3fg
hyprctl animations
```

预期结果：

- `hyprctl configerrors` 没有输出
- `natural_scroll` 显示 `bool: true` 和 `set: true`
- `drag_3fg` 显示 `int: 1` 和 `set: true`
- `hyprctl animations` 中的 `workspaces` 显示 `enabled: 1`、`style: slide`
- 三指放在触控板上移动时可以拖动目标
- 四指水平滑动时工作区随手指移动，松手后完成切换或回弹

## 回滚

删除上述 `hl.config`、`hl.gesture`、`hl.curve` 和 `hl.animation` 配置块，然后重新执行：

```bash
hyprctl reload
hyprctl configerrors
```

## 已验证环境

- Omarchy 4.5.0
- Hyprland 0.57.2
- libinput 1.32.0
- 内置 HID-over-I2C 触控板

