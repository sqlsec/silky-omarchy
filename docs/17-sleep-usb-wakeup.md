# 17 · 高通平台合盖睡眠优化：防 USB 误唤醒与 Wi-Fi 7 唤醒硬复位

简体中文 | [English](en/17-sleep-usb-wakeup.md)

## 效果与范围

本模块面向高通 Snapdragon X 笔记本（实机 Lenovo Yoga Slim 7x 83ED，内核 `7.3.0-78-omarchy`，默认 `deep` 睡眠），通过两个独立的 `systemd-sleep` 钩子解决两类合盖睡眠问题：

1. **防 `dwc3-qcom` USB 控制器每 5 分钟误唤醒**：合盖挂起期间临时关闭三个高通 USB 控制器的 `power/wakeup`，即使 USB-C 口上一直插着 YubiKey、USB 接收器或扩展坞，也不再每隔约 5 分钟自行唤醒拉高功耗；唤醒后按原状态恢复。
2. **防 `ath12k_wifi7` Wi-Fi 7 驱动唤醒硬复位重启**：挂起前卸载 `ath12k_wifi7` 模块（失败时回退为 PCI `unbind`），让 `1c08000.pcie` 干净进入 L2 低功耗态；唤醒后先执行一次内核内存规整（`/proc/sys/vm/compact_memory`），再重新加载 `ath12k_wifi7`（或重新 `bind`），消除长时间运行后开盖 1–2 秒内整机硬复位重启及日志损坏问题。

### 已确认的原因

**1. USB 误唤醒（`dwc3-qcom`）**：

