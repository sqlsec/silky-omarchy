# 00 · 给 AI 编程助手的复现索引

把这份文件连同仓库地址交给 Claude Code、Codex、Cursor 等 AI 编程助手，它就能按模块复现这套优化，不需要你逐条解释。每个模块列出：要达到的效果、关键文件、检索关键词、容易踩的坑、验证命令。细节见对应的编号文档。

## 环境前提

- 发行版：Omarchy 4.x（Arch Linux + Hyprland 0.57.x，**Lua 配置**：`~/.config/hypr/*.lua`，`hl.config` / `hl.bind` / `hl.window_rule` / `hl.layer_rule`）
- 测试机器：Lenovo Yoga Slim 7 14Q8X9，Snapdragon X Elite，Adreno X1-85，aarch64，2944×1840@90Hz，缩放 2
- 桌面外壳：MacShell 0.5.1（Quickshell / QML），锁屏 MacLock
- 输入法：fcitx5 + WowType（拼音 + 离线语音）
- 规则：永远不改 `/usr/share/omarchy/`，只改 `~/.config`、`~/.local`；改 Hyprland 配置后执行 `hyprctl configerrors`

给 AI 的通用提示词：

> 这是 Omarchy（Hyprland Lua 配置）系统。按 `docs/00-ai-reproduction.md` 的模块 N 复现，只改用户目录，每一步改完用文中的验证命令确认，修改前备份原文件。

## 安装顺序

```bash
./scripts/install-macshell-optimizations.sh   # 02：MacShell 补丁（需要先装好 MacShell 0.5.1）
./scripts/install-silky-gestures.sh           # 03：工作区手势插件
./scripts/install-macos-theme.sh              # 04：macOS Tahoe 主题
omarchy theme set macos-tahoe-dark
./scripts/install-voice-overlay.sh            # 05：语音浮条
./scripts/install-zsh.sh                      # 06：终端
./scripts/install-maclock.sh                  # 07：所有锁屏改用 MacLock
./scripts/install-boot-screen.sh              # 07：macOS 风格开机解锁界面
./scripts/install-shortcuts.sh                # 10：快捷键冲突 + Super+K 面板
./scripts/install-menu-glass.sh               # 11：Omarchy 菜单玻璃 + 深浅色
```

01 是手动合并的配置片段，没有脚本。

---

## 01 触控板手势

- **效果**：自然滚动；三指拖移；四指左右滑切换工作区，1:1 跟手
- **文件**：`config/hypr/input-touchpad.lua` → `~/.config/hypr/input.lua`；`config/hypr/looknfeel-workspaces.lua` → `looknfeel.lua`
- **关键词**：`input.touchpad.natural_scroll`、`input.natural_scroll`（鼠标）、`drag_3fg = 1`、`hl.gesture({ fingers = 4, direction = "horizontal", action = "workspace" })`、`workspace_swipe_create_new = false`、`hl.animation({ leaf = "workspaces", style = "slide" })`
- **坑**：Omarchy 默认关掉了 workspaces 动画，必须重新打开才有跟手滑动；三指拖移和三指切换会抢手势，所以切换用四指
- **验证**：`hyprctl getoption input:touchpad:natural_scroll`、`hyprctl getoption input:natural_scroll`

## 02 MacShell 优化

- **效果**：简体中文；紧凑版“关于本机”（正确识别 Snapdragon / Adreno）；触控屏拖窗口；实时玻璃走 Vulkan；消除鼠标周期性卡顿；锁屏显示壁纸；电池图标去 `%`；不显示桌面图标；截图只用一个工具
- **文件**：`patches/macshell-0.5.1-silky.patch`（对 `~/.config/quickshell/{MacShell,MacLock}` 的统一 diff）、`scripts/install-macshell-optimizations.sh`
- **关键词**：
  - 渲染：`QSG_RHI_BACKEND=vulkan`、`QSG_RENDER_LOOP=threaded`（写在 `~/.config/macshell/env`）
  - 卡顿：MacShell “自动对比度”用 `grim` 定时截屏 → 每次让 Hyprland 主线程停 60–110 ms；改成事件驱动，并用 `assets/tone-wall.sh` 直接读壁纸算亮度
  - 触控拖窗：Hyprland 0.57 丢弃没有鼠标按键序列号的 `xdg_toplevel.move`；新增 `TouchWindowMove.qml`，用 Hyprland IPC 按手指位移移动窗口
  - 设置丢失：MacShell 用 `hyprctl eval` 临时写鼠标/触控板设置，`configreloaded` 后要重新应用
  - 锁屏壁纸：MacLock 读 `~/.local/state/omarchy/current/background`
  - 主题联动：新增 IPC `qs -c MacShell ipc call appearance set dark|light`
  - 截图冲突：Omarchy 和 MacShell 同时绑定 `PRINT` → 删掉 `macshell.lua` 里的绑定
