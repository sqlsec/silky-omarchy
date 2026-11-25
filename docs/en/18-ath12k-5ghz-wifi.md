# 18 · Fix 5 GHz Wi-Fi Connection Stalls and Disappearing Networks (Qualcomm `ath12k_wifi7`)

[简体中文](../18-ath12k-5ghz-wifi.md) | English

## Effect and scope

On Qualcomm FastConnect 7800 (WCN7850, `ath12k_wifi7_pci`) wireless adapters, switching from 2.4 GHz to 5 GHz, waking from sleep, or reconnecting no longer stalls on "Connecting…" for 25 seconds and fails, and no longer leaves every nearby 5 GHz Wi-Fi network missing from scan results until reboot. Saved 5 GHz networks are also preferred automatically on boot and wake.

Trigger and confirmed root cause (measured on Lenovo Yoga Slim 7x 83ED, `WCN785x [17cb:1107]`, kernel `7.3.0-78-omarchy`, firmware `WLAN.HMT.1.1.c7-00108`, `NetworkManager 1.58.1` + `wpa_supplicant 2.12`):

1. **Back-to-back MAC flips within ~70 ms collide firmware 11d scans with association scans**: NetworkManager enables `wifi.scan-rand-mac-address=yes` by default. Disconnecting from 2.4 GHz to activate a 5 GHz profile flips the adapter to a random scan MAC (`set-hw-addr (scanning)`) and, ~70 ms later during connection preparation, flips it back to the permanent MAC (`set-hw-addr (preserve)`). On `ath12k`, tearing down and recreating the vdev restarts firmware `11d` country scans (`ath12k_mac_11d_scan_start`) and emits four `CTRL-EVENT-REGDOM-CHANGE` events in ~80 ms. When `wpa_supplicant` issues `WMI_START_SCAN_CMDID` 8 ms later, firmware rejects it with `ath12k_wifi7_pci 0004:01:00.0: received scan start failure event`.
2. **An `ath12k` scan state-machine race stalls activation for 25 seconds**: Disassembling `ath12k.ko` confirms that when `ath12k_wmi_op_rx` receives `WMI_SCAN_EVENT_START_FAILED` in `ATH12K_SCAN_STARTING (1)`, it only queues `vdev_clean_wk` on `wiphy_work_queue` and calls `complete(&ar->scan.started)` without clearing `ar->scan.state` first. Because `ath12k_start_scan` holds `wiphy_lock`, the queued work cannot run yet; `ath12k_start_scan` wakes up, sees `ar->scan.state == 1 != 0`, assumes the scan started, and returns `0`. `wpa_supplicant` then waits on a scan that never started while the UI shows "Connecting…" for 25 seconds until NetworkManager aborts with `ssid-not-found`.
3. **5 GHz scanning stays wedged in firmware across soft radio toggles**: After that collision, WCN7850 firmware skips every 5 GHz channel during scans—an `nl80211` scan across 26 channels (2.4 GHz + `5180–5825 MHz`) finishes in `0.62 s` while disconnected (matching only the 13 channels on 2.4 GHz) and reports zero 5 GHz BSSIDs. Toggling Wi-Fi in the UI or running `omarchy restart wifi` only toggles soft `rfkill` / `nmcli radio wifi` without reloading the MHI PCIe firmware, so 5 GHz never comes back until the module is reloaded or the laptop reboots.
4. **Equal autoconnect priorities and unset global regdomain**: Split-SSID 2.4 GHz and 5 GHz profiles both default to `connection.autoconnect-priority = 0`, letting 2.4 GHz win whenever it finishes scanning first. Meanwhile `/etc/conf.d/wireless-regdom` has every entry commented out, causing `/usr/bin/set-wireless-regdom` to exit with code `1` on udev events and leaving the global regdomain at `country 00: DFS-UNSET`.

This module addresses the issue across prevention, self-healing, and connection policy:

- Disables random scan MACs on `ath12k_wifi7_pci` so network switches no longer flip the MAC twice or restart colliding 11d scans;
- Enables `WIRELESS_REGDOM="CN"` in `/etc/conf.d/wireless-regdom` when no country is configured;
- Raises `connection.autoconnect-priority` from `0` to `10` on saved 5 GHz profiles;
- Runs an event-driven, zero-polling journal watcher (`silky-ath12k-recovery.service`) that reloads `ath12k_wifi7` within ~2.5 seconds if firmware ever emits `received scan start failure event` without landing on a 5 GHz link.

For MacShell's asynchronous scan waiting and cache handling in the UI, see [02 · Wi-Fi scanning and recovery](02-macshell.md#wi-fi-scanning-and-recovery).

## Installation and usage

Run from the repository root (prompts once for `sudo`; if the 5 GHz radio is currently wedged, the installer automatically reloads `ath12k_wifi7` to recover it immediately):

```bash
./scripts/install-ath12k-wifi-fix.sh
```

Subcommands:

```bash
./scripts/install-ath12k-wifi-fix.sh --status           # Read-only status and 2.4/5 GHz BSS counts (no sudo)
./scripts/install-ath12k-wifi-fix.sh --priorities-only  # Prefer saved 5 GHz profiles over 2.4 GHz (no sudo)
./scripts/install-ath12k-wifi-fix.sh --recover          # Reload ath12k_wifi7 now to reset firmware (uses sudo)
```