- 高通 Snapdragon X 平台在电池供电下进入 `deep` 睡眠后，固件大约每 5 分钟会短暂离开一次最深睡眠态（CX collapse exit；Omarchy 上游在 [omacom/omarchy#18835](https://github.com/omacom/omarchy/pull/18835) 亦证实同一现象）。
- 系统默认将三个高通 USB 控制器（`/sys/bus/platform/drivers/dwc3-qcom/{a000000,a600000,a800000}.usb`）的 `power/wakeup` 设为 `enabled`。`dwc3-qcom` 驱动在挂起时会检查 `device_may_wakeup(dev)`，为 `true` 时把 `dp_hs_phy_irq` 等 PHY 中断注册到 PDC 作为硬件唤醒源。
- 当任一端口插着全速 USB 设备（实机为一直插在 `a000000.usb` / `usb1` 上的 `YubiKey OTP+FIDO+CCID (1050:0407)`，D+ 上拉）时，每到 5 分 00–02 秒固件退出最深睡眠的瞬间就会触发 `dp_hs_phy_irq`（实机 `IRQ 178`，`/sys/power/pm_wakeup_irq` 记录为 `178`，累计触发 19 次；合盖时空置的另外两路控制器对应的 `IRQ 182` / `IRQ 186` 均为 0 次，盖子开关 `IRQ 135 (gpio_keys)` 仅合盖与开盖各 1 次）。
- 每次误唤醒后，系统重启 12 核 CPU、重建 PCIe 与 `ath12k` Wi-Fi 并在清醒约 28 秒后由 `systemd-logind` 再次发起挂起；实测合盖 53 分钟内循环唤醒 9 次，电量从 80% 掉至 77%（平均约 1.6 W）。安装 `silky-dwc3-lid-wake` 后，实机 6 小时 51 分钟合盖期间 0 次中途误唤醒，平均待机功耗降至约 `0.67–0.74 W`（约 `1%/小时`）。

**2. 唤醒硬复位（`ath12k_wifi7` + `qcom-pcie 1c08000.pcie`）**：

- 实机两次合盖睡眠唤醒（开机约 1 小时及 8.5 小时后）均出现开盖点亮屏幕 1–2 秒内整机硬复位重启，磁盘无唤醒日志，下次启动报 `system.journal corrupted or uncleanly shut down`。
- 内核日志证实：带载挂起时 `qcom-pcie 1c08000.pcie: Timeout waiting for L2 entry! LTSSM: 0x11`；长时间运行后内存碎片化导致 `ath12k_wifi7_pci 0004:01:00.0: failed to post rx buf to pipe: 2 err: -12`，唤醒时出现 `qmi dma allocation failed (7274496 B type 1)`，极易触发底层硬件/SMMU 硬复位。

## 安装与使用

在仓库根目录运行，会提示输入 sudo 密码：

```bash
./scripts/install-sleep-usb-wakeup.sh
```

只读查看当前安装状态、各 USB 控制器 `power/wakeup` 与 `ath12k_wifi7` 模块状态（无需 sudo）：

```bash
./scripts/install-sleep-usb-wakeup.sh --status
```

| 仓库文件 | 安装位置 |
| --- | --- |
| [`config/systemd/system-sleep/silky-dwc3-lid-wake`](../config/systemd/system-sleep/silky-dwc3-lid-wake) | `/usr/lib/systemd/system-sleep/silky-dwc3-lid-wake` |
| [`config/systemd/system-sleep/silky-ath12k-sleep`](../config/systemd/system-sleep/silky-ath12k-sleep) | `/usr/lib/systemd/system-sleep/silky-ath12k-sleep` |

依赖：`bash`、`busctl`（`systemd`）、`modprobe`、`sudo`。安装脚本会先做语法检查，若目标位置已存在且内容不同，会将旧文件备份至 `/var/backups/silky-omarchy/`（不放在 `/usr/lib/systemd/system-sleep/` 目录内，避免 `systemd-sleep` 误把备份当成钩子执行），可重复运行。无需重启、重载或重新登录，下一次合盖睡眠立即生效。

## 实现与兼容性

- 钩子脚本：[`config/systemd/system-sleep/silky-dwc3-lid-wake`](../config/systemd/system-sleep/silky-dwc3-lid-wake)、[`config/systemd/system-sleep/silky-ath12k-sleep`](../config/systemd/system-sleep/silky-ath12k-sleep)；安装与卸载入口：[`scripts/install-sleep-usb-wakeup.sh`](../scripts/install-sleep-usb-wakeup.sh)。
- 参照 Omarchy 自带的 `/usr/lib/systemd/system-sleep/yoga-slim7x-lid-wake` 设计，保持独立文件，不改动 `/usr/lib/systemd/system-sleep/` 下任何软件包管理的文件。
- `silky-dwc3-lid-wake`：
  - `pre` 阶段：仅在睡眠动作为 `suspend`、`suspend-after-failed-hibernate` 或 `hybrid-sleep`，且 `org.freedesktop.login1.Manager.LidClosed` 为 `b true` 时，将当前为 `enabled` 的 `dwc3-qcom` 控制器改为 `disabled`，并将修改过的路径记录到 `/run/silky-dwc3-lid-wake.state`。
  - `post` 阶段：若状态文件存在，仅将记录过的路径写回 `enabled` 并删除状态文件。
- `silky-ath12k-sleep`：
  - `pre` 阶段：仅在 `suspend`、`suspend-after-failed-hibernate` 或 `hybrid-sleep` 且已加载 `ath12k_wifi7`（或 `ath12k_pci`）时，用带 8 秒超时的 `modprobe -r` 卸载模块并写入 `/run/silky-ath12k-sleep.state`；若模块卸载失败，回退至对应 PCI 驱动目录执行 `unbind`。任何情况下都以 0 退出，不阻塞挂起。
  - `post` 阶段：若状态文件存在，先触发一次 `/proc/sys/vm/compact_memory` 内存规整以减少 7 MB QMI DMA 分配失败，再按记录重新 `modprobe`（或 PCI `bind`）并清理状态文件，随后 NetworkManager 自动重连 Wi-Fi。
- 不受影响的功能：
  - 开盖唤醒（走 `gpio_keys`，不经 `dwc3-qcom`）；
  - 电源键唤醒（走 `pmic_pwrkey`）；
  - 合盖 USB-C PD 充电（走 `pmic-glink` / `ucsi` / `qcom-battmgr`）；
  - 开盖睡眠时外接 USB 键鼠唤醒（`LidClosed` 为 `b false` 时 `silky-dwc3-lid-wake` 直接退出）。
- 适用平台与限制：面向使用 `dwc3-qcom` 与 `ath12k_wifi7` 的高通 Snapdragon X（aarch64）笔记本（本机环境：Lenovo Yoga Slim 7x 83ED、内核 `7.3.0-78-omarchy`、`systemd 262`）。在不含对应驱动的硬件上钩子为空操作。若机器在**开盖**睡眠时插着 YubiKey 也遇到 5 分钟唤醒，可改用 udev 规则常驻关闭对应控制器的 `power/wakeup`。

## 验证

1. 安装后查看状态：

```bash
./scripts/install-sleep-usb-wakeup.sh --status
```

预期：两个钩子均为 `Hook state: installed (executable)`、`Hook content: matches repository`，列出三个 `dwc3-qcom` 控制器以及 `ath12k_wifi7` / `0004:01:00.0`。

2. 实机合盖验证（带 YubiKey，纯电池合盖 15 分钟以上后开盖）：

```bash
journalctl -b --since "20 minutes ago" -u systemd-suspend.service --no-pager | grep -E "Performing sleep|System returned"
journalctl -b -k --since "20 minutes ago" --no-pager | grep -E "Timeout waiting for L2|qmi dma allocation failed"
cat /sys/power/pm_wakeup_irq
```

预期：合盖期间只有**一次**进入挂起与**一次**返回（无 5 分钟循环唤醒）；开盖后不发生硬重启、Wi-Fi 自动重连，内核不再出现 `Timeout waiting for L2 entry`；`pm_wakeup_irq` 为盖子开关 IRQ（如 `135`）而非 `dp_hs_phy_irq`（`178`）。

验证进度：
- `silky-dwc3-lid-wake` 已在本机完成 6 小时 51 分钟合盖实测（0 次中途误唤醒）。
- `silky-ath12k-sleep` 已通过语法检查、隔离模拟测试（`modprobe` 卸载/重载、PCI `unbind`/`bind` 回退、`hibernate` 跳过、安装/卸载幂等）以及本机安装部署（`--status` 全部匹配）；长时间运行后的实机合盖唤醒稳定性待下一轮实际合盖睡眠验证。

## 回滚

```bash
./scripts/install-sleep-usb-wakeup.sh --uninstall
```

这会先恢复 `/run/silky-dwc3-lid-wake.state` 与 `/run/silky-ath12k-sleep.state` 中残留的状态（若有）并清理状态文件，再删除两个 `/usr/lib/systemd/system-sleep/silky-*` 钩子。备份文件保留在 `/var/backups/silky-omarchy/`，不需要时可手动删除。无需重启或重新登录，下次睡眠即恢复默认行为。
