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

