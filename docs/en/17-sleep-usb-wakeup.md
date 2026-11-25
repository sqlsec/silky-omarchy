# 17 · Snapdragon X Closed-Lid Sleep Fixes: USB Wakeup Guard & Wi-Fi 7 Resume Hard-Reset Fix

[简体中文](../17-sleep-usb-wakeup.md) | English

## Effect and scope

Targeting Qualcomm Snapdragon X laptops (measured on Lenovo Yoga Slim 7x 83ED, kernel `7.3.0-78-omarchy`, default `deep` sleep), this module installs two independent `systemd-sleep` hooks to fix two closed-lid suspend issues:

1. **Stop `dwc3-qcom` USB 5-minute wake loops**: temporarily disables `power/wakeup` on all three Qualcomm USB controllers while suspending with the lid closed so a plugged-in YubiKey, USB receiver, or dock no longer wakes the laptop every ~5 minutes; restores previous states on resume.
2. **Prevent `ath12k_wifi7` resume hard resets**: unloads `ath12k_wifi7` before suspend (falling back to PCI `unbind`) so `1c08000.pcie` enters L2 cleanly, then compacts memory (`/proc/sys/vm/compact_memory`) and reloads `ath12k_wifi7` (or re-binds PCI) on resume, eliminating sudden SoC hard resets and journal corruption 1–2 seconds after opening the lid.

### Confirmed root causes

**1. USB spurious wakeups (`dwc3-qcom`)**:

