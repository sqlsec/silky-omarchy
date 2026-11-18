# 15 · Obsidian：macOS 27 风格主题、文件图标与丝滑打字

简体中文 | [English](en/15-obsidian.md)

## 效果

把 Obsidian 改成 macOS 27 的样子，并跟随桌面的日间 / 夜间模式：

- **深浅色自动切换**：主题设为「跟随系统」。Omarchy 切换 `macos-tahoe-light/dark` 或在 MacShell 里切换外观时，Obsidian 会立即跟着变，不用重启。
- **玻璃材质**：右键菜单、命令面板和快速切换（Spotlight 样式，大号输入框）、设置等弹窗、悬浮预览、提示气泡、通知、侧栏和底部状态栏，都用模糊加饱和度做成磨砂玻璃。左右侧栏是浮在窗口里的圆角玻璃面板，编辑区是一张圆角纸面。
- **Finder 风格文件树**：文件夹是 macOS 蓝色文件夹，展开时换成打开的样式。不同后缀有各自的图标，包括笔记、文本、Canvas、Base、PDF、Word / WPS、表格、演示、图片、SVG、音频、视频、压缩包、网页链接，以及 JS / TS / Python / Shell / JSON / CSS / HTML / Lua / YAML / Rust / Go / C 等代码文件。代码文件的图标是带红黄绿三个点的深色小终端。选中行用强调色填满，和 Finder 侧栏一样。
- **丝滑打字**：光标在两个位置之间平滑滑过去，不再跳格；闪烁改成渐隐渐显。配套插件 Silky Typing 会让刚打出的字带一点模糊和强调色光晕淡入。拼音等输入法上屏的整段文字也会淡入。
- **代码块像 macOS 终端窗口**：深色玻璃底，左上角有红黄绿三个点，标题栏居中显示语言名，语法高亮用 Xcode Default (Dark) 配色。深浅两种模式下代码块都是深色窗口，行内代码是跟随深浅色的浅色小胶囊。
- 其他细节：Apple 系统色和字体栈（`-apple-system`、Inter、Noto Sans CJK SC，等宽字体用 SF Mono / JetBrainsMono Nerd Font）；窗口按钮是红黄绿圆点，悬停时显示符号；开关是 iOS 样式；任务复选框是 Reminders 样式的圆形；滚动条只在悬停时出现；菜单和弹窗有轻微的弹出动画。开启系统的「减少动态效果」后，所有动画都会关闭。

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
| 复制插件 | `<库>/.obsidian/plugins/silky-typing/`（来自 [`config/obsidian/plugins/silky-typing/`](../config/obsidian/plugins/silky-typing/)） |
| 启用主题并跟随系统 | `<库>/.obsidian/appearance.json`：`"cssTheme": "Silky macOS"`、`"theme": "system"`，其他键保留 |
| 登记插件 | `<库>/.obsidian/community-plugins.json` 加上 `silky-typing` |
| 首次运行时备份 | 原来的 `appearance.json`、`community-plugins.json` 存到 `~/.local/state/silky-omarchy/obsidian/<库路径哈希>/` |

可以重复运行。之后再运行只会更新主题和插件文件，第一次的备份保持不变。

正在运行的 Obsidian 会自动加载主题，不需要重启。打字淡入插件需要每个库手动打开一次：**设置 → 第三方插件 → 关闭「安全模式」（Restricted mode），然后确认「Silky Typing」已开启**。这个开关存在 Obsidian 自己的 localStorage 里，属于安全设置，脚本不会替你改。不开插件时，光标滑动和柔和闪烁照样有效，因为它们只靠主题 CSS。

可选设置：

- 想在文件树里看到 docx、xlsx、zip 等文件和它们的图标，打开 **设置 → 文件与链接 → 检测所有类型文件**。Obsidian 默认只显示它能打开的类型。
- 强调色默认是 Apple 蓝。在 **设置 → 外观 → 强调色** 里换颜色后，选中行、光标、开关和打字光晕都会跟着变。

## 实现

| 文件 | 作用 |
| --- | --- |
| [`theme.css`](../config/obsidian/themes/Silky%20macOS/theme.css) | 整套主题：深浅色变量、玻璃、浮动侧栏、红黄绿窗口按钮、文件树、光标、终端代码块 |
| [`build-icons.py`](../config/obsidian/build-icons.py) | 用 Python 直接画所有文件和文件夹图标（SVG，不用第三方素材），以 data URI 写进 `theme.css` 里 `@silky-icons-start` / `@silky-icons-end` 之间。改图标或加后缀后运行 `python3 config/obsidian/build-icons.py` |
| [`silky-typing/main.js`](../config/obsidian/plugins/silky-typing/main.js) | CodeMirror 6 扩展：给刚输入的字符加一个 260 ms 后自动移除的 `silky-typed` 标记 |
| [`silky-typing/styles.css`](../config/obsidian/plugins/silky-typing/styles.css) | 没有启用 Silky macOS 主题时的后备淡入动画 |
| [`install-obsidian-theme.sh`](../scripts/install-obsidian-theme.sh) | 安装、备份与 `--remove` 回滚 |

几个关键点：

