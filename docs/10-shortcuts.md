# 10 · 快捷键：MacShell 优先，Super+K 换成可搜索的 macOS 面板

简体中文 | [English](en/10-shortcuts.md)

## 目标

1. MacShell 和 Omarchy 抢同一个键时，只保留 MacShell 的功能；Omarchy 原来的动作挪到没人用的键上，不丢功能。
2. Super+K 不再弹 Omarchy 的等宽文字菜单，而是一块 MacShell macOS 27 风格的毛玻璃面板：分组、键帽（⌘ ⌥ ⌃ ⇧）、即时搜索，回车直接执行选中的快捷键。

## 冲突是怎么来的

Hyprland 允许一个键上挂多个绑定，**按一下会全部执行**。MacShell 的 `macshell.lua` 直接 `hl.bind`，没有先解绑 Omarchy 的同名键，结果：

| 键 | 按一下同时发生的事 |
| --- | --- |
| Super+Space | MacShell 聚焦搜索 + Omarchy 菜单 |
| Super+V | MacShell 剪贴板历史 + Omarchy “通用粘贴”（往当前窗口发 Ctrl+V） |
| Alt+Tab | MacShell 应用切换器 + Omarchy “聚焦下一个窗口”“置顶” |
| Super+L | MacLock 锁屏 + Omarchy “循环切换工作区布局” |

另外 Alt+Shift+Tab 在 Omarchy 里是“聚焦上一个窗口”，MacShell 有反向切换（`switcher prev`）但没绑键，这里一并按 macOS 习惯给了 MacShell。

查法：`hyprctl binds` 按 `modmask + key` 分组，找出现不止一次的键（Lua 绑定的 `arg` 只显示编号，要看说明靠下面的 registry）。

## 改动后的键位

MacShell（保留，并补上中文说明，Super+K 面板里能看到）：

| 键 | 功能 |
| --- | --- |
| Super+Space | 聚焦搜索 |
| Super+V | 剪贴板历史 |
| Super+. | 表情与符号 |
| Super+Z | 系统设置 |
| Alt+Tab / Alt+Shift+Tab | 切换应用 / 反向切换 |
| Ctrl+Alt+W | 墙纸 |
| Super+L | 锁屏（MacLock） |

Omarchy 被挪走的动作：

| 动作 | 原来 | 现在 |
| --- | --- | --- |
| Omarchy 菜单 | Super+Space | **Super+Ctrl+M** |
| 通用粘贴（终端里是 Ctrl+Shift+V） | Super+V | **Super+Alt+V** |
| 循环切换工作区布局 | Super+L | **Super+Shift+L**（反向仍是 Super+Alt+L） |
| 聚焦下一个窗口并置顶 | Alt+Tab | **Alt+`**（1 左边那个键） |
| 聚焦上一个窗口 | Alt+Shift+Tab | **Alt+Shift+`** |

新键位都先确认过在当前配置里没被占用。Super+C / Super+X（通用复制 / 剪切）不冲突，保持不变。

### Super+T

在同一工作区，分别对两个窗口按 `Super+T` 可将它们切为平铺。聚焦已全屏或最大化的平铺窗口时，按一次会让它回到分屏布局。应用自身的全屏状态可以保留在平铺区域内。MacShell「显示」和「窗口」菜单的浮动／平铺操作使用同一动作。

Hyprland 切回浮动时会还原窗口的浮动尺寸和位置，微信曾因此伸进菜单栏。如果还原位置离菜单栏太近，快捷键会把窗口放到当前屏幕顶部保留区下方 4 个逻辑像素，高度超过剩余空间时也会缩短。在微信主窗口按 `Super+T` 切入浮动，确认窗口上沿位于菜单栏下方，再按一次确认可切回平铺。

如果工作区处于浮动布局，先用 `Super+Shift+L` 切到「平铺」，这样新窗口也会自动加入分屏。平铺布局下按 `Super+J` 切换左右或上下分割。

需要单窗口平铺时，用 `Super+Alt+T`。Silky 会把其他窗口移到同一显示器的下一个工作区，最后一个工作区则回到第一个。在原工作区聚焦同一个窗口，再按 `Super+Alt+T` 切回浮动并移回本次挪走且仍在目标工作区的窗口。

