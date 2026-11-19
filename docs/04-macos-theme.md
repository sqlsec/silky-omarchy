# 04 · macOS Tahoe 主题（深色 / 浅色）

简体中文 | [English](en/04-macos-theme.md)

## 目标

- 两个 Omarchy 主题：`macos-tahoe-dark` 和 `macos-tahoe-light`，配色取自 Apple 系统色板
- 窗口有 macOS 的质感：细边框、连续曲率圆角、聚焦窗口下方柔和的深阴影、半透明表面背后的玻璃模糊
- 图标换成 MacTahoe：蓝色文件夹、macOS 风格应用图标
- 文件管理器（Nautilus）换上 Finder 外观：半透明侧边栏、左上角红绿灯、空格键快速预览（sushi）
- 浮动窗口带 macOS 红绿灯标题栏：关闭、全屏
- 切换主题时，GTK 外观、鼠标指针和 MacShell 深浅色一起切换

## 组成

| 部分 | 文件 | 说明 |
| --- | --- | --- |
| 配色 | `themes/macos-tahoe-*/colors.toml` | Apple 系统色。浅色版终端文字用的是高对比度变体，否则黄色、绿色在白底上看不清 |
| 窗口外观 | `themes/macos-tahoe-*/hyprland.lua` | 1 px 半透明描边、14 px 圆角（`rounding_power = 2.6` 接近 Apple 的连续曲率）、阴影、3 次模糊 |
| 图标 | `themes/macos-tahoe-*/icons.theme` | `Silky-MacTahoe-dark` / `Silky-MacTahoe-light`（继承 MacTahoe，统一侧边栏符号图标） |
| GTK / Finder | MacTahoe GTK 主题 | 上游预编译的 release，不需要 sassc |
| 联动 | `hooks/theme-set-silky-macos` | Omarchy 的 theme-set hook |
| 红绿灯 | `config/hypr/silky-titlebar-guard.lua` + `config/hypr/silky-macos.lua` | 把 Omarchy 浮动窗口标题栏改成圆形红绿灯 |

第三方部分都固定到具体 commit（见 `scripts/install-macos-theme.sh` 开头），保证每次安装的结果一致：

