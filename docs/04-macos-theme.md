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

<a id="remmina"></a>

## Remmina 简体中文与 macOS 外观

Remmina 1.4.44 自带简体中文翻译，但系统语言是 `en_US`，所以界面一直是英文。安装后，从启动器、Dock、`rdp://` 链接或托盘小程序打开 Remmina，菜单、列标题和对话框都显示简体中文。macOS Tahoe 主题下，主窗口还有以下变化：

- 标题栏按钮不再是灰色圆底，改成无边框图标，指针悬停或按下时才出现圆角底色；标题使用 10pt 半粗体。
- 快速连接栏变薄，协议下拉框和地址栏都用 7 px 圆角，聚焦时有一圈柔和的强调色光晕。
- 连接列表去掉表格网格线，行距加大；列标题改用小号常规字重的次要色；页脚状态栏的文字也缩小、变淡，不再显示单独的底色条。

在仓库根目录运行：

```bash
./scripts/install-remmina-mac.sh
remmina --quit
```

然后从应用菜单重新打开 Remmina。Remmina 是单实例程序，所以安装前已经运行的进程（包括托盘小程序）需要先退出，新语言和样式才能生效。需要 `remmina`、`zh_CN.UTF-8` locale，外观部分还需要先装 [macOS Tahoe 主题](#安装与切换)。

### 实现

| 文件 | 作用 |
| --- | --- |
| [`bin/silky-remmina`](../bin/silky-remmina) | 安装到 `~/.local/bin/silky-remmina`。设置 `LANGUAGE=zh_CN:en`、`LC_MESSAGES=zh_CN.UTF-8`，并按当前 `gtk-theme` 选择 `GTK_THEME=Silky-Remmina-Dark` 或 `Silky-Remmina-Light`，再交给 `remmina-file-wrapper`。使用其他 GTK 主题时只切换语言 |
| [`config/remmina/silky-remmina.css`](../config/remmina/silky-remmina.css) | 主窗口样式，颜色取自 MacTahoe 的命名颜色，深浅两套共用 |
| [`scripts/install-remmina-mac.sh`](../scripts/install-remmina-mac.sh) | 生成 `~/.local/share/themes/Silky-Remmina-{Dark,Light}/gtk-3.0/`（先导入 MacTahoe，再导入上面的样式），把 `org.remmina.Remmina*.desktop` 复制到 `~/.local/share/applications/` 并改写所有 `Exec`，同时改写 `~/.config/autostart/remmina-applet.desktop`。内容有变化时才写入，原文件备份为 `*.bak.<时间>` |

Remmina 主窗口的控件没有设置 CSS 名称，写进全局 `~/.config/gtk-3.0/gtk.css` 会影响所有 GTK3 应用。因此改用只给 Remmina 进程加载的独立主题。外观在启动时确定：Remmina 运行期间切换日间 / 夜间，要等下次启动才会跟随。`GTK_THEME` 和语言变量也会传给 Remmina 启动的外部工具。Remmina 窗口不受 XWayland 影响，原生 Wayland 下已验证。

### 验证

```bash
grep -h '^Exec' ~/.local/share/applications/org.remmina.Remmina.desktop
tr '\0' '\n' < /proc/"$(pgrep -xn remmina)"/environ | grep -E '^(GTK_THEME|LANGUAGE)='
hyprctl clients -j | jq -r '.[] | select(.class == "org.remmina.Remmina") | .title'
```

预期 `Exec` 都指向 `~/.local/bin/silky-remmina`，进程环境里有 `GTK_THEME=Silky-Remmina-Dark`（或 `-Light`）和 `LANGUAGE=zh_CN:en`，窗口标题为 `Remmina 远程桌面客户端`。已在实机深色外观下确认中文界面、无网格线列表、扁平标题栏按钮和状态栏；浅色外观和远程会话窗口待验证。

### 回滚

```bash
remmina --quit
rm ~/.local/share/applications/org.remmina.Remmina.desktop ~/.local/share/applications/org.remmina.Remmina-file.desktop
rm -r ~/.local/share/themes/Silky-Remmina-Dark ~/.local/share/themes/Silky-Remmina-Light ~/.local/bin/silky-remmina
```

再把安装器报告的 `~/.config/autostart/remmina-applet.desktop.bak.*` 恢复为 `remmina-applet.desktop`，然后重新打开 Remmina。

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
