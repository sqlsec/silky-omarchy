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

Hyprland 切回浮动时会还原窗口的浮动尺寸和位置，微信和带服务端标题栏的终端（`hyprbars`）曾因此伸进菜单栏。如果还原位置离菜单栏太近，快捷键会计入窗口顶部装饰高度（优先读取 `silky_gestures.window_top_inset`，回退到 `o.silky_titlebar_height`），把窗口放到当前屏幕顶部保留区下方 4 个逻辑像素，高度超过剩余空间时也会缩短。在微信或 Foot 窗口按 `Super+T` 切入浮动，确认窗口外框上沿位于菜单栏下方，再按一次确认可切回平铺。

如果工作区处于浮动布局，先用 `Super+Shift+L` 切到「平铺」，这样新窗口也会自动加入分屏。平铺布局下按 `Super+J` 切换左右或上下分割。

需要单窗口平铺时，用 `Super+Alt+T`。Silky 会把其他窗口移到同一显示器的下一个工作区，最后一个工作区则回到第一个。在原工作区聚焦同一个窗口，再按 `Super+Alt+T` 切回浮动并移回本次挪走且仍在目标工作区的窗口。

已关闭、手动移到其他工作区、后来被置顶或与无关窗口重新分组的窗口会跳过。移窗记录从切入平铺时开始，Hyprland 重载配置或重启后会清除。

### 工作区布局切换：居中液态玻璃 OSD、顶栏图标与进程内直切

原 `Super+Shift+L` 调用外部脚本 `omarchy-hyprland-workspace-layout-toggle`，需要串行启动 `bash`、`hyprctl`、`jq`、`omarchy-i18n` 和 `omarchy-notification-send`，存在明显延迟，且只在右上角发出一条 `omarchy-action` 蓝色铃铛通知（污染通知中心），切换后顶栏也没有常驻状态指示。

- **进程内直切、平衡分屏与浮动快照恢复**：[config/hypr/silky-shortcuts.lua](../config/hypr/silky-shortcuts.lua) 将 `Super+Shift+L` 改为直接执行 Hyprland 进程内的 `o.silky_workspace_layout_cycle`（保留 `floating → dwindle → scrolling` 三态循环，直接调用 `o.workspace_mode` 并原子更新 `~/.local/state/omarchy/workspace-layouts/<id>.lua`），不再启动外部脚本或发送 D-Bus 通知。切入 `dwindle` 平铺且窗口数 ≥ 3 时，自动执行最大面积优先平衡分裂（`balance_dwindle_workspace`），避免原生螺旋二分把第 5–10 个窗口压成邮票大小（实测 10 窗口下最小窗保持 `358 × 190`，最大/最小面积比约 `2:1`），并在重排期间临时开启 `cursor.no_warps` 防止指针跳走。离开 `floating` 模式前会自动记录该工作区所有浮动窗口的坐标、尺寸与堆叠顺序；切回 `floating`（含「全部恢复浮动」）时精准还原原位而不强行抢夺鼠标焦点。绿灯布局菜单（[silky-folio.lua](../config/hypr/silky-folio.lua)）的切换也复用同一入口。
- **右上角液态玻璃 OSD**：[SilkyWorkspaceLayoutOSD.qml](../config/macshell/SilkyWorkspaceLayoutOSD.qml) 监听 Hyprland `silky-ws-layout` 自定义事件，复用与音量／亮度 OSD 完全一致的位置（右上角 `x = width - 256 - 22`、`y = barH + 14`）、尺寸（`256 × 67` 全圆角药丸）与 `SilkyGlassMarker`（`kind: 1`）液态玻璃材质；单色纯白图标与文字随切换做微弹缩放和轻滑淡入，下方配有 3 段丝滑滑动光条，不进通知中心，1.2 秒后淡出。
- **顶栏工作区旁布局图标**：[scripts/install-workspace-layout-ui.py](../scripts/install-workspace-layout-ui.py) 在 MacShell 顶栏工作区数字右侧加入紧凑的布局图标（[SilkyWorkspaceLayoutIcon.qml](../config/macshell/SilkyWorkspaceLayoutIcon.qml)）：处于非默认布局（平铺/滚动）时高亮胶囊提示，左键直接循环切换当前屏幕激活工作区布局，右键弹出液态玻璃菜单可直选三种布局或一键「全部恢复浮动」。
- **安装、验证与回滚**：

