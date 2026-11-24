# 15 · Obsidian：macOS 27 风格主题、文件图标与丝滑打字

简体中文 | [English](en/15-obsidian.md)

## 效果

把 Obsidian 改成 macOS 27 的样子，并跟随桌面的日间 / 夜间模式：

- **深浅色自动切换**：主题设为「跟随系统」。Omarchy 切换 `macos-tahoe-light/dark` 或在 MacShell 里切换外观时，Obsidian 会立即跟着变，不用重启。
- **原生实时磨砂侧栏与实色编辑区**：参考 Files（Folio）与 Foot 的视觉分层，左右侧栏与功能区作为边到边的原生 Hyprland 实时磨砂玻璃（深色 `rgba(38, 38, 42, 0.77)`、浅色 `rgba(242, 242, 245, 0.83)`），直接折射并模糊窗口后方的壁纸与叠放窗口；右侧主编辑区与标签栏保持完全实色（深色 `#1c1c1e`、浅色 `#ffffff`），保障持续阅读与写作的清晰度。右键菜单、命令面板、弹窗、悬浮预览、提示气泡与状态栏同样采用磨砂玻璃。全屏时侧栏切换为实色。
- **Finder 风格文件树**：文件夹是 macOS 蓝色文件夹，展开时换成打开的样式。不同后缀有各自的图标，包括笔记、文本、Canvas、Base、PDF、Word / WPS、表格、演示、图片、SVG、音频、视频、压缩包、网页链接，以及 JS / TS / Python / Shell / JSON / CSS / HTML / Lua / YAML / Rust / Go / C 等代码文件。代码文件的图标是带红黄绿三个点的深色小终端。选中行用强调色填满，和 Finder 侧栏一样。
- **丝滑打字**：光标在两个位置之间平滑滑过去，不再跳格；闪烁改成渐隐渐显。配套插件 Silky Typing 会让刚打出的字带一点模糊和强调色光晕淡入。拼音等输入法上屏的整段文字也会淡入。
- **代码块像 macOS 终端窗口**：深色玻璃底，左上角有红黄绿三个点，标题栏居中显示语言名，语法高亮用 Xcode Default (Dark) 配色。深浅两种模式下代码块都是深色窗口，行内代码是跟随深浅色的浅色小胶囊。
- **窗口按钮与布局（对标 Folio 与 Foot）**：左上角红黄绿三灯采用 12 px 实色圆面、8 px 间距、8 × 8 px 画布与 1.1 px 圆端笔画，失焦时变灰，悬停按钮组时显色并出现符号。右侧不再留出按钮空位。
  - 红灯关闭当前窗口（保留 Obsidian 原有未保存确认行为）。
  - 黄灯最小化到 MacShell Dock，可从 Dock 缩略图恢复同一窗口、工作区、位置与尺寸（未运行 MacShell 时回退 `omarchy-hyprland-window-minimize`）。
  - 绿灯单击与 `Super+F` 一致切换真正全屏，进入全屏后把指针移到屏幕左上缘可浮出与 Foot 共用的退出控制条（黄灯置灰、绿灯显示向内斜角）。右键点击或长按绿灯（≥ 350 ms）弹出与 Folio / Foot 共用的两排 8 位置窗口布局菜单（上下左右半屏与四个角落），悬停显示蓝色落位预览，点击避开菜单栏和 Dock 预留区精确落位。
  - 双击顶栏空白处切换最大化与还原；拖动顶栏空白处到屏幕左右边缘触发与 Folio 相同的半屏/四角蓝色吸附预览，松手自动落位。
  - 窗口透明背景与按钮交互由 Silky Window Controls 插件提供。
- 其他细节：Apple 系统色和字体栈（`-apple-system`、Inter、Noto Sans CJK SC，等宽字体用 SF Mono / JetBrainsMono Nerd Font）；开关是 iOS 样式；任务复选框是 Reminders 样式的圆形；滚动条只在悬停时出现；菜单和弹窗有轻微的弹出动画。开启系统的「减少动态效果」后，所有动画都会关闭。

## 安装

```bash
./scripts/install-obsidian-theme.sh                  # 安装到 ~/.config/obsidian/obsidian.json 里登记的所有库
./scripts/install-obsidian-theme.sh ~/Notes          # 只装到指定的库
./scripts/install-obsidian-theme.sh --no-plugin      # 只装主题，不要打字淡入效果
```

在仓库根目录运行，需要 `python3`。对每个库，脚本会：

