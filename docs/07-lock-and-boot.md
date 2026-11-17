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

[`bin/silky-lock`](../bin/silky-lock) 通过 MacLock 的 IPC（`lock-via-ipc.sh`）上锁，并做 `omarchy-system-lock` 原本的附带工作：切回默认键盘布局、锁定 1Password、关闭屏保。`silky-lock --is-locked` 供闲置服务判断是否已锁；`silky-lock --sleep` 会等到 MacLock 报告已锁（`qs -c MacLock ipc call lockscreen state` 返回 `busy`）再返回。

[`bin/silky-sleep-lock`](../bin/silky-sleep-lock) 持有 logind 的 delay 抑制锁，收到 `PrepareForSleep` 后用 MacLock 上锁，锁好后立即退出以释放抑制锁让系统睡眠，systemd 随后重启它，为下一次睡眠重新拿锁。

### 闲置服务

```bash
omarchy plugin clone omarchy.idle
```

复制出的插件 id 不能用 `omarchy.` 开头（`id is reserved for first-party Omarchy plugins`），所以改名为 `silky.idle`，保留 `"clonedFrom": "omarchy.idle"`，这样它仍然读取 `shell.json` 里的 `idle.screensaver` / `idle.lock` 时长。然后：

```bash
omarchy plugin enable silky.idle
omarchy plugin disable omarchy.idle
omarchy restart shell
```

`Service.qml` 只改两行：锁屏命令换成 `silky-lock`，屏保前的“是否已锁”判断换成 `silky-lock --is-locked`。

## 开机界面

这台机器的磁盘是 LUKS 加密的，开机先在 Plymouth 里输入磁盘密码，之后 SDDM 自动登录（`/etc/sddm.conf.d/autologin.conf`）。所以“开机登录界面”就是 Plymouth 的解锁界面。它运行在 initramfs 里，那时还没有任何用户程序，MacLock 本身没法在这里运行，只能做一个外观一致的 Plymouth 主题。

[`plymouth/silky-maclock.script`](../plymouth/silky-maclock.script) 是 Plymouth script 主题，[`scripts/install-boot-screen.sh`](../scripts/install-boot-screen.sh) 用 ImageMagick 生成素材。布局与 MacLock 一致，数值直接取自 `MacLock/LockScreen.qml`：

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
systemctl --user is-active silky-sleep-lock omarchy-sleep-lock
systemd-inhibit --list --no-pager | grep Silky
hyprctl binds -j | jq -r '.[] | select(.key=="L") | .description'
plymouth-set-default-theme
```

预期：`silky.idle` 启用、`omarchy.idle` 停用；`silky-sleep-lock` 为 active、`omarchy-sleep-lock` 为 inactive；抑制锁列表里有 “Silky Omarchy”；Plymouth 默认主题为 `silky-maclock`。

锁屏和开机界面都已在真机上确认。

## 回滚

```bash
omarchy plugin enable omarchy.idle && omarchy plugin disable silky.idle
systemctl --user disable --now silky-sleep-lock.service
systemctl --user unmask omarchy-sleep-lock.service && systemctl --user start omarchy-sleep-lock.service
./scripts/install-boot-screen.sh --restore
```

再删掉 `~/.config/hypr/bindings.lua` 里的 Super+Ctrl+L 覆盖，以及 `~/.config/omarchy/extensions/omarchy-menu.jsonc` 里的 `system.lock`。
