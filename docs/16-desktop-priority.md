# 16 · 桌面优先调度：Hyprland 与 MacShell 先拿到 CPU / GPU

简体中文 | [English](en/16-desktop-priority.md)

## 效果与范围

后台程序把 CPU 吃满时（编译、Chromium / Electron 渲染进程、代理、语音识别等），桌面合成器和菜单栏 / Dock 仍然先被调度，动画和指针不跟着掉帧。

- Hyprland、Xwayland、MacShell（`qs` / `quickshell`）和 fcitx5 的所有线程改用负 nice，CPU 争抢时排在普通应用前面。
- 同时给这些线程设 `uclamp.min`。它们一醒来，schedutil 就把所在 CPU 簇拉到较高频率，第一帧不必等升频。
- 接通电源时，把 Adreno GPU 的最低频率提到 550 MHz，避免空闲后第一段动画卡在 300 MHz 起步。用电池时恢复原值，不额外耗电。
- 应用已经主动降级的线程保持不动，比如 Mesa 的 `disk$` / `traceq` 缓存线程（`SCHED_BATCH`）、自己设了 nice 的线程、rtkit 管理的线程。磁盘缓存和后台工作不会抢到前台。

触发原因（实机确认）：Hyprland、MacShell 默认都是 nice 0，和十几个 Chromium / Electron 渲染进程同权竞争；`hyprland.log` 里出现过几十条 libinput 的 `scheduled expiry is in the past … your system is too slow`，说明合成器的输入处理被推迟过。Hyprland 0.57 自己不会申请实时调度。GPU 方面 aquamarine 已经拿到高优先级 EGL 上下文（`IMG_context_priority … Got a high priority context`），无需另外设置。

| 进程 | nice | uclamp.min（0–1024） |
| --- | --- | --- |
| `Hyprland` | -11 | 512 |
| `qs`、`quickshell`（MacShell / Omarchy Shell） | -8 | 384 |
| `Xwayland` | -6 | 256 |
| `fcitx5` | -6 | 256 |

这里没有用实时调度（`SCHED_RR` / `SCHED_FIFO`），合成器卡死时也不会锁住整机。nice 最低限制在 -15。

## 安装与使用

在仓库根目录运行，会提示输入 sudo 密码：

```bash
./scripts/install-desktop-priority.sh
```

脚本先检查语法，备份已存在且内容不同的 `/etc/silky/desktop-priority.conf`（`*.bak.<时间>`），然后安装并启动服务，可以重复运行：

| 仓库文件 | 安装位置 |
| --- | --- |
| [`bin/silky-desktop-priority`](../bin/silky-desktop-priority) | `/usr/local/bin/silky-desktop-priority` |
| [`config/silky/desktop-priority.conf`](../config/silky/desktop-priority.conf) | `/etc/silky/desktop-priority.conf` |
| [`config/systemd/system/silky-desktop-priority.service`](../config/systemd/system/silky-desktop-priority.service) | `/etc/systemd/system/silky-desktop-priority.service` |

依赖：`python3`、systemd。不需要重新登录，服务每 2 秒扫描一次新线程，重启 Hyprland 或 MacShell 后会自动重新提权。

调整进程或数值时编辑 `/etc/silky/desktop-priority.conf`（格式：`进程名 = nice uclamp.min`），然后执行：

```bash
sudo systemctl restart silky-desktop-priority.service
```

不想要 GPU 频率下限时，把 `[gpu]` 的 `ac_min_freq_mhz` 设为 `0`。

## 实现与兼容性