```bash
python3 ./scripts/install-workspace-layout-ui.py
python3 ./scripts/install-workspace-layout-ui.py --check
```

2026-11-23 实机验证（Hyprland 0.57.2，双屏 `eDP-1` + `DP-1`）：`o.silky_workspace_layout_set(8, "dwindle", true)` 与切回 `floating` 端到端耗时约 6–8 ms（含 `hyprctl` 调用），`8.lua` 写入与清理正确，MacShell 重载后 `macbar` 与 `macosd` 正常，`hyprctl configerrors` 为空。回滚时从 `~/.config/quickshell/MacShell/{shell,MacBar}.qml.bak.ws-layout.*` 与 `~/.config/hypr/silky-shortcuts.lua.bak.*` 恢复，再重载 Hyprland 与 MacShell。

### 窗口移入后跟随目标工作区布局

跨屏拖放、概览拖放或用快捷键把窗口移到另一常规工作区时，落位后按目标工作区的布局显示。拖入浮动工作区会浮动，拖入平铺或滚动工作区会加入该布局。全屏窗口退出全屏后适配，置顶窗口继续置顶。

Hyprland 0.57.2 会在拖动平铺窗口时临时浮动，松手时再恢复平铺。[快捷键配置](../config/hypr/silky-shortcuts.lua) 通过 [Silky Gestures](../plugins/silky-gestures/main.cpp) 判断拖动是否结束，然后按当前目标布局调整窗口。

从仓库根目录运行 `bash scripts/install-silky-gestures.sh` 和 `bash scripts/install-shortcuts.sh`，再运行 `hyprctl configerrors` 检查加载结果。

2026-11-24 在双屏会话中用模拟鼠标拖放临时 Foot 窗口，确认 6 → 1 松手后浮动，1 → 6 松手后平铺。通过概览移窗也确认，手动浮动的窗口移到工作区 5 后加入滚动布局，全屏窗口从 6 移到 1 时保持全屏，退出全屏后转为浮动。

回滚时恢复安装前备份的 `~/.config/hypr/silky-shortcuts.lua` 和 `~/.local/lib/silky-omarchy/silky-gestures-<Hyprland版本>.so`，卸载并重新加载该插件，然后运行 `hyprctl reload`。

### 微信图片查看器与聊天记录窗口的默认尺寸

微信主窗口浮动时，点开图片或视频弹出的「图片和视频」窗口仍会在平铺工作区里和其他窗口分屏；而且微信自己给的尺寸常常偏高，竖长截图能开到 874 逻辑像素高、顶着菜单栏（本机屏幕 1472×920 @ scale 2）。聊天记录窗口（标题 `"群名"的聊天记录(条数)`）同样开得偏大，两侧还留大片空白。[config/hypr/silky-app-windows.lua](../config/hypr/silky-app-windows.lua) 使用 `hl.window_rule` 按 `class` `wechat` 与标题精确匹配这两个窗口，打开时就浮动、居中并给一个适中默认尺寸：查看器 900×620，聊天记录 820×720；仅把两个弹窗标题登记到 `o.floating_apps.title`（不再把 `^wechat$` 写入 `o.floating_apps.class`），从而既让弹窗保持自带浮动，又不影响微信主窗口在浮动工作区首帧即以浮动打开。打开后仍可用 `Super+T` 临时平铺，窗口也可以随意拉伸，微信内部的图片放大不受影响。

微信关闭查看器后并不销毁窗口，下一张图片复用同一个窗口（地址不变，也不发 `openwindow` 事件），所以打开时的规则只对规则加载之后新建的查看器生效；同一文件里还挂了 `config.reloaded`，每次 `hyprctl reload` 时把这两类窗口中仍平铺的、或任一维度超过默认尺寸的，切为浮动、缩回默认尺寸并居中，没超的窗口不动，保住手动调小的结果。

