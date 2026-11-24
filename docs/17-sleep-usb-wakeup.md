# 17 · 合盖睡眠防 USB 控制器误唤醒（Qualcomm `dwc3-qcom`）

简体中文 | [English](en/17-sleep-usb-wakeup.md)

## 效果与范围

合盖进入 `deep`（或 `s2idle`）挂起时，即使 USB-C 口上一直插着 YubiKey、USB 接收器或扩展坞，笔记本也不再每隔约 5 分钟自行唤醒一次，避免整段合盖睡眠被反复唤醒拉高功耗。

触发条件与已确认的原因（实机 Lenovo Yoga Slim 7x 83ED，内核 `7.3.0-78-omarchy`，默认 `deep` 睡眠）：

- 高通 Snapdragon X 平台在电池供电下进入 `deep` 睡眠后，固件大约每 5 分钟会短暂离开一次最深睡眠态（CX collapse exit；Omarchy 上游在 [omacom/omarchy#18835](https://github.com/omacom/omarchy/pull/18835) 亦证实同一现象）。
- 系统默认将三个高通 USB 控制器（`/sys/bus/platform/drivers/dwc3-qcom/{a000000,a600000,a800000}.usb`）的 `power/wakeup` 设为 `enabled`。`dwc3-qcom` 驱动在挂起时会检查 `device_may_wakeup(dev)`，为 `true` 时把 `dp_hs_phy_irq` 等 PHY 中断注册到 PDC 作为硬件唤醒源。
- 当任一端口插着全速 USB 设备（实机为一直插在 `a000000.usb` / `usb1` 上的 `YubiKey OTP+FIDO+CCID (1050:0407)`，D+ 上拉）时，每到 5 分 00–02 秒固件退出最深睡眠的瞬间就会触发 `dp_hs_phy_irq`（实机 `IRQ 178`，`/sys/power/pm_wakeup_irq` 记录为 `178`，累计触发 19 次；合盖时空置的另外两路控制器对应的 `IRQ 182` / `IRQ 186` 均为 0 次，盖子开关 `IRQ 135 (gpio_keys)` 仅合盖与开盖各 1 次）。
- 每次误唤醒后，系统重启 12 核 CPU、重建 PCIe 与 `ath12k` Wi-Fi 并在清醒约 28 秒后由 `systemd-logind` 再次发起挂起；实测合盖 53 分钟内循环唤醒 9 次，电量从 80% 掉至 77%（平均约 1.6 W）。

本优化在**合盖挂起期间**临时关闭所有 `dwc3-qcom` 控制器的 `power/wakeup`，唤醒后按原状态恢复。

## 安装与使用

在仓库根目录运行，会提示输入 sudo 密码：

```bash
./scripts/install-sleep-usb-wakeup.sh
```

只读查看当前安装状态与各控制器 `power/wakeup`（无需 sudo）：

```bash
./scripts/install-sleep-usb-wakeup.sh --status
```

| 仓库文件 | 安装位置 |
| --- | --- |
| [`config/systemd/system-sleep/silky-dwc3-lid-wake`](../config/systemd/system-sleep/silky-dwc3-lid-wake) | `/usr/lib/systemd/system-sleep/silky-dwc3-lid-wake` |

依赖：`bash`、`busctl`（`systemd`）、`sudo`。安装脚本会先做语法检查，若目标位置已存在且内容不同，会将旧文件备份至 `/var/backups/silky-omarchy/`（不放在 `/usr/lib/systemd/system-sleep/` 目录内，避免 `systemd-sleep` 误把备份当成钩子执行），可重复运行。无需重启、重载或重新登录，下一次合盖睡眠立即生效。

## 实现与兼容性

- 钩子脚本：[`config/systemd/system-sleep/silky-dwc3-lid-wake`](../config/systemd/system-sleep/silky-dwc3-lid-wake)，安装与卸载入口：[`scripts/install-sleep-usb-wakeup.sh`](../scripts/install-sleep-usb-wakeup.sh)。
- 参照 Omarchy 自带的 `/usr/lib/systemd/system-sleep/yoga-slim7x-lid-wake` 设计，但保持独立文件，不改动 `/usr/lib/systemd/system-sleep/` 下任何软件包管理的文件。
- `pre` 阶段：仅在睡眠动作为 `suspend`、`suspend-after-failed-hibernate` 或 `hybrid-sleep`，且 `org.freedesktop.login1.Manager.LidClosed` 为 `b true` 时，遍历 `/sys/bus/platform/drivers/dwc3-qcom/*/power/wakeup`，仅将当前值为 `enabled` 的控制器改为 `disabled`，并将本次修改过的路径记录到 `/run/silky-dwc3-lid-wake.state`。原本已被用户设为 `disabled` 的控制器保持不动。
- `post` 阶段：若状态文件存在，仅将记录过的路径写回 `enabled` 并删除状态文件。
- 不受影响的功能：
  - 开盖唤醒（走 `gpio_keys`，不经 `dwc3-qcom`）；
  - 电源键唤醒（走 `pmic_pwrkey`）；
  - 合盖 USB-C PD 充电（走 `pmic-glink` / `ucsi` / `qcom-battmgr`）；
  - 开盖睡眠时外接 USB 键鼠唤醒（`LidClosed` 为 `b false` 时钩子直接退出）。
- 适用平台与限制：面向使用 `dwc3-qcom` 驱动的高通 Snapdragon X（aarch64）笔记本（本机环境：Lenovo Yoga Slim 7x 83ED、内核 `7.3.0-78-omarchy`、`systemd 262`）。在非 `dwc3-qcom` 硬件上钩子为空操作。若机器不经过合盖、而是在**开盖**睡眠时插着 YubiKey 也遇到 5 分钟唤醒，可改用 udev 规则常驻关闭对应控制器的 `power/wakeup`。

## 验证

1. 安装后查看状态：

```bash
./scripts/install-sleep-usb-wakeup.sh --status
```

预期：`Hook state: installed (executable)`、`Hook content: matches repository`，且列出三个 `dwc3-qcom` 控制器。

2. 实机合盖验证（带 YubiKey，纯电池合盖 15 分钟后开盖）：

```bash
journalctl -b --since "20 minutes ago" -u systemd-suspend.service --no-pager | grep -E "Performing sleep|System returned"
cat /sys/power/pm_wakeup_irq
grep -E "^\s*(135|178|182|186):" /proc/interrupts
```

预期：15 分钟内只有**一次**进入挂起与**一次**返回（不再每 5 分钟唤醒一次）；`pm_wakeup_irq` 为盖子开关 IRQ（如 `135`）而非 `dp_hs_phy_irq`（`178`）。若需要核对高通硬件低功耗占比，可在合盖前后用 `sudo cat /sys/kernel/debug/qcom_stats/soc_sleep_stats` 对比 `CXSD` / `AOSD` 计数与累计时间。

验证进度：
- 语法检查、`--status` 本机只读检测、以及覆盖合盖挂起/恢复、开盖跳过、休眠跳过、幂等重装、差异备份与卸载恢复的隔离测试均已通过。
- 本机通过 `sudo` 安装后的 15 分钟实机合盖睡眠对比待用户安装后实测确认。

## 回滚

```bash
./scripts/install-sleep-usb-wakeup.sh --uninstall
```

这会先恢复 `/run/silky-dwc3-lid-wake.state` 中残留记录的 `power/wakeup`（若有）并清理状态文件，再删除 `/usr/lib/systemd/system-sleep/silky-dwc3-lid-wake`。备份文件保留在 `/var/backups/silky-omarchy/`，不需要时可手动删除。无需重启或重新登录，下次睡眠即恢复默认行为。
