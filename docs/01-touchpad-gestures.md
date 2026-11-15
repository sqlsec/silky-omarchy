# 01 · 触控板手势

## 目标

- 三指移动：像 macOS 的“三指拖移”一样拖动窗口、文件、选中文本和滑块
- 四指左右滑动：以跟手动画切换当前显示器上的工作区
- 滑到工作区边缘时回弹，不自动创建新的空工作区

## 为什么这样分配

三指拖移和工作区切换如果使用相同的手指数，会发生手势竞争。将拖移固定为三指、工作区固定为四指，既接近 macOS 的使用习惯，也能由 Hyprland 和 libinput 原生完成，无需安装额外的手势守护程序。

## 配置

将 [`config/hypr/input-touchpad.lua`](../config/hypr/input-touchpad.lua) 的内容加入 `~/.config/hypr/input.lua`。

关键设置：

```lua
hl.config({
  input = {
    touchpad = {
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

`drag_3fg = 1` 表示使用三指拖移；值 `2` 会改用四指，与四指工作区手势冲突，因此不要使用。

## 应用与验证

```bash
hyprctl reload
hyprctl configerrors
hyprctl getoption input:touchpad:drag_3fg
```

预期结果：

- `hyprctl configerrors` 没有输出
- `drag_3fg` 显示 `int: 1` 和 `set: true`
- 三指放在触控板上移动时可以拖动目标
- 四指水平滑动时工作区随手指移动，松手后完成切换或回弹

## 回滚

删除上述 `hl.config` 与 `hl.gesture` 配置块，然后重新执行：

```bash
hyprctl reload
hyprctl configerrors
```

## 已验证环境

- Omarchy Linux
- Hyprland 0.57.2
- 内置 HID-over-I2C 触控板