聊天记录窗口的高度下限是微信自己定的：实测（2026-11-20，微信 4.1.13）程序化请求 600/640/660/700 高度都被弹回 720，调大则随意，所以 820×720 已是能收到的最小高度，这条规则的收益主要是收窄宽度、减少两侧留白。

标题来自微信 4.1.13 中文界面（Wayland 原生窗口，非 XWayland）。界面语言切成英文或以后版本改了标题时，规则不会命中，用下面的命令查新标题后改正则。

### 微信后台不再自动抢焦点置顶

在浮动工作区模式下，微信（XWayland，`class` `wechat`）收到新消息或后台状态更新时会发送 X11 `_NET_ACTIVE_WINDOW` 激活请求；Omarchy 在 `/usr/share/omarchy/default/hypr/looknfeel.lua` 默认开启了全局 `misc.focus_on_activate = true`，Hyprland 会直接把焦点切给微信并将其抬升到所有浮动窗口最前方（`pinned` 实际为 `false`，但视觉上像莫名其妙置顶）。Omarchy 上游已为 Telegram（`org.telegram.desktop`）单独关闭该行为，未覆盖微信。

[config/hypr/silky-app-windows.lua](../config/hypr/silky-app-windows.lua) 为 `^wechat$` 增加了 `focus_on_activate = false` 规则（`silky-wechat-no-focus-steal`），拦住后台自动抢焦点，不影响鼠标点击、Dock、`Alt+Tab` 等主动切换窗口。

### 微信主窗口关闭后重开保留上次状态

微信 4.x 点击关闭按钮（`×`）隐藏到系统托盘时会销毁 `xdg_toplevel`，再次从托盘或启动器点开时新建主窗口。配合 [touch-scroll.c](../plugins/wechat-wayland/touch-scroll.c) 拦截非用户点击触发的 `set_maximized`，[config/hypr/silky-app-windows.lua](../config/hypr/silky-app-windows.lua) 监听微信主窗口（`class` 为 `wechat` 且标题为 `微信` 或 `WeChat`）的 `window.destroy`、`window.fullscreen` 与 `window.open`，将关闭前的窗口状态（普通窗口 / 最大化 / 全屏，以及普通浮动窗口的位置与尺寸）持久化到 `~/.local/state/silky-omarchy/wechat-main-window.state`；再次打开时自动恢复对应状态与几何尺寸（并按当前显示器可见工作区钳位），不再默认最大化或重置位置。回滚或清除记忆只需删除该状态文件并重载 Hyprland。

### 拔掉外接显示器后工作区与窗口自动回到内屏

多屏模式下，[config/hypr/silky-workspaces.lua](../config/hypr/silky-workspaces.lua)（安装到 `~/.config/hypr/silky-workspaces.lua`，由 `hyprland.lua` 在 Omarchy 默认配置前 `require("hypr.silky-workspaces")`）将工作区 1–5 分配给内屏 `eDP-1`、6–9 分配给外接显示器（优先 `desc:BOE 0x0A52`，并回退到任意已连接的非镜像外接屏）。

