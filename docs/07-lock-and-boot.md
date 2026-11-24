# 07 · 统一用 MacLock 锁屏，开机解锁界面换成 macOS 风格

简体中文 | [English](en/07-lock-and-boot.md)

## 目标

- 停用 Omarchy 自带的锁屏，所有锁屏都用 MacShell 的 MacLock
- 开机输入磁盘密码的界面做成 macOS FileVault 的样子：模糊壁纸、圆形头像、用户名、毛玻璃密码框

## 锁屏有哪些入口

Omarchy 的锁屏不只是一个快捷键，一共有四个入口，都要改：

| 入口 | 原来 | 现在 |
| --- | --- | --- |
| Super+L | MacShell 已绑定 MacLock | 不变 |
| Super+Ctrl+L、Omarchy 菜单里的“锁定” | `omarchy-system-lock` | `silky-lock` |
| 闲置 5 分钟 | Omarchy shell 的 `omarchy.idle` 服务调用 `omarchy-system-lock` | 复制出的 `silky.idle` 服务调用 `silky-lock` |
| 合盖 / 睡眠前 | 用户服务 `omarchy-sleep-lock.service` | 用户服务 `silky-sleep-lock.service`，原服务被 mask |

[`bin/silky-lock`](../bin/silky-lock) 通过 MacLock 的 IPC（`lock-via-ipc.sh`）上锁，并做 `omarchy-system-lock` 原本的附带工作：切回默认键盘布局、锁定 1Password、关闭屏保。新版 Omarchy 屏保（`omarchy-screensaver` 1.3.1+）运行独立进程 `/usr/lib/omarchy-screensaver/omarchy-screensaver` 而非旧版 `ttfx` 终端窗口，若不显式结束会在 MacLock 之下继续运行并在解锁后重新出现；`silky-lock` 会在上锁时结束该进程（等待退出或强杀）并恢复 `cursor:invisible false`，同时保留对旧版 `ttfx` / `org.omarchy.screensaver` 的兼容清理。`silky-lock --is-locked` 供闲置服务判断是否已锁；`silky-lock --sleep` 会等到 MacLock 报告已锁（`qs -c MacLock ipc call lockscreen state` 返回 `busy`）再返回。

[`bin/silky-sleep-lock`](../bin/silky-sleep-lock) 持有 logind 的 delay 抑制锁，收到 `PrepareForSleep` 后用 MacLock 上锁，锁好后立即退出以释放抑制锁让系统睡眠，systemd 随后重启它，为下一次睡眠重新拿锁。

### 闲置服务与熄屏

```bash
omarchy plugin clone omarchy.idle
```

复制出的插件 id 不能用 `omarchy.` 开头（`id is reserved for first-party Omarchy plugins`），所以改名为 `silky.idle`，保留 `"clonedFrom": "omarchy.idle"`，这样它仍然读取 `~/.config/omarchy/shell.json` 里的 `idle` 配置。然后：

```bash
omarchy plugin enable silky.idle
omarchy plugin disable omarchy.idle
omarchy restart shell
```

[`config/omarchy/plugins/silky.idle/Service.qml`](../config/omarchy/plugins/silky.idle/Service.qml) 基于新版 `omarchy.idle`（通过进程退出和活动信号停止 `omarchy-screensaver`，并支持修改超时后自动重武装 `IdleMonitor`）做了两处扩展：

- 锁屏命令换成 `silky-lock`，屏保前的“是否已锁”判断换成 `silky-lock --is-locked`
- 新增可选的 `idle.dpms` 熄屏计时（默认 `0` 关闭，由独立 `IdleMonitor` 驱动，遵循 `stay-awake` 开关）：达到时长后执行 `omarchy-brightness-keyboard off; omarchy-brightness-display off` 熄灭屏幕与键盘背光但不进入睡眠；任意按键或鼠标移动唤醒时由 Hyprland 亮屏并调用 `omarchy-system-wake` 恢复键盘背光

例如在 `~/.config/omarchy/shell.json` 中统一配置电源与电池模式为 5 分钟屏保、10 分钟锁屏、15 分钟熄屏（不睡眠）：

