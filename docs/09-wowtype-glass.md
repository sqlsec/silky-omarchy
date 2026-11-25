# 09 · WowType 候选框：圆角毛玻璃与微信重影修复

简体中文 | [English](en/09-wowtype-glass.md)

```bash
./scripts/install-wowtype-glass.sh
```

装完重启一次微信。

## 微信里候选条为什么模糊、有重影

其他应用的候选框由 fcitx5 自己画，走 Wayland input-method-v2 的弹出层，一直是同一个表面，所以很丝滑。

微信不一样：它把 fcitx5-qt 客户端静态编进了自己的二进制，并声明了 `ClientSideInputPanel`
（`busctl --user call org.fcitx.Fcitx5 /controller org.fcitx.Fcitx.Controller1 DebugInfo` 里微信那条
`frontend:dbus` 的 cap 含 bit 39）。于是候选条是微信自己的 Qt 画的一个 xdg_popup，**每敲一个键就销毁重建一次**。
Hyprland 默认给弹出层做淡入淡出（`fadePopups` 继承 `fade`），旧候选条还在淡出、新候选条在淡入，两层叠在一起就是重影，
叠上 `blur:popups` 更显得糊。静止时其实是清晰的。

修复只需一行：`config/hypr/silky-ime.lua` 关掉 `fadePopups`。代价是右键菜单等弹出层也不再淡入，直接出现。

## 微信里候选条连续打字时闪烁

关掉淡入淡出后重影没了，但连续打字时候选条仍会一闪一闪，不如其他应用跟手。

原因：微信 4.1.13（Qt 6.6）自带的 fcitx5-qt 比较旧，它的 `updatePosition()` 没有走 `xdg_popup.reposition`，
只要锚点变了就 `hide()` 再 `show()`，候选条被销毁重建，中间会空一帧。锚点就是输入光标；拼音直接显示在
输入框里（预编辑，preedit）时，每敲一个字母光标都右移一格，于是候选条每次按键都重建。
上游新版 fcitx5-qt 已经改用 reposition，但微信是静态链接的，换不了。

修复：Silky 自带一个很小的 fcitx5 插件 [`plugins/silky-wechat-preedit`](../plugins/silky-wechat-preedit/silky-wechat-preedit.cpp)，
只对微信的 D-Bus 输入上下文（`program:wechat frontend:dbus`）关闭预编辑。拼音改为显示在候选条第一行，
光标在组词期间不动，候选条只是原地重绘、改变宽度，不再重建。其他应用和微信的 `wayland_v2` 上下文不受影响。
代价：在微信里打字时输入框内看不到拼音，拼音在候选条上方。

- 安装：`./scripts/install-wowtype-glass.sh` 会用 `make` 针对本机 fcitx5 头文件（`Fcitx5Core`，Arch 的 `fcitx5` 包自带）编译，
  装到 `~/.local/lib/silky-omarchy/libsilkywechatpreedit.so`，并写入 `~/.local/share/fcitx5/addon/silky-wechat-preedit.conf`
  （`Library=` 用绝对路径，不往 `/usr/lib` 写东西），然后通过 D-Bus 重启 fcitx5。缺少 `make`、`pkg-config` 或头文件时跳过，并打印原因。
  微信不用重启，下一次聚焦输入框时会自动重连 fcitx5。
- 在 fcitx5 5.1.23 上实机构建并加载。fcitx5 大版本更新后重新运行安装脚本。
- 新建输入上下文和每次获得焦点时都会再关一次预编辑，因为 fcitx5 重载全局配置时会把所有上下文恢复为默认值。
  在微信里按 `Ctrl+Alt+P`（fcitx5 的“切换预编辑”）可以临时恢复内嵌拼音，切走再回来会再次关闭。

之前试过的 `QT_IM_MODULE=wayland` / `ibus` 两种接口在这个微信版本里都只能打英文，不要再用；
`Super+I` 依赖现在的 fcitx（D-Bus）接口。

## Silky Glass 皮肤

`wowtype-glass/build-themes.py` 生成两套 fcitx5 主题到 `~/.local/share/fcitx5/themes/`：

| 主题 | 底色 | 选中 |
| --- | --- | --- |
| `silky-glass-dark` | 40% 不透明深灰 + 细亮边 | macOS 蓝 `#0A84FF` 圆角胶囊 |
| `silky-glass-light` | 50% 不透明近白 + 细暗边 | macOS 蓝 `#007AFF` 圆角胶囊 |