- **坑**：MacShell 靠 `~/.config/hypr/macshell.lua` + `hyprland.lua` 里的 `-- >>> MacShell (added by install.sh) >>>` 块开机自启，丢了会导致重启后菜单栏、Dock 消失、滚轮方向反了；重新生成补丁时必须基于纯净的 0.5.1 源码
- **验证**：`./scripts/install-macshell-optimizations.sh --check` 显示 `patch state: applied`；`pgrep -af '^qs -c MacShell'`；`qs -c MacShell ipc show`

## 03 工作区手势插件

- **效果**：工作区到头有阻尼和回弹；触控屏三指滑动、边缘单指滑动切换工作区；触控屏拖动浮动窗口的标题区移动、拖边缘/四角缩放、长按 0.4 秒后任意位置拖动
- **文件**：`plugins/silky-gestures/main.cpp`、`config/hypr/silky-gestures.lua`、`scripts/install-silky-gestures.sh`
- **关键词**：Hyprland C++ 插件、`HyprlandAPI`、`pkg-config hyprland`、按版本命名 `~/.local/lib/silky-omarchy/silky-gestures-<版本>.so`、`gestures.workspace_swipe_touch = false`；窗口拖动：`Desktop::viewState()->hitTest().windowAt(pos, RESERVED_EXTENTS | INPUT_EXTENTS | ALLOW_FLOATING)`、`g_layoutManager->beginDragTarget(target, MBIND_MOVE / MBIND_RESIZE, corner)`、`moveMouse`、`endDragTarget`，开始前 `Pointer::pointerController()->warpTo`；触摸先照常交给应用，确定是窗口操作时再 `g_pSeatManager->sendTouchCancel()` 接管（不要扣留按下再补发：补发的按下和抬起同在一个 `wl_touch.frame` 里，Electron 会丢掉这次点击）
- **坑**：暂扣了按下事件的手指，之后的移动/抬起也必须暂扣直到抬起（按手指 ID 单独记录，别依赖手势状态），否则 Qt 应用收到不成对的触摸点会崩溃；插件必须针对正在运行的 Hyprland 版本编译，每次更新 Hyprland 后要重新运行脚本
- **验证**：`hyprctl plugin list`

## 04 macOS Tahoe 主题

- **效果**：深色/浅色两个 Omarchy 主题；Apple 系统色；14 px 连续曲率圆角、细描边、深阴影、玻璃模糊；MacTahoe 图标（蓝色文件夹）；Finder 风格 Nautilus；浮动窗口红绿灯；切主题时 GTK、指针、MacShell 深浅色一起变
- **文件**：`themes/macos-tahoe-{dark,light}/{colors.toml,hyprland.lua,icons.theme}`、`hooks/theme-set-silky-macos`、`config/hypr/silky-titlebar-guard.lua`、`config/hypr/silky-macos.lua`、`scripts/install-macos-theme.sh`
- **关键词**：
  - 第三方（固定 commit）：`vinceliuice/MacTahoe-icon-theme`、`vinceliuice/MacTahoe-gtk-theme`（用 `release/*.tar.xz` 预编译包，免 sassc）
  - libadwaita 主题：把 `~/.config/gtk-4.0/{gtk.css,gtk-dark.css,assets}` 链接到主题
  - 红绿灯在左：`gsettings set org.gnome.desktop.wm.preferences button-layout 'close,maximize:'`
  - 圆角曲率：`decoration.rounding = 14`、`rounding_power = 2.6`
  - 主题 hook：`~/.config/omarchy/hooks/theme-set.d/`，参数是主题 slug
  - 标题栏：Omarchy 自带 `omarchy-hyprland-titlebars`（hyprbars 构建，浮动工作区时由 `workspace-modes.lua` 加载），选项有 `button_rounding`、`bar_color_inactive`；按钮只能 `add_button` 不能删 → 在 Omarchy 默认配置之前把 `hl.plugin.hyprbars.add_button` 换成空函数拦掉方形按钮，之后用原函数加圆形红绿灯；白名单规则 `["hyprbars:no_bar"] = true/false`
  - 图标：ChatGPT / Claude 用官方图标（MacTahoe 的别名改名为 `*.mactahoe-backup`），Dock 里 `dockIconScale()` 做视觉校正