| Repository file | Installed path |
| --- | --- |
| [`config/networkmanager/30-silky-ath12k-wifi.conf`](../../config/networkmanager/30-silky-ath12k-wifi.conf) | `/etc/NetworkManager/conf.d/30-silky-ath12k-wifi.conf` |
| [`bin/silky-ath12k-recovery`](../../bin/silky-ath12k-recovery) | `/usr/local/bin/silky-ath12k-recovery` |
| [`config/systemd/system/silky-ath12k-recovery.service`](../../config/systemd/system/silky-ath12k-recovery.service) | `/etc/systemd/system/silky-ath12k-recovery.service` |

Dependencies: `bash`, `python3`, `nmcli` (`NetworkManager`), `iw`, `busctl` / `systemctl` / `journalctl` (`systemd`), `kmod` (`modprobe`), `sudo`. Changes take effect immediately via `nmcli general reload conf` and `systemctl enable --now`; no reboot or re-login is needed.

## Implementation and compatibility

- **Scoped NetworkManager rule**: [`30-silky-ath12k-wifi.conf`](../../config/networkmanager/30-silky-ath12k-wifi.conf) uses `match-device=driver:ath12k_wifi7_pci` to set `wifi.scan-rand-mac-address=no` only on WCN7850 adapters without affecting other interfaces or connected-state MAC policies.
- **Event-driven, zero-polling recovery**: [`bin/silky-ath12k-recovery`](../../bin/silky-ath12k-recovery) (`--watch`) blocks on `journalctl -kf -n 0 -o cat` with zero periodic wakeups. When `ath12k_wifi7_pci` logs `received scan start failure event` or `failed to send WMI_START_SCAN_CMDID`, it waits 2.5 seconds: if the adapter already associated onto `>= 5000 MHz` from cached scan results, it leaves the connection untouched; if it is still stuck connecting or has zero cached 5 GHz / 6 GHz BSSIDs, it enforces a 90-second cooldown and runs `nmcli radio wifi off` → `modprobe -r ath12k_wifi7 ath12k` → `modprobe ath12k_wifi7` → `nmcli radio wifi on` followed by `RequestScan`. If `modprobe -r` is busy, it falls back to PCI driver `unbind` / `bind`.
- **Hardware guard**: [`silky-ath12k-recovery.service`](../../config/systemd/system/silky-ath12k-recovery.service) sets `ConditionPathExists=/sys/bus/pci/drivers/ath12k_wifi7_pci`, so non-WCN7850 machines run no background process.
- **Connection priorities and backups**: [`scripts/install-ath12k-wifi-fix.sh`](../../scripts/install-ath12k-wifi-fix.sh) raises `connection.autoconnect-priority` from `0` to `10` on saved profiles with `802-11-wireless.band == "a"` or names ending in `5G` / `5Ghz` / `5GHz`, saving original priorities in `~/.local/state/silky-omarchy/wifi-5ghz-priority.state`. Existing system configs are backed up to `/var/backups/silky-omarchy/` (kept outside `/etc/NetworkManager/conf.d/` so NetworkManager never parses backup files).
- **Known limits**: WCN7850 uses a firmware `self-managed` regulatory domain (`phy#0`). Under `CN: DFS-FCC` (learned from nearby AP Country IEs), channels `36–64` (`5180–5320 MHz`) and `149–165` (`5745–5825 MHz`) are enabled while `100–144` (`5500–5720 MHz`) are disabled. Routers manually pinned to channels `100–144` should be moved to `36–48` or `149–165`.

## Verification

1. Inspect installation and radio health:

```bash
./scripts/install-ath12k-wifi-fix.sh --status
```

Expected: `NetworkManager conf` is `installed`, `Configured WIRELESS_REGDOM` is `CN`, `Recovery service` is `active`, `Interface wlP4p1s0` reports non-zero `5GHz` cached BSSIDs, and `5 GHz wedge detected right now: no`.

2. Verify dual-band visibility and switching:

```bash
nmcli -f IN-USE,SSID,CHAN,FREQ,SIGNAL device wifi list --rescan yes
```

Expected: both `2412–2472 MHz` and `5180–5825 MHz` networks appear; switching between 2.4 GHz and 5 GHz in the menu bar or System Settings completes without scan-MAC flips or `received scan start failure event` in the journal.

Verification status:
- Syntax checks, live read-only `--status` wedge detection on the target laptop, passwordless `--priorities-only` tuning on the target laptop, and isolated end-to-end tests covering active-wedge recovery, idempotent re-install, PCI `unbind`/`bind` fallback, `--watch` auto-recovery with cooldown debounce, and `--uninstall` state restoration all passed.
- Running the full `sudo` installer (`./scripts/install-ath12k-wifi-fix.sh`) on the live machine to reload `ath12k_wifi7` and persist `/etc` units awaits user password entry in a terminal.

## Rollback

```bash
./scripts/install-ath12k-wifi-fix.sh --uninstall
```

This stops and disables `silky-ath12k-recovery.service`, removes `/etc/systemd/system/silky-ath12k-recovery.service`, `/usr/local/bin/silky-ath12k-recovery`, and `/etc/NetworkManager/conf.d/30-silky-ath12k-wifi.conf`, restores `/etc/conf.d/wireless-regdom` if managed by the installer, restores recorded `autoconnect-priority` values on saved Wi-Fi profiles, and reloads `systemd` and `NetworkManager`. Backups remain in `/var/backups/silky-omarchy/`.
