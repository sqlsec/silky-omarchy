# 18 · 5 GHz Wi-Fi 连接卡死与列表消失修复（Qualcomm `ath12k_wifi7`）

简体中文 | [English](en/18-ath12k-5ghz-wifi.md)

## 效果与范围

在高通 FastConnect 7800（WCN7850，`ath12k_wifi7_pci`）无线网卡上，从 2.4 GHz 切换到 5 GHz 网络、睡眠唤醒或重新连接时，不再卡在「正在连接…」25 秒后报错失败，也不再出现失败后周围所有 5 GHz Wi-Fi 从扫描列表中整片消失、只剩 2.4 GHz 且开关 Wi-Fi 无法恢复的问题。同时开机和唤醒后优先自动连接已保存的 5 GHz 网络。

触发条件与已确认的原因（实机 Lenovo Yoga Slim 7x 83ED，网卡 `WCN785x [17cb:1107]`，内核 `7.3.0-78-omarchy`，固件 `WLAN.HMT.1.1.c7-00108`，`NetworkManager 1.58.1` + `wpa_supplicant 2.12`）：

1. **70 ms 内连续翻转硬件 MAC 引发 11d 扫描与关联扫描撞车**：NetworkManager 默认开启 `wifi.scan-rand-mac-address=yes`。每次断开旧网络准备激活目标 5 GHz 网络时，NetworkManager 先把接口改为随机扫描 MAC（`set-hw-addr (scanning)`），约 70 ms 后进入连接准备阶段又改回真实硬件 MAC（`set-hw-addr (preserve)`）。在 `ath12k` 中，这两次链路重建连续触发固件 `11d` 国家码扫描（`ath12k_mac_11d_scan_start`）及连续 4 次 `CTRL-EVENT-REGDOM-CHANGE`；8 ms 后 `wpa_supplicant` 发起关联扫描 `WMI_START_SCAN_CMDID`，直接被固件拒绝并上报 `ath12k_wifi7_pci 0004:01:00.0: received scan start failure event`。
2. **`ath12k` 驱动扫描状态机竞态导致干等 25 秒超时**：反汇编 `ath12k.ko` 确认，`ath12k_wmi_op_rx` 在 `ATH12K_SCAN_STARTING (1)` 状态下收到 `WMI_SCAN_EVENT_START_FAILED` 时，仅通过 `wiphy_work_queue` 异步排队 `vdev_clean_wk` 并立即 `complete(&ar->scan.started)`，未同步将 `ar->scan.state` 置回 `0`。此时正持有 `wiphy_lock` 的 `ath12k_start_scan` 被唤醒后读到 `ar->scan.state == 1`，误判扫描已成功启动并返回 `0`，导致 `wpa_supplicant` 持续等待一个从未启动的扫描，面板一直显示「正在连接…」，直至 25 秒后 NetworkManager 因 `ssid-not-found` 放弃激活。
3. **固件 5 GHz 扫描通道假死且软开关不复位固件**：上述并发冲突发生后，WCN7850 固件会跳过所有 5 GHz 信道扫描——实测 `nl80211` 下发 26 个 2.4 GHz + 5 GHz 信道（含 `5180–5825 MHz`），未关联状态下仅耗时 `0.62 s`（恰好为 13 个 2.4 GHz 信道驻留耗时）即返回完成，全楼所有 5 GHz BSSID 计数降为 `0`。面板 Wi-Fi 开关与 `omarchy restart wifi` 仅调用 `rfkill` / `nmcli radio wifi off/on`，不会重新加载 MHI PCIe 固件，因而无法恢复。
4. **同优先级下 2.4 GHz 抢先自动连接与全局管制域未设置**：双频路由器拆分 SSID 时，两个配置的 `connection.autoconnect-priority` 默认均为 `0`，2.4 GHz 先扫出即被抢先激活；此外 `/etc/conf.d/wireless-regdom` 默认全注释，每次 `cfg80211` 触发 udev 都会令 `/usr/bin/set-wireless-regdom` 以退出码 `1` 失败，全局管制域停留在 `country 00: DFS-UNSET`。

