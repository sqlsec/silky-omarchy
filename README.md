# Silky Omarchy

一套受 macOS 启发的 Omarchy Linux 体验优化，逐项记录设计思路、配置、验证方法和回滚方式。

## 优化进度

| 模块 | 状态 | 内容 |
| --- | --- | --- |
| 触控板 | ✅ 已实现 | 三指拖移、四指横滑切换工作区 |
| MacShell | ✅ 已实现 | 简体中文、关于页、触控优化、实时玻璃与 Vulkan GPU 渲染 |

## 配置原则

- 只修改用户配置，不直接修改 `/usr/share/omarchy/`
- 每项优化都提供配置片段、验证步骤与回滚说明
- 优先使用 Omarchy 和 Hyprland 的原生能力，减少额外守护进程

## 文档

- [01 · 触控板手势](docs/01-touchpad-gestures.md)
- [02 · MacShell 汉化、实时玻璃与 GPU 优化](docs/02-macshell.md)

