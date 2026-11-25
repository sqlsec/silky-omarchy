#!/usr/bin/env python3
"""Read NetworkManager's Wi-Fi list with fast cache reads and reliable scan completion."""

import json
import os
import subprocess
import sys
import time

FRESH_SCAN_MS = 30_000
SCAN_WAIT_SECONDS = 22.0
POLL_INTERVAL = 0.35


def command(*args, timeout=3):
    return subprocess.run(
        args, check=True, capture_output=True, text=True, errors="replace",
        timeout=timeout, env={**os.environ, "LC_ALL": "C"},
    ).stdout


def wifi_devices():
    devices = command("nmcli", "-t", "-f", "TYPE,DBUS-PATH", "device", "status")
    return [
        path
        for kind, _, path in (line.partition(":") for line in devices.splitlines())
        if kind == "wifi" and path
    ]


def last_scan(path):
    value = command(
        "busctl", "--system", "--timeout=2s", "get-property",
        "org.freedesktop.NetworkManager", path,
        "org.freedesktop.NetworkManager.Device.Wireless", "LastScan",
    )
    return int(value.split()[1])


def request_scan(path):
    proc = subprocess.run(
        [
            "busctl", "--system", "--timeout=3s", "call",
            "org.freedesktop.NetworkManager", path,
            "org.freedesktop.NetworkManager.Device.Wireless", "RequestScan",
            "a{sv}", "0",
        ],
        capture_output=True, text=True, errors="replace",
        timeout=4, env={**os.environ, "LC_ALL": "C"},
    )
    if proc.returncode == 0:
        return "requested"
    err = (proc.stderr or proc.stdout or "").lower()
    if "not allowed" in err or "scanning" in err:
        return "throttled"
    raise RuntimeError(err.strip() or "RequestScan failed")


def emit_known(uuids):
    """K: lines, one JSON object per saved Wi-Fi profile: the SSID can differ from the profile name (hidden-2021)."""
    if not uuids:
        return
    out = command(
        "nmcli", "-t", "-f", "connection.uuid,connection.id,connection.autoconnect,802-11-wireless.ssid",
        "connection", "show", *uuids, timeout=5,
    )
    profile = {}
    for line in out.splitlines() + [""]:
        key, _, value = line.partition(":")
        if key == "connection.uuid":
            profile = {"uuid": value}
        elif key == "connection.id":
            profile["name"] = value
        elif key == "connection.autoconnect":
            profile["autoconnect"] = value == "yes"
        elif key == "802-11-wireless.ssid":
            profile["ssid"] = value
            if profile.get("uuid"):
                print("K:" + json.dumps(profile, ensure_ascii=False))


def emit_cached_list():
    networks = command(
        "nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY",
        "device", "wifi", "list", "--rescan", "no", timeout=5,
    )
    profiles = command("nmcli", "-t", "-f", "NAME,UUID,TYPE", "connection", "show", timeout=5)
    uuids = []
    for line in profiles.splitlines():
        if line.endswith(":802-11-wireless"):
            name, _, uuid = line.removesuffix(":802-11-wireless").rpartition(":")
            print("S:" + name)
            uuids.append(uuid)
    emit_known(uuids)
    for line in networks.splitlines():
        print("N:" + line)


def wifi_list(mode):
    if mode == "cached":
        emit_cached_list()
        return

    paths = wifi_devices()
    if not paths:
        raise RuntimeError("No Wi-Fi device")

    previous = {path: last_scan(path) for path in paths}

    if mode == "auto":
        now_ms = int(time.clock_gettime(time.CLOCK_BOOTTIME) * 1000)
        if any(stamp > 0 and (now_ms - stamp) <= FRESH_SCAN_MS for stamp in previous.values()):
            emit_cached_list()
            return

    requested = False
    throttled = False
    for path in paths:
        outcome = request_scan(path)
        if outcome == "requested":
            requested = True
        else:
            throttled = True

    if not requested and throttled:
        emit_cached_list()
        return

    deadline = time.monotonic() + SCAN_WAIT_SECONDS
    while time.monotonic() < deadline:
        if any(last_scan(path) > stamp for path, stamp in previous.items()):
            emit_cached_list()
            return
        time.sleep(POLL_INTERVAL)

    raise RuntimeError("No completed Wi-Fi scan")


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "refresh"
    if mode not in ("cached", "auto", "refresh"):
        sys.exit(2)
    try:
        wifi_list(mode)
    except (subprocess.SubprocessError, OSError, RuntimeError, ValueError):
        sys.exit(1)
