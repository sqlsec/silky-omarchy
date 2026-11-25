#!/usr/bin/python3
"""Silky Omarchy: Wi-Fi details for MacShell (the Option-click view and Settings → Wi-Fi → Details…).

Prints one JSON object for the first Wi-Fi device: interface name, hardware addresses, and, while connected, the same
fields macOS shows: IP address, router, security, BSSID, channel / band / width, country code, RSSI, noise, Tx rate,
PHY mode, MCS index and NSS. Sources: nmcli, NetworkManager over busctl, and iw (link, survey dump, reg get).
Fields that a driver does not report are left out. Needs: NetworkManager, iw.
"""
import json
import os
import re
import subprocess

ENV = {**os.environ, "LC_ALL": "C"}


def run(*args, timeout=3):
    try:
        return subprocess.run(args, capture_output=True, text=True, errors="replace", timeout=timeout, env=ENV).stdout
    except (OSError, subprocess.SubprocessError):
        return ""


def nm_fields(text):
    out = {}
    for line in text.splitlines():
        key, _, value = line.partition(":")
        out.setdefault(key, value)
    return out


def unescape(value):
    return value.replace("\\:", ":").replace("\\\\", "\\")


def security_label(sec, key_mgmt):
    sec = sec or ""
    if key_mgmt == "wpa-eap" or "802.1X" in sec:
        kind = "enterprise"
    elif key_mgmt in ("", "none") and not sec.strip():
        return "", ""
    else:
        kind = "personal"
    parts = [p for p in ("WEP", "WPA1", "WPA2", "WPA3") if p in sec]
    if not parts and key_mgmt == "sae":
        parts = ["WPA3"]
    if not parts and key_mgmt == "wpa-psk":
        parts = ["WPA2"]
    names = "/".join("WPA" if p == "WPA1" else p for p in parts) or sec.strip()
    return names, ("" if names == "WEP" else kind)


def main():
    devices = run("nmcli", "-t", "-f", "DEVICE,TYPE,DBUS-PATH", "device", "status")
    iface = path = ""
    for line in devices.splitlines():
        parts = line.split(":")
        if len(parts) >= 3 and parts[1] == "wifi":
            iface, path = parts[0], parts[2]
            break
    info = {"iface": iface}
    if not iface:
        print(json.dumps(info))
        return

    perm = run("busctl", "--system", "--timeout=2s", "get-property", "org.freedesktop.NetworkManager", path,
               "org.freedesktop.NetworkManager.Device.Wireless", "PermHwAddress")
    match = re.search(r'"([0-9A-Fa-f:]{17})"', perm)
    if match:
        info["hwaddr"] = match.group(1).lower()

    dev = nm_fields(run("nmcli", "-t", "-f", "GENERAL.HWADDR,GENERAL.STATE,GENERAL.CONNECTION,IP4.ADDRESS,IP4.GATEWAY",
                        "device", "show", iface))
    state = dev.get("GENERAL.STATE", "")
    info["connected"] = state.startswith("100")
    if not info["connected"]:
        print(json.dumps(info, ensure_ascii=False))
        return
    info["mac"] = unescape(dev.get("GENERAL.HWADDR", "")).lower()
    info["ip"] = dev.get("IP4.ADDRESS[1]", "").split("/")[0]
    info["router"] = dev.get("IP4.GATEWAY", "")
    connection = dev.get("GENERAL.CONNECTION", "")

    key_mgmt = ""
    if connection:
        key_mgmt = nm_fields(run("nmcli", "-t", "-f", "802-11-wireless-security.key-mgmt", "connection", "show",
                                 "id", connection)).get("802-11-wireless-security.key-mgmt", "")

    link = run("iw", "dev", iface, "link")
    bssid = re.search(r"Connected to ([0-9a-f:]{17})", link)
    if bssid:
        info["bssid"] = bssid.group(1)
    ssid = re.search(r"^\s*SSID: (.*)$", link, re.M)
    if ssid:
        info["ssid"] = ssid.group(1)
    signal = re.search(r"signal: (-?\d+) dBm", link)
    if signal:
        info["rssi"] = int(signal.group(1))
    tx = re.search(r"tx bitrate: ([\d.]+) MBit/s(.*)", link)
    if tx:
        info["txRate"] = round(float(tx.group(1)))
        flags = tx.group(2)
        for prefix, phy in (("EHT", "802.11be"), ("HE", "802.11ax"), ("VHT", "802.11ac"), ("", "802.11n")):
            mcs = re.search(prefix + r"-?MCS (\d+)" if prefix else r"\bMCS (\d+)", flags)
            if mcs:
                info["phy"] = phy
                info["mcs"] = int(mcs.group(1))
                nss = re.search(prefix + r"-NSS (\d+)", flags) if prefix else None
                if nss:
                    info["nss"] = int(nss.group(1))
                break

    chan = re.search(r"channel (\d+) \((\d+) MHz\), width: (\d+) MHz", run("iw", "dev", iface, "info"))
    if chan:
        freq = int(chan.group(2))
        info["channel"] = int(chan.group(1))
        info["band"] = "6 GHz" if freq >= 5925 else ("5 GHz" if freq >= 4900 else "2.4 GHz")
        info["width"] = int(chan.group(3))
        survey = run("iw", "dev", iface, "survey", "dump")
        for block in survey.split("Survey data from")[1:]:
            if "[in use]" in block:
                noise = re.search(r"noise:\s+(-?\d+) dBm", block)
                if noise:
                    info["noise"] = int(noise.group(1))

    country = re.search(r"country (\w\w):", run("iw", "reg", "get"))
    if country and country.group(1) != "00":
        info["country"] = country.group(1)

    aps = run("nmcli", "-t", "-f", "ACTIVE,SECURITY", "device", "wifi", "list", "ifname", iface, "--rescan", "no")
    sec = ""
    for line in aps.splitlines():
        if line.startswith("yes:"):
            sec = line[4:]
            break
    name, kind = security_label(sec, key_mgmt)
    info["security"] = name          # "" = open network
    info["securityKind"] = kind      # personal | enterprise | ""
    print(json.dumps(info, ensure_ascii=False))


if __name__ == "__main__":
    main()
