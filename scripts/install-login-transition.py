#!/usr/bin/env python3
"""Install Silky's seamless login transition (boot-lock or greeter fade)."""

import argparse
import os
import pwd
import re
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

SOURCE = Path(__file__).resolve().parents[1] / "config/hypr/silky-login-transition"
GREETER = Path("/usr/local/share/macshell-greeter/LockScreen.qml")
GREETD_CONFIG = Path("/etc/greetd/config.toml")
INITIAL_SESSION_BIN = Path("/usr/local/bin/silky-boot-session")
PLYMOUTH_DROPIN_SRC = Path(__file__).resolve().parents[1] / "config/systemd/plymouth-quit-retain-splash.conf"
PLYMOUTH_DROPIN_DST = Path("/etc/systemd/system/plymouth-quit.service.d/silky-retain-splash.conf")

# Previous autostart blocks kept for clean in-place upgrades and --restore.
OLD_STARTUP = """-- Draw the login wallpaper while the desktop wallpaper starts.
o.exec_on_start([[ /bin/bash "$HOME/.config/hypr/silky-login-transition/start" ]])

"""
PREVIOUS_STARTUP = OLD_STARTUP.replace("o.exec_on_start", """hl.layer_rule({
  match = { namespace = "^silky-login-wallpaper$" },
  no_anim = true,
  animation = "none",
})
o.exec_on_start""")
TIMED_PREVIOUS_STARTUP = "hl.config({ debug = { disable_time = false } })\n" + PREVIOUS_STARTUP

STARTUP = """-- Silky login transition: arm MacLock on boot and reveal the desktop seamlessly on unlock.
hl.config({ misc = { session_lock_xray = true } })
o.exec_on_start([[ /bin/bash "$HOME/.config/hypr/silky-login-transition/boot-lock" ]])

"""

VOICE_TIMER = Path(__file__).resolve().parents[1] / "config/systemd/silky-login-vinput.timer"
GREETER_MONITOR = GREETER.with_name("hyprland.lua.in")
MONITOR_MODE = r"[0-9]{3,5}x[0-9]{3,5}@[0-9]{2,3}(?:\.[0-9]{1,3})?"
MONITOR_MARKER = "-- Silky login transition: match the desktop's internal display."
MONITOR_ANCHOR = "\nhl.config({"
BOOT_LOCK_MARKER = "# Silky login transition: single Hyprland session with immediate MacLock."
BOOT_LOCK_BLOCK_RE = re.compile(
    r"\n?" + re.escape(BOOT_LOCK_MARKER) + r"\n\[initial_session\]\n"
    r'command = "[^"\n]+"\n'
    r'user = "[^"\n]+"\n'
)
GREETER_CHANGES = (
    ("// whole screen fades in over the (xray) desktop and back out on unlock\n"
     "    opacity: shown && !leaving ? 1 : 0",
     "// Fade in the login screen. Keep the wallpaper as the controls leave.\n"
     "    opacity: shown ? 1 : 0"),
    ("// slow settle-in zoom, and a gentle zoom-out as the lock lifts\n"
     "            scale: ls.leaving ? 1.06 : (ls.shown ? 1.0 : 1.09)",
     "// Settle to the same wallpaper crop as the desktop.\n"
     "            scale: ls.shown ? 1.0 : 1.09"),
    ("blur: ls.st.engaged ? 0.55 : 0.0\n"
     "            opacity: ls.st.engaged ? 1 : 0",
     "blur: ls.st.engaged && !ls.leaving ? 0.55 : 0.0\n"
     "            opacity: ls.st.engaged && !ls.leaving ? 1 : 0"),
    ("// top/bottom vignette so white text always reads, like the macOS lock screen\n"
     "        Rectangle {\n"
     "            anchors.fill: parent",
     "// Keep white login text readable, then clear the vignette as it leaves.\n"
     "        Rectangle {\n"
     "            anchors.fill: parent\n"
     "            opacity: ls.leaving ? 0 : 1\n"
     "            Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutQuint } }"),
)


def write(path, content, mode):
    if path.is_file() and path.read_text() == content and (path.stat().st_mode & 0o777) == mode:
        return
    if path.exists():
        backup = path.with_name(f"{path.name}.bak.silky-login-transition.{time.time_ns()}")
        shutil.copy2(path, backup)
        print(f"Backup: {backup}")
    fd, name = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.")
    temporary = Path(name)
    try:
        with os.fdopen(fd, "w") as file:
            file.write(content)
        temporary.chmod(mode)
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def greeter_config(content, restore):
    for original, updated in GREETER_CHANGES:
        before, after = (updated, original) if restore else (original, updated)
        if content.count(before) == 1 and after not in content:
            content = content.replace(before, after, 1)
        elif content.count(after) != 1 or before in content:
            raise ValueError("Unrecognized MacShell greeter layout. No changes written.")
    return content


