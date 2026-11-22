# 04 · macOS Tahoe 主题（深色 / 浅色）

简体中文 | [English](en/04-macos-theme.md)

## 目标

- 两个 Omarchy 主题：`macos-tahoe-dark` 和 `macos-tahoe-light`，配色取自 Apple 系统色板
- 窗口有 macOS 的质感：细边框、连续曲率圆角、聚焦窗口下方柔和的深阴影、半透明表面背后的玻璃模糊
- 图标换成 MacTahoe：蓝色文件夹、macOS 风格应用图标
- 文件管理器（Nautilus）换上 Finder 外观：半透明侧边栏、左上角红绿灯、空格键快速预览（sushi）
- 浮动窗口带 macOS 红绿灯标题栏，可关闭、最小化、最大化和还原
- 切换主题时，GTK 外观、鼠标指针和 MacShell 深浅色一起切换

## 组成

| 部分 | 文件 | 说明 |
| --- | --- | --- |
| 配色 | `themes/macos-tahoe-*/colors.toml` | Apple 系统色。浅色版终端文字用的是高对比度变体，否则黄色、绿色在白底上看不清 |
| 窗口外观 | `themes/macos-tahoe-*/hyprland.lua` | 1 px 半透明描边、14 px 圆角（`rounding_power = 2.6` 接近 Apple 的连续曲率）、阴影、3 次模糊；深浅色的模糊亮度都是 `1.0`（深色原为 `0.82`，会让 MacShell 玻璃比 Liquid Glass 深，见 [02](02-macshell.md#改用-hyprland-模糊普通模糊)） |
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

Nautilus 会把后方窗口和壁纸虚化成柔和的色块。侧栏透色更强，并带有细高光，文件区使用主题的实色视图背景，叠放窗口时文件名和图标也清晰。

[GTK 4 覆盖](../config/gtk-4.0/nautilus-glass.css)随主题安装脚本写入 `~/.local/share/themes/Silky-MacTahoe-{Dark,Light}/gtk-4.0/`。已安装 MacTahoe GTK 主题时，可在仓库根目录运行 `./scripts/install-macos-theme.sh --no-icons --no-gtk --no-bars` 更新。使用任一 macOS Tahoe 主题，保存工作并退出 Nautilus 的进程后重新打开。桌面虚化需要 GTK 的 Wayland 背景效果支持和开启虚化的 Hyprland。验证环境为 Nautilus 51.1、GTK 4.24.1、Hyprland 0.57.2。

验证时让文件窗口和另一扇含文字的窗口重叠。侧栏应能透出模糊后的色调，文件区应不透出后方内容。要回退玻璃样式，从安装器打印的 `gtk.css.bak.*` 和 `gtk-dark.css.bak.*` 恢复更新前的对应文件，再退出并重新打开 Nautilus。

ChatGPT 之前做的图标调整已经整合进安装脚本：

- 为 Omarchy 自带应用补上图标别名：`omacalc → calc`、`omawrite → text-editor`、`omarchy-discord → discord`
- MacTahoe 把 ChatGPT 和 Claude 的图标重画了。脚本把这两个别名改名为 `*.mactahoe-backup`，让它们使用厂商自己的官方图标
- ChatGPT 的官方图标透明留白和 MacTahoe 不一致，MacShell 补丁中的 `dockIconScale()` 在 Dock 里把它缩小 4%；Claude 已经重绘到标准圆角方块上，系数为 1.0
- `scripts/tune-app-icons.py` 让启动器里其余应用也统一成 MacTahoe 风格，结果直接装进 `MacTahoe/apps/scalable`，应用程序面板、Dock 和 Spotlight 都会使用：
  - 工具类和 Omarchy 自带应用链接到对应的 macOS 图标，例如 `imv → accessories-image-viewer`、`omacut → VideoTrimmer`、`hype → Keynote`、`gliff → remote-desktop`、`signed → PDF`、`monologue → Photo Booth`、`LimineSnapperSync → timeshift`、`wemeetapp → meeting`、`zoom → Zoom`
  - 有品牌或自定义标志的应用（Claude、Kimi Code、HEY、Superwhisper、WorkBuddy、协作、Basecamp、Netcatty、Clippy、WowType、Google Messages、Fantasi、Flowtunes 以及 Omarchy 浏览器 / 终端 / 媒体查看器 / Game Vibes / Agent 启动器等）保留自己的标志，重新放到 MacTahoe 同款的圆角方块上：512 画布中 442 px、圆角 100，阴影取自主题自带的 Zoom 图标；带描边和硬阴影的深色卡片先裁净外框再按原底色居中贴合；圆形或单独字形的标志放在浅色底板上
  - 原来指向绝对路径 PNG 或扁平设备图标的 `.desktop`（如 `antigravity.desktop`、`kimi-code.desktop`、`kbd-layout-viewer5.desktop` 等）在 `~/.local/share/applications/` 中改为使用对应的 MacTahoe 主题图标名
  - 装好新应用后再运行一次 `python3 scripts/tune-app-icons.py` 即可；没有对应关系的新应用需要先加到脚本里的 `ALIASES` 或 `BRANDS`
- MacShell 的 Dock 和 Spotlight 从 `~/.config/macshell/env` 中的 `QS_ICON_THEME` 读取图标主题

## Folio 的 Finder 外观

Folio 使用 MacTahoe 图标包已有的 Finder 图标，Dock 和 MacShell 应用面板沿用同一个 `folio` 应用 ID。左侧导航栏保留磨砂，右侧路径栏、文件区和预览区使用完全不透明的主题底色。文件夹沿用蓝色图标和圆角选中框。左上角红灯关闭，黄灯最小化。绿灯用加号表示进入全屏，用向内的斜角图标表示退出全屏，单击与 `Super+F` 一样切换全屏。全屏时黄灯置灰。右键点绿灯或按住绿灯可打开窗口布局菜单，通过两排图标选择四个半屏位置或四个角落，方便与其他窗口并排。悬停时显示位置名称。全屏时菜单可退出全屏，布局图标置灰。拖动按钮旁的空白或用鼠标、触屏拖动路径栏可以移动浮动窗口，双击该区域可最大化或还原。拖到屏幕左右边缘时，中段预览半屏，上下两段分别预览对应的四分之一屏。蓝色预览以线性动画切换位置和尺寸，离开边缘时淡出。松手后立即提交吸附，预览在 45 毫秒内淡出。预览和窗口都避开菜单栏及 Dock 的预留区域。

顶栏高 44 px，红黄绿按钮采用 12 px 实色圆点和 8 px 间隔，与 Foot 的圆点大小对齐。悬停时 Files 的符号使用原有路径笔画。侧栏背景贯通顶部和内容区，文件区的细线下方仍有背景。列视图自动对齐时会避开只露出半个图标的位置。

Tahoe 主题下，浮动 Folio 的侧栏磨砂直接取窗口下方的画面，并由 Hyprland 裁出圆角。针对侧栏圆角出现的彩色细边，[Folio 窗口规则](../config/hypr/silky-folio.lua)让它使用实时背景并去掉半透明外描边。普通 Folio 窗口在首帧直接以不透明内容呈现，跳过上游为平铺窗口准备的 150 ms 隐藏等待与 100 ms 淡入动画，避免打开瞬间先闪出一整块纯虚化的空白玻璃（文件选择器模式保留原有行为）。更新这份用户配置后运行 `hyprctl reload` 即可作用于已打开的窗口。可把 Folio 叠到深浅反差明显的窗口上，观察左上角和左下角。回滚时从该文件移除 `silky-folio-rounded-glass-edge` 规则并重载。

用鼠标单击或触屏轻点顶部路径文字及旁边的空白，可以编辑并选中当前路径。拖动路径栏仍可移动窗口。用鼠标点击或触屏轻点文件区空白即可取消编辑。触屏滑动仍可滚动文件。按 `Ctrl+L` 也可进入编辑。输入后按回车跳转，按 `Esc` 退出编辑。路径右侧的复制图标用于复制当前目录的完整路径。在分栏视图中，选中子文件夹并在右侧栏展开其内容时，顶部路径栏、窗口标题、路径编辑和复制路径按钮会同步包含该子文件夹；选中文件或切换到列表/网格视图时，路径栏回到所在目录。

分栏、列表和图标视图都支持触屏单指滑动滚动文件，鼠标仍可拖放文件。分栏视图中，触屏单指轻点与鼠标左键一致。单指长按或双指轻点会在先触碰的位置打开右键菜单。手指移动超过系统的拖动阈值后，该次手势不会弹出菜单。 如果启用了 Silky Gestures，用其安装脚本重建插件，使文件区的长按交给 Folio。见 [触控屏移动、缩放浮动窗口](03-silky-gestures.md#触控屏移动缩放浮动窗口)。

回收站视图把顶部空间留给文件列表。在左侧右键点「回收站」即可选择居中显示的「清空」，也可从回收站的文件区打开同一操作。选择后需确认，回收站为空时侧栏菜单中的操作置灰。

先通过主题安装脚本安装 MacTahoe 图标包，并启用 `macos-tahoe-dark` 或 `macos-tahoe-light`。从仓库根目录运行：

```bash
./scripts/install-folio-macos.sh
hyprctl reload
qs -c MacShell ipc call macshell reload
```

安装器以 Folio 0.6.1 的固定源码构建[窗口补丁](../patches/folio-0.6.1-silky.patch)。构建依赖 Git、CMake、C++ 编译器、pkg-config、Qt 6、GLib/GIO 和 zlib。它在 `~/.local/share/silky-omarchy/folio/` 放置构建产物，通过 `~/.local/bin/folio` 和用户级 `folio.desktop` 保留原有 Dock 固定项及文件快捷键。预览、系统文件选择器和其他主题使用软件包提供的 Folio。在 Tahoe 主题下，启动器只检查用户构建所需的共享库及符号。更新内核或系统 Folio 后，Dock、默认目录入口和两种文件管理器快捷键继续使用相同的用户构建和视图设置。定制版仍基于 0.6.1，独立于系统 Folio 更新。用户构建缺失或动态库不兼容时，启动器使用软件包版本。可在升级后用 `gtk-launch folio.desktop /tmp` 打开目录，并检查 `/proc/<Folio PID>/exe` 是否指向用户目录下的构建。已在系统 Folio 0.7.1 和内核 7.3.0-75-omarchy 上验证桌面入口。[Folio 窗口规则](../config/hypr/silky-folio.lua)在 Hyprland 里取消 Folio 的整窗透明度，让应用自己的侧栏透明度生效。

MacShell 的[窗口接入脚本](../scripts/tune-folio-macshell.py)让黄灯把窗口缩进 Dock 分隔线和废纸篓之间。点击独立的窗口缩略图即可恢复。见 [窗口最小化](02-macshell.md#窗口最小化)。未运行 MacShell 时，Omarchy 的最小化只适用于浮动工作区。已在 Hyprland 0.57.2、MacShell 0.5.3 和 Folio 0.6.1 的原生 Wayland 会话验证。重开 Folio 后依次点击绿灯两次、黄灯、Dock 缩略图和红灯，预期是进入全屏、退出全屏、最小化、恢复同一窗口和关闭。右键与长按绿灯都应打开菜单，所选半区应避开菜单栏和 Dock 预留区域。四角图标应和拖动到角落的预览一致。全屏时布局图标和黄灯应置灰。在轮廓明显的壁纸上检查右侧空白区域，浮动和全屏时都应为纯色，左侧仍能透出模糊的色彩。若全屏里出现空的 Dock 轮廓，见 [Dock 液态玻璃插件](02-macshell.md#dock-液态玻璃插件原型)。

回滚时恢复安装器打印的 `.bak.folio.*`，若原先没有用户级启动器和桌面入口，移除 `~/.local/bin/folio` 与 `~/.local/share/applications/folio.desktop`。恢复 MacShell 的 `MacDock.qml` 和 `shell.qml` 备份后重载 MacShell，再重新打开 Folio。已最小化的窗口先从 Dock 恢复。移除 Folio 的透明度、最小化叠层和半屏布局配置时，从 `~/.config/hypr/hyprland.lua` 移除 `require("hypr.silky-folio")` 后重载 Hyprland。

<a id="foot-glass"></a>

## Foot 的 Tahoe 外观

参考 Folio 的内容分层，Foot 用实色石墨灰或暖白承载输出，磨砂集中在 30 px 浮动标题栏。正文使用 11 pt Monaco，中文、终端图标和 emoji 有字体回退。正文四周留白为左右 20 px、上下 16 px。深浅两套 ANSI 配色都使用蓝色选区和细竖线光标。MacShell 的日间、夜间和自动外观会切换已加载配色的 Foot 窗口。

浮动标题栏的红灯关闭窗口，黄灯走 MacShell 的最小化动作并可从 Dock 恢复。绿灯单击与 Files 一样进入全屏，右键或长按打开两排布局图标，可选上下左右半屏和四角。全屏时把指针移到屏幕左上缘，可用绿灯退出。拖动标题栏空白处可移动窗口，双击可最大化或还原。拖到左右边缘时，中段预览半屏，上下两段预览对应的角落。松手只落位当前窗口，菜单栏和 Dock 的预留空间参与计算。

Foot 与 Files 的彩色圆面均为 12 px。悬停时，Silky Gestures 在 Tahoe 共用标题栏上用与 Files 相同的路径和 1.1 px 圆端笔画绘制叉、横线和加号，并按显示器缩放生成贴合像素网格的纹理。Foot 的全屏浮条沿用 Files 的内收斜角作为退出标记，黄色按钮置灰。更新需要运行 `./scripts/install-silky-gestures.sh` 并安装同版 `silky-macos.lua`，然后重载 Hyprland。未安装新版插件时，共用标题栏使用配置里的字体符号。回滚时恢复 `silky-macos.lua` 和上一版插件，再重新登录以载入原插件。全屏浮条由 `FootWindowLayout.qml` 提供，更新后重载 MacShell。

在仓库根目录运行：

```bash
./scripts/install-foot-glass.sh
foot --check-config
systemctl --user is-active silky-foot-glass.service
```

浮动标题栏由[主题安装器](#安装与切换)提供。Foot 安装器备份变更的 `~/.config/foot/foot.ini` 和 `~/.config/foot/silky-glass.ini`，首次迁移把字体写进 `foot.ini`，便于继续使用 Omarchy 的字号和字体命令。[外观配置](../config/foot/silky-glass.ini)需要支持双配色的 Foot，已在 1.28.0 验证。字体使用已安装的 Monaco、JetBrainsMono Nerd Font、Sarasa Mono SC 和 Noto Color Emoji，以及 Fontconfig 提供的回退。用户服务监视 `org.gnome.desktop.interface color-scheme`，为新窗口设置初始外观，并通知运行中的窗口切换配色。

窗口布局使用现有的 Files/MacShell 集成。已有该集成时，从仓库根目录更新 `config/hypr/silky-folio.lua` 和 `config/hypr/silky-macos.lua` 到 `~/.config/hypr/`，先备份同名文件和 `~/.local/lib/silky-omarchy/` 下的当前 Silky Gestures 插件。运行 `./scripts/install-silky-gestures.sh` 重建输入插件，运行 `python3 scripts/tune-folio-macshell.py ~/.config/quickshell/MacShell --backup` 更新菜单，最后执行 `hyprctl reload` 和 `qs -c MacShell ipc call macshell reload`。回滚布局时恢复这两份 Lua 备份、MacShell 的 `shell.qml` 备份和原插件，再重新登录以载入原插件。

通过默认终端入口新开窗口，检查中文、ANSI 色、选区和标题栏按钮。安装前打开的窗口在会话结束后重新打开即可载入新版。使用 `foot --server` 时，等活动会话结束再重启服务进程。

在 Hyprland 0.57.2 实机上核对了两套配色和 MacShell 最小化、恢复原会话。隔离 Wayland 会话用模拟鼠标验证绿灯右键、长按、全屏进入与退出、蓝色吸附预览和右上角落位，并核对八种落位均避开菜单栏与 Dock。更新后在内屏模拟拖动标题栏，Wayland 送显记录为 89.6 FPS。实体触屏待复测。

回到上版外观时，恢复安装器打印的 Foot 备份并新开窗口。完全取消外观同步时，执行 `systemctl --user disable --now silky-foot-glass.service`，并恢复首次安装前的 `foot.ini` 或删除其中的两个 Silky include。标题栏单独回滚时恢复 `~/.config/hypr/silky-macos.lua` 的备份并运行 `hyprctl reload`。

<a id="remmina"></a>

## Remmina 简体中文与 macOS 外观

Remmina 1.4.44 自带简体中文翻译，但系统语言是 `en_US`，所以界面一直是英文。安装后，无论从启动器、Dock、`rdp://` 链接还是托盘小程序打开 Remmina，菜单、列标题和对话框都显示简体中文。macOS Tahoe 主题下还有以下变化：

- **MacShell 玻璃**：主窗口标题栏和会话工具栏使用磨砂。主窗口的连接列表、快速连接区和页脚用实色底（深色 `#1c1c1e`、浅色 `#f6f6f8`），远程桌面画面也保持实色。
- **日间 / 夜间实时跟随**：通过 MacShell 或 `omarchy theme set` 切换外观时，已打开的 Remmina 窗口会立即切换，不需要重启。
- **主窗口**：标题栏按钮无边框，悬停时才显示圆角底色。连接列表去掉网格线，选中行显示为左右留边的圆角胶囊，颜色取 MacShell 强调色，窗口失焦时变为浅灰。快速连接栏、列标题和页脚都改为次要色小字。
- **远程连接窗口**：工具栏从左侧移到顶部，形成统一标题栏。左侧是红绿灯和连接名。按住标题栏的连接名或中间空白处直接拖动即可移动浮动窗口，不用按 `Super`；双击可最大化。右侧工具按钮换成一套 16 px 细线图标，提示文字也改成直白的说明，例如“远程分辨率跟随窗口”和“发送组合键”，并保留原有快捷键提示。已开启的开关（全屏、缩放、捕获键盘等）显示为强调色。
- **精简工具栏**：常用的连接列表、窗口贴合、全屏、动态分辨率、缩放、捕获键盘、截屏和断开连接直接显示。复制连接、仅查看、反转滚动、编辑连接设置、最小化和重新连接收进 `⋯` 菜单。当前协议不支持的插件菜单（画质选项、远程操作、发送组合键）会自动隐藏，分隔线也一并去掉。
- **远程画面清晰、大小合适**：在 2 倍缩放的屏幕上，原版 Remmina 按窗口的逻辑尺寸（约 1159×630）向 Windows 请求分辨率，再把每个远程像素放大成 2×2，Windows 界面看起来像 200% 缩放，而且发虚。补丁后的 RDP 插件按实际像素（约 2318×1260）请求分辨率并 1:1 显示，Windows 再按 150% 缩放，界面约为原来的 3/4，文字锐利。调整窗口大小时远程分辨率继续跟随，远程鼠标指针也按高分屏大小显示。详见[远程画面的高分屏缩放](#remmina-hidpi)。
- **标签栏**：只有一个会话时隐藏，有两个及以上会话时才显示，样式为圆角分段标签。标签行的空白处同样可以拖动窗口。

在仓库根目录运行：

```bash
./scripts/install-remmina-mac.sh
```

顶部工具栏和“单个会话不显示标签栏”由模块直接实现，不依赖 Remmina 的首选项。Remmina 只在启动时读取 `~/.config/remmina/remmina.pref`，退出时又会重写它，所以安装器写入的 `toolbar_placement` 可能被覆盖。安装器仍会在 Remmina 未运行时写入这两项，作为不加载模块时的备用设置。安装后请结束远程会话，运行 `remmina --quit`，再从应用菜单打开 Remmina。Remmina 是单实例程序，安装前已经运行的进程（包括托盘小程序）要先退出，新语言和外观才会生效。依赖 `remmina`、`zh_CN.UTF-8` locale，以及用来编译模块的 `gcc`、`pkgconf`、`gtk3` 和 `librsvg`。高分屏 RDP 插件还需要 `cmake`、`make`、`curl`、`patch` 和 `freerdp`（Remmina 的依赖已带上），首次安装会下载约 4 MB 的 Remmina 源码。外观部分还需要先装 [macOS Tahoe 主题](#安装与切换)，Hyprland 需开启窗口模糊（macOS Tahoe 主题已开启）。

### 实现

| 文件 | 作用 |
| --- | --- |
| [`plugins/silky-remmina/silky-remmina.c`](../plugins/silky-remmina/silky-remmina.c) | 只加载到 Remmina 的 GTK3 模块。仅在 MacTahoe 主题下，把下面的样式表叠加到当前 GTK 主题上，并监听 `gtk-theme-name` 实时切换深浅色。给主窗口和连接窗口加上 `.silky-glass`、`.silky-dark` / `.silky-light`，并设置 RGBA visual，使背景能透明。从 `~/.config/macbar/settings.json` 读取 MacShell 强调色，定义为 `@silky_accent`。主窗口列表的选中胶囊由模块绘制。连接窗口的工具栏按图标名识别各个按钮，替换图标和提示文字，隐藏或收进 `⋯` 菜单，并在横向工具栏前插入红绿灯和标题。启动时把自己从 `GTK_MODULES` 中移除，Remmina 启动的外部程序不会加载它 |
| [`config/remmina/silky-remmina.css`](../config/remmina/silky-remmina.css) | 玻璃颜色、主窗口、统一工具栏、红绿灯和标签栏的样式。文件变化后模块会自动重新加载 |
| [`config/remmina/icons/`](../config/remmina/icons/) | 工具栏线条图标：16×16、1.25 px 圆角描边，`currentColor` 在绘制时替换为按钮当前文字色 |
| [`patches/remmina-1.4.44-rdp-hidpi.patch`](../patches/remmina-1.4.44-rdp-hidpi.patch) | 只改 RDP 插件的 `plugins/rdp/rdp_event.c`，见下方[高分屏缩放](#remmina-hidpi) |
| [`bin/silky-remmina`](../bin/silky-remmina) | 安装到 `~/.local/bin/silky-remmina`。设置 `LANGUAGE=zh_CN:en`、`LC_MESSAGES=zh_CN.UTF-8`，模块存在时加上 `GTK_PATH` 和 `GTK_MODULES=silky-remmina`。高分屏插件的版本和已装 Remmina 不一致时，把插件改名为 `remmina-plugin-rdp.so.disabled-<版本>` 并发通知，避免旧插件加载进新版 Remmina。最后交给 `remmina-file-wrapper` |
| [`scripts/install-remmina-mac.sh`](../scripts/install-remmina-mac.sh) | 在临时目录编译模块，安装到 `~/.local/share/silky-remmina/gtk-3.0/modules/`，样式表和图标装到 `~/.local/share/silky-remmina/`。把 `org.remmina.Remmina*.desktop` 复制到 `~/.local/share/applications/` 并改写所有 `Exec`，同时改写 `~/.config/autostart/remmina-applet.desktop`。Remmina 未运行时设置 `toolbar_placement=0`（顶部）和 `always_show_tab=false`。只在内容变化时写入，原文件备份为 `*.bak.<时间>` |

Remmina 的控件大多没有 CSS 名称，规则写进全局 `~/.config/gtk-3.0/gtk.css` 会影响所有 GTK3 应用。旧版本改用 `GTK_THEME` 加载单独主题，但这会把外观固定在启动时，切换日间 / 夜间后要重启 Remmina 才能跟随。GTK3 模块不锁定主题，只叠加样式，所以能实时跟随。GTK3 只从 `GTK_PATH` 下的 `modules/` 目录按名称加载模块，不支持绝对路径。GTK3 的符号图标只会给 `path` 等元素重新填色，无法使用描边图标，所以工具栏图标由模块调用 librsvg，按当前颜色绘制。绘制图标的控件不带自己的 GdkWindow，否则图标会挡住按钮中心，只有点按钮边缘才有反应。`⋯` 菜单关闭后才销毁：GTK 先关闭菜单再执行所选项，立即销毁会让菜单项点击失效。

模块把窗口模式下的工具栏移到 Remmina 网格的第一行，把连接区域放到第二行，所以不论首选项把工具栏放在哪一侧，都会显示在顶部。要保留 Remmina 自己的位置和标签栏行为，在 `bin/silky-remmina` 里设置 `SILKY_REMMINA_TOOLBAR=native`，此时只有横向工具栏才显示红绿灯和标题，按钮精简和新图标依然生效。拖动由 GTK 发出 `xdg_toplevel.move`，Hyprland 对浮动窗口会直接跟随指针移动；平铺窗口由 Hyprland 的平铺布局决定，不会因拖动而移动。GTK3 按钮不会拦截按下事件，事件会继续冒泡到父控件，所以模块只在连接名和空白区域的事件盒上发起拖动，并跳过从按钮、输入框开始的按下，否则窗口管理器会接管指针，按钮收不到松开事件，点击就会失效。全屏时使用 Remmina 自己的浮动工具栏，不加红绿灯。只针对 Remmina 1.4.44 / GTK 3.24 验证过，Remmina 改了工具栏图标名后，对应按钮会保留原样。Remmina 在原生 Wayland 下运行，不涉及 XWayland。

<a id="remmina-hidpi"></a>

### 远程画面的高分屏缩放

Remmina 1.4.44 的 RDP 插件在“动态分辨率”模式下，用 `gtk_widget_get_allocation()` 得到的逻辑尺寸作为远程分辨率，并按逻辑像素 1:1 绘制。在 Hyprland 缩放为 2 的屏幕上，每个远程像素会被 GTK 放大成 2×2。[补丁](../patches/remmina-1.4.44-rdp-hidpi.patch)只在动态分辨率模式且 GTK 缩放大于 1 时生效，做四件事：

- 发给服务器的分辨率乘以缩放倍数，连接建立后立即按实际像素更正一次
- 绘制、重绘区域和鼠标坐标复用 Remmina 现有的“缩放”路径，比例正好是 1/2，所以画面 1:1、不发虚
- 远程鼠标指针按设备像素生成光标，不再放大一倍
- 缩放倍数为 1、固定分辨率和“缩放”模式的行为保持不变

画面里 Windows 内容的大小由 Remmina 的“桌面缩放比例 %”控制（首选项 → RDP，对应 `remmina.pref` 的 `rdp_desktopScaleFactor`，需要 `rdp_deviceScaleFactor` 同时非 0）。安装器在这两项未设置时写入 `150` 和 `100`，已有的设置不会被覆盖。想要更小可以改为 `125`，更大可以改为 `175`，下次连接生效，不需要重启 Remmina。可选值为 100–500，设备缩放只接受 100、140、180。这两项是全局设置，对所有 RDP 连接都生效。Windows Server 2012 R2 / Windows 8.1 及以上才会在会话中途按新的缩放比例重排界面。

安装器从 GitLab 下载固定版本的 Remmina 1.4.44 源码（校验 SHA-256），打补丁后只编译 `remmina-plugin-rdp` 目标，功能开关与 Arch 软件包一致（含 CUPS 打印、libsecret），装到 `~/.config/remmina/plugins/remmina-plugin-rdp.so`。Remmina 会先查找这个目录，同名插件不会再从 `/usr/lib/remmina/plugins/` 加载，软件包管理的文件保持原样。源码缓存在 `~/.cache/silky-omarchy/remmina-1.4.44/`，补丁或版本未变时不会重新编译。Remmina 不是 1.4.44 时安装器跳过这一步，设置 `SILKY_REMMINA_HIDPI=0` 也可以跳过，设置 `SILKY_REMMINA_SCALE=125` 可以在首次安装时选用其他比例。

已验证：补丁通过编译器检查且编译无警告；新插件和系统插件链接的库、导出符号完全一致；隔离实例只加载了用户目录中的插件。实机 RDP 会话中的清晰度、窗口缩放时的分辨率跟随和鼠标指针位置待验证。

### 验证

```bash
grep -h '^Exec' ~/.local/share/applications/org.remmina.Remmina.desktop
grep -c libsilky-remmina /proc/"$(pgrep -xn remmina)"/maps
grep -E '^(toolbar_placement|always_show_tab)=' ~/.config/remmina/remmina.pref
grep -o '/[^ ]*remmina-plugin-rdp.so' /proc/"$(pgrep -xn remmina)"/maps | sort -u
grep -E '^rdp_(desktop|device)ScaleFactor=' ~/.config/remmina/remmina.pref
```

预期 `Exec` 都指向 `~/.local/bin/silky-remmina`，进程映射中有该模块（计数大于 0）。偏好里的两项只是备用值，即使仍是 `toolbar_placement=3`，工具栏也应在顶部。打开一个连接后，窗口顶部应为红绿灯、连接名和细线图标，点击 `⋯` 能看到收进去的操作。通过 MacShell 切换日间 / 夜间时，连接列表的实色背景和标题栏、会话工具栏的磨砂应立即切换。RDP 插件路径应为 `~/.config/remmina/plugins/remmina-plugin-rdp.so`，缩放偏好为 `rdp_desktopScaleFactor=150` 和 `rdp_deviceScaleFactor=100`。连上 Windows 后，在远程桌面右键 → 显示设置，分辨率应约为窗口实际像素（窗口逻辑尺寸的 2 倍），缩放为 150%，文字边缘锐利。

已在隔离实例（独立 D-Bus 与配置目录，使用 WWW 协议的测试连接）中验证：模块加载、顶部工具栏、精简按钮与 `⋯` 菜单、线条图标、主窗口玻璃与选中胶囊，运行中从深色切到浅色，以及首选项为左侧工具栏时仍显示在顶部。实机 RDP 会话的显示效果和 Hyprland 模糊效果待验证。

### 回滚

```bash
remmina --quit
rm ~/.local/share/applications/org.remmina.Remmina.desktop ~/.local/share/applications/org.remmina.Remmina-file.desktop
rm -r ~/.local/share/silky-remmina ~/.local/bin/silky-remmina
rm ~/.config/remmina/plugins/remmina-plugin-rdp.so ~/.config/remmina/plugins/.silky-hidpi
```

只回滚高分屏插件时执行第二段的最后一条即可，Remmina 下次启动会重新加载系统插件；再在首选项 → RDP 里把桌面缩放比例改回 0，或删掉 `remmina.pref` 中的 `rdp_desktopScaleFactor` 和 `rdp_deviceScaleFactor`。源码缓存在 `~/.cache/silky-omarchy/remmina-1.4.44/`，可以删除。再把安装器报告的 `~/.config/autostart/remmina-applet.desktop.bak.*` 恢复为 `remmina-applet.desktop`。要恢复原来的左侧工具栏和常驻标签栏，用备份 `~/.config/remmina/remmina.pref.bak.*` 覆盖 `remmina.pref`，或在 Remmina 首选项 → 外观里修改。旧版本生成的 `~/.local/share/themes/Silky-Remmina-{Dark,Light}` 已不再使用，可以删除。然后重新打开 Remmina。

## 红绿灯标题栏

Omarchy 本身就会给浮动工作区里的窗口加标题栏：`default/hypr/workspace-modes.lua` 加载它自己的插件 `omarchy-hyprland-titlebars`（`/usr/lib/omarchy-hyprland-titlebars/titlebars.so`，基于 hyprbars），右侧放三个方形按钮 × □ −（`button_rounding = 0`）。在 macOS Tahoe 主题下改成：

- 统一标题栏高 30 px，标题居中。深浅主题的底色都略微透出下方的壁纸或窗口，聚焦时约 80% 不透明，失焦时约 84%。Hyprland 启用全局模糊时，标题栏背景也使用模糊。
- 左上角三个**圆形**按钮，直径 12 px、间距 8 px，颜色为 `#ff5f57`、`#febc2e` 和 `#28c840`
- 指针移到灯上才显示 × − + 符号；窗口失焦时灯变灰
- 红灯关闭窗口，黄灯最小化到 Dock。Foot 和下方四个系统应用点绿灯切换全屏，双击标题栏空白处切换最大化。
- 标题栏用于由 Hyprland 装饰的窗口，包括 Foot、其他列入配置的终端和下方四个系统应用。自绘窗口按钮的应用继续使用各自的装饰。

### 实现

| 文件 | 作用 |
| --- | --- |
| `config/hypr/silky-titlebar-guard.lua` | 在 `hyprland.lua` 里排在 `require("default.hypr.omarchy")` **之前**。hyprbars 的按钮只能添加、不能删除，所以在 macOS 主题下把 `hl.plugin.hyprbars.add_button` 换成空函数，Omarchy 的三个方形按钮就加不进去；原函数保存在 `silky_add_button` |
| `config/hypr/silky-macos.lua` | 排在 Omarchy 默认配置之后，覆盖标题栏样式，用原函数加三个圆形按钮，按白名单设置 `hyprbars:no_bar` 规则 |

只有 Omarchy 已经加载了标题栏插件（某个工作区处于浮动模式）时才应用这些设置；否则直接跳过，不会出现 `unknown field 'hyprbars:no_bar'` 配置错误。不再自己编译 hyprbars，也就不需要在 Hyprland 更新后重新编译。

通过上面的主题安装脚本更新 [标题栏配置](../config/hypr/silky-macos.lua)，脚本会重载 Hyprland。可在浮动工作区把两个 Foot 窗口叠起来，切换焦点并观察标题栏能否透出下层颜色。只回滚这项效果时，恢复安装器报告的 `~/.config/hypr/silky-macos.lua.bak.*`，或将两个标题栏颜色改回不透明并将 `bar_blur` 设为 `false`，然后运行 `hyprctl reload`。

<a id="system-app-audit"></a>

### 系统应用按窗口标准整改

| 应用 | 变化 |
| --- | --- |
| 计算器、Omacut、Write、媒体查看器 | 浮动窗口使用 30 px 共用标题栏。黄灯通过 MacShell 最小化到 Dock，绿灯单击与 `Super+F` 一致，进入全屏后从左上角浮条退出。绿灯右键或长按打开半屏和四角选项。布局菜单和拖拽预览根据应用的最小、最大尺寸和屏幕的可用空间筛选位置。 |
| 罗技鼠标（Omalogi） | 独立窗口使用共用标题栏，编辑区使用随主题变化的实色底。见[独立窗口](14-omalogi.md#独立窗口)。 |
| 微信 | 主窗口的聊天内容和列表以原有色彩显示，去掉了合成器的整窗半透明和渐变描边。更新 [微信启动器配套配置](01-touchpad-gestures.md#微信会话列表触屏滚动) 后，Hyprland 重载即可应用窗口规则。 |
| AccessClient 的 PuTTY | 原生 XWayland 控制台使用实色。按 [快捷键安装入口](10-shortcuts.md#安装) 更新 `silky-app-windows.lua`，重载后检查浮动 SSH 窗口。 |
| Nautilus、Remmina | [Nautilus](#文件管理器磨砂玻璃) 把磨砂放在辅助区域，文件区使用实色。[Remmina](#remmina) 的连接列表使用实色，标题栏和会话工具栏保留磨砂。更新 Remmina 样式后重新打开启动器窗口即可检查。 |

四个系统应用沿用 Omarchy 的应用 ID 和启动器。需要 Hyprland 0.57.2 对应的 Silky Gestures 插件及已有的 Folio/MacShell 集成。更新主题的标题栏配置，并备份和替换 `~/.config/hypr/silky-folio.lua` 后，在仓库根目录执行：

```bash
./scripts/install-silky-gestures.sh
python3 scripts/tune-folio-macshell.py ~/.config/quickshell/MacShell --backup
hyprctl reload
hyprctl configerrors
qs -c MacShell ipc call macshell reload
```

布局尺寸由 [Silky Gestures](../plugins/silky-gestures/foot-layout.hpp) 读取，[Hyprland 配置](../config/hypr/silky-folio.lua) 统一计算预览和落位，并为 30 px 合成器标题栏留出空间。未加载支持布局的插件时，新增四个应用的绿灯仍由合成器切换全屏，可按 `Super+F` 退出。

验证时，从启动器打开四个系统应用，分别使用绿灯右键、长按、`Esc`、单击以及左上角退出浮条。小于最小窗口尺寸的位置会置灰，拖入对应边缘也不会吸附。点黄灯后从 Dock 恢复，核对同一窗口和位置。微信、PuTTY、Nautilus 和 Remmina 可在后方叠放带高对比文字的窗口，检查聊天、终端、文件或连接列表的底色。

验证环境为 Hyprland 0.57.2、2 倍缩放的 90 Hz 内屏，以及 1472×920 的隔离 Wayland 会话。模拟输入覆盖了共用绿灯菜单和全屏交互、Foot 全部八种布局、媒体查看器拖拽吸附和 Write 的禁用位置。通过 MacShell 的 Dock IPC 恢复计算器时，窗口标识、工作区和几何位置与原来一致。Remmina 隔离实例和 Nautilus 的 GTK4 样式测试在深浅外观下均用鲜艳背景测过正文底色。微信和 PuTTY 的规则使用模拟窗口类名验证。实体触屏、外接屏和实际 RDP 会话待验。

回滚时恢复安装器打印的标题栏、插件和 MacShell 备份，以及更新前的 `silky-folio.lua`。重新加载 Hyprland 和 MacShell，重新登录可载入回滚后的插件。微信、PuTTY 和两份 GTK 样式按各自安装章节的备份恢复。Remmina 只回滚样式时恢复 `~/.local/share/silky-remmina/silky-remmina.css.bak.*`，再重新打开应用。

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