| 动作 | 位置 |
| --- | --- |
| 复制主题 | `<库>/.obsidian/themes/Silky macOS/`（来自 [`config/obsidian/themes/Silky macOS/`](../config/obsidian/themes/Silky%20macOS/)） |
| 复制插件 | `<库>/.obsidian/plugins/silky-typing/` 和 `<库>/.obsidian/plugins/silky-window-controls/`（来自 [`config/obsidian/plugins/`](../config/obsidian/plugins/)） |
| 启用主题并跟随系统 | `<库>/.obsidian/appearance.json`：`"cssTheme": "Silky macOS"`、`"theme": "system"`，其他键保留 |
| 登记插件 | `<库>/.obsidian/community-plugins.json` 加上 `silky-typing` 和 `silky-window-controls` |
| 修正启动入口 | `~/.local/share/applications/obsidian.desktop`：复制系统的 `obsidian.desktop`，只把 `StartupWMClass` 改成 `md.obsidian.Obsidian`。如果原来已有用户级入口，会先备份到 `~/.local/state/silky-omarchy/obsidian/obsidian.desktop.backup` |
| Hyprland 实时磨砂规则 | `~/.config/hypr/silky-obsidian.lua`（来自 [`config/hypr/silky-obsidian.lua`](../config/hypr/silky-obsidian.lua)），并在 `~/.config/hypr/hyprland.lua` 追加 `require("hypr.silky-obsidian")` |
| 首次运行时备份 | 原来的 `appearance.json`、`community-plugins.json` 存到 `~/.local/state/silky-omarchy/obsidian/<库路径哈希>/` |

可以重复运行。之后再运行只会更新主题、插件和 Hyprland 规则，第一次的备份保持不变。若同步使用了 MacShell 最小化、全屏浮条与 8 位置布局菜单，同时更新 [`config/hypr/silky-folio.lua`](../config/hypr/silky-folio.lua) 到 `~/.config/hypr/` 并运行：

```bash
python3 scripts/tune-folio-macshell.py ~/.config/quickshell/MacShell --backup
hyprctl reload
qs -c MacShell ipc call macshell reload
```

正在运行的 Obsidian 会自动加载主题；更新或首次启用插件后需要重启 Obsidian 或重新开关一次插件。两个插件需要每个库手动打开一次：**设置 → 第三方插件 → 关闭「安全模式」（Restricted mode），然后确认「Silky Typing」和「Silky Window Controls」已开启**。这个开关存在 Obsidian 自己的 localStorage 里，属于安全设置，脚本不会替你改。不开插件时，光标滑动、柔和闪烁和按钮外观照样有效，但不会启用窗口透明通道和 Hyprland 按钮动作。`--no-plugin` 只装主题，不装两个插件。

可选设置：

- 想在文件树里看到 docx、xlsx、zip 等文件和它们的图标，打开 **设置 → 文件与链接 → 检测所有类型文件**。Obsidian 默认只显示它能打开的类型。
- 强调色默认是 Apple 蓝。在 **设置 → 外观 → 强调色** 里换颜色后，选中行、光标、开关和打字光晕都会跟着变。

## 实现

| 文件 | 作用 |
| --- | --- |
| [`theme.css`](../config/obsidian/themes/Silky%20macOS/theme.css) | 整套主题：深浅色变量、边到边磨砂侧栏、实色编辑区、12 px 红黄绿窗口按钮（含失焦变灰）、文件树、光标、终端代码块 |
| [`build-icons.py`](../config/obsidian/build-icons.py) | 用 Python 直接画所有文件和文件夹图标（SVG，不用第三方素材），以 data URI 写进 `theme.css` 里 `@silky-icons-start` / `@silky-icons-end` 之间。改图标或加后缀后运行 `python3 config/obsidian/build-icons.py` |
| [`silky-typing/main.js`](../config/obsidian/plugins/silky-typing/main.js) | CodeMirror 6 扩展：给刚输入的字符加一个 260 ms 后自动移除的 `silky-typed` 标记 |
| [`silky-typing/styles.css`](../config/obsidian/plugins/silky-typing/styles.css) | 没有启用 Silky macOS 主题时的后备淡入动画 |
| [`silky-window-controls/main.js`](../config/obsidian/plugins/silky-window-controls/main.js) | 开启 Electron 窗口透明底色（`#00000000`），同步失焦样式，并接管黄灯最小化到 Dock、绿灯全屏与右键/长按布局菜单、顶栏双击最大化与拖拽边缘吸附 |
| [`silky-obsidian.lua`](../config/hypr/silky-obsidian.lua) | Hyprland 窗口规则：为 `md.obsidian.Obsidian` 启用实时合成器磨砂（`opacity = "0.995 override 0.995 override 1.0 override"`、`xray = false`、`border_size = 0`） |
| [`silky-folio.lua`](../config/hypr/silky-folio.lua) 与 [`FootWindowLayout.qml`](../config/macshell/FootWindowLayout.qml) | 将 `md.obsidian.Obsidian` 接入共用的 MacShell Dock 最小化、全屏左上缘退出浮条、两排 8 位置布局菜单与蓝色吸附预览 |
| [`install-obsidian-theme.sh`](../scripts/install-obsidian-theme.sh) | 安装、备份与 `--remove` 回滚 |