本模块从预防、自愈与连接策略三层解决该问题：

- 为 `ath12k_wifi7_pci` 关闭扫描随机 MAC，消除切换网络时的双改 MAC 与 11d 扫描冲撞；
- 在 `/etc/conf.d/wireless-regdom` 未配置时启用 `WIRELESS_REGDOM="CN"`；
- 将已保存 5 GHz Wi-Fi 配置的 `autoconnect-priority` 从 `0` 提升至 `10`；
- 部署零轮询的内核日志监听自愈服务 `silky-ath12k-recovery.service`，一旦固件仍因极端时序上报 `received scan start failure event` 且未连上 5 GHz，约 2.5 秒内自动重载 `ath12k_wifi7` 复位固件并重扫恢复。

MacShell 面板侧的异步扫描等待与列表缓存逻辑见 [02 · 无线局域网扫描与断线恢复](02-macshell.md#无线局域网扫描与断线恢复)。

## 安装与使用

在仓库根目录运行，会提示输入一次 `sudo` 密码（若当前正处于 5 GHz 假死状态，安装过程中会自动重载驱动当场恢复）：

```bash
./scripts/install-ath12k-wifi-fix.sh
```

常用子命令：

```bash
./scripts/install-ath12k-wifi-fix.sh --status           # 只读查看配置、服务与当前 2.4/5 GHz 扫描状态（无需 sudo）
./scripts/install-ath12k-wifi-fix.sh --priorities-only  # 仅提升已保存 5 GHz Wi-Fi 自动连接优先级（无需 sudo）
./scripts/install-ath12k-wifi-fix.sh --recover          # 手动立即重载 ath12k_wifi7 复位固件（需要 sudo）
```

| 仓库文件 | 安装位置 |
| --- | --- |
| [`config/networkmanager/30-silky-ath12k-wifi.conf`](../config/networkmanager/30-silky-ath12k-wifi.conf) | `/etc/NetworkManager/conf.d/30-silky-ath12k-wifi.conf` |
| [`bin/silky-ath12k-recovery`](../bin/silky-ath12k-recovery) | `/usr/local/bin/silky-ath12k-recovery` |
| [`config/systemd/system/silky-ath12k-recovery.service`](../config/systemd/system/silky-ath12k-recovery.service) | `/etc/systemd/system/silky-ath12k-recovery.service` |

依赖：`bash`、`python3`、`nmcli`（`NetworkManager`）、`iw`、`busctl` / `systemctl` / `journalctl`（`systemd`）、`kmod`（`modprobe`）、`sudo`。安装后通过 `nmcli general reload conf` 和 `systemctl enable --now` 立即生效，无需重启或重新登录。

## 实现与兼容性

- **精准作用域**：[`30-silky-ath12k-wifi.conf`](../config/networkmanager/30-silky-ath12k-wifi.conf) 通过 `match-device=driver:ath12k_wifi7_pci` 仅匹配 `ath12k_wifi7_pci` 设备关闭 `wifi.scan-rand-mac-address`，不影响其他外接网卡，也不改动已连接状态下的 MAC 策略。
- **事件驱动零轮询自愈**：[`bin/silky-ath12k-recovery`](../bin/silky-ath12k-recovery) 在 `--watch` 模式下阻塞读取 `journalctl -kf -n 0 -o cat`，平时不产生定时唤醒。匹配到 `ath12k_wifi7_pci` 的 `received scan start failure event` 或 `failed to send WMI_START_SCAN_CMDID` 后，等待 2.5 秒观察：若网卡已凭已有 BSS 缓存关联到 `>= 5000 MHz` 频段则不打断连接；若仍卡在连接中或缓存内已无任何 5 GHz / 6 GHz BSS，则在 90 秒冷却保护下自动执行 `nmcli radio wifi off` → `modprobe -r ath12k_wifi7 ath12k` → `modprobe ath12k_wifi7` → `nmcli radio wifi on` 并触发 `RequestScan`。若内核模块因引用暂时繁忙，自动回退 PCI 驱动 `unbind` / `bind`。
- **硬件条件守卫**：[`silky-ath12k-recovery.service`](../config/systemd/system/silky-ath12k-recovery.service) 声明 `ConditionPathExists=/sys/bus/pci/drivers/ath12k_wifi7_pci`，在非 WCN7850 硬件上不会启动常驻进程。
- **连接优先级与备份**：[`scripts/install-ath12k-wifi-fix.sh`](../scripts/install-ath12k-wifi-fix.sh) 将 `802-11-wireless.band == "a"` 或名称以 `5G` / `5Ghz` / `5GHz` 结尾且原优先级为 `0` 的已保存配置设为 `10`，原值记录在 `~/.local/state/silky-omarchy/wifi-5ghz-priority.state`。系统配置文件修改前备份到 `/var/backups/silky-omarchy/`（不放在 `/etc/NetworkManager/conf.d/` 内，避免被 NetworkManager 重复加载）。
- **已知限制**：WCN7850 的 `phy#0` 为固件自管理管制域（`self-managed`），在中国大陆环境下收到周边 AP 的 `Country: CN` 信标后会按 `CN: DFS-FCC` 开放 `36–64`（`5180–5320 MHz`）与 `149–165`（`5745–5825 MHz`）信道，禁用 `100–144`（`5500–5720 MHz`）信道。若家用路由器手动锁在 `100–144` 信道，需在路由器后台改为 `36–48` 或 `149–165`。

## 验证

1. 查看安装与射频状态：

```bash
./scripts/install-ath12k-wifi-fix.sh --status
```

预期：`NetworkManager conf` 为 `installed`，`Configured WIRELESS_REGDOM` 为 `CN`，`Recovery service` 为 `active`，`Interface wlP4p1s0` 的 `5GHz` 缓存 BSS 数量大于 `0`，`5 GHz wedge detected right now: no`。

2. 验证双频切换与 5 GHz 扫描列表：

```bash
nmcli -f IN-USE,SSID,CHAN,FREQ,SIGNAL device wifi list --rescan yes
```

预期：列表中同时包含周边 `2412–2472 MHz` 与 `5180–5825 MHz` 网络；在顶栏或「系统设置 → 无线局域网」中来回切换 2.4 GHz 与 5 GHz 网络，切换过程不再在日志中产生随机扫描 MAC 翻转或 `received scan start failure event`。

验证进度：
- 脚本语法检查、本机只读 `--status` 实机故障识别、本机免密 `--priorities-only` 优先级调整、以及覆盖假死自动恢复、幂等重装、模块忙时 PCI `unbind`/`bind` 回退、`--watch` 日志触发与冷却防抖、`--uninstall` 完整还原的隔离测试均已通过。
- 本机执行 `sudo` 完整安装与 `ath12k_wifi7` 实时重载恢复待用户在终端输入密码运行 `./scripts/install-ath12k-wifi-fix.sh` 确认。

## 回滚

```bash
./scripts/install-ath12k-wifi-fix.sh --uninstall
```

该命令会停止并禁用 `silky-ath12k-recovery.service`，移除 `/etc/systemd/system/silky-ath12k-recovery.service`、`/usr/local/bin/silky-ath12k-recovery` 与 `/etc/NetworkManager/conf.d/30-silky-ath12k-wifi.conf`，按备份恢复由本脚本启用的 `/etc/conf.d/wireless-regdom`，还原已保存 Wi-Fi 连接原有的 `autoconnect-priority`，并重载 `systemd` 与 `NetworkManager` 配置。历史备份保留在 `/var/backups/silky-omarchy/`，可按需手动删除。