- **已确认原因**：拔掉外接显示器时，Hyprland 移除该输出后，原外接屏上有窗口的工作区（如工作区 6）会失去绑定显示器（`monitor: "?"`、`monitorID: null`，Lua API 中 `workspace.monitor == nil`），其上的浮动窗口 `monitor` 为 `-1` 且坐标仍停留在原外接屏的离屏坐标。原实现在 `workspaces.reconcile()` 和 `workspaces.focus()` 中写了 `if workspace and workspace.monitor and ...`，导致 `workspace.monitor == nil` 的孤儿工作区被直接跳过，既不会迁回 `eDP-1`，按 `Super+6` 也无法切回；同时忽略了 `monitor.removed` 回调传入的 `gone` 参数。
- **修复方式**：`reconcile(added, gone)` 与 `focus(id)` 改为在 `workspace.monitor == nil` 或不匹配目标显示器（含正被移除的 `gone`）时直接执行 `workspace.move` 迁回内屏，并对 9 号以上的孤儿常规工作区做兜底迁移；迁回和钳位时按目标显示器的逻辑尺寸、旋转、`reserved`（顶栏与 Dock 预留区）以及窗口的 `hyprbars` 服务端标题栏高度（通过 `silky_gestures.window_top_inset` 或 `o.silky_titlebar_height` 获取）计算最小 Y 坐标与最大高度，避免带标题栏的浮动窗口（如 Foot）的外框顶边压过顶栏。收到 `monitor.removed` 后额外追加一次 150 ms 单次复核以防合成器 teardown 时序滞后。配合 [`silky-gestures`](03-silky-gestures.md#浮动窗口不能越过菜单栏)（0.8.4+）的合成器级非拖动守护与 `post-update` 钩子，避免多屏切换或系统更新后复发。
- **验证与回滚**：2026-11-23 在本机（Hyprland 0.57.2，双屏 `eDP-1` + `DP-1` @ `1472x-319`）实机验证：此前被钳位到 `at.y = -296`、30 px `hyprbars` 标题栏越过顶栏（`-319..-296`）的 `foot` 窗口在部署重载后自动归位到 `at.y = -266`（外框顶边 `-296`，紧贴顶栏下沿），人为将 `foot` 推到 `y = -310` 后重载也会立刻拉回，全屏双屏 15 个浮动窗口 0 越界，`hyprctl configerrors` 为空。回滚时从 `~/.config/hypr/silky-workspaces.lua.bak.*`、`silky-shortcuts.lua.bak.*`、`silky-macos.lua.bak.*` 恢复并执行 `hyprctl reload`。

## 原理

| 文件 | 作用 |
| --- | --- |
| `config/hypr/silky-keys-registry.lua` | 在 `hyprland.lua` **最前面**加载。包一层 `hl.bind` / `hl.unbind`，记下每个绑定的键、说明、来源文件和 dispatcher；提供 `silky_keys.dump(path)` 和 `silky_keys.run(n)` |
| `config/hypr/silky-shortcuts.lua` | 在 `hyprland.lua` **最后**加载（在 `hypr.macshell` 之后）。先 `hl.unbind` 冲突键，再只绑 MacShell 的功能，把 Omarchy 的动作绑到新键 |
| `config/hypr/silky-keys.lua` | 登录时启动面板；`o.rebind("SUPER + K", …)`；给 `silky-keys` 图层加背景模糊 |
| `keys-panel/shell.qml` → `~/.config/quickshell/SilkyKeys/` | 面板本体（常驻 Quickshell，IPC 目标 `keys`） |
| `config/hypr/silky-app-windows.lua` | 按应用的窗口规则：禁止微信后台自动抢焦点置顶；微信「图片和视频」与聊天记录窗口始终浮动、居中，默认尺寸适中 |

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

微信图片查看器与聊天记录：在微信里点开一张图片、打开一个聊天记录窗口，然后执行

```bash
hyprctl clients -j | jq -c '.[] | select(.class=="wechat") | {title, size, floating}'
```

「图片和视频」一行应为 `"size":[900,620]`、`"floating":true`，聊天记录应为 `"size":[820,720]`，两者居中且不碰菜单栏。2026-11-20 在本机实机确认：`hyprctl configerrors` 为空；规则加载后新建的查看器打开即 900×620 居中；聊天记录窗口重载后收窄并居中。程序化把聊天记录高度调到 720 以下会被微信弹回，属微信自身的最小高度，不是规则问题；复用的旧查看器在重载时被收回默认尺寸这一步待验证。

微信后台防抢焦点：2026-11-22 在本机（Hyprland 0.57.2、微信 4.1.29 XWayland）实机对比验证：`hyprctl configerrors` 为空；修复前向微信 X11 窗口发送 `_NET_ACTIVE_WINDOW` 会立刻将焦点切给微信并抬升到最前，修复后保持原焦点窗口不变。

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

只撤销微信图片查看器和聊天记录窗口规则：删除 `~/.config/hypr/silky-app-windows.lua` 和 `hyprland.lua` 里的 `require("hypr.silky-app-windows")`，执行 `hyprctl reload`。已经浮动的窗口会保持浮动，按 `Super+T` 或重启微信即恢复平铺。

Super+K 回到 Omarchy 自带的菜单，冲突键恢复成同时触发两边。
