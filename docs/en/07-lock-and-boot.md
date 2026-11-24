# 07 · MacLock everywhere and a macOS-style boot screen

[简体中文](../07-lock-and-boot.md) | English

## Goals

- Retire Omarchy's own lock screen; every lock uses MacShell's MacLock
- Make the boot disk-password screen look like macOS FileVault: blurred wallpaper, round avatar, user name, frosted password field

## Every way the screen gets locked

Omarchy's lock is not just one shortcut. There are four entry points, and all of them need changing:

| Entry point | Before | Now |
| --- | --- | --- |
| Super+L | MacShell already binds MacLock | Unchanged |
| Super+Ctrl+L, "Lock" in the Omarchy menu | `omarchy-system-lock` | `silky-lock` |
| 5 minutes idle | The Omarchy shell's `omarchy.idle` service calls `omarchy-system-lock` | A cloned `silky.idle` service calls `silky-lock` |
| Lid close / before sleep | User service `omarchy-sleep-lock.service` | User service `silky-sleep-lock.service`; the original is masked |

[`bin/silky-lock`](../../bin/silky-lock) locks through MacLock's IPC (`lock-via-ipc.sh`) and does the side jobs `omarchy-system-lock` used to: switch back to the default keyboard layout, lock 1Password, and stop the screensaver. Newer Omarchy releases (`omarchy-screensaver` 1.3.1+) run a standalone `/usr/lib/omarchy-screensaver/omarchy-screensaver` process instead of the legacy `ttfx` terminal window; without terminating it, the screensaver stays alive underneath MacLock and reappears after unlock. `silky-lock` now terminates that process (waiting briefly before `SIGKILL`) and restores `cursor:invisible false`, while keeping the legacy `ttfx` / `org.omarchy.screensaver` cleanup as a fallback. `silky-lock --is-locked` lets the idle service check whether the screen is already locked; `silky-lock --sleep` returns only once MacLock reports it is locked (`qs -c MacLock ipc call lockscreen state` returns `busy`).

[`bin/silky-sleep-lock`](../../bin/silky-sleep-lock) holds a logind delay inhibitor. On `PrepareForSleep` it locks with MacLock, then exits as soon as the screen is locked so the inhibitor is released and the system can sleep; systemd restarts it to take the inhibitor again for the next sleep.

### Idle service and display off

```bash
omarchy plugin clone omarchy.idle
```

A cloned plugin's id may not start with `omarchy.` (`id is reserved for first-party Omarchy plugins`), so it is renamed to `silky.idle`, keeping `"clonedFrom": "omarchy.idle"` so it still reads the `idle` config from `~/.config/omarchy/shell.json`. Then:

```bash
omarchy plugin enable silky.idle
omarchy plugin disable omarchy.idle
omarchy restart shell
```

[`config/omarchy/plugins/silky.idle/Service.qml`](../../config/omarchy/plugins/silky.idle/Service.qml) tracks upstream `omarchy.idle` (stopping `omarchy-screensaver` on user activity/exit and re-arming `IdleMonitor` when timeouts change) with two extensions:

- The lock command becomes `silky-lock`, and the "already locked?" check before the screensaver becomes `silky-lock --is-locked`
- An optional `idle.dpms` timeout in seconds (default `0`, disabled) backed by a dedicated `IdleMonitor` that respects `stay-awake`: when reached, it runs `omarchy-brightness-keyboard off; omarchy-brightness-display off` to turn off the display and keyboard backlight without suspending; any key press or pointer movement wakes the display via Hyprland and runs `omarchy-system-wake`

For example, to use 5 min screensaver, 10 min lock, and 15 min display off (no suspend) on both AC and battery, set in `~/.config/omarchy/shell.json`:

```json
"idle": {
  "screensaver": 300,
  "lock": 600,
  "dpms": 900
}
```

## Stale lock screen notifications

Restarting or reloading MacShell resets its in-memory notification list. Earlier MacShell versions wrote `~/.cache/macshell/lock-notifs.json` only when the list changed, so MacLock could keep showing old WeChat or other notifications until a new one arrived.