- **坑**：不要再自己编译加载上游 hyprbars，会和 Omarchy 的那份叠加（两排按钮、方形按钮）；在运行中卸载重复实例会注销 `hyprbars:no_bar` 规则名，只能重新登录；只在插件已加载时写 hyprbars 规则，否则报 `unknown field`
- **验证**：`omarchy theme current`、`gsettings get org.gnome.desktop.interface gtk-theme`、`hyprctl plugin list | grep -c hyprbars` 应为 1

## 05 WowType 语音浮条

- **效果**：WowType 语音输入时，屏幕底部弹出毛玻璃浮条：渐变话筒 + 三条随音量起伏的彩色声波 + 状态文字
- **文件**：`voice-overlay/bridge.py`、`voice-overlay/shell.qml` → `~/.config/quickshell/SilkyVoice/`；`config/hypr/silky-voice.lua`
- **关键词**：D-Bus 名 `io.github.gloridust.WowType.VoiceOverlay`、对象 `/io/github/gloridust/WowType`、接口 `io.github.gloridust.WowType.Voice1`、信号 `State(u state, s label, level, x, y, w, h, b relative, d scale)`（50 ms 一次）、回执信号 `Ack(u)`、音量 0–100 对应 -60…-10 dB；Quickshell `PanelWindow` + `WlrLayershell.namespace: "silky-voice"` + `mask: Region {}`（点击穿透）+ `FrameAnimation` + `Canvas`（`globalCompositeOperation = "lighter"`）
- **坑**：每个显示的状态都要回 `Ack`，否则 WowType 退回文字提示；Omarchy 默认把右 Alt 绑给“系统听写”（Superwhisper），会和 WowType 的右 Alt 同时触发 → 清空 `~/.config/omarchy/defaults/dictation`
- **验证**：`busctl --user list | grep VoiceOverlay`；外观预览 `SILKY_VOICE_DEMO=1 qs -c SilkyVoice`；手动模拟 `gdbus emit --session --object-path /io/github/gloridust/WowType --signal io.github.gloridust.WowType.Voice1.State 1 '' 70.0 0 0 0 0 false 1.0`

## 06 终端

- **效果**：zsh + Oh My Zsh，ys 主题，灰色历史建议、命令对错实时着色、更多补全，同时保持启动快
- **文件**：`config/zsh/zshrc` → `~/.zshrc`；`scripts/install-zsh.sh`
- **关键词**：`zsh-users/zsh-autosuggestions`、`zsh-users/zsh-syntax-highlighting`（必须是最后一个插件）、`zsh-users/zsh-completions`（只加到 `fpath`，不作为插件）、`zstyle ':omz:update' mode disabled`、`DISABLE_MAGIC_FUNCTIONS`、`ZSH_DISABLE_COMPFIX`、`ZSH_COMPDUMP` 放到 `~/.cache`；从 Omarchy 的 bash 配置移植 `mise activate zsh`、`zoxide init zsh`、`/usr/share/fzf/key-bindings.zsh`、eza 别名
- **验证**：`time zsh -i -c exit`

## 07 锁屏与开机界面