几个关键点：

- **原生实时磨砂侧栏与实色编辑区**：Obsidian 自带的「半透明窗口」开关仅对 macOS 开放，但原生 Wayland 下的 Electron 仍可通过 `@electron/remote` 调用 `BrowserWindow.setBackgroundColor("#00000000")` 开放窗口 Alpha 通道。由于 Chromium 会把 `wl_surface.opaque_region` 标为整窗不透明，Hyprland 在精确 `1.0` 不透明度下会跳过 blur pass；[`silky-obsidian.lua`](../config/hypr/silky-obsidian.lua) 将非全屏透明度设为 `0.995 override` 并关闭 `xray` 与外描边，既触发 Hyprland 对半透明侧栏执行实时高斯模糊、避免圆角彩边，又让右侧实色编辑区在视觉上保持完全实色。全屏保持 `1.0 override`。
- **深浅色信号链**：Omarchy 的 `omarchy-theme-set-gnome` 和 MacShell 都会写 `org.gnome.desktop.interface color-scheme`，`xdg-desktop-portal-gtk` 把它转给 Electron 的 `prefers-color-scheme`，Obsidian 在「跟随系统」模式下会切换 `body.theme-light` / `body.theme-dark`。这和 [11 · 菜单玻璃](11-menu-glass.md)、[09 · 候选框](09-wowtype-glass.md) 用的是同一个信号。
- **文件图标**：Obsidian 给文件树每一行写了 `data-path`，主题用 `.nav-file-title[data-path$=".pdf" i]` 这样的选择器按后缀匹配，图标画在 `.nav-file-title-content::before` 里，重命名时不会被编辑进文件名。
- **光标滑动**：Obsidian 1.15 用的是 CodeMirror 的 `drawSelection` 自绘光标。更新光标时，CodeMirror 会复用同一个 `.cm-cursor` 元素，只改它的 `left` / `top`，所以给这两个属性加 90 ms 过渡就能滑动。闪烁动画原本是 `steps(1)` 硬切，改成缓动曲线。
- **打字淡入与输入法**：插件只处理 `input.type` 事件，插入 8 个字符以内时才加标记，粘贴和片段补全不处理。每个标记带唯一属性，CodeMirror 就不会把相邻标记合并，前面的字也不会跟着重播动画。输入法组字（preedit）期间完全不碰 DOM，否则会打断 Chromium 的输入法处理。组字期间插入的范围会先记下来，`compositionend` 之后再统一淡入。标记过期删除时如果正在组字，就推迟到组字结束。

已知限制：