- 高亮贴边：外框和高亮之间不留间距（`PAD = 0`），外框圆角等于高亮圆角（都是 8px，`R = HR + PAD`）。选中第一个候选时，蓝色高亮正好盖住外框左端的圆角，两者是同一条弧线。
- 高亮的边距必须等于文字边距：fcitx5 的 `[InputPanel/Highlight/Margin]` 有两个作用，一是高亮从文字向外扩出的距离，二是 `highlight.png` 的九宫格边框。它比 `[InputPanel/TextMargin]` 大时，高亮会溢出候选框被裁掉，圆角就变成了方角（试过高亮边距 11、文字上下边距 6，就是这样）。现在两者都是左右 11、上下 8，圆角半径不超过上下边距（`HR <= TM_Y`）。系统自带的 default 和 wowtype 主题也是两者相等。
- 玻璃感：底色不透明度原来是 74%（深色），模糊几乎透不出来，背后是深色时看上去就是一块灰板。现在深色 40%、浅色 50%，比 Omarchy 菜单玻璃（55% / 68%）更透一些：候选条很小，透得多才看得出玻璃。圆角和半透明画在 PNG 九宫格里：微信内置的 fcitx5-qt 只认图片、纯色和边距，不认模糊、深色主题、强调色等键。
- 磨砂由 Hyprland 提供：`decoration.blur.input_methods`（fcitx5 自己的候选框）和 `decoration.blur.popups`（微信的候选条），
  `ignorealpha = 0.1` 让透明圆角外侧不被模糊。
- 想改颜色、圆角：改 `build-themes.py` 顶部的 `R`、`HR` 和 `SKINS`，重新运行安装脚本。
- 比例：fcitx5 默认字体 `Sans 10` 配原来 7+5 px 的上下边距，候选条显得又高字又小。现在字体是 `Inter 12`（和 Omarchy 菜单同款，中文自动回退；没装 Inter 就用 `Sans 12`），高亮贴边、文字上下边距 8，整条更紧凑、字更大。字体由 `silky-ime-theme` 写进 `classicui.conf` 的 `Font=`，只在你没自己设置 `Font=` 时才写；想换字号直接改那一行即可，之后不会被覆盖。

## 深色 / 浅色自动切换

`silky-ime-theme.service` 运行 `silky-ime-theme --watch`，监听 `org.gnome.desktop.interface color-scheme`
（Omarchy 切主题、macOS Tahoe 深浅色都会改它），把 `classicui.conf` 的 `Theme=` 改成对应皮肤并让 fcitx5 重载 classicui。

没有用 fcitx5 自带的“跟随系统深色”（`UseDarkTheme`）：微信那份 fcitx5-qt 不支持，只读 `Theme=`。统一改 `Theme=`，
微信和其他应用始终是同一套皮肤。文件是原地改写的（不换 inode），微信内的客户端能察觉到变化；若某次没跟上，重启微信即可。

## WPS 的候选栏、迷你工具栏与字体