- **效果**：所有锁屏都用 MacLock；开机磁盘解锁界面与 MacLock 布局一致（清晰壁纸、底部圆形头像、用户名、毛玻璃密码框，单位 u = 屏高/1200）
- **文件**：`bin/silky-lock`、`bin/silky-sleep-lock`、`config/systemd/silky-sleep-lock.service`、`config/omarchy/plugins/silky.idle/`、`config/hypr/bindings-lock.lua`、`config/omarchy/omarchy-menu-lock.jsonc`、`plymouth/silky-maclock.script`、`scripts/install-maclock.sh`、`scripts/install-boot-screen.sh`
- **关键词**：
  - Omarchy 锁屏的四个入口：`omarchy-system-lock`（Super+Ctrl+L、菜单 `system.lock`）、`omarchy.idle` 服务、`omarchy-sleep-lock.service`（`systemd-inhibit --mode=delay` + `dbus-monitor` 监听 `PrepareForSleep`）
  - MacLock IPC：`qs -c MacLock ipc call lockscreen lock|state`（`ready` / `busy` / `stopping`），入口脚本 `~/.config/quickshell/MacLock/lock-via-ipc.sh`
  - `omarchy plugin clone omarchy.idle` → 改 id 为 `silky.idle`（`omarchy.` 前缀保留给官方），保留 `clonedFrom` 才能读到 `shell.json` 的 `idle` 配置
  - 开机：LUKS + Plymouth（script 模块：`Plymouth.SetDisplayPasswordFunction`、`Image.Scale`、`Sprite.SetPosition`）+ SDDM 自动登录；`plymouth-set-default-theme`，`limine-mkinitcpio` 重建 initramfs
- **坑**：睡眠锁服务锁好后必须立即退出释放 delay 抑制锁，否则 logind 要等到超时才睡眠；Plymouth 在 initramfs 里没有中文字体，文字要预先渲染成图片；高分屏要在 `plymouthd.conf` 设 `DeviceScale=1` 并按原生分辨率出图，否则 Plymouth 按 2 倍缩放整帧放大、发虚；`omarchy-plymouth-set-by-theme` 会把主题改回 `omarchy`
- **验证**：`omarchy plugin list | grep idle`、`systemctl --user is-active silky-sleep-lock`、`plymouth-set-default-theme`
- **状态**：开机界面需要重启后确认

## 10 快捷键

- **效果**：MacShell 与 Omarchy 共用的键（Super+Space、Super+V、Alt+Tab、Alt+Shift+Tab、Super+L）只触发 MacShell；Omarchy 的动作挪到 Super+Ctrl+M（菜单）、Super+Alt+V（通用粘贴）、Super+Shift+L（布局）、Alt+` / Alt+Shift+`（窗口轮换）。Super+K 是毛玻璃快捷键面板：分组、⌘⌥⌃⇧ 键帽、多词搜索、回车执行
- **文件**：`config/hypr/silky-keys-registry.lua`（hyprland.lua 最前）、`config/hypr/silky-shortcuts.lua` 与 `config/hypr/silky-keys.lua`（最后）；`keys-panel/shell.qml` → `~/.config/quickshell/SilkyKeys/`
- **关键词**：Hyprland 一个键多个 bind 会全部执行；包装 `hl.bind`/`hl.unbind` 记录 dispatcher；`hyprctl dispatch 'function() silky_keys.run(n) end'`（与配置同一 Lua 状态）；Omarchy 翻译表 `default/i18n/<lang>/keybindings.json`；`IpcHandler { target: "keys" }`；图层 `silky-keys` 模糊
- **坑**：Omarchy 的 keybindings 缓存在 Hyprland 0.57 下只剩编号，无法执行；`wtype` 注入的按键不触发 Hyprland 绑定；`hl.unbind` 清掉该键全部绑定，所以 silky-shortcuts 必须在 hypr.macshell 之后；`pkill -f 'qs -c SilkyKeys'` 会杀掉执行它的 shell
- **验证**：`./scripts/silky-doctor.sh`（冲突检查 + 面板在跑）；`qs -c SilkyKeys ipc call keys search 截图`

## 11 Omarchy 菜单玻璃