- **为什么玻璃只模糊应用内部**：Obsidian 自带的「半透明窗口」只在 macOS 上生效（源码里有 `process.platform === "darwin"` 判断），Linux 上的 Electron 窗口不透明，Hyprland 也模糊不到窗口内部的某一块区域。所以这里的玻璃用 CSS `backdrop-filter` 模糊 Obsidian 自己的内容。窗口底色上有一层很淡的强调色渐变，让玻璃面板有东西可以折射。
- **深浅色信号链**：Omarchy 的 `omarchy-theme-set-gnome` 和 MacShell 都会写 `org.gnome.desktop.interface color-scheme`，`xdg-desktop-portal-gtk` 把它转给 Electron 的 `prefers-color-scheme`，Obsidian 在「跟随系统」模式下会切换 `body.theme-light` / `body.theme-dark`。这和 [11 · 菜单玻璃](11-menu-glass.md)、[09 · 候选框](09-wowtype-glass.md) 用的是同一个信号。
- **文件图标**：Obsidian 给文件树每一行写了 `data-path`，主题用 `.nav-file-title[data-path$=".pdf" i]` 这样的选择器按后缀匹配，图标画在 `.nav-file-title-content::before` 里，重命名时不会被编辑进文件名。
- **光标滑动**：Obsidian 1.15 用的是 CodeMirror 的 `drawSelection` 自绘光标。更新光标时，CodeMirror 会复用同一个 `.cm-cursor` 元素，只改它的 `left` / `top`，所以给这两个属性加 90 ms 过渡就能滑动。闪烁动画原本是 `steps(1)` 硬切，改成缓动曲线。
- **打字淡入与输入法**：插件只处理 `input.type` 事件，插入 8 个字符以内时才加标记，粘贴和片段补全不处理。每个标记带唯一属性，CodeMirror 就不会把相邻标记合并，前面的字也不会跟着重播动画。输入法组字（preedit）期间完全不碰 DOM，否则会打断 Chromium 的输入法处理。组字期间插入的范围会先记下来，`compositionend` 之后再统一淡入。标记过期删除时如果正在组字，就推迟到组字结束。

已知限制：

- 阅读视图里的代码块拿不到语言名，标题栏只显示红黄绿三个点；实时预览模式的标题栏会显示语言。
- 本机的 `~/.config/obsidian/user-flags.conf` 里有 `-disable-gpu`，Obsidian 用软件合成。模糊只用在菜单、命令面板、侧栏等区域，还没有专门测过 CPU 开销。去掉这个参数后，模糊交给 GPU 处理，会更省 CPU。
- 实时预览里代码块的首行和末行是 ```` ``` ```` 围栏行，光标移进代码块时能看到它们，位置在终端标题栏下方。

## 验证

已在 Obsidian 1.15.1（aarch64，Wayland 原生窗口，Electron 内置 Chromium）上验证：

- **隔离测试**：用 `--user-data-dir` 启动一个只打开临时测试库的独立 Obsidian 实例，通过 DevTools 协议检查：`cssTheme` 是 `Silky macOS`，深浅两种模式的截图正常；`.cm-cursor` 的 `transition` 包含 `left` / `top`；`.cm-cursorLayer` 的缓动是 `cubic-bezier(0.45, 0, 0.55, 1)`；模拟逐字输入时每个字各有一个 `.silky-typed`；模拟拼音组字 `ni`→`nihao` 期间没有新增标记，上屏的「你好」随后被标记；约 0.7 秒后标记全部清除，文本没有改动。
- **实机**：在本机两个库上运行安装脚本后，正在运行的 Obsidian 不重启就换成了浮动玻璃侧栏。打字淡入要等关闭安全模式后才会生效，还需要在实机上确认。

自己检查：

```bash
grep -h '"cssTheme"\|"theme"' ~/path/to/vault/.obsidian/appearance.json   # "Silky macOS" 和 "system"
gsettings set org.gnome.desktop.interface color-scheme prefer-light       # Obsidian 立即变浅色；再设回 prefer-dark
```

在 Obsidian 里：

1. 按 `Ctrl+P`，命令面板应该是圆角玻璃，背后的内容透过来变模糊。
2. 在笔记里随便打几个字，再用拼音输入一个词：光标应该滑过去，新字淡入，输入法候选和上屏都正常。
3. 写一个 ```` ```bash ```` 代码块：应该显示成带红黄绿三个点的深色终端窗口，标题栏有 `bash`。

待验证：多显示器上缩放比例不同（2× 和 2.5×）时的模糊开销；Obsidian 弹出的独立窗口（popout）。

## 回滚

```bash
./scripts/install-obsidian-theme.sh --remove           # 所有登记的库
./scripts/install-obsidian-theme.sh --remove ~/Notes   # 指定的库
```

脚本会删除 `themes/Silky macOS/` 和 `plugins/silky-typing/`，再用 `~/.local/state/silky-omarchy/obsidian/<哈希>/` 里的备份恢复 `appearance.json` 和 `community-plugins.json`。如果原来没有这两个文件，就直接删掉。恢复后 Obsidian 会自动切回原来的主题。如果只想换回默认外观、保留文件，在 **设置 → 外观 → 主题** 里选「默认」即可。

注意：`--remove` 会把这两个文件恢复成第一次安装前的样子，安装之后在外观设置里做的其他修改（比如字号）也会一起撤销。