```json
"idle": {
  "screensaver": 300,
  "lock": 600,
  "dpms": 900
}
```

## 锁屏残留旧通知

MacShell 重启或重载后，内存中的通知列表会重新初始化。旧版 MacShell 只在通知列表变化时写入 `~/.cache/macshell/lock-notifs.json`，所以新通知到来前，MacLock 可能一直显示上一次运行留下的微信等旧通知。

从仓库根目录运行 `python3 scripts/macshell_notification_center.py --install`。补丁让 MacShell 在启动或重载时主动发布当前列表。安装器会备份用户配置并重载 MacShell，已有的 systemd 用户服务会在更新后重新应用补丁。验证时，在有未读测试通知的情况下重载 MacShell，确认缓存变为 `[]`，再用 `notify-send` 发一条新通知，确认缓存随之更新。回滚参见[通知中心修复](02-macshell.md#微信通知跳转与横幅)。

## 锁屏头像

在 MacShell 的「系统设置 → 用户与群组」更换头像后，侧栏与账户页会一起更新。下次 MacLock 锁屏时优先读取同一份 `~/.face`，头像加载独立于 Wi-Fi 查询。

设置侧栏和账户页通过 [Qt Quick 曲线渲染组件](../config/macshell/SilkyAccountAvatar.qml)裁切圆形头像，缩小图片时使用 mipmap 采样。已在本机 2× 缩放下对比选中侧栏账户时的圆边。也可切到 1× 缩放检查高亮背景上的效果。

适用于本机 MacShell 0.5.3。常规安装会应用此项。只更新头像时，先备份 `~/.config/quickshell/MacShell/MacDock.qml` 和 `~/.config/quickshell/MacLock/shell.qml`，在仓库根目录运行以下命令。

```bash
python3 scripts/tune-macshell-avatar.py ~/.config/quickshell/{MacShell/MacDock.qml,MacLock/shell.qml}
qs ipc -c MacShell call macshell reload
```

换图后核对侧栏，再按 `Super+L` 查看锁屏。隔离测试中，模拟 Wi-Fi 查询延迟时，新锁屏能先载入头像。回滚时恢复两份备份，移除此次新增的 `~/.config/quickshell/MacShell/SilkyAccountAvatar.qml`，再重载 MacShell。MacLock 会在下次锁屏时读取恢复后的配置。

## 登录壁纸过渡

适用于使用 greetd 和 MacLock / MacShell 的 Hyprland 桌面。实机开机日志显示，传统的双 Hyprland 交接（MacShell 登录界面退出 → 桌面 Hyprland 冷启动）存在约 5.2 秒黑屏：greeter 会话关闭约 1.28 秒、桌面 Hyprland 初始化 DRM 与 Adreno X1-85 OpenGL ES 约 2.57 秒（空配置的 greeter Hyprland 冷启动同样需约 2.70 秒）、临时壁纸启动与解码 6K 原图约 1.08 秒。只要存在两个 Hyprland 进程交接显示设备，冷初始化阶段的黑屏便无法完全消除。

现采用**单 Hyprland 会话 + 开机即 MacLock 锁屏**方案彻底消除登录黑屏：

- 系统侧 [`config/hypr/silky-login-transition/initial-session`](../config/hypr/silky-login-transition/initial-session) 安装至 `/usr/local/bin/silky-boot-session`，并在 `/etc/greetd/config.toml` 添加 `[initial_session]`，开机直接启动唯一桌面 Hyprland 并写入一次性锁屏标志与 `SILKY_BOOT_LOCK=1`；原有 `[default_session]`（`macshell-greeter`）保留，退出登录后仍回到原登录界面且不会二次锁屏。同时写入 [`config/systemd/plymouth-quit-retain-splash.conf`](../config/systemd/plymouth-quit-retain-splash.conf) 至 `/etc/systemd/system/plymouth-quit.service.d/silky-retain-splash.conf`，将 `plymouth quit` 改为 `plymouth quit --retain-splash`，把开机画面保留在帧缓冲上直到 Hyprland 接管显示。
- 桌面侧 [`config/hypr/silky-login-transition/boot-lock`](../config/hypr/silky-login-transition/boot-lock) 安装至 `~/.config/hypr/silky-login-transition/boot-lock`，由 `~/.config/hypr/autostart.lua` 顶部最先拉起 `qs -c MacLock` 绑定 `ext-session-lock-v1` 会话锁，并开启 Hyprland 的 `misc.session_lock_xray = true`。非首屏辅助组件 [`silky-voice.lua`](../config/hypr/silky-voice.lua) 与 [`silky-keys.lua`](../config/hypr/silky-keys.lua) 延后 3 秒启动（`Super+K` 仍支持按需即时拉起），避免开机首秒与 MacLock / MacShell 争抢 CPU 与磁盘 I/O。锁屏期间壁纸引擎、菜单栏与 Dock 在后台就绪；输入密码后锁屏以 420 ms 透明淡出，直接露出同一张壁纸与桌面，**0 黑屏**（平时 `Super+L` 解锁同样受益）。
- 安全边界说明：未开启 LUKS 磁盘加密时，开机自动进入用户会话再由 Wayland 会话锁遮挡意味着未输密码前用户后台服务已在运行，适合个人独用设备；如需严格的双会话隔离，可跳过 `--boot-lock`，仅使用 `--greeter` 与 `--greeter-mode`。

从仓库根目录运行（桌面侧依赖 Hyprland Lua 配置、Quickshell 与 MacLock）：

```bash
python3 scripts/install-login-transition.py
sudo python3 scripts/install-login-transition.py --boot-lock
```

安装脚本覆盖前自动备份，写入位置在 `~/.config/hypr/`、`/usr/local/bin/` 与 `/etc/greetd/config.toml`，均在 Omarchy 软件包管理范围之外，常规 `omarchy update` 会保留。

可选辅助项（兼容旧版双会话登录界面与开机并发优化）：

- `sudo python3 scripts/install-login-transition.py --greeter --greeter-mode 2944x1840@90`：让注销后退回的 MacShell 0.5.3 登录界面在退场时保留壁纸并对齐 `eDP-1` 90 Hz（先用 `hyprctl monitors all` 确认模式支持）。
- `python3 scripts/install-login-transition.py --defer-voice`：把已启用的 `vinput-daemon.service`（开机预热约 1.7 秒）延后至用户 systemd 启动后约 5 秒再预热，提前听写仍可按需通过 D-Bus 启动。

验证：运行 `hyprctl reload && hyprctl configerrors` 应无报错，`hyprctl getoption misc:session_lock_xray` 返回 `bool: true`；桌面侧安装与幂等重跑已在当前会话实测，`/etc/greetd/config.toml` 的应用、重跑与精确还原已通过隔离测试。开机完整 0 黑屏过渡待执行 `--boot-lock` 并重启后实测。

回滚（下次开机生效）：

```bash
python3 scripts/install-login-transition.py --restore
sudo python3 scripts/install-login-transition.py --boot-lock --restore
# 若之前启用了可选辅助项，按需一并撤销：
sudo python3 scripts/install-login-transition.py --greeter --restore
python3 scripts/install-login-transition.py --defer-voice --restore
```

## 开机界面

这套 Plymouth 主题最初用于开机先输入 LUKS 磁盘密码、随后 SDDM 自动登录的配置。Plymouth 在用户会话启动前运行于 initramfs，所以磁盘解锁画面由独立主题绘制。使用 greetd 的 MacShell 用户登录界面时，参见上面的[登录壁纸过渡](#登录壁纸过渡)。

[`plymouth/silky-maclock.script`](../plymouth/silky-maclock.script) 是 Plymouth script 主题，[`scripts/install-boot-screen.sh`](../scripts/install-boot-screen.sh) 用 ImageMagick 生成素材。开机无磁盘密码阶段会在当前壁纸下方居中（距底 108u，不遮挡壁纸主体）显示 macOS 风格的 210u × 5u 圆角细进度条（4× 超采样抗锯齿），在 Plymouth 活跃的 ~0.45 秒内以三次缓出曲线（ease-out cubic）从 8 % 平滑推进至 90 %，配合 `plymouth quit --retain-splash` 保留在帧缓冲上直到 Hyprland 淡入 MacLock。磁盘解锁布局与 MacLock 一致，数值直接取自 `MacLock/LockScreen.qml`：

| 元素 | MacLock | 开机界面 |
| --- | --- | --- |
| 单位 | `u = 屏幕高度 / 1200` | 同（设备像素） |
| 壁纸 | 当前壁纸，未输入时不模糊 | 当前壁纸，原生分辨率，不模糊 |
| 头像 | 70u 圆形，1 px 22 % 白色描边 | 同 |
| 用户名 | 15u 半粗体，淡阴影 | 同 |
| 密码框 | 210u × 36u 胶囊，玻璃材质 | 同尺寸，半透明白 + 细描边 + 顶部高光 |
| 提示文字 | “输入密码”，14u，62 % 白，左缩进 16u | 同 |
| 位置 | 整组距底部 78u，间距 10u | 同 |
| 时钟 | 大号玻璃数字 | 无（Plymouth 脚本读不到时间） |

### 高分辨率屏

早期版本在这块 2944×1840 的屏上看起来发虚、有光晕，原因有两个：

- Plymouth 自动把高分屏当作 2 倍缩放：脚本拿到的窗口只有 1472×920，画完后整帧放大 2 倍。现在在 `/etc/plymouth/plymouthd.conf` 里设 `DeviceScale=1`，脚本直接按设备像素工作
- 背景原来只生成 1600×1000 并做强模糊、提饱和，被拉伸后亮部晕进暗部。现在背景按屏幕原生分辨率生成、不模糊；头像、密码框按 4 倍绘制再缩小，边缘平滑

所有素材按内屏实际尺寸绘制（脚本里的 `BUILD_HEIGHT`），在内屏上原样显示不缩放；外接其他尺寸的屏幕时才按比例缩放。

```bash
./scripts/install-boot-screen.sh --preview   # 只生成 plymouth/preview.png，不改系统
./scripts/install-boot-screen.sh             # 安装并重建 initramfs（需要密码）
./scripts/install-boot-screen.sh --restore   # 换回 Omarchy 原来的开机界面（同时去掉 DeviceScale=1）
```

换壁纸或头像后重新运行一次即可更新。安装时需要输入密码，并重建开机镜像（本机是 limine + UKI，约 1 分钟）；sudo 等待密码超时后脚本会中止，什么也不改，重新运行即可。如果主题脚本出错，Plymouth 会退回纯文字的密码提示，磁盘照样可以解锁。

注意：在 Omarchy 设置里重新设置 Plymouth（`omarchy-plymouth-set-by-theme`）会把默认主题改回 `omarchy`，之后需要重新运行安装脚本。

## 验证

```bash
omarchy plugin list | grep idle
omarchy-shell idle status
systemctl --user is-active silky-sleep-lock omarchy-sleep-lock
systemd-inhibit --list --no-pager | grep Silky
hyprctl binds -j | jq -r '.[] | select(.key=="L") | .description'
plymouth-set-default-theme
```

预期：`silky.idle` 启用、`omarchy.idle` 停用；`omarchy-shell idle status` 中 `enabled` 为 `true`，`screensaver`、`lock`、`dpms` 与 `shell.json` 一致且 `dpmsOff` 为 `false`；`silky-sleep-lock` 为 active、`omarchy-sleep-lock` 为 inactive；抑制锁列表里有 “Silky Omarchy”；Plymouth 默认主题为 `silky-maclock`。

锁屏、闲置配置和开机界面已在真机上验证；完整 5/10/15 分钟超时流程与解锁后无屏保残留待下一轮实际闲置时观察确认。

## 回滚

```bash
omarchy plugin enable omarchy.idle && omarchy plugin disable silky.idle
systemctl --user disable --now silky-sleep-lock.service
systemctl --user unmask omarchy-sleep-lock.service && systemctl --user start omarchy-sleep-lock.service
./scripts/install-boot-screen.sh --restore
```

再删掉 `~/.config/hypr/bindings.lua` 里的 Super+Ctrl+L 覆盖，以及 `~/.config/omarchy/extensions/omarchy-menu.jsonc` 里的 `system.lock`。
