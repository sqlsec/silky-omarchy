# 00 · 给 AI 编程助手的复现索引

简体中文 | [English](en/00-ai-reproduction.md)

> 全部界面与交互改动的总览见 [12 · UI 交互优化总览](12-ui-interactions.md)。

把这份文件连同仓库地址交给 Claude Code、Codex、Cursor 等 AI 编程助手，它就能按模块复现这套优化，不需要你逐条解释。每个模块列出：要达到的效果、关键文件、检索关键词、容易踩的坑、验证命令。细节见对应的编号文档。

## 环境前提

- 发行版：Omarchy 4.x，本机 4.5.0（Arch Linux + Hyprland 0.57.2，**Lua 配置**：`~/.config/hypr/*.lua`，`hl.config` / `hl.bind` / `hl.window_rule` / `hl.layer_rule`）
- 测试机器：Lenovo Yoga Slim 7 14Q8X9，Snapdragon X Elite，Adreno X1-85，aarch64，2944×1840@90Hz，缩放 2
- 桌面外壳：MacShell 0.5.2（Quickshell 0.3.2 / Qt 6.12 / QML），锁屏 MacLock；02 支持全新及已应用 Silky 的 0.5.2（见 [02 · 版本](02-macshell.md#版本)）
- libinput 1.32.0（03 的补丁版本 1.32.0-1.2），内核 7.3
- 输入法：fcitx5 + WowType（拼音 + 离线语音）
- 规则：永远不改 `/usr/share/omarchy/`，只改 `~/.config`、`~/.local`；改 Hyprland 配置后执行 `hyprctl configerrors`

给 AI 的通用提示词：

> 这是 Omarchy（Hyprland Lua 配置）系统。按 `docs/00-ai-reproduction.md` 的模块 N 复现，只改用户目录，每一步改完用文中的验证命令确认，修改前备份原文件。

## 安装顺序

```bash
./scripts/install-macshell-optimizations.sh   # 02：MacShell 补丁（建议使用 MacShell 0.5.2）
./scripts/install-silky-gestures.sh           # 03：工作区手势插件
python3 scripts/install-macshell-overview.py  # 13：四指上滑 / 下滑窗口总览（需要 02、03）
./scripts/install-macos-theme.sh              # 04：macOS Tahoe 主题
./scripts/install-foot-glass.sh               # 04：可选，Foot 日夜磨砂玻璃
./scripts/install-remmina-mac.sh              # 04：可选，Remmina 简体中文与 macOS 外观
omarchy theme set macos-tahoe-dark
./scripts/install-voice-overlay.sh            # 05：语音浮条
./scripts/install-zsh.sh                      # 06：终端
./scripts/install-maclock.sh                  # 07：所有锁屏改用 MacLock
./scripts/install-boot-screen.sh              # 07：macOS 风格开机解锁界面
./scripts/install-nautilus-actions.sh         # 08：Nautilus 右键菜单
./scripts/install-nautilus-zh-cn.py            # 08：可选的 Nautilus 简体中文界面
./scripts/install-nautilus-wallpaper.py        # 08：可选的 Nautilus 右键设置桌面背景
./scripts/install-wowtype-glass.sh            # 09：WowType 候选框皮肤
./scripts/install-shortcuts.sh                # 10：快捷键冲突 + Super+K 面板
./scripts/install-menu-glass.sh               # 11：Omarchy 菜单玻璃 + 深浅色
./scripts/install-obsidian-theme.sh           # 15：Obsidian 主题 + 打字淡入插件
./scripts/install-desktop-priority.sh         # 16：桌面优先调度（需要 sudo）
```

01 的全局配置片段手动合并。可选的微信适配更新使用独立脚本。

---

## 01 触控板手势

- **效果**：自然滚动；三指拖移；四指左右滑切换工作区，1:1 跟手
- **文件**：`config/hypr/input-touchpad.lua` → `~/.config/hypr/input.lua`；`config/hypr/looknfeel-workspaces.lua` → `looknfeel.lua`
- **关键词**：`input.touchpad.natural_scroll`、`input.natural_scroll`（鼠标）、`drag_3fg = 1`、`hl.gesture({ fingers = 4, direction = "horizontal", action = "workspace" })`、`workspace_swipe_create_new = false`、`hl.animation({ leaf = "workspaces", style = "slide" })`
- **坑**：Omarchy 默认关掉了 workspaces 动画，必须重新打开才有跟手滑动；三指拖移和三指切换会抢手势，所以切换用四指
- **验证**：`hyprctl getoption input:touchpad:natural_scroll`、`hyprctl getoption input:natural_scroll`
- **可选微信更新**：已配置 Wayland 触屏启动器时，运行 `./scripts/install-wechat-touch-scroll.sh`，然后重启微信。见 [微信触屏滚动](01-touchpad-gestures.md#微信会话列表触屏滚动)。

## 02 MacShell 优化

- MacShell 0.5.3 的[按应用切换顶栏菜单](02-macshell.md#按应用切换顶栏菜单)可单独安装。运行 `python3 scripts/install-macshell-app-menus.py` 后重载 MacShell。
- [通知中心小组件](02-macshell.md#通知中心小组件)（天气、股市、屏幕使用时间、电池、日历、系统、AI 用量，小 / 中 / 大）可单独安装：先装顶栏系统监控，再运行 `python3 scripts/install-macshell-widgets.py` 并重载 MacShell。文件在 `config/macshell/widgets/`，数据进程 `widgets.py` 安装为 `assets/silky-widgets.py`，布局存 `~/.config/silky/widgets.json`，屏幕时间存 `~/.local/state/silky/screen-time/`。股票条目由 `widgets.py` 的 `resolve()` 解析：A 股 / 港股 / 美股走腾讯行情，其他市场走 Yahoo Finance。
- **效果**：简体中文；紧凑版“关于本机”（正确识别 Snapdragon / Adreno）；触控屏拖窗口；实时玻璃走 Vulkan；消除鼠标周期性卡顿；锁屏显示壁纸；电池图标去 `%`；不显示桌面图标；截图只用一个工具
- **文件**：`patches/macshell-0.5.1-silky.patch`、`patches/macshell-0.5.2-silky.patch`（对 `~/.config/quickshell/{MacShell,MacLock}` 的统一 diff）、`scripts/install-macshell-optimizations.sh`
- **关键词**：
  - 渲染：`QSG_RHI_BACKEND=vulkan`、`QSG_RENDER_LOOP=threaded`（写在 `~/.config/macshell/env`）
  - 卡顿：MacShell “自动对比度”用 `grim` 定时截屏 → 每次让 Hyprland 主线程停 60–110 ms；改成事件驱动，并用 `assets/tone-wall.sh` 直接读壁纸算亮度
  - 触控拖窗：Hyprland 0.57 丢弃没有鼠标按键序列号的 `xdg_toplevel.move`；新增 `TouchWindowMove.qml`，用 Hyprland IPC 按手指位移移动窗口
  - 设置丢失：MacShell 用 `hyprctl eval` 临时写鼠标/触控板设置，`configreloaded` 后要重新应用
  - 锁屏壁纸：MacLock 读 `~/.local/state/omarchy/current/background`
  - 主题联动：新增 IPC `qs -c MacShell ipc call appearance set dark|light`
  - 截图冲突：Omarchy 和 MacShell 同时绑定 `PRINT` → 删掉 `macshell.lua` 里的绑定
- **坑**：MacShell 靠 `~/.config/hypr/macshell.lua` + `hyprland.lua` 里的 `-- >>> MacShell (added by install.sh) >>>` 块开机自启，丢了会导致重启后菜单栏、Dock 消失、滚轮方向反了；重新生成补丁时必须基于纯净的 0.5.1 源码（GitHub 上现在的 0.5.1 标签已和生成补丁时的不同，有 3 个 hunk 打不上）；0.5.2 使用单独的版本补丁
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
- **状态**：锁屏和开机界面都已在真机上确认

## 08 Nautilus 右键菜单

- **效果**：本地文件 / 文件夹右键「复制路径」（多选每行一个）、「在终端打开」、压缩包「解压到此处 / 解压到…」
- **文件**：`nautilus/silky_actions.py` → `~/.local/share/nautilus-python/extensions/`
- **关键词**：`nautilus-python`、`Nautilus.MenuProvider`、`xdg-terminal-exec`
- **验证**：`nautilus -q` 后重新打开，右键看菜单

## 09 WowType 候选框

- **效果**：圆角毛玻璃候选框，深浅色两套皮肤随 `color-scheme` 切换；Inter 12 号字；高亮贴边，与外框共用 8 px 圆角；底色半透明（40% / 50%）透出模糊；微信内候选条不再重影
- **文件**：`wowtype-glass/build-themes.py`（生成 fcitx5 主题 PNG + theme.conf）、`wowtype-glass/silky-ime-theme` + `config/systemd/silky-ime-theme.service`、`config/hypr/silky-ime.lua`
- **关键词**：fcitx5 classicui `Theme=`、`Font=`、`[InputPanel/ContentMargin]`、`[InputPanel/TextMargin]`、`[InputPanel/Highlight/Margin]`（同时是九宫格边框和高亮外扩距离）；微信内置 fcitx5-qt 只认图片 / 纯色 / 边距；Hyprland `decoration.blur.input_methods`、`fadePopups` 关掉防重影
- **坑**：高亮边距必须等于文字边距、圆角半径不超过它（`HR <= TM_Y`），否则高亮溢出、圆角被裁成方角；外框圆角 = 高亮圆角 + 内边距（`R = HR + PAD`）；微信要重启才换皮肤
- **验证**：`grep -E '^(Theme|Font)=' ~/.config/fcitx5/conf/classicui.conf`

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

## 13 窗口总览（四指上滑 / 下滑）

- **效果**：触控板或触控屏四指上滑显示当前工作区所有窗口，四指下滑显示当前应用所有窗口（含其他工作区），反向滑动回到桌面；进度线性跟手，松手后匀速走完，动画中再按住可打断、反向；点击窗口聚焦过去
- **文件**：`plugins/silky-gestures/main.cpp`（`CSilkyOverviewGesture`）、`config/macshell/overview/SilkyOverview.qml`、`scripts/install-macshell-overview.py`
- **关键词**：`g_pTrackpadGestures->addGesture(…, 4, TRACKPAD_GESTURE_DIR_VERTICAL, …)`、`ITrackpadGesture::begin/update/end`、`events.config.preReload / reloaded`（重载会清空手势表）、`removeGesture`（卸载前必须删）、socket2 `silkyoverview>>begin,up|down / update,<位移> / end[,cancel]`、Quickshell `Hyprland.rawEvent`、`SafeCapture`（`want` / `wantLive`）、`FrameAnimation` 恒速推进、`WlrLayer.Overlay`、`qs -c MacShell ipc call overview …`
- **坑**：插件在读配置期间加载，第一次 `reloaded` 不能重复注册（用 `preReload` 标记）；总览窗口不能在手势开始时才创建（Vulkan 表面 + 管线约 0.5 秒没有帧），要常驻并停在屏幕外（margins 移出 + 空输入区域 + `no_anim` 图层规则），启动时预画一次编译着色器；手势中只用单帧捕获，停稳后再实时；缩略图固定大小 + `ShaderEffectSource` + 圆角着色器 `silkyround.frag`，不要每个窗口一个随尺寸变化的 layer/MultiEffect；不要全屏实时模糊；总览的捕获不能跟 Dock 的“实时窗口捕获”开关走；捕获拿到第一帧前不要盖壁纸，但等待期间的手指行程不能丢；层叠顺序要和 Hyprland 一致；Dock 在总览图层下面，要留洞淡出
- **验证**：`qs -c MacShell ipc call overview begin up` → `update 120` → `state`（`p` 为 0.5）→ `end`；`socat … .socket2.sock | grep silkyoverview` 看真实手势事件

## 14 Omalogi 罗技鼠标（汉化 + ARM）

- **效果**：Omalogi 界面、动作库、提示、报错全部中文；在 aarch64 上从源码构建安装；作为普通窗口（自己的 app id）打开，可平铺 / 浮动、跟随工作区；有线和无线鼠标同时连着时可切换编辑哪一只
- **文件**：`patches/omalogi-0.3.8-zh.patch`、`scripts/install-omalogi.sh`、`docs/14-omalogi.md`、`config/icons/omalogi.svg`、`config/applications/io.github.elberacasa.omalogi.desktop`、`omalogi-app/shell.qml`、`bin/silky-omalogi`、`config/hypr/silky-omalogi.lua`（图标走 `tune-app-icons.py` 的 `BRANDS`；入口 `Icon=` 用绝对路径，因为 Qt 会缓存“找不到图标”直到 MacShell 进程重启；ARM 上插件 `install.sh` 经 `~/.local/share/silky-omarchy/install-omalogi.sh` 软链接转交）
- **关键词**：上游提交 `ff3d8c2`（v0.3.8）、`include_str!("../plugin/…")`（插件嵌在二进制里）、`omalogi setup`、`Model.zh / zhMessage / zhGroup / zhSource`、`problemKind`、`omarchy-shell shell toggle io.github.elberacasa.omalogi '{}'`
- **坑**：插件由 `omalogi setup` 从二进制写出，改已安装的 QML 会被覆盖，必须构建前打补丁；Rust 侧的动作名和报错不能翻（CLI、Rust 测试、`problemKind` 都按英文判断），只在插件显示时翻；daemon 的 `source` 是 `rule N` / `default`；上游 `install.sh` 只认 x86_64；`node --test plugin/tests` 有 14 个断言英文原文的用例会失败，属预期
- **坑（窗口）**：`PanelWindow`→`FloatingWindow`；Omarchy Shell 进程里的窗口 class 固定 `org.quickshell`，要单独进程 + `//@ pragma AppId`；Lua 版 Hyprland 的 `hyprctl dispatch` 收 Lua 表达式（`hl.dsp.focus({ window = "class:…" })`）；浮动工作区会把新窗口缩成 1100×760，需要自己的 float 规则；窗口要停在 Dock 上方（1280×700），压进 Dock 区域 Dock 会自动隐藏；窗口尺寸别用 `Style.space()`；G604 实测后在设备表标为 `verified`，否则一直显示「未测试」；无线鼠标的 `picture` 和刚启动的 `serve` 抢接收器，要重试；未验证型号的按键列表多行，原布局只留一行高度
- **验证**：`file ~/.local/bin/omalogi`（aarch64）、`systemctl --user is-active omalogi.service`、打开窗口无鼠标时显示“请连接鼠标”、`hyprctl clients` 里有 class `io.github.elberacasa.omalogi` 的浮动窗口、`cargo test --release` 全过

## 15 Obsidian 主题与丝滑打字

- **效果**：Obsidian 主题 Silky macOS：菜单、命令面板、弹窗、悬浮预览、侧栏都是玻璃材质，侧栏是浮动圆角面板；外观「跟随系统」，随 `color-scheme` 实时切换；文件树是 Finder 蓝色文件夹，不同后缀有各自的图标；光标平滑滑动、柔和闪烁；插件 Silky Typing 让新输入的字淡入（含输入法上屏）；代码块是带红黄绿三个点的深色终端窗口，用 Xcode 深色配色
- **文件**：`config/obsidian/themes/Silky macOS/{manifest.json,theme.css}`、`config/obsidian/build-icons.py`（生成 SVG 图标块）、`config/obsidian/plugins/silky-typing/{manifest.json,main.js,styles.css}`、`config/obsidian/plugins/silky-window-controls/{manifest.json,main.js}`（绿色按钮执行 `Super+Alt+F` 的全宽切换，Omarchy 丢掉最大化请求）、`scripts/install-obsidian-theme.sh`、`docs/15-obsidian.md`
- **关键词**：`appearance.json` 的 `cssTheme` / `theme: "system"`、`community-plugins.json`、`.nav-file-title[data-path$=".pdf" i]`、`.nav-file-title-content::before`、`.cm-cursor` 的 `left/top` 过渡、`.cm-cursorLayer` 的 `cm-blink`、`registerEditorExtension`、`StateField` + `Decoration.mark`、`isUserEvent("input.type.compose")`、`compositionend`、`view.composing`
- **坑**：Obsidian 的半透明窗口只在 macOS 生效，玻璃只能模糊应用内部；安全模式开关存在 localStorage，脚本不改，要用户手动关；相邻 mark 会被 CodeMirror 合并，导致动画重播，所以每个 mark 要带唯一属性；组字期间不能改 DOM，否则会打断输入法；Obsidian 默认不显示未知后缀的文件，要开「检测所有类型文件」；DevTools 测试别用 9333 端口（本机已被占用）；软件包的 `obsidian.desktop` 写的是 `StartupWMClass=obsidian`，但 Wayland 窗口的 app id 是 `md.obsidian.Obsidian`，Dock 认不出窗口，点图标会一直跳，所以脚本要写一份用户级入口来修正
- **验证**：独立实例 `obsidian --user-data-dir=<临时目录> --remote-debugging-port=<端口>` 打开测试库，检查 `app.customCss.theme`、`.silky-typed` 的数量，用 `Input.insertText` / `Input.imeSetComposition` 模拟输入；切换 `color-scheme` 看 Obsidian 是否跟着变

## 16 桌面优先调度

- **效果**：root 服务每 2 秒给 `Hyprland`（nice -11，uclamp.min 512）、`qs` / `quickshell`（-8，384）、`Xwayland`、`fcitx5`（-6，256）的新线程提权；接电时 Adreno devfreq 最低 550 MHz，电池时恢复
- **文件**：`bin/silky-desktop-priority`、`config/silky/desktop-priority.conf`（→ `/etc/silky/`）、`config/systemd/system/silky-desktop-priority.service`、`scripts/install-desktop-priority.sh`（`--uninstall` 回滚）、`docs/16-desktop-priority.md`
- **关键词**：`sched_setattr`（aarch64 274 / x86_64 314）、`SCHED_FLAG_UTIL_CLAMP_MIN`、`CAP_SYS_NICE`、`/sys/class/devfreq/*gpu*/min_freq`、`power_supply/*/online`
- **坑**：nice 按线程生效，要遍历 `/proc/<pid>/task`；跳过非 `SCHED_OTHER` 和 nice 不为 0 的线程（Mesa `disk$` 缓存线程是 `SCHED_BATCH`）；读 `/proc/…/stat` 要从最后一个 `)` 之后切字段，`[pango] fontcon` 这类线程名带空格，用 awk 数列会错位；Hyprland 在 greetd 的 `session-N.scope` 里，和直接从会话拉起的 Chromium 同一个 cgroup，所以不能用 scope 的 `CPUWeight`；aquamarine 已拿到高优先级 EGL 上下文；不要用实时调度
- **验证**：`/usr/local/bin/silky-desktop-priority --config /etc/silky/desktop-priority.conf --status`、`ps -L -o tid,ni,cls,comm -p "$(pgrep -x Hyprland)"`；无 root 预览用 `--dry-run`

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
