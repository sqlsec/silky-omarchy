# 09 · WowType 候选框：圆角毛玻璃与微信重影修复

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
| `silky-glass-dark` | 74% 不透明深灰 + 细亮边 | macOS 蓝 `#0A84FF` 圆角胶囊 |
| `silky-glass-light` | 84% 不透明近白 + 细暗边 | macOS 蓝 `#007AFF` 圆角胶囊 |

- 圆角（12px）和半透明画在 PNG 九宫格里：微信内置的 fcitx5-qt 只认图片、纯色和边距，不认模糊、深色主题、强调色等键。
- 磨砂由 Hyprland 提供：`decoration.blur.input_methods`（fcitx5 自己的候选框）和 `decoration.blur.popups`（微信的候选条），
  `ignorealpha = 0.1` 让透明圆角外侧不被模糊。
- 想改颜色、圆角：改 `build-themes.py` 顶部的 `R`、`HR` 和 `SKINS`，重新运行安装脚本。

## 深色 / 浅色自动切换

`silky-ime-theme.service` 运行 `silky-ime-theme --watch`，监听 `org.gnome.desktop.interface color-scheme`
（Omarchy 切主题、macOS Tahoe 深浅色都会改它），把 `classicui.conf` 的 `Theme=` 改成对应皮肤并让 fcitx5 重载 classicui。

没有用 fcitx5 自带的“跟随系统深色”（`UseDarkTheme`）：微信那份 fcitx5-qt 不支持，只读 `Theme=`。统一改 `Theme=`，
微信和其他应用始终是同一套皮肤。文件是原地改写的（不换 inode），微信内的客户端能察觉到变化；若某次没跟上，重启微信即可。

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