- WPS 随包提供自己的 Qt Fcitx 插件。编辑器进程缺少 `QT_IM_MODULE=fcitx` 时，Omarchy 可以切换到 WowType，但 WPS 正文接不到候选词。`wps-dark-border` 为调用它的 WPS 启动项指定 XWayland 和 Fcitx。从仓库根目录运行 `./scripts/install-wowtype-glass.sh` 更新启动器，然后保存文档、退出 WPS，再从应用程序面板或文件管理器重新打开。在正文中按 `Super+I`，输入 `ninhao` 并选「你好」。本机已验证 WPS 从桌面入口打开后加载自带的 Fcitx 插件，并在隔离的 X11 测试窗口中确认 WowType 候选词可以上屏。需要回滚时恢复 `~/.local/bin/wps-dark-border.bak.*` 并重开 WPS。[Fcitx Wayland 文档](https://fcitx-im.org/wiki/Using_Fcitx_5_on_Wayland)
- MacShell Dock 将 WPS 文字、表格、演示、PDF 和整合窗口归到红色 WPS Office 图标。拖选文字时出现的迷你工具栏不占 Dock 位置。已有的 WPS 固定项也会合并。运行 `./scripts/install-macshell-optimizations.sh`，或单独执行 `python3 scripts/tune-wps-dock.py ~/.config/quickshell/MacShell/MacDock.qml --backup`，再运行 `qs -c MacShell ipc call macshell reload`。在 WPS 正文里拖选文字并打开右键菜单，检查 Dock 里只有一个 WPS 图标，点击它仍能切回文档。回滚时用脚本输出的备份恢复 `MacDock.qml` 后重载 MacShell。
- WPS 走 XWayland。Fcitx5 的 X11 候选栏从 Xresources 读取 `Xft.dpi`。有 `xprop`（Arch 的 `xorg-xprop`）时，安装脚本和 Hyprland 启动时会用内置屏幕的缩放补上这个值，无内置屏幕时使用第一个输出。例如 2× 对应 192 DPI。已经配置的 DPI 会优先使用。其他读取 Xresources 的 X11 应用也可能使用这个值。[Fcitx 的 DPI 说明](https://fcitx-im.org/wiki/Theme_Customization#Classic_User_interface)
- Omarchy 的浮动工作区会给新窗口套用默认尺寸和层叠位置，导致 WPS 的浮动迷你工具栏、右键菜单等弹出面板被强行拉大并在周围出现大片白边。Hyprland 规则通过 `o.window(..., { float = true })` 将 `Fcitx5 Input Window` 和 WPS 各组件（文字 `wps`、表格 `et`、演示 `wpp`、PDF `wpspdf` 及整合外壳 `wpsoffice`，`initial_class` 与 `title` 均匹配 `^(wps|et|wpp|wpspdf|wpsoffice)$`）的弹出面板登记为自行浮动（规则名 `silky-wps-popups`）。这些弹窗现在按应用给出的紧凑尺寸和位置显示，不再出现多余白边；候选栏禁用 Hyprland 模糊和窗口动画以避免首帧出现大片背景，WPS 弹出面板同时关闭了 Hyprland 阴影。
- 拖动 WPS 文字的右侧滚动条时，页码提示使用独立的 XWayland 窗口标题 `KToolTipWidget`。旧规则只匹配组件名称，浮动工作区会在提示出现时套用默认尺寸。[窗口规则](../config/hypr/silky-ime.lua) 现在也匹配这个标题，提示沿用 WPS 给出的尺寸和位置。运行 `./scripts/install-wowtype-glass.sh`，或备份并同步 `~/.config/hypr/silky-ime.lua` 后执行 `hyprctl reload`，无需重启 WPS。用多页文档拖动滚动滑块，页码提示应紧贴滑块。实机在 Hyprland 0.57.2、WPS 12.1.2.29183 的整合模式下测到提示从 942 × 626 恢复到约 82 × 37 个逻辑像素。回滚时从标题匹配中移除 `|KToolTipWidget`，再重载 Hyprland。
- WPS 的「查找和替换」对话框是非模态窗口，浮动工作区原先把它当作新应用窗口，拉成默认的 942 × 626 逻辑像素，查找框下方空出大片空白。[窗口规则](../config/hypr/silky-ime.lua) `silky-wps-find-dialog` 以 `initial_class` 加标题 `^(查找和替换|Find and Replace)$` 将它登记为自行浮动，只把这个标题加进浮动工作区的排除列表，WPS 文档窗口仍使用浮动工作区的默认尺寸。运行 `./scripts/install-wowtype-glass.sh`，或备份并同步 `~/.config/hypr/silky-ime.lua` 后执行 `hyprctl reload`，下次按 `Ctrl+F` 即生效，无需重启 WPS。实机在 Hyprland 0.57.2、WPS 12.1.2.29183 整合模式、1472 × 920 逻辑像素屏幕上测得对话框从 942 × 626 回到 WPS 自带的 548 × 308，窗口不再带 `omarchy-mode-opened` 标签。可用 `hyprctl clients -j` 查看标题为 `查找和替换` 的窗口尺寸。其他语言界面的对话框标题需要另行加入匹配。回滚时删除 `silky-wps-find-dialog` 规则或恢复 `~/.config/hypr/silky-ime.lua.bak.*`，再执行 `hyprctl reload`。
- 「查找和替换」对话框没有标题栏，WPS 也不处理拖动它顶部的操作；WPS 属于自绘外框应用，Hyprland 不给它加标题栏，原先只能按住 `Super` 拖动。[`config/hypr/silky-ime.lua`](../config/hypr/silky-ime.lua) 把「查找 / 替换 / 定位」标签右侧的顶部空白（距对话框左缘 200 逻辑像素以后、顶部 40 逻辑像素以内）当作标题栏：不按修饰键在这里按下左键、移动超过 3 逻辑像素后，对话框跟随指针移动，松开即停。按键绑定为 `non_consuming`，WPS 仍收到每次点击，标签和下方控件照常响应；`Super` + 拖动仍走 Hyprland 原生移动。移动由 8 ms 的 Lua 定时器以绝对坐标 `hl.dsp.window.move` 完成，只在拖动期间运行。部署方式同上，`hyprctl reload` 后立即生效。已实机确认对话框接受绝对坐标移动并在新位置正确重绘、`hyprctl binds -j` 中两组 `mouse:272` 非消费绑定与 Folio 的拖动绑定共存；本机无法注入鼠标按键，真实鼠标拖动和触控板拖动待实机确认。回滚时删除 `silky-wps-find-dialog` 规则下方的拖动代码块（`WPS_FIND_*` 常量、定时器与两条 `mouse:272` 绑定），再执行 `hyprctl reload`。
- **修复 WPS 划选文字后再次框选把前一段文字带过去的问题**：在浮动工作区的点击聚焦（`input:follow_mouse = 0`）下，划选文字松手后弹出的迷你工具栏如果抢走焦点，用户直接去文档别处重新滑选其他文字时，WPS 的选区/鼠标状态会错乱，把上一段划选的文字带过去而不是重新框选。[`config/hypr/silky-ime.lua`](../config/hypr/silky-ime.lua) 给 `silky-wps-popups` 加上 `no_initial_focus = true`，弹出迷你工具栏时焦点继续留在主文档窗口（仍可直接点击工具栏上的按钮）。运行 `./scripts/install-wowtype-glass.sh`（或手动同步 `~/.config/hypr/silky-ime.lua` 后执行 `hyprctl reload`）立即生效，无需重启 WPS；实机已验证在 WPS 文字中连续划选多段文字可正常重新框选。回滚只需去掉 `silky-wps-popups` 中的 `no_initial_focus = true`（或恢复 `~/.config/hypr/silky-ime.lua.bak.*`）并执行 `hyprctl reload`。
- **去掉 WPS 浮动窗口外圈黑边**：WPS 整合模式的主窗口 `KPromeMainWindow`（`wps-office-cn 12.1.2.29183-1`）在非最大化时会通过 `_updateMargins()` / `onSkinChanged()` 给主布局强行加上四周外边距（普通 2 px、触屏设备 5 px，再乘 DPI 缩放，在 2× 屏上表现为一圈约 10 物理像素的粗黑边）。[`plugins/silky-wps-noborder/`](../plugins/silky-wps-noborder/silky-wps-noborder.cpp) 构建一个很小的 `LD_PRELOAD` 拦截库（`~/.local/lib/silky-omarchy/libsilkywpsnoborder.so`），仅在 `QLayout::setContentsMargins` 作用于 `KPromeMainWindow` 及其 `centralWidget()` 根布局时把边距归零，其他控件不受影响。[`wps-dark-border`](../plugins/silky-wps-noborder/wps-dark-border)（安装到 `~/.local/bin/wps-dark-border`，由用户目录 `~/.local/share/applications/wps-office-*.desktop` 调用）通过 `bwrap --ro-bind-data` 在运行时为 `/usr/bin/{wps,et,wpp,wpspdf}` 追加该 `LD_PRELOAD`（同时保留 `/usr/lib/libfreetype.so` 和暗色皮肤兜底），不修改任何系统包文件。完全退出并重新打开 WPS 后生效；回滚只需删除 `~/.local/lib/silky-omarchy/libsilkywpsnoborder.so` 并恢复 `~/.local/bin/wps-dark-border.bak.*`。
- 在 WPS 正文里点出光标，用 `Super+I` 切到 WowType，在同一页不同高度输入拼音，候选词应靠近光标；在 WPS 文字、表格、演示中拖选内容或右键打开菜单与迷你工具栏，弹出框应紧贴内容、无大片白边；完全退出并重新打开 WPS 浮动窗口，左右和底部不再出现外圈粗黑边（WPS 实机界面效果待重启 WPS 后确认）。可用 `xprop -root RESOURCE_MANAGER` 检查 DPI。

如果 WPS 报缺字体，可从自己的 Windows `Windows/Fonts` 将 Linux 能识别的字体复制到 `~/.local/share/fonts/Windows/`，运行 `fc-cache -f`，保存文档后完全退出并重新打开 WPS。用 `fc-match -f '%{family} %{file}\n' '宋体'` 检查实际匹配的字体，核对返回的家族名称和文件。

新版 Windows 的 `simfang.ttf` 家族名是「仿宋」，旧文档可能明确要求 `仿宋_GB2312`。遇到这种情况，安装内嵌家族名为 `FangSong_GB2312,仿宋_GB2312` 的字体文件，然后用 `fc-match -f '%{family} %{file}\n' '仿宋_GB2312'` 再确认，不必在 WPS 里对文档点「永久转换」。[安阳学院字体下载页](https://www.ayxy.edu.cn/xxh/contents/127/2224.html)

## MacShell 下 `Super+I` 切换输入法失效

Omarchy `4.0.0.r8205` 起，默认的 `Super+I` / `Super+Shift+I` 绑定调用 `omarchy-input-method cycle [back]`，而它内部通过 `omarchy-shell shell cycleInput` 转发给 Omarchy 自带外壳里的 `indicator.py`。当系统用 MacShell 替代 `omarchy-shell` 后，该 IPC 返回 `omarchy-shell is not running`，导致在任何停留在 `keyboard-us` 输入上下文的窗口（例如 ChatGPT 桌面端）里按 `Super+I` 都无法切到 WowType，且每次更新 `omarchy-dev` 都会保留这套依赖 `omarchy-shell` 的默认绑定。

修复：[`wowtype-glass/silky-input-cycle`](../wowtype-glass/silky-input-cycle)（安装到 `~/.local/bin/silky-input-cycle`）直接通过 `busctl` 调用 `org.fcitx.Fcitx5` 的 `Controller1` 接口（`CurrentInputMethodGroup`、`InputMethodGroupInfo`、`CurrentInputMethod`、`SetCurrentIM`）按组内顺序正反向轮换输入法，多键盘布局下与 Omarchy 原版一致先轮换 `hyprctl switchxkblayout`，Fcitx5 未运行时退回仅切换键盘布局。[`config/hypr/silky-ime.lua`](../config/hypr/silky-ime.lua) 在 `default.hypr.omarchy` 之后加载，先 `hl.unbind` 掉默认绑定，再把 `SUPER + I` / `SUPER + SHIFT + I` 绑定到 `~/.local/bin/silky-input-cycle`（及 `back`），不修改 `/usr/share/omarchy/` 下的软件包文件，系统更新后仍继续生效。

- 安装与生效：从仓库根目录运行 `./scripts/install-wowtype-glass.sh`（会自动安装脚本、更新 `~/.config/hypr/silky-ime.lua` 并执行 `hyprctl reload`），无需重启应用或重新登录。
- 验证：本机已验证 `hyprctl reload` 与 `hyprctl configerrors` 无报错，`hyprctl binds -j` 中 `SUPER + I` / `SUPER + SHIFT + I` 各保留一条绑定，直接执行 `~/.local/bin/silky-input-cycle` 与 `~/.local/bin/silky-input-cycle back` 可在 `wowtype` 与 `keyboard-us` 之间切换（`fcitx5-remote -n` 实时变化）；在 ChatGPT 等窗口内按实体键盘 `Super+I` 切换待用户实机确认。
- 回滚：删掉 `~/.local/bin/silky-input-cycle`，从 `~/.config/hypr/silky-ime.lua` 移除 `SUPER + I` / `SUPER + SHIFT + I` 覆盖段并运行 `hyprctl reload`。

## 验证

```bash
systemctl --user is-active silky-ime-theme
grep '^Theme=' ~/.config/fcitx5/conf/classicui.conf
hyprctl animations | grep -A3 'name: fadePopups$'   # enabled: 0
grep -c libsilkywechatpreedit /proc/$(pgrep -x fcitx5)/maps   # 大于 0
```

然后在微信输入框打 `nihao`，连续敲键时候选条应只有一层、边缘清晰。拼音应显示在候选条第一行，
候选条位置固定、不再闪烁。切换深浅色后，候选框跟着变。上面的命令检查已在本机执行。插件加载后的微信打字效果还需在实机上确认。

## 回滚

```bash
systemctl --user disable --now silky-ime-theme
mv ~/.config/fcitx5/conf/classicui.conf.silky-backup ~/.config/fcitx5/conf/classicui.conf
```

再从 `~/.config/hypr/hyprland.lua` 删掉 `require("hypr.silky-ime")`，执行 `hyprctl reload`。

只想恢复微信里的内嵌拼音时，删掉插件并重启 fcitx5：

```bash
rm ~/.local/share/fcitx5/addon/silky-wechat-preedit.conf ~/.local/lib/silky-omarchy/libsilkywechatpreedit.so
fcitx5 -rd
```