- On battery power in `deep` suspend, Qualcomm Snapdragon X firmware periodically leaves its deepest sleep state (CX collapse exit) roughly every 5 minutes (also documented upstream in [omacom/omarchy#18835](https://github.com/omacom/omarchy/pull/18835)).
- By default, all three Qualcomm USB controllers (`/sys/bus/platform/drivers/dwc3-qcom/{a000000,a600000,a800000}.usb`) have `power/wakeup` set to `enabled`. During suspend, `dwc3-qcom` checks `device_may_wakeup(dev)` and arms PHY wakeup interrupts such as `dp_hs_phy_irq` on the PDC.
- With a full-speed USB device attached (on this machine a `YubiKey OTP+FIDO+CCID (1050:0407)` staying plugged into `a000000.usb` / `usb1`, pulling D+ high), each 5:00–5:02 firmware CX exit fires `dp_hs_phy_irq` (`IRQ 178`; `/sys/power/pm_wakeup_irq` reported `178` with 19 interrupts, while `IRQ 182` and `IRQ 186` stayed at 0 and the lid switch `IRQ 135 (gpio_keys)` fired only on close and open).
- Each spurious wake brought up all 12 CPU cores, PCIe links, and `ath12k` Wi-Fi for ~28 seconds before re-suspending (9 wakes in 53 minutes, ~1.6 W average). With `silky-dwc3-lid-wake` installed, a 6 h 51 min closed-lid test recorded 0 spurious wakes and ~`0.67–0.74 W` average drain (~`1%/hour`).

**2. Resume hard resets (`ath12k_wifi7` + `qcom-pcie 1c08000.pcie`)**:

- Two closed-lid resumes on this machine (after ~1 h and ~8.5 h of uptime) suffered an immediate SoC hard reset 1–2 seconds after opening the lid, leaving no resume logs on disk and reporting `system.journal corrupted or uncleanly shut down` on the next boot.
- Kernel logs confirmed `qcom-pcie 1c08000.pcie: Timeout waiting for L2 entry! LTSSM: 0x11` on suspend, `ath12k_wifi7_pci 0004:01:00.0: failed to post rx buf to pipe: 2 err: -12` after hours of memory fragmentation, and `qmi dma allocation failed (7274496 B type 1)` on resume.

## Installation and usage

Run from the repository root (prompts for sudo):

```bash
./scripts/install-sleep-usb-wakeup.sh
```

Inspect installation status, controller wakeup flags, and `ath12k_wifi7` module state without sudo:

```bash
./scripts/install-sleep-usb-wakeup.sh --status
```

| Repository file | Installed path |
| --- | --- |
| [`config/systemd/system-sleep/silky-dwc3-lid-wake`](../../config/systemd/system-sleep/silky-dwc3-lid-wake) | `/usr/lib/systemd/system-sleep/silky-dwc3-lid-wake` |
| [`config/systemd/system-sleep/silky-ath12k-sleep`](../../config/systemd/system-sleep/silky-ath12k-sleep) | `/usr/lib/systemd/system-sleep/silky-ath12k-sleep` |

Dependencies: `bash`, `busctl` (`systemd`), `modprobe`, `sudo`. The installer validates syntax before copying and backs up any differing existing file to `/var/backups/silky-omarchy/` (kept outside `/usr/lib/systemd/system-sleep/` so `systemd-sleep` never runs a backup as an extra hook). Safe to re-run. No reboot, reload, or re-login is needed; it takes effect on the next closed-lid suspend.

## Implementation and compatibility

- Hook scripts: [`config/systemd/system-sleep/silky-dwc3-lid-wake`](../../config/systemd/system-sleep/silky-dwc3-lid-wake), [`config/systemd/system-sleep/silky-ath12k-sleep`](../../config/systemd/system-sleep/silky-ath12k-sleep); installer and rollback entry point: [`scripts/install-sleep-usb-wakeup.sh`](../../scripts/install-sleep-usb-wakeup.sh).
- Follows the same pattern as Omarchy's `/usr/lib/systemd/system-sleep/yoga-slim7x-lid-wake`, installed under its own `silky-` filenames without touching any packaged files.
- `silky-dwc3-lid-wake`:
  - `pre` phase: only when the sleep action is `suspend`, `suspend-after-failed-hibernate`, or `hybrid-sleep` and `org.freedesktop.login1.Manager.LidClosed` is `b true`, switches any `enabled` `dwc3-qcom` controller to `disabled` and records only the modified paths in `/run/silky-dwc3-lid-wake.state`.
  - `post` phase: if the state file exists, writes `enabled` back to each recorded path and removes the state file.
- `silky-ath12k-sleep`:
  - `pre` phase: for `suspend`, `suspend-after-failed-hibernate`, or `hybrid-sleep` when `ath12k_wifi7` (or `ath12k_pci`) is loaded, runs `modprobe -r` with an 8 s timeout and records the module in `/run/silky-ath12k-sleep.state`; if unloading fails, falls back to writing each device BDF to PCI `unbind`. Always exits 0 so suspend is never blocked.
  - `post` phase: if the state file exists, triggers `/proc/sys/vm/compact_memory` to ease contiguous 7 MB QMI DMA allocation, reloads the recorded module (or writes back PCI `bind`), and removes the state file; NetworkManager reconnects Wi-Fi automatically.
- Unaffected behaviour:
  - Lid-open wakeups (`gpio_keys`, independent of `dwc3-qcom`);
  - Power-button wakeups (`pmic_pwrkey`);
  - Closed-lid USB-C PD charging (`pmic-glink` / `ucsi` / `qcom-battmgr`);
  - Open-lid USB keyboard/mouse wakeups (`silky-dwc3-lid-wake` exits immediately when `LidClosed` is `b false`).
- Compatibility and limits: targets Qualcomm Snapdragon X (`aarch64`) laptops using `dwc3-qcom` and `ath12k_wifi7` (verified environment: Lenovo Yoga Slim 7x 83ED, kernel `7.3.0-78-omarchy`, `systemd 262`). On hardware without those drivers, both hooks are no-ops. If a YubiKey also causes 5-minute wakes during **open-lid** suspend, use a persistent udev rule to keep that controller's `power/wakeup` disabled.

## Verification

1. Check status after installing:

```bash
./scripts/install-sleep-usb-wakeup.sh --status
```

Expected: both hooks report `Hook state: installed (executable)` and `Hook content: matches repository`, listing all three `dwc3-qcom` controllers and `ath12k_wifi7` / `0004:01:00.0`.

2. Real-hardware closed-lid test (keep the YubiKey plugged in, unplug AC, close the lid for 15+ minutes, then open):

```bash
journalctl -b --since "20 minutes ago" -u systemd-suspend.service --no-pager | grep -E "Performing sleep|System returned"
journalctl -b -k --since "20 minutes ago" --no-pager | grep -E "Timeout waiting for L2|qmi dma allocation failed"
cat /sys/power/pm_wakeup_irq
```

Expected: only **one** suspend entry and **one** return (no 5-minute wake loop); no hard reset on wake, Wi-Fi reconnects automatically, no `Timeout waiting for L2 entry` in dmesg, and `pm_wakeup_irq` reports the lid switch IRQ (e.g. `135`) rather than `dp_hs_phy_irq` (`178`).

Verification status:
- `silky-dwc3-lid-wake` is confirmed on real hardware across a 6 h 51 min closed-lid sleep (0 spurious wakes).
- `silky-ath12k-sleep` passed syntax checks, isolated sandbox tests (`modprobe` unload/reload, PCI `unbind`/`bind` fallback, `hibernate` skip, idempotent install/uninstall), and live installation (`--status` matches repository); long-uptime closed-lid resume stability awaits the next live sleep cycle.

## Rollback

```bash
./scripts/install-sleep-usb-wakeup.sh --uninstall
```

This restores any pending state recorded in `/run/silky-dwc3-lid-wake.state` and `/run/silky-ath12k-sleep.state`, deletes the state files, and removes both `/usr/lib/systemd/system-sleep/silky-*` hooks. Any backups remain in `/var/backups/silky-omarchy/` and can be removed manually. No reboot or re-login is required; the next suspend uses the default behaviour.