- [vinceliuice/MacTahoe-icon-theme](https://github.com/vinceliuice/MacTahoe-icon-theme)
- [vinceliuice/MacTahoe-gtk-theme](https://github.com/vinceliuice/MacTahoe-gtk-theme)

主题不自带壁纸（Apple 官方壁纸有版权）。安装时把当前壁纸复制到 `~/.config/omarchy/backgrounds/macos-tahoe-*/`，你可以往这两个目录里放更多壁纸。

## 安装与切换

```bash
./scripts/install-macos-theme.sh
```

```bash
omarchy theme set macos-tahoe-dark
```

```bash
omarchy theme set macos-tahoe-light
```

可选参数：`--no-icons`、`--no-gtk`、`--no-bars`（不改标题栏）。已经打开的 GTK 应用（文件、设置）需要重新打开才会换上新外观。

## 切换主题时联动的内容

Omarchy 自己的主题机制只会设置 Adwaita 和图标主题。hook 在 `macos-tahoe-*` 主题下额外做了这些：

- GTK 3 主题设为 `MacTahoe-Dark` / `MacTahoe-Light`；libadwaita（GTK 4）通过把 `~/.config/gtk-4.0/gtk.css` 等链接到主题文件来生效
- 窗口按钮布局设为 `close,maximize:`，红绿灯在左边
- 鼠标指针换成 MacTahoe（深浅色下都是 macOS 的黑色箭头）
- 通过 `qs -c MacShell ipc call appearance set dark|light` 切换 MacShell 菜单栏、Dock 和控制中心的深浅色，并更新 Dock 使用的图标主题

切换到其他主题时，hook 删掉它创建的 GTK 4 链接（你自己写的 `gtk.css` 会被备份并恢复，不会被删除），并恢复原来的按钮布局和鼠标指针。原始值保存在 `~/.local/state/silky-omarchy/macos-theme.previous`。

## 图标

Nautilus 侧边栏使用 MacTahoe 原有的符号图标，并显示为蓝色；项目文件夹复用主题内的代码文件夹符号图标。

### 文件管理器磨砂玻璃

Nautilus 会把后方窗口和壁纸虚化成柔和的色块。侧栏透色更强，并带有细高光，文件区使用更厚的底色以保持文件名和图标清晰。

[GTK 4 覆盖](../config/gtk-4.0/nautilus-glass.css)随主题安装脚本写入 `~/.local/share/themes/Silky-MacTahoe-{Dark,Light}/gtk-4.0/`。已安装 MacTahoe GTK 主题时，可在仓库根目录运行 `./scripts/install-macos-theme.sh --no-icons --no-gtk --no-bars` 更新。使用任一 macOS Tahoe 主题，保存工作并退出 Nautilus 的进程后重新打开。桌面虚化需要 GTK 的 Wayland 背景效果支持和开启虚化的 Hyprland。验证环境为 Nautilus 51.1、GTK 4.24.1、Hyprland 0.57.2。

验证时让文件窗口和另一扇含文字的窗口重叠。侧栏应能透出后方色调，同时把后方文字化开，前景文件名仍清晰。要回退玻璃样式，从安装器打印的 `gtk.css.bak.*` 和 `gtk-dark.css.bak.*` 恢复更新前的对应文件，再退出并重新打开 Nautilus。

ChatGPT 之前做的图标调整已经整合进安装脚本：

- 为 Omarchy 自带应用补上图标别名：`omacalc → calc`、`omawrite → text-editor`、`omarchy-discord → discord`
- MacTahoe 把 ChatGPT 和 Claude 的图标重画了。脚本把这两个别名改名为 `*.mactahoe-backup`，让它们使用厂商自己的官方图标
- ChatGPT 的官方图标透明留白和 MacTahoe 不一致，MacShell 补丁中的 `dockIconScale()` 在 Dock 里把它缩小 4%；Claude 已经重绘到标准圆角方块上，系数为 1.0
- `scripts/tune-app-icons.py` 让启动器里其余应用也统一成 MacTahoe 风格，结果直接装进 `MacTahoe/apps/scalable`，应用程序面板、Dock 和 Spotlight 都会使用：
  - 工具类和 Omarchy 自带应用链接到对应的 macOS 图标，例如 `imv → accessories-image-viewer`、`omacut → VideoTrimmer`、`hype → Keynote`、`gliff → remote-desktop`、`signed → PDF`、`monologue → Photo Booth`、`LimineSnapperSync → timeshift`、`wemeetapp → meeting`、`zoom → Zoom`
  - 有品牌的应用（Claude、HEY、Superwhisper、WorkBuddy、协作、Basecamp、Netcatty、Clippy、WowType、Google Messages 等）保留自己的标志，重新放到 MacTahoe 同款的圆角方块上：512 画布中 442 px、圆角 100，阴影取自主题自带的 Zoom 图标；圆形或单独字形的标志放在浅色底板上
  - 原来指向手工 PNG 的本地 `.desktop` 改为使用主题图标名
  - 装好新应用后再运行一次 `python3 scripts/tune-app-icons.py` 即可；没有对应关系的新应用需要先加到脚本里的 `ALIASES` 或 `BRANDS`
- MacShell 的 Dock 和 Spotlight 从 `~/.config/macshell/env` 中的 `QS_ICON_THEME` 读取图标主题

<a id="foot-glass"></a>

## Foot 磨砂玻璃

夜间用烟紫底，日间用浅雾白。Foot 只给默认背景加透明度，文字保持清晰。MacShell「外观」切换到日间、夜间或自动模式后，已加载玻璃配色的 Foot 窗口会跟随系统外观。浮动窗口沿用现有红绿灯标题栏。

在仓库根目录运行：

```bash
./scripts/install-foot-glass.sh
foot --check-config
systemctl --user is-active silky-foot-glass.service
```

安装器备份 `~/.config/foot/foot.ini` 并加入[玻璃配色](../config/foot/silky-glass.ini)和启动外观配置。需要支持双配色与背景虚化的 Foot（已在 1.28.0 验证）及开启背景虚化的 Hyprland，macOS Tahoe 主题已启用虚化。用户服务监视 `org.gnome.desktop.interface color-scheme`，写入新窗口的起始外观，并通知运行中的 Foot 切换配色。

安装后打开一个新的 Foot 窗口，把它放在有明显色彩的壁纸或窗口前，再通过 MacShell 切换日间和夜间，观察同一窗口的背景和文字。安装前打开的窗口需要重新打开才能加载玻璃配色。若使用 `foot --server`，等现有会话结束后重启该服务进程，新客户端即可载入玻璃配色。

回滚时运行 `systemctl --user disable --now silky-foot-glass.service`，把安装器报告的备份内容写回 `~/.config/foot/foot.ini`，然后打开新的 Foot 窗口。

<a id="remmina"></a>

## Remmina 简体中文与 macOS 外观

Remmina 1.4.44 自带简体中文翻译，但系统语言是 `en_US`，所以界面一直是英文。安装后，无论从启动器、Dock、`rdp://` 链接还是托盘小程序打开 Remmina，菜单、列标题和对话框都显示简体中文。macOS Tahoe 主题下还有以下变化：

- **MacShell 玻璃**：主窗口和远程连接窗口都是半透明背景，Hyprland 会模糊透出来的壁纸和窗口。夜间为烟灰玻璃 `#1c1c1e`，日间为磨砂白 `#f6f6f8`，比菜单更不透明一些，文字依然清晰。远程桌面画面本身保持不透明。
- **日间 / 夜间实时跟随**：通过 MacShell 或 `omarchy theme set` 切换外观时，已打开的 Remmina 窗口会立即切换，不需要重启。
- **主窗口**：标题栏按钮无边框，悬停时才显示圆角底色。连接列表去掉网格线，选中行显示为左右留边的圆角胶囊，颜色取 MacShell 强调色，窗口失焦时变为浅灰。快速连接栏、列标题和页脚都改为次要色小字。
- **远程连接窗口**：工具栏从左侧移到顶部，形成统一标题栏。左侧是红绿灯和连接名。按住标题栏的连接名或空白处直接拖动即可移动浮动窗口，不用按 `Super`；双击可最大化。右侧工具按钮换成一套 16 px 细线图标，提示文字也改成直白的说明，例如“远程分辨率跟随窗口”和“发送组合键”，并保留原有快捷键提示。已开启的开关（全屏、缩放、捕获键盘等）显示为强调色。
- **精简工具栏**：常用的连接列表、窗口贴合、全屏、动态分辨率、缩放、捕获键盘、截屏和断开连接直接显示。复制连接、仅查看、反转滚动、编辑连接设置、最小化和重新连接收进 `⋯` 菜单。当前协议不支持的插件菜单（画质选项、远程操作、发送组合键）会自动隐藏，分隔线也一并去掉。
- **标签栏**：只有一个会话时隐藏，有两个及以上会话时才显示，样式为圆角分段标签。标签行的空白处同样可以拖动窗口。

在仓库根目录运行：

```bash
./scripts/install-remmina-mac.sh
```

安装器只在 Remmina 未运行时修改 `~/.config/remmina/remmina.pref`，因为 Remmina 退出时会重写这个文件。如果安装时 Remmina 正在运行，请先结束远程会话，运行 `remmina --quit`，再重新运行一次安装器，然后从应用菜单打开 Remmina。Remmina 是单实例程序，安装前已经运行的进程（包括托盘小程序）要先退出，新语言和外观才会生效。依赖 `remmina`、`zh_CN.UTF-8` locale，以及用来编译模块的 `gcc`、`pkgconf`、`gtk3` 和 `librsvg`。外观部分还需要先装 [macOS Tahoe 主题](#安装与切换)，Hyprland 需开启窗口模糊（macOS Tahoe 主题已开启）。

### 实现

| 文件 | 作用 |
| --- | --- |
| [`plugins/silky-remmina/silky-remmina.c`](../plugins/silky-remmina/silky-remmina.c) | 只加载到 Remmina 的 GTK3 模块。仅在 MacTahoe 主题下，把下面的样式表叠加到当前 GTK 主题上，并监听 `gtk-theme-name` 实时切换深浅色。给主窗口和连接窗口加上 `.silky-glass`、`.silky-dark` / `.silky-light`，并设置 RGBA visual，使背景能透明。从 `~/.config/macbar/settings.json` 读取 MacShell 强调色，定义为 `@silky_accent`。主窗口列表的选中胶囊由模块绘制。连接窗口的工具栏按图标名识别各个按钮，替换图标和提示文字，隐藏或收进 `⋯` 菜单，并在横向工具栏前插入红绿灯和标题。启动时把自己从 `GTK_MODULES` 中移除，Remmina 启动的外部程序不会加载它 |
| [`config/remmina/silky-remmina.css`](../config/remmina/silky-remmina.css) | 玻璃颜色、主窗口、统一工具栏、红绿灯和标签栏的样式。文件变化后模块会自动重新加载 |
| [`config/remmina/icons/`](../config/remmina/icons/) | 工具栏线条图标：16×16、1.25 px 圆角描边，`currentColor` 在绘制时替换为按钮当前文字色 |
| [`bin/silky-remmina`](../bin/silky-remmina) | 安装到 `~/.local/bin/silky-remmina`。设置 `LANGUAGE=zh_CN:en`、`LC_MESSAGES=zh_CN.UTF-8`，模块存在时加上 `GTK_PATH` 和 `GTK_MODULES=silky-remmina`，再交给 `remmina-file-wrapper` |
| [`scripts/install-remmina-mac.sh`](../scripts/install-remmina-mac.sh) | 在临时目录编译模块，安装到 `~/.local/share/silky-remmina/gtk-3.0/modules/`，样式表和图标装到 `~/.local/share/silky-remmina/`。把 `org.remmina.Remmina*.desktop` 复制到 `~/.local/share/applications/` 并改写所有 `Exec`，同时改写 `~/.config/autostart/remmina-applet.desktop`。Remmina 未运行时设置 `toolbar_placement=0`（顶部）和 `always_show_tab=false`。只在内容变化时写入，原文件备份为 `*.bak.<时间>` |

Remmina 的控件大多没有 CSS 名称，规则写进全局 `~/.config/gtk-3.0/gtk.css` 会影响所有 GTK3 应用。旧版本改用 `GTK_THEME` 加载单独主题，但这会把外观固定在启动时，切换日间 / 夜间后要重启 Remmina 才能跟随。GTK3 模块不锁定主题，只叠加样式，所以能实时跟随。GTK3 只从 `GTK_PATH` 下的 `modules/` 目录按名称加载模块，不支持绝对路径。GTK3 的符号图标只会给 `path` 等元素重新填色，无法使用描边图标，所以工具栏图标由模块调用 librsvg，按当前颜色绘制。

只有横向工具栏（`toolbar_placement=0` 或 `2`）显示红绿灯和标题。在 Remmina 首选项里改回左侧或右侧时，按钮精简和新图标依然生效。全屏时使用 Remmina 自己的浮动工具栏，不加红绿灯。只针对 Remmina 1.4.44 / GTK 3.24 验证过，Remmina 改了工具栏图标名后，对应按钮会保留原样。Remmina 在原生 Wayland 下运行，不涉及 XWayland。

### 验证

```bash
grep -h '^Exec' ~/.local/share/applications/org.remmina.Remmina.desktop
grep -c libsilky-remmina /proc/"$(pgrep -xn remmina)"/maps
grep -E '^(toolbar_placement|always_show_tab)=' ~/.config/remmina/remmina.pref
```

预期 `Exec` 都指向 `~/.local/bin/silky-remmina`，进程映射中有该模块（计数大于 0），偏好为 `toolbar_placement=0` 和 `always_show_tab=false`。打开一个连接后，窗口顶部应为红绿灯、连接名和细线图标，点击 `⋯` 能看到收进去的操作。通过 MacShell 切换日间 / 夜间时，主窗口和连接窗口应立即变色，背后的壁纸被模糊。

已在隔离实例（独立 D-Bus 与配置目录，使用 WWW 协议的测试连接）中验证：模块加载、顶部工具栏、精简按钮与 `⋯` 菜单、线条图标、主窗口玻璃与选中胶囊，以及运行中从深色切到浅色。实机 RDP 会话的显示效果和 Hyprland 模糊效果待验证。

### 回滚

```bash
remmina --quit
rm ~/.local/share/applications/org.remmina.Remmina.desktop ~/.local/share/applications/org.remmina.Remmina-file.desktop
rm -r ~/.local/share/silky-remmina ~/.local/bin/silky-remmina
```

再把安装器报告的 `~/.config/autostart/remmina-applet.desktop.bak.*` 恢复为 `remmina-applet.desktop`。要恢复原来的左侧工具栏和常驻标签栏，用备份 `~/.config/remmina/remmina.pref.bak.*` 覆盖 `remmina.pref`，或在 Remmina 首选项 → 外观里修改。旧版本生成的 `~/.local/share/themes/Silky-Remmina-{Dark,Light}` 已不再使用，可以删除。然后重新打开 Remmina。

## 红绿灯标题栏

Omarchy 本身就会给浮动工作区里的窗口加标题栏：`default/hypr/workspace-modes.lua` 加载它自己的插件 `omarchy-hyprland-titlebars`（`/usr/lib/omarchy-hyprland-titlebars/titlebars.so`，基于 hyprbars），右侧放三个方形按钮 × □ −（`button_rounding = 0`）。在 macOS Tahoe 主题下改成：

- 统一标题栏高 30 px，标题居中。深浅主题的底色都略微透出下方的壁纸或窗口，聚焦时约 80% 不透明，失焦时约 84%。Hyprland 启用全局模糊时，标题栏背景也使用模糊。
- 左上角两个**圆形**按钮：12 px、`button_rounding = 6`、间距 8 px，`#ff5f57` / `#28c840`
- 指针移到灯上才显示 × − + 符号；窗口失焦时灯变灰
- 关闭 → 关闭窗口；绿灯 → 最大化 / 还原；双击标题栏同样最大化
- 只加在自己不画按钮的窗口上，目前是终端（foot、kitty、Alacritty、Ghostty、WezTerm）；Claude、Chrome、Electron 应用、GTK / libadwaita 应用和 MacShell 窗口保留自己的按钮。要给别的应用加，把 class 加进 `silky-macos.lua` 的 `with_bar`

### 实现

| 文件 | 作用 |
| --- | --- |
| `config/hypr/silky-titlebar-guard.lua` | 在 `hyprland.lua` 里排在 `require("default.hypr.omarchy")` **之前**。hyprbars 的按钮只能添加、不能删除，所以在 macOS 主题下把 `hl.plugin.hyprbars.add_button` 换成空函数，Omarchy 的三个方形按钮就加不进去；原函数保存在 `silky_add_button` |
| `config/hypr/silky-macos.lua` | 排在 Omarchy 默认配置之后：覆盖标题栏样式，用原函数加两个圆形按钮，按白名单设置 `hyprbars:no_bar` 规则 |

只有 Omarchy 已经加载了标题栏插件（某个工作区处于浮动模式）时才应用这些设置；否则直接跳过，不会出现 `unknown field 'hyprbars:no_bar'` 配置错误。不再自己编译 hyprbars，也就不需要在 Hyprland 更新后重新编译。

通过上面的主题安装脚本更新 [标题栏配置](../config/hypr/silky-macos.lua)，脚本会重载 Hyprland。可在浮动工作区把两个 Foot 窗口叠起来，切换焦点并观察标题栏能否透出下层颜色。只回滚这项效果时，恢复安装器报告的 `~/.config/hypr/silky-macos.lua.bak.*`，或将两个标题栏颜色改回不透明并将 `bar_blur` 设为 `false`，然后运行 `hyprctl reload`。

### 踩过的坑

- 早期版本另外编译加载了一份上游 hyprbars，和 Omarchy 自己的那份叠在一起：每个窗口两排按钮、按钮是方的、而且看起来像“加载了两次”
- 在运行中的会话里卸载其中一份，会连带注销 `hyprbars:no_bar` 等规则名，之后配置一直报错，只能重新登录

## 验证

```bash
omarchy theme current
gsettings get org.gnome.desktop.interface gtk-theme
gsettings get org.gnome.desktop.wm.preferences button-layout
qs -c MacShell ipc call appearance get
hyprctl plugin list | grep -c hyprbars
hyprctl configerrors
```

预期：主题名为 `Macos Tahoe Dark`，GTK 主题 `MacTahoe-Dark`，按钮布局 `close,maximize:`，MacShell 返回 `dark`，`hyprctl -j plugin list` 里 hyprbars 只有 1 个（Omarchy 的），没有配置错误。

已在真机上确认：主题切换、Finder 风格 Nautilus（蓝色文件夹、玻璃侧边栏、红绿灯）、窗口圆角和阴影、MacShell 深浅色联动。

**待验证**：浮动窗口的红绿灯标题栏需要在干净的会话里确认。在运行中的会话里卸载 hyprbars 的重复实例会连带注销它的窗口规则名，之后配置报错 `unknown field 'hyprbars:no_bar'`，而且没法在配置里捕获；只能重新登录。为防止开机时加载两次，加载命令放在 `flock` 下，并且只在 `hyprctl plugin list` 里还没有 hyprbars 时才加载。

## 回滚

```bash
omarchy theme set tokyo-night
```

切回任意其他主题后，hook 会恢复 GTK、按钮布局和指针。要彻底移除：

- 删除 `~/.config/omarchy/themes/macos-tahoe-*`、`~/.config/omarchy/backgrounds/macos-tahoe-*`
- 删除 `~/.config/omarchy/hooks/theme-set.d/silky-macos`
- 删除 `hyprland.lua` 里的 `require("hypr.silky-titlebar-guard")` 和 `require("hypr.silky-macos")`，以及这两个文件
- 删除 `~/.local/share/themes/MacTahoe-*`