Run `python3 scripts/macshell_notification_center.py --install` from the repository root. The patch publishes the current list when MacShell starts or reloads. The installer backs up the user configuration and reloads MacShell, and the existing systemd user service reapplies the patch after updates. To verify, reload MacShell with an unread test notification and check that the cache becomes `[]`. Send a fresh notification with `notify-send` and check that the cache updates. For rollback, see the [Notification Center fixes](02-macshell.md#wechat-activation-and-notification-banners).

## Lock screen avatar

Changing the picture in MacShell System Settings → Users & Groups updates both the sidebar and the account page. The next MacLock session reads the same `~/.face` first and loads the picture independently of Wi-Fi queries.

Settings clips both pictures with a [Qt Quick curve-rendered circle](../../config/macshell/SilkyAccountAvatar.qml) and uses mipmap sampling when reducing the image. The selected sidebar account was compared before and after at 2× scale on this machine. At 1× scale, select the account and check the circle edge against the selection highlight.

This change was targeted at the local MacShell 0.5.3 installation. The standard installer applies it. To update the avatar alone, first back up `~/.config/quickshell/MacShell/MacDock.qml` and `~/.config/quickshell/MacLock/shell.qml`, then run the following from the repository root.

```bash
python3 scripts/tune-macshell-avatar.py ~/.config/quickshell/{MacShell/MacDock.qml,MacLock/shell.qml}
qs ipc -c MacShell call macshell reload
```

Change the picture, check the sidebar, then press `Super+L` to check the lock screen. In isolation, MacLock loaded the picture while a simulated Wi-Fi query was still running. To roll back, restore both backed-up files, remove the newly added `~/.config/quickshell/MacShell/SilkyAccountAvatar.qml`, and reload MacShell. MacLock reads the restored configuration on the next lock.

## Login wallpaper transition

This applies to Hyprland desktops using greetd and MacLock / MacShell. Boot logs on this machine showed roughly 5.2 seconds of black screen during a two-Hyprland handoff (MacShell greeter exiting → desktop Hyprland cold start): ~1.28 s closing the greeter session, ~2.57 s initializing DRM and Adreno X1-85 OpenGL ES in desktop Hyprland (even the minimal greeter Hyprland took ~2.70 s to cold-start), and ~1.08 s launching a temporary Quickshell wallpaper and decoding a 6K image. As long as two separate Hyprland compositors hand over the display, the cold-init black screen cannot be eliminated.

The transition now uses a **single Hyprland session with immediate MacLock boot locking** for a zero-black-screen unlock:

- System side: [`config/hypr/silky-login-transition/initial-session`](../../config/hypr/silky-login-transition/initial-session) installs to `/usr/local/bin/silky-boot-session` and adds `[initial_session]` to `/etc/greetd/config.toml`, launching the single desktop Hyprland on boot with `SILKY_BOOT_LOCK=1` and a one-shot pending marker. The existing `[default_session]` (`macshell-greeter`) remains intact, so logging out still returns to the standard greeter without double-locking on re-login. It also installs [`config/systemd/plymouth-quit-retain-splash.conf`](../../config/systemd/plymouth-quit-retain-splash.conf) to `/etc/systemd/system/plymouth-quit.service.d/silky-retain-splash.conf` so `plymouth quit --retain-splash` keeps the boot splash on screen until Hyprland takes over DRM.
- Desktop side: [`config/hypr/silky-login-transition/boot-lock`](../../config/hypr/silky-login-transition/boot-lock) installs to `~/.config/hypr/silky-login-transition/boot-lock` and runs first in `~/.config/hypr/autostart.lua`, invoking `qs -c MacLock` directly to bind `ext-session-lock-v1` while enabling Hyprland's `misc.session_lock_xray = true`. Non-critical Quickshell helpers ([`silky-voice.lua`](../../config/hypr/silky-voice.lua) and [`silky-keys.lua`](../../config/hypr/silky-keys.lua)) stagger startup by 3 seconds (`Super+K` still spawns SilkyKeys on demand) so MacLock and MacShell avoid first-second CPU/IO contention. The wallpaper engine, bar, and dock finish starting behind the lock; after entering the password, the lock screen fades out over 420 ms directly into the same wallpaper and desktop with **zero black screen** (normal `Super+L` unlocks benefit too).
- Security trade-off: without LUKS disk encryption, starting the user session on boot and covering it with a Wayland session lock means user background services start before the password is entered. This fits single-user personal machines; if strict pre-login session isolation is required, skip `--boot-lock` and use `--greeter` / `--greeter-mode` only.

Run from the repository root (the desktop side requires Hyprland's Lua configuration, Quickshell, and MacLock):

```bash
python3 scripts/install-login-transition.py
sudo python3 scripts/install-login-transition.py --boot-lock
```

The installer backs up replaced files and writes only to `~/.config/hypr/`, `/usr/local/bin/`, and `/etc/greetd/config.toml`—all outside package management, so routine `omarchy update` runs preserve the setup.

Optional companion flags (for the logout greeter and startup contention):

- `sudo python3 scripts/install-login-transition.py --greeter --greeter-mode 2944x1840@90`: keeps the wallpaper visible during MacShell 0.5.3 greeter exit and aligns `eDP-1` to 90 Hz (verify supported modes with `hyprctl monitors all` first).
- `python3 scripts/install-login-transition.py --defer-voice`: moves an enabled `vinput-daemon.service` (~1.7 s warmup) to a timer ~5 s after user systemd startup while keeping D-Bus on-demand activation.

Verification: `hyprctl reload && hyprctl configerrors` should report no errors and `hyprctl getoption misc:session_lock_xray` should return `bool: true`. Desktop installation, idempotent reruns, and `/etc/greetd/config.toml` apply/reapply/restore transforms were verified in isolation and live session. Full zero-black-screen boot transition awaits running `--boot-lock` and rebooting.

To roll back (takes effect on next boot):

```bash
python3 scripts/install-login-transition.py --restore
sudo python3 scripts/install-login-transition.py --boot-lock --restore
# Also undo optional flags if previously enabled:
sudo python3 scripts/install-login-transition.py --greeter --restore
python3 scripts/install-login-transition.py --defer-voice --restore
```

## Boot screen

This Plymouth theme was originally used on a setup that prompted for the LUKS disk password and then logged in automatically through SDDM. Plymouth draws the disk-unlock screen in the initramfs, before the user session starts. For the MacShell greeter on greetd, see [Login wallpaper transition](#login-wallpaper-transition).

[`plymouth/silky-maclock.script`](../../plymouth/silky-maclock.script) is a Plymouth script theme, and [`scripts/install-boot-screen.sh`](../../scripts/install-boot-screen.sh) renders its assets with ImageMagick. During non-LUKS boot, it displays a macOS-style 210u × 5u rounded progress bar (4× supersampled) centered near the bottom of the current wallpaper (108u above the bottom edge, keeping the center artwork unobstructed), sweeping smoothly with a cubic ease-out curve from 8% to 90% over Plymouth's ~0.45 s active window and holding via `plymouth quit --retain-splash` until Hyprland fades in MacLock. The disk-unlock layout matches MacLock, with values taken straight from `MacLock/LockScreen.qml`:

| Element | MacLock | Boot screen |
| --- | --- | --- |
| Unit | `u = screen height / 1200` | Same (device pixels) |
| Wallpaper | Current wallpaper, not blurred before typing | Current wallpaper, native resolution, not blurred |
| Avatar | 70u circle, 1 px 22% white outline | Same |
| User name | 15u semibold, faint shadow | Same |
| Password field | 210u × 36u pill, glass material | Same size, translucent white + hairline outline + top highlight |
| Placeholder | "Enter Password", 14u, 62% white, 16u left inset | Same |
| Position | The whole group 78u from the bottom, 10u spacing | Same |
| Clock | Large glass digits | None (Plymouth scripts cannot read the time) |

### High-resolution screens

Early versions looked soft and haloed on this 2944×1840 screen, for two reasons:

- Plymouth automatically treats a high-DPI screen as 2× scale: the script got a 1472×920 window and the whole frame was enlarged 2×. Now `/etc/plymouth/plymouthd.conf` sets `DeviceScale=1` and the script works in device pixels
- The background used to be rendered at only 1600×1000 with strong blur and extra saturation; stretched up, the bright parts bled into the dark ones. Now the background is rendered at the screen's native resolution without blur, and the avatar and password field are drawn at 4× and scaled down for smooth edges

All assets are drawn at the built-in screen's real size (`BUILD_HEIGHT` in the script) and shown unscaled there; they are scaled only on external screens of other sizes.

```bash
./scripts/install-boot-screen.sh --preview   # only writes plymouth/preview.png, changes nothing in the system
./scripts/install-boot-screen.sh             # install and rebuild the initramfs (asks for your password)
./scripts/install-boot-screen.sh --restore   # back to Omarchy's original boot screen (also removes DeviceScale=1)
```

Run it again after changing the wallpaper or avatar. Installing asks for your password and rebuilds the boot image (limine + UKI here, about 1 minute); if sudo times out waiting for the password the script stops without changing anything, so just run it again. If the theme script fails, Plymouth falls back to a plain text password prompt and the disk still unlocks.

Note: resetting Plymouth in Omarchy's settings (`omarchy-plymouth-set-by-theme`) sets the default theme back to `omarchy`; run the installer again afterwards.

## Verify

```bash
omarchy plugin list | grep idle
omarchy-shell idle status
systemctl --user is-active silky-sleep-lock omarchy-sleep-lock
systemd-inhibit --list --no-pager | grep Silky
hyprctl binds -j | jq -r '.[] | select(.key=="L") | .description'
plymouth-set-default-theme
```

Expected: `silky.idle` enabled and `omarchy.idle` disabled; `omarchy-shell idle status` shows `enabled: true`, `screensaver`/`lock`/`dpms` matching `shell.json`, and `dpmsOff: false`; `silky-sleep-lock` active and `omarchy-sleep-lock` inactive; the inhibitor list contains "Silky Omarchy"; the default Plymouth theme is `silky-maclock`.

The lock screen, idle configuration, and boot screen have been verified on real hardware; a full 5/10/15-minute idle cycle and post-unlock screensaver cleanup can be confirmed on the next idle period.

## Rollback

```bash
omarchy plugin enable omarchy.idle && omarchy plugin disable silky.idle
systemctl --user disable --now silky-sleep-lock.service
systemctl --user unmask omarchy-sleep-lock.service && systemctl --user start omarchy-sleep-lock.service
./scripts/install-boot-screen.sh --restore
```

Then remove the Super+Ctrl+L override from `~/.config/hypr/bindings.lua` and `system.lock` from `~/.config/omarchy/extensions/omarchy-menu.jsonc`.
