#!/usr/bin/env python3
"""Collect network services and VPN entries for MacShell Settings -> Network."""
import json
import os
import re
import shutil
import subprocess
import sys


def run_cmd(args, timeout=3):
    try:
        res = subprocess.run(
            args,
            capture_output=True,
            text=True,
            timeout=timeout,
            env={**os.environ, "LC_ALL": "C"},
        )
        return res.returncode, res.stdout
    except (OSError, subprocess.SubprocessError):
        return 1, ""


def split_nmcli_line(line):
    """Split a terse nmcli line on unescaped colons."""
    fields = []
    buf = []
    escaped = False
    for ch in line:
        if escaped:
            buf.append(ch)
            escaped = False
        elif ch == "\\":
            escaped = True
        elif ch == ":":
            fields.append("".join(buf))
            buf = []
        else:
            buf.append(ch)
    fields.append("".join(buf))
    return fields


def get_ipv4_map():
    rc, out = run_cmd(["ip", "-4", "-o", "addr", "show"])
    ips = {}
    if rc != 0:
        return ips
    for line in out.splitlines():
        parts = line.split()
        if len(parts) >= 4:
            dev = parts[1]
            addr = parts[3]
            if dev not in ips:
                ips[dev] = addr
    return ips


def read_eth_speed(dev):
    try:
        val = int(open(f"/sys/class/net/{dev}/speed").read().strip())
        return str(val) if val > 0 else ""
    except (OSError, ValueError):
        return ""


def get_wifi_radio():
    rc, out = run_cmd(["nmcli", "radio", "wifi"])
    if rc != 0:
        return True
    return out.strip().lower() == "enabled"


def detect_external_tun_label(dev, con):
    low = (dev or "").lower()
    if low == "tailscale0":
        return "Tailscale", ""
    if low.startswith("zt"):
        return "ZeroTier", dev
    if low in {"meta", "mihomo", "clash", "utun"} or "clash" in low or "mihomo" in low:
        return "Clash Verge", dev
    if low.startswith("wg"):
        return con or dev, dev
    return con or dev, dev


def state_to_kind(state, dev_type, wifi_on):
    s = (state or "").lower()
    if s.startswith("connected"):
        return "connected"
    if s.startswith("connecting") or s.startswith("deactivating") or s.startswith("disconnecting"):
        return "connecting"
    if dev_type == "wifi" and not wifi_on:
        return "off"
    if dev_type == "ethernet" and s == "unavailable":
        return "unplugged"
    return "disconnected"


def collect():
    ips = get_ipv4_map()
    wifi_on = get_wifi_radio()
    has_tailscale = shutil.which("tailscale") is not None

    # 1. Active & saved NM connections (used to surface controllable VPN / WireGuard / TUN profiles)
    nm_vpns = []
    nm_vpn_devs = set()
    nm_dev_uuid = {}
    rc, con_out = run_cmd(["nmcli", "-t", "-f", "NAME,UUID,TYPE,DEVICE,STATE", "connection", "show"])
    if rc == 0:
        for raw in con_out.splitlines():
            if not raw.strip():
                continue
            fields = split_nmcli_line(raw)
            if len(fields) < 5:
                continue
            name, uuid, ctype, dev, state = fields[:5]
            if dev and dev != "--":
                nm_dev_uuid[dev] = (uuid, ctype, name)
            if ctype in {"vpn", "wireguard"}:
                st = state.lower()
                if st == "activated":
                    kind = "connected"
                elif st in {"activating", "deactivating"}:
                    kind = "connecting"
                else:
                    kind = "disconnected"
                dev_clean = "" if dev in {"", "--"} else dev
                if dev_clean:
                    nm_vpn_devs.add(dev_clean)
                nm_vpns.append({
                    "id": f"nm:{uuid}",
                    "name": name,
                    "detail": "WireGuard" if ctype == "wireguard" else "",
                    "dev": dev_clean,
                    "ip": ips.get(dev_clean, "") if dev_clean else "",
                    "statusKind": kind,
                    "controllable": True,
                    "backend": "nm",
                    "uuid": uuid,
                    "external": False,
                })

    # 2. Devices from nmcli dev
    services = []
    tun_vpns = []
    rc, dev_out = run_cmd(["nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "dev"])
    if rc == 0:
        for raw in dev_out.splitlines():
            if not raw.strip():
                continue
            fields = split_nmcli_line(raw)
            if len(fields) < 3:
                continue
            dev = fields[0]
            dtype = fields[1]
            state = fields[2]
            con = fields[3] if len(fields) > 3 and fields[3] != "--" else ""

            if dtype in {"loopback", "wifi-p2p", "bridge", "dummy", "veth", "docker"}:
                continue
            if dev in nm_vpn_devs:
                continue

            if dtype in {"wifi", "ethernet"}:
                kind = state_to_kind(state, dtype, wifi_on)
                services.append({
                    "dev": dev,
                    "type": dtype,
                    "state": state,
                    "statusKind": kind,
                    "con": con if kind == "connected" else "",
                    "ip": ips.get(dev, "") if kind == "connected" else "",
                    "speed": read_eth_speed(dev) if (dtype == "ethernet" and kind == "connected") else "",
                })
            elif dtype in {"tun", "wireguard", "vpn"}:
                external = "(externally)" in state.lower()
                kind = state_to_kind(state, dtype, wifi_on)
                title, detail = detect_external_tun_label(dev, con)
                if dev == "tailscale0":
                    tun_vpns.append({
                        "id": "tailscale:tailscale0",
                        "name": "Tailscale",
                        "detail": dev,
                        "dev": dev,
                        "ip": ips.get(dev, ""),
                        "statusKind": kind,
                        "controllable": has_tailscale,
                        "backend": "tailscale" if has_tailscale else "external",
                        "uuid": "",
                        "external": not has_tailscale,
                    })
                elif not external and dev in nm_dev_uuid:
                    uuid, _, cname = nm_dev_uuid[dev]
                    tun_vpns.append({
                        "id": f"nm:{uuid}",
                        "name": cname or title,
                        "detail": dev if (cname and cname != dev) else "",
                        "dev": dev,
                        "ip": ips.get(dev, ""),
                        "statusKind": kind,
                        "controllable": True,
                        "backend": "nm",
                        "uuid": uuid,
                        "external": False,
                    })
                else:
                    tun_vpns.append({
                        "id": f"ext:{dev}",
                        "name": title,
                        "detail": detail if detail != title else "",
                        "dev": dev,
                        "ip": ips.get(dev, ""),
                        "statusKind": kind,
                        "controllable": False,
                        "backend": "external",
                        "uuid": "",
                        "external": True,
                    })

    # Sort services: Wi-Fi first, then Ethernet, then others; connected first within same type.
    type_order = {"wifi": 0, "ethernet": 1}
    services.sort(key=lambda s: (type_order.get(s["type"], 9), 0 if s["statusKind"] == "connected" else 1, s["dev"]))

    # Sort VPNs: controllable connected first, controllable disconnected next, then external active.
    vpns = nm_vpns + tun_vpns
    vpns.sort(key=lambda v: (
        0 if v["controllable"] else 1,
        0 if v["statusKind"] == "connected" else (1 if v["statusKind"] == "connecting" else 2),
        v["name"].lower(),
        v["dev"].lower(),
    ))

    return {"services": services, "vpns": vpns}


if __name__ == "__main__":
    json.dump(collect(), sys.stdout, ensure_ascii=False)