- 阅读视图里的代码块拿不到语言名，标题栏只显示红黄绿三个点；实时预览模式的标题栏会显示语言。
- **窗口按钮与布局接管**：Obsidian 原生的最大化请求会被 Omarchy 默认规则（`suppress_event = "maximize"`）拦截，且 Electron 内部状态容易与 Hyprland 脱节。插件在捕获阶段拦截按钮点击，通过 `hyprctl` 与 MacShell IPC 分别执行最小化到 Dock、真正全屏切换、两排 8 位置布局菜单（右键或长按绿灯 ≥ 350 ms）、顶栏空白双击最大化与拖拽边缘吸附；目标窗口按主进程 PID 与标题匹配 `address:`，不会误操作其他焦点窗口。不在 Hyprland 下时插件不做任何事。
- **窗口按钮的位置**：Obsidian 在 Linux / Windows 上用 `--frame-right-space` 给窗口按钮在右侧留位置，在 macOS 上用 `--frame-left-space` 在左侧留位置。主题把两者对调（左侧 78 px，右侧 0），把 `.titlebar-button-container.mod-right` 移到左上角（12 px 实色圆面、8 px 间距，无深色内描边），用 8 × 8 px 画布、1.1 px 圆端笔画的居中 SVG 背景绘制 ×、−、+ 符号；全屏时隐藏自绘三灯，交由 MacShell `FootWindowLayout` 左上缘浮条处理退出。从右到左书写（RTL）的系统不做调整。
- **Dock 图标一直跳、窗口打不开**：Obsidian 1.15 的原生 Wayland 窗口的 app id 是 `md.obsidian.Obsidian`，而软件包自带的 `obsidian.desktop` 写的是 `StartupWMClass=obsidian`。MacShell 的 Dock 因此认不出已经打开的窗口，图标下也没有运行圆点。点 Dock 图标时会再启动一个进程，这个进程把请求交给已经在运行的 Obsidian 后就退出，Dock 却一直等新窗口出现，图标就一直跳。如果原来的窗口被别的窗口挡住，看起来就像打不开。安装脚本生成的用户级入口改正了 `StartupWMClass`，Quickshell 的 `DesktopEntries.heuristicLookup` 就能把窗口对上图标；入口里带一行 `X-Silky-Omarchy=obsidian-wmclass`，回滚时只删带这个标记的文件。
- 本机的 `~/.config/obsidian/user-flags.conf` 里有 `-disable-gpu`，Obsidian 用软件合成。模糊只用在菜单、命令面板、侧栏等区域，还没有专门测过 CPU 开销。去掉这个参数后，模糊交给 GPU 处理，会更省 CPU。
- 实时预览里代码块的首行和末行是 ```` ``` ```` 围栏行，光标移进代码块时能看到它们，位置在终端标题栏下方。

## 验证

已在 Obsidian 1.15.1（aarch64，Wayland 原生窗口，Electron 内置 Chromium）上验证：

- **隔离测试**：用 `--user-data-dir` 启动一个只打开临时测试库的独立 Obsidian 实例，通过 DevTools 协议检查：`cssTheme` 是 `Silky macOS`，深浅两种模式的截图正常；`.cm-cursor` 的 `transition` 包含 `left` / `top`；`.cm-cursorLayer` 的缓动是 `cubic-bezier(0.45, 0, 0.55, 1)`；模拟逐字输入时每个字各有一个 `.silky-typed`；模拟拼音组字 `ni`→`nihao` 期间没有新增标记，上屏的「你好」随后被标记；约 0.7 秒后标记全部清除，文本没有改动。
- **实机**：在本机两个库上运行安装脚本后，正在运行的 Obsidian 不重启就换成了浮动玻璃侧栏。打字淡入要等关闭安全模式后才会生效，还需要在实机上确认。

另在隔离实例（Hyprland 0.57.2、MacShell 0.5.3、Obsidian 1.15.1、2× 缩放内屏）里验证了新版 macOS 风格改造：

- **视觉与虚化**：启用主题与 Silky Window Controls 后，左侧边栏与底部 vault 栏连续铺满左侧边缘并呈现原生 Hyprland 实时磨砂玻璃，右侧编辑区与标签栏为完全实色（`#1c1c1e`）；左上角红黄绿三灯为 12 px 实色圆面、8 px 间距，窗口失焦（例如弹出菜单）时自动变灰。
- **窗口状态与布局**：`o.silky_foot_fullscreen` 在 `fullscreen = 2` 与 `0` 之间正确切换；右键绿灯在按钮下方弹出两排 8 位置布局菜单；执行左半屏落位后窗口精确落到 `[0, 23] 736×822`（避开顶部 23 px 菜单栏与底部 Dock 预留区）；调用 `qs -c MacShell ipc call window minimizeFoot <address>` 返回 `true` 最小化到 Dock，随后 `restore` 恢复到原工作区与相同几何位置 `[0, 23] 736×822`。

待验证：浅色模式实机复查、实体触屏长按绿灯、多显示器不同缩放比例时的落位与 Obsidian 弹出独立窗口（popout）。

## 回滚

```bash
./scripts/install-obsidian-theme.sh --remove           # 所有登记的库
./scripts/install-obsidian-theme.sh --remove ~/Notes   # 指定的库
```

脚本会删除 `themes/Silky macOS/`、`plugins/silky-typing/` 和 `plugins/silky-window-controls/`，删除带标记的 `~/.local/share/applications/obsidian.desktop`（原来有用户级入口时恢复备份），删除 `~/.config/hypr/silky-obsidian.lua` 并从 `~/.config/hypr/hyprland.lua` 移除 `require("hypr.silky-obsidian")`，再用 `~/.local/state/silky-omarchy/obsidian/<哈希>/` 里的备份恢复 `appearance.json` 和 `community-plugins.json`。若同步更新了 `silky-folio.lua` 与 MacShell `FootWindowLayout.qml`，可分别从 `.bak.*` 备份恢复并执行 `hyprctl reload` 与 `qs -c MacShell ipc call macshell reload`。如果原来没有两个 JSON 文件就直接删掉，恢复后 Obsidian 会自动切回原来的主题。如果只想换回默认外观、保留文件，在 **设置 → 外观 → 主题** 里选「默认」即可。

注意：`--remove` 会把这两个文件恢复成第一次安装前的样子，安装之后在外观设置里做的其他修改（比如字号）也会一起撤销。