已关闭、手动移到其他工作区、后来被置顶或与无关窗口重新分组的窗口会跳过。移窗记录从切入平铺时开始，Hyprland 重载配置或重启后会清除。

### 微信图片查看器始终浮动

微信主窗口浮动时，点开图片或视频弹出的「图片和视频」窗口仍会在平铺工作区里和其他窗口分屏。[`config/hypr/silky-app-windows.lua`](../config/hypr/silky-app-windows.lua) 按 `class` `wechat`、标题 `图片和视频` 匹配这个窗口，打开时就浮动并居中，大小由微信自己决定。它通过 `o.window` 注册为自带浮动的应用，浮动工作区布局也不会再改它的尺寸。微信关闭查看器后并不销毁窗口，下一张图片复用同一个窗口（地址不变，也不发 `openwindow` 事件），所以打开时的规则只对规则加载之后新建的查看器生效；同一文件里还挂了 `config.reloaded`，每次 `hyprctl reload` 时把仍在平铺的查看器切为浮动并居中。打开后仍可用 `Super+T` 临时平铺。

标题来自微信 4.1.13 中文界面（Wayland 原生窗口，非 XWayland）。界面语言切成英文或以后版本改了标题时，规则不会命中，用下面的命令查新标题后改正则。

## 原理

| 文件 | 作用 |
| --- | --- |
| `config/hypr/silky-keys-registry.lua` | 在 `hyprland.lua` **最前面**加载。包一层 `hl.bind` / `hl.unbind`，记下每个绑定的键、说明、来源文件和 dispatcher；提供 `silky_keys.dump(path)` 和 `silky_keys.run(n)` |
| `config/hypr/silky-shortcuts.lua` | 在 `hyprland.lua` **最后**加载（在 `hypr.macshell` 之后）。先 `hl.unbind` 冲突键，再只绑 MacShell 的功能，把 Omarchy 的动作绑到新键 |
| `config/hypr/silky-keys.lua` | 登录时启动面板；`o.rebind("SUPER + K", …)`；给 `silky-keys` 图层加背景模糊 |
| `keys-panel/shell.qml` → `~/.config/quickshell/SilkyKeys/` | 面板本体（常驻 Quickshell，IPC 目标 `keys`） |
| `config/hypr/silky-app-windows.lua` | 按应用的窗口规则：微信「图片和视频」窗口始终浮动、居中 |

为什么要 registry：

- Omarchy 原来的 Super+K 菜单靠 `hyprctl binds` 加一份 Lua 扫描缓存来知道每个键做什么。在 Hyprland 0.57 上这份缓存失效了：`arg` 只剩编号，dispatcher 是 `HL.Dispatcher(exec_cmd)`、`function: 0x…`，选中后其实执行不了。
- Hyprland 的 Lua API 没有列出绑定的函数（`hl.get_binds` 不存在），而 `wtype` 这类虚拟键盘发出的按键**不会**触发 Hyprland 绑定，没法模拟按键。
- `hyprctl dispatch 'function() … end'` 运行在和配置同一个 Lua 环境里，所以只要加载配置时把 dispatcher 存起来，面板就能用 `hyprctl dispatch 'function() silky_keys.run(42) end'` 原样执行。同一个键上的多个绑定会一起执行，和真的按下去一样。
- 说明文字用 Omarchy 自己的翻译表（`/usr/share/omarchy/default/i18n/<语言>/keybindings.json`），带数字的说明（“切换到工作区 3”）按 `%1` 模式匹配。

面板：

- 打开时调用一次 `silky_keys.dump` 拿到当前所有绑定，所以改了配置后 `hyprctl reload` 即可，面板不用重启。
- 外观跟随 MacShell 设置（`~/.config/macbar/settings.json` 的 `darkMode`、`accent`、`fontFamily`），改了即时生效；字体为 Open Runde 时直接加载 MacShell 自带的字体文件。
- 圆角 28 的玻璃板：Hyprland 背景模糊 + 半透明底色 + 顶部高光 + 内外两圈细边；搜索框为胶囊形；选中行是强调色圆角条，键帽变成半透明白。打开 220 ms 淡入并轻微回弹，关闭 150 ms。
- 分组：MacShell、常用、应用、窗口、工作区、截屏与录制、系统与工具、媒体与硬件、输入、我的快捷键（按绑定来源文件和说明划分）。
- 搜索：多个词任意顺序、全部命中才显示；匹配中文说明、英文原文、键名（`super k`、`ctrl shift`、`⌘K`、`win`/`cmd`/`option` 别名）和组名。结果保持分组顺序。
- 键盘：↑↓ / Ctrl+N / Ctrl+P / Tab 选择，PgUp/PgDn 跳 10 行，↩ 执行，Esc 先清空搜索再关闭；点面板外关闭。鼠标只有真的移动时才改变选中行，列表在静止的指针下滚动时不会抢走键盘选中项。
- 执行时先关面板，140 ms 后焦点回到原窗口再执行，所以“通用复制”这类发给当前窗口的快捷键也能正常工作。鼠标拖拽类绑定（Super+左键移动窗口等）只展示、不执行。