- 优先使用原生 C++ 实现（[`plugins/silky-desktop-priority/main.cpp`](../plugins/silky-desktop-priority/main.cpp)），由 [`scripts/install-desktop-priority.sh`](../scripts/install-desktop-priority.sh) 编译安装到 `/usr/local/bin/silky-desktop-priority`；系统缺少 `g++` 时自动回退到 Python 版 [`bin/silky-desktop-priority`](../bin/silky-desktop-priority)。C++ 版先读 `/proc/<pid>/comm` 快速过滤非目标进程，单次 `--status` 耗时由约 50 ms 降至约 6.4 ms，常驻内存与 CPU 占用显著低于 Python 解释器。
- 服务以 root 运行，只保留 `CAP_SYS_NICE` 能力（给别的进程设负 nice 和 `uclamp.min` 都需要它），并启用 `ProtectSystem=strict`、`ProtectHome`、`PrivateNetwork`，内存上限 64 MB，自身 nice 5。
- 用 `sched_setattr(2)` 一次性写入 `SCHED_OTHER`、nice 和 `SCHED_FLAG_UTIL_CLAMP_MIN`，逐线程设置，因为 Linux 的 nice 是按线程生效的。系统调用号已包含 aarch64 和 x86_64；其他架构退回到只设 nice。
- 只匹配 UID ≥ 1000 的进程，按 `/proc/<pid>/comm` 精确匹配，所以 MacShell 启动的 `python3`、`inotifywait` 等子进程不会被提权。PID 和线程按启动时间缓存，每轮只读新出现的进程。
- 停止服务时（`SIGTERM`），已提权线程恢复为 nice 0、`uclamp.min` 0，GPU 最低频率恢复为原值。
- 交流电判断：`/sys/class/power_supply` 下任一非电池电源 `online=1`。
- 为什么不用 cgroup 权重：Hyprland 从 greetd 会话启动，`session-N.scope` 里同时有 Chromium、ChatGPT 等从会话直接拉起的应用，提高整个 scope 的 `CPUWeight` 会把它们一起提上去。按进程设置更精确。
- 已验证环境：Lenovo Yoga Slim 7x（Snapdragon X Elite，12 核 Oryon，3 个簇各 4 核，Adreno X1-85），内核 7.3（`CONFIG_UCLAMP_TASK=y`，`CONFIG_PREEMPT=y`），Hyprland 0.57.2，quickshell 0.3.2，schedutil。如果内核没有 uclamp，只有 nice 生效；没有 devfreq GPU 时跳过 GPU 部分。
- 限制：Qt / quickshell 的 GPU 上下文优先级无法从外部修改，MacShell 只能靠 CPU 侧优先和 GPU 频率下限受益。Xwayland 提权后，WPS、微信等 X11 应用的绘制也会略微受益。

## 验证

```bash
systemctl status silky-desktop-priority.service
/usr/local/bin/silky-desktop-priority --config /etc/silky/desktop-priority.conf --status
ps -L -o tid,ni,cls,comm -p "$(pgrep -x Hyprland)"
```

预期：服务是 `active (running)`；`--status` 里每个目标进程的 `boosted` 接近线程数（差额是 `SCHED_BATCH` 缓存线程和带 reset-on-fork 的 `module-rt` 线程），主线程 nice 为配置值，`uclamp.min` 为配置值；接通电源时 GPU 行显示 `min=550000000`。

压力对比（实机）：开 12 个满载进程 `stress-ng --cpu 12 --timeout 60s`（或 `for i in $(seq 12); do timeout 60 sh -c 'while :; do :; done' & done`），在此期间拖动窗口、打开控制中心、切换工作区。启用服务后动画应保持顺滑，`hyprland.log` 里不再新增 `your system is too slow`。

不安装、只预览会改动哪些线程（无需 root）：

```bash
bin/silky-desktop-priority --config config/silky/desktop-priority.conf --dry-run
```

## 回滚

```bash
./scripts/install-desktop-priority.sh --uninstall
```

这会停止并禁用服务（停止时恢复 nice、`uclamp.min` 和 GPU 频率下限），删除 `/usr/local/bin/silky-desktop-priority` 和 unit 文件，并执行 `daemon-reload`。`/etc/silky/desktop-priority.conf` 和它的备份保留，不需要时手动删除。无需重启或重新登录。
