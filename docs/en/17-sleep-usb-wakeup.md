# 17 · Prevent USB Controller Wakeups During Closed-Lid Sleep (Qualcomm `dwc3-qcom`)

[简体中文](../17-sleep-usb-wakeup.md) | English

## Effect and scope

When suspending to `deep` (or `s2idle`) with the lid closed, leaving a YubiKey, USB receiver, or dock plugged into a USB-C port no longer wakes the laptop every ~5 minutes, preventing repeated wake cycles from draining the battery during closed-lid sleep.

Trigger and confirmed root cause (measured on Lenovo Yoga Slim 7x 83ED, kernel `7.3.0-78-omarchy`, default `deep` sleep):

- On battery power in `deep` suspend, Qualcomm Snapdragon X firmware periodically leaves its deepest sleep state (CX collapse exit) roughly every 5 minutes (also documented upstream in [omacom/omarchy#18835](https://github.com/omacom/omarchy/pull/18835)).
- By default, all three Qualcomm USB controllers (`/sys/bus/platform/drivers/dwc3-qcom/{a000000,a600000,a800000}.usb`) have `power/wakeup` set to `enabled`. During suspend, `dwc3-qcom` checks `device_may_wakeup(dev)` and, when true, arms PHY wakeup interrupts such as `dp_hs_phy_irq` on the PDC.
- With a full-speed USB device attached (on this machine a `YubiKey OTP+FIDO+CCID (1050:0407)` staying plugged into `a000000.usb` / `usb1`, pulling D+ high), each 5:00–5:02 firmware CX exit fires `dp_hs_phy_irq` (`IRQ 178`; `/sys/power/pm_wakeup_irq` reported `178` with 19 interrupts, while the other two idle controllers `IRQ 182` and `IRQ 186` stayed at 0 and the lid switch `IRQ 135 (gpio_keys)` fired only twice—once on close and once on open).
- Each spurious wake brings up all 12 CPU cores, PCIe links, and `ath12k` Wi-Fi for ~28 seconds before `systemd-logind` re-suspends on the closed lid. Over a 53-minute closed-lid test, the laptop woke 9 times and dropped from 80% to 77% battery (~1.6 W average).

This hook disables `power/wakeup` on `dwc3-qcom` controllers only while suspending with the lid closed, and restores their previous state on resume.

## Installation and usage

Run from the repository root (prompts for sudo):

```bash
./scripts/install-sleep-usb-wakeup.sh
```

Inspect installation status and current controller wakeup flags without sudo:

```bash
./scripts/install-sleep-usb-wakeup.sh --status
```

| Repository file | Installed path |
| --- | --- |
| [`config/systemd/system-sleep/silky-dwc3-lid-wake`](../../config/systemd/system-sleep/silky-dwc3-lid-wake) | `/usr/lib/systemd/system-sleep/silky-dwc3-lid-wake` |

Dependencies: `bash`, `busctl` (`systemd`), `sudo`. The installer validates syntax before copying and backs up any differing existing file to `/var/backups/silky-omarchy/` (kept outside `/usr/lib/systemd/system-sleep/` so `systemd-sleep` never runs a backup as an extra hook). Safe to re-run. No reboot, reload, or re-login is needed; it takes effect on the next closed-lid suspend.

## Implementation and compatibility

- Hook script: [`config/systemd/system-sleep/silky-dwc3-lid-wake`](../../config/systemd/system-sleep/silky-dwc3-lid-wake); installer and rollback entry point: [`scripts/install-sleep-usb-wakeup.sh`](../../scripts/install-sleep-usb-wakeup.sh).
- Follows the same pattern as Omarchy's `/usr/lib/systemd/system-sleep/yoga-slim7x-lid-wake`, installed under its own `silky-` filename without touching any packaged files.
- `pre` phase: only when the sleep action is `suspend`, `suspend-after-failed-hibernate`, or `hybrid-sleep` and `org.freedesktop.login1.Manager.LidClosed` is `b true`, iterates over `/sys/bus/platform/drivers/dwc3-qcom/*/power/wakeup`, switches any controller currently `enabled` to `disabled`, and records only the modified paths in `/run/silky-dwc3-lid-wake.state`. Controllers already set to `disabled` are left alone.
- `post` phase: if the state file exists, writes `enabled` back to each recorded path and removes the state file.
- Unaffected behaviour:
  - Lid-open wakeups (`gpio_keys`, independent of `dwc3-qcom`);
  - Power-button wakeups (`pmic_pwrkey`);
  - Closed-lid USB-C PD charging (`pmic-glink` / `ucsi` / `qcom-battmgr`);
  - Open-lid USB keyboard/mouse wakeups (the hook exits immediately when `LidClosed` is `b false`).
- Compatibility and limits: targets Qualcomm Snapdragon X (`aarch64`) laptops using `dwc3-qcom` (verified environment: Lenovo Yoga Slim 7x 83ED, kernel `7.3.0-78-omarchy`, `systemd 262`). On hardware without `dwc3-qcom`, the hook is a no-op. If a YubiKey also causes 5-minute wakes during **open-lid** suspend, use a persistent udev rule to keep that controller's `power/wakeup` disabled.

## Verification

1. Check status after installing:

```bash
./scripts/install-sleep-usb-wakeup.sh --status
```

Expected: `Hook state: installed (executable)`, `Hook content: matches repository`, and all three `dwc3-qcom` controllers listed.

2. Real-hardware closed-lid test (keep the YubiKey plugged in, unplug AC, close the lid for 15 minutes, then open):

```bash
journalctl -b --since "20 minutes ago" -u systemd-suspend.service --no-pager | grep -E "Performing sleep|System returned"
cat /sys/power/pm_wakeup_irq
grep -E "^\s*(135|178|182|186):" /proc/interrupts
```

Expected: only **one** suspend entry and **one** return over the 15-minute window (no 5-minute wake loop); `pm_wakeup_irq` reports the lid switch IRQ (e.g. `135`) rather than `dp_hs_phy_irq` (`178`). To verify Qualcomm SoC deep low-power residency, compare `sudo cat /sys/kernel/debug/qcom_stats/soc_sleep_stats` (`CXSD` / `AOSD`) before and after closing the lid.

Verification status:
- Syntax checks, read-only `--status` on the target machine, and isolated tests covering closed-lid suspend/resume, open-lid skip, hibernate skip, idempotent re-install, backup-on-change, and uninstall state restoration all passed.
- A live 15-minute closed-lid test after running the `sudo` installer remains to be confirmed by the user.

## Rollback

```bash
./scripts/install-sleep-usb-wakeup.sh --uninstall
```

This restores any pending `power/wakeup` entries recorded in `/run/silky-dwc3-lid-wake.state`, deletes the state file, and removes `/usr/lib/systemd/system-sleep/silky-dwc3-lid-wake`. Any backups remain in `/var/backups/silky-omarchy/` and can be removed manually. No reboot or re-login is required; the next suspend uses the default behaviour.