def greeter_monitor_config(content, mode):
    rule = re.escape(MONITOR_MARKER) + r'\nhl\.monitor\(\{ output = "eDP-1", mode = "' + MONITOR_MODE + (
        r'", position = "auto", scale = 1 \}\)\n\n'
    )
    content, removed = re.subn(rule, "", content)
    if removed > 1 or MONITOR_MARKER in content:
        raise ValueError("Unrecognized Silky login display rule. No changes written.")
    if mode is None:
        return content
    if content.count(MONITOR_ANCHOR) != 1 or 'output   = ""' not in content or 'mode     = "preferred"' not in content:
        raise ValueError("Unrecognized MacShell monitor template. No changes written.")
    rule = f'{MONITOR_MARKER}\nhl.monitor({{ output = "eDP-1", mode = "{mode}", position = "auto", scale = 1 }})\n'
    return content.replace(MONITOR_ANCHOR, "\n" + rule + MONITOR_ANCHOR, 1)


def greetd_boot_lock_config(content, user, restore, command_path=str(INITIAL_SESSION_BIN)):
    cleaned, removed = BOOT_LOCK_BLOCK_RE.subn("", content)
    if removed > 1 or BOOT_LOCK_MARKER in cleaned:
        raise ValueError("Unrecognized Silky initial_session block in greetd config. No changes written.")
    if restore:
        return cleaned
    if re.search(r"^\s*\[initial_session\]\s*$", cleaned, re.MULTILINE):
        raise ValueError("greetd config already has an unmanaged [initial_session] section. No changes written.")
    anchor = "[default_session]"
    if cleaned.count(anchor) != 1:
        raise ValueError("Expected a single [default_session] section in greetd config. No changes written.")
    block = (
        f"{BOOT_LOCK_MARKER}\n"
        f"[initial_session]\n"
        f'command = "{command_path}"\n'
        f'user = "{user}"\n\n'
    )
    return cleaned.replace(anchor, block + anchor, 1)


def resolve_login_user(explicit):
    user = explicit or os.environ.get("SUDO_USER")
    if not user or user == "root":
        raise ValueError("Pass --user <username> (or run via sudo from the desktop user).")
    if not re.fullmatch(r"[a-z_][a-z0-9_-]*", user):
        raise ValueError(f"Invalid username: {user}")
    try:
        pwd.getpwnam(user)
    except KeyError as exc:
        raise ValueError(f"User does not exist: {user}") from exc
    return user


def defer_voice(restore):
    systemd = Path.home() / ".config/systemd/user"
    timer = systemd / VOICE_TIMER.name
    service = systemd / "vinput-daemon.service"
    eager = systemd / "default.target.wants" / service.name
    backup = systemd / "vinput-daemon.login-startup-backup"
    systemctl = ["systemctl", "--user"]

    if restore:
        if not backup.is_symlink():
            return
        if eager.is_symlink() and eager.readlink() != backup.readlink():
            raise ValueError("The vinput startup link was changed after installation.")
        if eager.exists() and not eager.is_symlink():
            raise ValueError("The vinput startup path was changed after installation.")
        backup.replace(eager)
        subprocess.run([*systemctl, "disable", "--now", timer.name], check=True)
        timer.unlink(missing_ok=True)
    else:
        if not backup.is_symlink() and (not eager.is_symlink() or eager.resolve() != service):
            raise ValueError("Expected vinput-daemon.service to be enabled by the user's default target.")
        write(timer, VOICE_TIMER.read_text(), 0o644)
        subprocess.run([*systemctl, "enable", timer.name], check=True)
        if eager.is_symlink() and eager.resolve() == service:
            eager.replace(backup)
    subprocess.run([*systemctl, "daemon-reload"], check=True)


