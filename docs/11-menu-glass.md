# 11 · Omarchy 自带菜单：macOS 27 玻璃质感，跟随日间 / 暗色

简体中文 | [English](en/11-menu-glass.md)

## 目标

Omarchy 自己的菜单（Super+Esc 系统菜单、Super+Ctrl+M Omarchy 菜单，以及继承同一套样式的剪贴板、表情面板）原来是不透明的深色卡片，背后整屏压暗，字体是终端等宽字体。改成和 MacShell 一样的样式：

- 半透明玻璃卡片，背后的窗口和壁纸被 Hyprland 模糊
- 背后不再压暗整屏
- 选中行用 MacShell 的强调色填满，白字（和 macOS 菜单一样）
- 细边框：暗色下是白色细线，浅色下是很淡的深色细线
- 比例字体 Inter（接近 SF Pro），中文自动回退
- 暗色是烟灰玻璃，浅色是磨砂白玻璃，切换外观时菜单实时跟着变，开着的菜单也会立即变

## 原理

Omarchy shell 的界面颜色来自 `shell.toml`：主题自带的一份，加上用户级的 `~/.config/omarchy/shell.toml`。用户级里的键**优先**于主题，而且是实时监听的（`omarchy display text size` 也是写这个文件），所以不用改 `/usr/share/omarchy` 下的任何文件，也不受切换主题影响。

| 文件 | 作用 |
| --- | --- |
| `bin/silky-menu-glass` → `~/.local/bin/` | 读 `org.gnome.desktop.interface color-scheme` 和 MacShell 的强调色，把 `[menu]`、`[launcher]` 两段写进 `~/.config/omarchy/shell.toml` 里一段带标记的区块（文件其他内容保留）。`--watch` 持续跟随，`--remove` 删掉区块 |
| `config/systemd/silky-menu-glass.service` | 用户服务，运行 `silky-menu-glass --watch` |
| `config/hypr/silky-menu-glass.lua` | 给 `omarchy-menu`、`omarchy-clipboard`、`omarchy-emojis` 三个图层加背景模糊；设置 `OMARCHY_MENU_FONT=Inter` |

为什么跟随 `color-scheme`：MacShell 切换外观（设置 → 外观，包括“自动”）时会写它，`omarchy theme set macos-tahoe-light/dark` 也会写它。WowType 候选框（09）用的也是同一个信号，所以菜单、候选框、MacShell 三者始终一致。

用到的 `shell.toml` 键（`[menu]`，`[launcher]` 相同）：

| 键 | 暗色 | 浅色 |
| --- | --- | --- |
| `background` / `background-alpha` | `#1c1c1e` / 0.55 | `#f7f7f9` / 0.68 |
| `text` | `#f5f5f7` | `#1d1d1f` |
| `border` / `border-alpha` / `border-width` | `#ffffff` / 0.14 / 1 | `#000000` / 0.09 / 1 |
| `scrim-alpha` | 0（不压暗） | 0 |
| `selected-background` / `selected-text` | MacShell 强调色 / 白 | 同左 |

圆角跟随 Hyprland 的 `decoration:rounding`（现在是 14），这里不单独改。

## 安装

```bash
./scripts/install-menu-glass.sh
```

会安装上面三个文件、启用服务、`hyprctl reload`，再执行一次 `omarchy-restart-shell`（菜单字体只在 Omarchy shell 启动时读取）。

## 验证

```bash
./scripts/silky-doctor.sh            # “Omarchy menus follow light / dark as glass”、“menu glass matches the current appearance”
omarchy-menu toggle system           # Super+Esc 同款
gsettings set org.gnome.desktop.interface color-scheme prefer-light   # 菜单立即变成浅色玻璃；再设回 prefer-dark
```

## 踩过的坑

- `omarchy-launch-shell` 用 `QS_DISABLE_FILE_WATCHER=1` 启动 shell，但用户级 `shell.toml` 的监听实测仍然有效，切换外观能实时生效。
- 写文件要原地覆盖，不能先写临时文件再改名：改名会让监听丢失。
- 背后的透明全屏层（用来点外面关闭菜单）的 alpha 是 0，`ignore_alpha = 0.05` 让 Hyprland 只模糊卡片本身，不会把整个屏幕都模糊掉。
- `OMARCHY_MENU_FONT` 必须在 Hyprland 的环境里（`hl.env`）：`omarchy-restart-shell` 通过 Hyprland 启动 shell，从 Hyprland 继承环境。

## 回滚

```bash
systemctl --user disable --now silky-menu-glass
~/.local/bin/silky-menu-glass --remove
rm ~/.config/hypr/silky-menu-glass.lua ~/.config/systemd/user/silky-menu-glass.service ~/.local/bin/silky-menu-glass
# 删掉 hyprland.lua 里的 require("hypr.silky-menu-glass")
hyprctl reload && omarchy-restart-shell
```
