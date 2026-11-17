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

[`bin/silky-lock`](../../bin/silky-lock) locks through MacLock's IPC (`lock-via-ipc.sh`) and does the side jobs `omarchy-system-lock` used to: switch back to the default keyboard layout, lock 1Password, stop the screensaver. `silky-lock --is-locked` lets the idle service check whether the screen is already locked; `silky-lock --sleep` returns only once MacLock reports it is locked (`qs -c MacLock ipc call lockscreen state` returns `busy`).

[`bin/silky-sleep-lock`](../../bin/silky-sleep-lock) holds a logind delay inhibitor. On `PrepareForSleep` it locks with MacLock, then exits as soon as the screen is locked so the inhibitor is released and the system can sleep; systemd restarts it to take the inhibitor again for the next sleep.

### Idle service

```bash
omarchy plugin clone omarchy.idle
```

A cloned plugin's id may not start with `omarchy.` (`id is reserved for first-party Omarchy plugins`), so it is renamed to `silky.idle`, keeping `"clonedFrom": "omarchy.idle"` so it still reads the `idle.screensaver` / `idle.lock` timeouts from `shell.json`. Then:

```bash
omarchy plugin enable silky.idle
omarchy plugin disable omarchy.idle
omarchy restart shell
```

`Service.qml` changes in two lines only: the lock command becomes `silky-lock`, and the "already locked?" check before the screensaver becomes `silky-lock --is-locked`.

## Boot screen

This machine's disk is LUKS-encrypted: at boot you type the disk password in Plymouth, after which SDDM logs in automatically (`/etc/sddm.conf.d/autologin.conf`). So the "boot login screen" is Plymouth's unlock screen. It runs inside the initramfs, before any user program exists, so MacLock itself cannot run there; the best we can do is a Plymouth theme that looks the same.

[`plymouth/silky-maclock.script`](../../plymouth/silky-maclock.script) is a Plymouth script theme, and [`scripts/install-boot-screen.sh`](../../scripts/install-boot-screen.sh) renders its assets with ImageMagick. The layout matches MacLock, with values taken straight from `MacLock/LockScreen.qml`:

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
systemctl --user is-active silky-sleep-lock omarchy-sleep-lock
systemd-inhibit --list --no-pager | grep Silky
hyprctl binds -j | jq -r '.[] | select(.key=="L") | .description'
plymouth-set-default-theme
```

Expected: `silky.idle` enabled and `omarchy.idle` disabled; `silky-sleep-lock` active and `omarchy-sleep-lock` inactive; the inhibitor list contains "Silky Omarchy"; the default Plymouth theme is `silky-maclock`.

Both the lock screen and the boot screen have been confirmed on real hardware.

## Rollback

```bash
omarchy plugin enable omarchy.idle && omarchy plugin disable silky.idle
systemctl --user disable --now silky-sleep-lock.service
systemctl --user unmask omarchy-sleep-lock.service && systemctl --user start omarchy-sleep-lock.service
./scripts/install-boot-screen.sh --restore
```

Then remove the Super+Ctrl+L override from `~/.config/hypr/bindings.lua` and `system.lock` from `~/.config/omarchy/extensions/omarchy-menu.jsonc`.