def strip_all_startup_blocks(content):
    for block in (STARTUP, TIMED_PREVIOUS_STARTUP, PREVIOUS_STARTUP, OLD_STARTUP):
        content = content.replace(block, "")
    return content


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group()
    action.add_argument(
        "--boot-lock",
        action="store_true",
        help="configure greetd [initial_session] for zero-black-screen single-Hyprland boot lock",
    )
    action.add_argument("--greeter", action="store_true", help="change the system login animation")
    action.add_argument("--defer-voice", action="store_true", help="warm up vinput after the initial login workload")
    parser.add_argument("--user", metavar="USERNAME", help="desktop user for --boot-lock (defaults to $SUDO_USER)")
    parser.add_argument("--greeter-mode", metavar="WIDTHxHEIGHT@HZ", help="match the desktop mode on eDP-1")
    parser.add_argument("--restore", action="store_true", help="undo the selected change")
    args = parser.parse_args()

    if args.greeter_mode and (not args.greeter or args.restore or not re.fullmatch(MONITOR_MODE, args.greeter_mode)):
        parser.error("--greeter-mode requires --greeter and a mode such as 2944x1840@90")
    if args.user and not args.boot_lock:
        parser.error("--user is only used with --boot-lock")

    if args.boot_lock:
        if os.geteuid() != 0:
            parser.error("--boot-lock requires root")
        if not GREETD_CONFIG.is_file():
            raise ValueError(f"Missing greetd config: {GREETD_CONFIG}")
        if args.restore:
            updated = greetd_boot_lock_config(GREETD_CONFIG.read_text(), None, restore=True)
            write(GREETD_CONFIG, updated, GREETD_CONFIG.stat().st_mode & 0o777)
            INITIAL_SESSION_BIN.unlink(missing_ok=True)
            if PLYMOUTH_DROPIN_DST.exists():
                PLYMOUTH_DROPIN_DST.unlink()
                try:
                    PLYMOUTH_DROPIN_DST.parent.rmdir()
                except OSError:
                    pass
                subprocess.run(["systemctl", "daemon-reload"], check=True)
            print("Removed greetd [initial_session] boot lock and Plymouth retain-splash drop-in. Reboot to use the standard greeter.")
            return
        user = resolve_login_user(args.user)
        INITIAL_SESSION_BIN.parent.mkdir(parents=True, exist_ok=True)
        write(INITIAL_SESSION_BIN, (SOURCE / "initial-session").read_text(), 0o755)
        updated = greetd_boot_lock_config(GREETD_CONFIG.read_text(), user, restore=False)
        write(GREETD_CONFIG, updated, GREETD_CONFIG.stat().st_mode & 0o777)
        PLYMOUTH_DROPIN_DST.parent.mkdir(parents=True, exist_ok=True)
        write(PLYMOUTH_DROPIN_DST, PLYMOUTH_DROPIN_SRC.read_text(), 0o644)
        subprocess.run(["systemctl", "daemon-reload"], check=True)
        print(f"Boot-lock initial_session and Plymouth retain-splash configured for '{user}'. Reboot to test.")
        return

    if args.greeter:
        if os.geteuid() != 0:
            parser.error("--greeter requires root")
        content = greeter_config(GREETER.read_text(), args.restore)
        if args.greeter_mode or (args.restore and GREETER_MONITOR.is_file()):
            monitor = greeter_monitor_config(GREETER_MONITOR.read_text(), args.greeter_mode)
            write(GREETER_MONITOR, monitor, GREETER_MONITOR.stat().st_mode & 0o777)
        write(GREETER, content, GREETER.stat().st_mode & 0o777)
        print("Greeter configuration ready for the next login.")
        return

    if os.geteuid() == 0:
        parser.error("run the desktop installation as the desktop user")

    if args.defer_voice:
        defer_voice(args.restore)
        print("vinput startup scheduling updated.")
        return

    hypr = Path.home() / ".config/hypr"
    autostart = hypr / "autostart.lua"
    content = autostart.read_text()
    destination = hypr / SOURCE.name
    if args.restore:
        write(autostart, strip_all_startup_blocks(content), autostart.stat().st_mode & 0o777)
        for name in ("boot-lock", "shell.qml", "start"):
            (destination / name).unlink(missing_ok=True)
        print("Removed the login transition startup hook.")
        return

    if not shutil.which("qs"):
        parser.error("desktop setup requires Quickshell (qs)")
    destination.mkdir(exist_ok=True)
    write(destination / "boot-lock", (SOURCE / "boot-lock").read_text(), 0o755)
    # Remove legacy temporary-wallpaper files if present.
    for legacy in ("shell.qml", "start"):
        (destination / legacy).unlink(missing_ok=True)
    cleaned = strip_all_startup_blocks(content)
    write(autostart, STARTUP + cleaned, autostart.stat().st_mode & 0o777)
    print("Desktop boot-lock transition ready. Reload Hyprland and run --boot-lock with sudo.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