## 安装

```bash
./scripts/install-shortcuts.sh
```

脚本会备份 `hyprland.lua`，把 registry 插到 Omarchy bootstrap 那一行后面，把 `silky-shortcuts` / `silky-keys` 移到文件最后，没有 `silky-app-windows` 时补上它的 `require`，然后 `hyprctl reload` 并重启面板。

## 验证

```bash
./scripts/silky-doctor.sh                                  # “no shortcut shared between MacShell and Omarchy”、“Super+K shortcut panel is running”
qs -c SilkyKeys ipc call keys search 截图                   # 带着搜索词打开面板
hyprctl dispatch 'function() silky_keys.dump("/tmp/k.json") end' && jq length /tmp/k.json
```

微信图片查看器：在微信里点开一张图片，然后执行

```bash
hyprctl clients -j | jq -c '.[] | select(.class=="wechat") | {title, floating}'
```

「图片和视频」一行应为 `"floating":true`，窗口居中显示。2026-11-18 在本机实机确认：`hyprctl configerrors` 为空，`hyprctl reload` 后已打开的查看器变为浮动并居中。重启微信后新建查看器由打开时的规则浮动，这一步待验证。

doctor 的冲突检查：从 registry 导出所有绑定，按“修饰键+键”分组，只要某个键既有 MacShell/MacLock 的说明又有别的说明就报错。Omarchy 或 MacShell 升级后新增了冲突，就会在这里看到，到 `silky-shortcuts.lua` 里照样挪走即可。

## 踩过的坑

- `silky-shortcuts.lua` 必须在 `hypr.macshell` **之后**加载：它里面的 `hl.unbind` 会把这个键上的所有绑定（包括 MacShell 的）都清掉，然后重新只绑 MacShell 的。放在前面的话，MacShell 会再加回一个重复绑定。
- registry 必须在 Omarchy 默认配置**之前**加载，否则记不到 Omarchy 的绑定。`hyprctl reload` 时 `hl` 表还在，所以原始的 `hl.bind` 存在 `_G.silky_keys_real` 里，避免一层层套娃。
- 不要用 `pkill -f 'qs -c SilkyKeys'`：执行它的 shell 自己的命令行里也有这串字，会把自己杀掉。安装脚本用的是 `pkill -x -f 'qs -c SilkyKeys( -d)?'`。

## 回滚

只回滚浮动窗口的位置修复时，从 `~/.config/hypr/silky-shortcuts.lua.bak.*` 恢复安装前的版本，再执行 `hyprctl reload`。安装脚本会在替换内容有变动的快捷键 Lua 文件时创建备份。

```bash
rm ~/.config/hypr/silky-keys-registry.lua ~/.config/hypr/silky-shortcuts.lua ~/.config/hypr/silky-keys.lua
# 删掉 hyprland.lua 里 require("hypr.silky-keys-registry")、require("hypr.silky-shortcuts")、require("hypr.silky-keys") 三行
pkill -x -f 'qs -c SilkyKeys( -d)?'; rm -r ~/.config/quickshell/SilkyKeys
hyprctl reload
```

只撤销微信图片查看器浮动：删除 `~/.config/hypr/silky-app-windows.lua` 和 `hyprland.lua` 里的 `require("hypr.silky-app-windows")`，执行 `hyprctl reload`。已经浮动的查看器会保持浮动，按 `Super+T` 或重启微信即恢复平铺。

Super+K 回到 Omarchy 自带的菜单，冲突键恢复成同时触发两边。