- **效果**：Super+Esc / Super+Ctrl+M 等 Omarchy 菜单（含剪贴板、表情）变成半透明模糊卡片，不压暗背景，选中行强调色填充，Inter 字体；随 `color-scheme` 实时切换暗色烟灰 / 浅色磨砂
- **文件**：`bin/silky-menu-glass`（写 `~/.config/omarchy/shell.toml` 的标记区块）、`config/systemd/silky-menu-glass.service`、`config/hypr/silky-menu-glass.lua`（图层模糊 + `OMARCHY_MENU_FONT`）
- **关键词**：Omarchy `Commons/Color.qml` 的 `menu.*` 键（`background-alpha`、`scrim-alpha`、`selected-background`…）；用户级 `shell.toml` 优先于主题且 `watchChanges: true`；图层 `omarchy-menu` / `omarchy-clipboard` / `omarchy-emojis`；`gsettings monitor org.gnome.desktop.interface color-scheme`
- **坑**：原地写文件（改名会丢监听）；`ignore_alpha` 避免透明全屏点击层被模糊；字体变量要 `hl.env` 后 `omarchy-restart-shell`
- **验证**：`./scripts/silky-doctor.sh`；`omarchy-menu toggle system`；切 `color-scheme` 看菜单变色

## 杂项

| 需求 | 做法 |
| --- | --- |
| 截图不发通知 | `o.rebind("PRINT", "Screenshot", "omasnap")`（Omarchy 默认带 `--notify`），MacShell 设置 `screenshotNotify = false` |
| MacShell 窗口被撑宽、打开时白边闪 | Omarchy 浮动工作区模式把新窗口统一放大，只放过有自己浮动规则的应用；MacShell 窗口创建后才用定时器关掉 Hyprland 边框 → `o.window("^(org\\.quickshell)$", { float = true, center = true, border_size = 0 })`（`config/hypr/silky-macshell-windows.lua`），然后重启 MacShell |
| 崩溃后两个菜单栏 / 两个 Dock | Quickshell 崩溃处理自己重启一份 + `macshell-start` 再启动一份 → `QS_DISABLE_CRASH_HANDLER=1`，`qs -n -c MacShell` |
| 触控拖终端标题栏没反应 / 变平铺 | Omarchy 标题栏插件只在鼠标指针在该窗口上时才接触摸，接手后松手时 `floatWindow(DISABLE)`；silky-gestures 自己处理标题栏拖动，松手后 `doLater` 兜底恢复浮动和位置、取消钉住 |
| 触摸问题排查 | 在插件里临时记录 `g_pInputManager->m_touchData`（touchFocusWindow / touchFocusLS / consumedTouches），再卸载插件做 A/B 对比 |
| 浮动窗口拖到菜单栏下面 | 保留区只约束平铺窗口；silky-gestures 在 `dragController()->m_events.motion/ended` 里把窗口顶端（含标题栏）钳到 `m_reservedArea.top()` 以下 |
| 任何改动后的整体检查 | `./scripts/silky-doctor.sh` |
| 玻璃面板边缘和背景错位 | 弹出面板折射过强（`thickness × 1.6`，斜面 26 px，边缘取样到 50–60 px 外）→ `MacBar.qml` 两处改为 `× 0.6`、斜面 18 px |
| 系统自带 Dock 冒出来 | `omarchy plugin disable omarchy.dock`（Omarchy shell 重启后它会回来） |
| 桌面不显示图标 | `~/.config/macdock/settings.json` 中 `desktopIcons = false` |
| Superwhisper 不自启 | `superwhisper general set launchAtLogin false`、`systemctl --user stop superwhisper` |
| Claude 桌面版提示“Hardware acceleration disabled” | 关机/重启时 GPU 子进程重启失败（`launch-failed`、`exitCode 1002`，同时 Network Service 收到 SIGTERM），被 Claude 误判为 3 次 GPU 崩溃而自动关闭硬件加速；内核日志没有 GPU 错误。在 Claude 的 Help 菜单里重新打开即可（配置项 `isHardwareAccelerationDisabled`，在 `~/.config/Claude/claude_desktop_config.json`） |
| 90 Hz 内屏 | `hl.monitor({ output = "eDP-1", mode = "2944x1840@90", scale = 2 })` |
