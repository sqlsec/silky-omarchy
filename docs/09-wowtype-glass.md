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

- WPS 走 XWayland。Fcitx5 的 X11 候选栏从 Xresources 读取 `Xft.dpi`。有 `xprop`（Arch 的 `xorg-xprop`）时，安装脚本和 Hyprland 启动时会用内置屏幕的缩放补上这个值，无内置屏幕时使用第一个输出。例如 2× 对应 192 DPI。已经配置的 DPI 会优先使用。其他读取 Xresources 的 X11 应用也可能使用这个值。[Fcitx 的 DPI 说明](https://fcitx-im.org/wiki/Theme_Customization#Classic_User_interface)
- Omarchy 的浮动工作区会给新窗口套用默认尺寸和层叠位置。Hyprland 规则通过 `o.window(..., { float = true })` 将 `Fcitx5 Input Window` 和 WPS 文字的划词迷你工具栏（类名和标题均为 `wps`）登记为自行浮动。这两种弹窗现在按应用给出的尺寸和位置显示。候选栏禁用 Hyprland 模糊和窗口动画，避免首帧出现大片背景。迷你工具栏同时关闭了 Hyprland 阴影。
- 在 WPS 正文里点出光标，用 `Super+I` 切到 WowType。在同一页不同高度输入拼音，候选词应靠近光标；拖选文字时，迷你工具栏应以紧凑尺寸弹出。可用 `xprop -root RESOURCE_MANAGER` 检查 DPI。

如果 WPS 报缺字体，可从自己的 Windows `Windows/Fonts` 将 Linux 能识别的字体复制到 `~/.local/share/fonts/Windows/`，运行 `fc-cache -f`，保存文档后完全退出并重新打开 WPS。用 `fc-match -f '%{family} %{file}\n' '宋体'` 检查实际匹配的字体，核对返回的家族名称和文件。

新版 Windows 的 `simfang.ttf` 家族名是「仿宋」，旧文档可能明确要求 `仿宋_GB2312`。遇到这种情况，安装内嵌家族名为 `FangSong_GB2312,仿宋_GB2312` 的字体文件，然后用 `fc-match -f '%{family} %{file}\n' '仿宋_GB2312'` 再确认，不必在 WPS 里对文档点「永久转换」。[安阳学院字体下载页](https://www.ayxy.edu.cn/xxh/contents/127/2224.html)

## 验证

```bash
systemctl --user is-active silky-ime-theme
grep '^Theme=' ~/.config/fcitx5/conf/classicui.conf
hyprctl animations | grep -A3 'name: fadePopups$'   # enabled: 0
```

然后在微信输入框打 `nihao`，连续敲键时候选条应只有一层、边缘清晰；切换深浅色后候选框跟着变。

## 回滚

```bash
systemctl --user disable --now silky-ime-theme
mv ~/.config/fcitx5/conf/classicui.conf.silky-backup ~/.config/fcitx5/conf/classicui.conf
```

再从 `~/.config/hypr/hyprland.lua` 删掉 `require("hypr.silky-ime")`，执行 `hyprctl reload`。
