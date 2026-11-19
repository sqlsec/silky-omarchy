# 16 · Desktop priority: Hyprland and MacShell get the CPU / GPU first

[简体中文](../16-desktop-priority.md) | English

## What it does

When background programs saturate the CPU (builds, Chromium / Electron renderers, proxies, speech recognition), the compositor, menu bar and Dock are still scheduled first, so animations and the pointer stay smooth.

- Every thread of Hyprland, Xwayland, MacShell (`qs` / `quickshell`) and fcitx5 gets a negative nice value, so these threads run before ordinary apps when they compete for CPU time.
- Those threads also get a `uclamp.min` floor. As soon as one wakes, schedutil raises its CPU cluster to a higher clock, so the first frame doesn't wait for the clock to ramp up.
- On AC power the Adreno GPU's minimum clock is raised to 550 MHz, so the first animation after idle no longer starts at 300 MHz. On battery the original floor is restored and no extra power is used.
- Threads the app has already deprioritised keep their settings: Mesa's `disk$` / `traceq` cache threads (`SCHED_BATCH`), threads with a nice value of their own and rtkit-managed threads. Disk caching and other background work are not pulled forward.

Cause, confirmed on this machine: Hyprland and MacShell ran at nice 0, with the same weight as a dozen Chromium / Electron renderers. `hyprland.log` had dozens of libinput warnings `scheduled expiry is in the past … your system is too slow`, which means the compositor's input handling was delayed. Hyprland 0.57 does not request realtime scheduling. On the GPU side, aquamarine already gets a high-priority EGL context (`IMG_context_priority … Got a high priority context`), so nothing is needed there.

| Process | nice | uclamp.min (0–1024) |
| --- | --- | --- |
| `Hyprland` | -11 | 512 |
| `qs`, `quickshell` (MacShell / Omarchy Shell) | -8 | 384 |
| `Xwayland` | -6 | 256 |
| `fcitx5` | -6 | 256 |

No realtime policy (`SCHED_RR` / `SCHED_FIFO`) is used, so a hung compositor cannot lock up the machine. nice is capped at -15.

## Install and use

Run from the repository root. It asks for your sudo password:

```bash
./scripts/install-desktop-priority.sh
```

The script checks syntax, backs up an existing `/etc/silky/desktop-priority.conf` if it differs (`*.bak.<time>`), then installs and starts the service. It is safe to re-run:

| Repository file | Installed to |
| --- | --- |
| [`bin/silky-desktop-priority`](../../bin/silky-desktop-priority) | `/usr/local/bin/silky-desktop-priority` |
| [`config/silky/desktop-priority.conf`](../../config/silky/desktop-priority.conf) | `/etc/silky/desktop-priority.conf` |
| [`config/systemd/system/silky-desktop-priority.service`](../../config/systemd/system/silky-desktop-priority.service) | `/etc/systemd/system/silky-desktop-priority.service` |

Dependencies: `python3` and systemd. No re-login is needed. The service scans for new threads every 2 seconds, so a restarted Hyprland or MacShell is boosted again automatically.

To change processes or values, edit `/etc/silky/desktop-priority.conf` (format: `name = nice uclamp.min`), then run:

```bash
sudo systemctl restart silky-desktop-priority.service
```

Set `ac_min_freq_mhz` under `[gpu]` to `0` to drop the GPU clock floor.

## Implementation and compatibility

- The service runs as root but keeps only `CAP_SYS_NICE`, which is required to give other processes a negative nice and a `uclamp.min`. It uses `ProtectSystem=strict`, `ProtectHome` and `PrivateNetwork`, a 64 MB memory cap, and runs at nice 5 itself.
- `sched_setattr(2)` writes `SCHED_OTHER`, nice and `SCHED_FLAG_UTIL_CLAMP_MIN` in one call, thread by thread, because nice applies per thread on Linux. Syscall numbers are included for aarch64 and x86_64; other architectures fall back to nice only.
- Only processes with UID ≥ 1000 are matched, by exact `/proc/<pid>/comm`, so children of MacShell such as `python3` and `inotifywait` are not boosted. PIDs and threads are cached by start time, so each pass reads only new processes.
- On stop (`SIGTERM`), boosted threads go back to nice 0 and `uclamp.min` 0, and the GPU floor is restored.
- AC detection: any non-battery supply under `/sys/class/power_supply` with `online=1`.
- Why not cgroup weights: Hyprland starts from the greetd session, and `session-N.scope` also holds Chromium, ChatGPT and other apps launched straight from the session. Raising the scope's `CPUWeight` would boost them too, so per-process settings are more precise.
- Tested on: Lenovo Yoga Slim 7x (Snapdragon X Elite, 12 Oryon cores in 3 clusters of 4, Adreno X1-85), kernel 7.3 (`CONFIG_UCLAMP_TASK=y`, `CONFIG_PREEMPT=y`), Hyprland 0.57.2, quickshell 0.3.2, schedutil. Without uclamp in the kernel only nice applies; without a devfreq GPU the GPU part is skipped.
- Limits: the GPU context priority of Qt / quickshell can't be changed from outside, so MacShell benefits only from CPU priority and the GPU clock floor. Boosting Xwayland also helps drawing in X11 apps such as WPS and WeChat a little.

## Verify

```bash
systemctl status silky-desktop-priority.service
/usr/local/bin/silky-desktop-priority --config /etc/silky/desktop-priority.conf --status
ps -L -o tid,ni,cls,comm -p "$(pgrep -x Hyprland)"
```

Expected: the service is `active (running)`. In `--status`, `boosted` is close to the thread count for each target (the gap is the `SCHED_BATCH` cache threads and the `module-rt` reset-on-fork thread), and the main thread's nice and `uclamp.min` match the config. On AC the GPU line shows `min=550000000`.

Stress comparison (on hardware): run 12 busy processes, `stress-ng --cpu 12 --timeout 60s` (or `for i in $(seq 12); do timeout 60 sh -c 'while :; do :; done' & done`), and meanwhile drag windows, open the Control Center and switch workspaces. With the service on, animations should stay smooth and `hyprland.log` should get no new `your system is too slow` lines.

To preview which threads would change, without installing or root:

```bash
bin/silky-desktop-priority --config config/silky/desktop-priority.conf --dry-run
```

## Roll back

```bash
./scripts/install-desktop-priority.sh --uninstall
```

This stops and disables the service (which restores nice, `uclamp.min` and the GPU floor), removes `/usr/local/bin/silky-desktop-priority` and the unit file, and runs `daemon-reload`. `/etc/silky/desktop-priority.conf` and its backups are kept; delete them by hand if unwanted. No reboot or re-login is needed.
