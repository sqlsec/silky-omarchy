#!/usr/bin/python3
"""Silky Omarchy: read and change one Wi-Fi connection for MacShell's network details window (Settings → Wi-Fi →
Details…), the macOS TCP/IP · DNS · Proxies · Hardware sheet.

  silky-wifi-conn.py get <uuid>      JSON: profile settings, live addresses / DHCP lease, desktop proxy
  silky-wifi-conn.py set <uuid>      JSON changes on stdin → {"ok": true} or {"ok": false, "error": "..."}
  silky-wifi-conn.py renew <uuid>    reconnect the profile, which asks DHCP for a new lease

IP, DNS, private address and MTU go to the NetworkManager profile (nmcli connection modify); an active profile is then
reactivated so they take effect. Proxies are desktop wide, not per network: they are GNOME's org.gnome.system.proxy
keys, which GTK / GIO programs, Chromium-based browsers and Firefox ("use system proxy settings") read.
Needs: NetworkManager, gsettings (glib2) for proxies.
"""
import ipaddress
import json
import os
import subprocess
import sys

ENV = {**os.environ, "LC_ALL": "C"}
FIELDS = ("connection.id,connection.autoconnect,ipv4.method,ipv4.addresses,ipv4.gateway,ipv4.dns,ipv4.ignore-auto-dns,"
          "ipv4.dns-search,ipv4.dhcp-client-id,ipv6.method,ipv6.addresses,ipv6.gateway,ipv6.dns,"
          "802-11-wireless.cloned-mac-address,802-11-wireless.mtu,GENERAL.STATE,GENERAL.DEVICES")


class Fail(Exception):
    pass


def run(*args, check=False, timeout=10):
    proc = subprocess.run(args, capture_output=True, text=True, errors="replace", timeout=timeout, env=ENV)
    if check and proc.returncode != 0:
        raise Fail((proc.stderr or proc.stdout).strip().splitlines()[-1:][0].replace("Error: ", "") if (proc.stderr or proc.stdout).strip() else "command failed")
    return proc.stdout


def fields(text):
    out = {}
    for line in text.splitlines():
        key, _, value = line.partition(":")
        if key in out:
            out[key] += "," + value
        else:
            out[key] = value
    return out


def split_list(value):
    return [v.strip() for v in value.replace(" ", ",").split(",") if v.strip() and v.strip() != "--"]


def gs(schema, key):
    out = run("gsettings", "get", schema, key).strip()
    if out.startswith("'") and out.endswith("'"):
        return out[1:-1]
    if out.startswith("@as "):
        out = out[4:]
    if out.startswith("["):
        return [item.strip().strip("'") for item in out[1:-1].split(",") if item.strip()]
    if out in ("true", "false"):
        return out == "true"
    try:
        return int(out)
    except ValueError:
        return out


def read_proxy():
    if not run("sh", "-c", "command -v gsettings").strip():
        return None
    base = "org.gnome.system.proxy"
    proxy = {"mode": gs(base, "mode"), "pac": gs(base, "autoconfig-url"), "ignore": gs(base, "ignore-hosts")}
    for kind in ("http", "https", "socks"):
        proxy[kind] = {"host": gs(f"{base}.{kind}", "host"), "port": gs(f"{base}.{kind}", "port")}
    return proxy


def get(uuid):
    s = fields(run("nmcli", "-t", "-f", FIELDS, "connection", "show", "uuid", uuid, check=True))
    out = {
        "uuid": uuid,
        "name": s.get("connection.id", ""),
        "autoconnect": s.get("connection.autoconnect") == "yes",
        "ipv4": {
            "method": s.get("ipv4.method", "auto"),
            "addresses": split_list(s.get("ipv4.addresses", "")),
            "gateway": s.get("ipv4.gateway", "").replace("--", ""),
            "clientId": s.get("ipv4.dhcp-client-id", "").replace("--", ""),
        },
        "ipv6": {"method": s.get("ipv6.method", "auto")},
        "dns": {
            "servers": split_list(s.get("ipv4.dns", "")) + split_list(s.get("ipv6.dns", "")),
            "ignoreAuto": s.get("ipv4.ignore-auto-dns") == "yes",
            "search": split_list(s.get("ipv4.dns-search", "")),
        },
        "mac": s.get("802-11-wireless.cloned-mac-address", "").replace("--", ""),
        "mtu": 0 if s.get("802-11-wireless.mtu", "auto") in ("auto", "0", "") else int(s["802-11-wireless.mtu"]),
        "active": s.get("GENERAL.STATE", "") == "activated",
        "device": s.get("GENERAL.DEVICES", ""),
        "proxy": read_proxy(),
    }
    live = {}
    if out["active"] and out["device"]:
        d = fields(run("nmcli", "-t", "-f", "GENERAL.HWADDR,IP4,IP6,DHCP4", "device", "show", out["device"]))
        addr = d.get("IP4.ADDRESS[1]", "")
        if addr:
            iface = ipaddress.ip_interface(addr)
            live["ip"] = str(iface.ip)
            live["mask"] = str(iface.network.netmask)
        live["router"] = d.get("IP4.GATEWAY", "").replace("--", "")
        live["dns"] = [v for k, v in sorted(d.items()) if k.startswith("IP4.DNS") or k.startswith("IP6.DNS")]
        live["ip6"] = [v for k, v in sorted(d.items()) if k.startswith("IP6.ADDRESS")]
        live["router6"] = d.get("IP6.GATEWAY", "").replace("--", "")
        live["mac"] = d.get("GENERAL.HWADDR", "").replace("\\", "").lower()
        for k, v in d.items():
            if k.startswith("DHCP4.OPTION"):
                name, _, value = v.partition(" = ")
                if name == "dhcp_lease_time":
                    live["lease"] = int(value)
                elif name == "expiry":
                    live["expiry"] = int(value)
    out["live"] = live
    print(json.dumps(out, ensure_ascii=False))


def ip4(value, what):
    try:
        return str(ipaddress.IPv4Address(value.strip()))
    except ValueError:
        raise Fail(f"invalid {what}: {value}")


def set_(uuid, change):
    args = []
    reconnect = False
    if "ipv4" in change:
        v4 = change["ipv4"]
        method = v4.get("method", "auto")
        if method not in ("auto", "manual", "disabled"):
            raise Fail(f"invalid IPv4 method: {method}")
        if method == "manual":
            address = ip4(v4.get("address", ""), "IP address")
            try:
                prefix = ipaddress.IPv4Network(f"0.0.0.0/{ip4(v4.get('mask', ''), 'subnet mask')}").prefixlen
            except ValueError:
                raise Fail(f"invalid subnet mask: {v4.get('mask')}")
            gateway = ip4(v4["gateway"], "router") if v4.get("gateway", "").strip() else ""
            args += ["ipv4.method", "manual", "ipv4.addresses", f"{address}/{prefix}", "ipv4.gateway", gateway]
        else:
            args += ["ipv4.method", method, "ipv4.addresses", "", "ipv4.gateway", ""]
        args += ["ipv4.dhcp-client-id", v4.get("clientId", "").strip()]
        reconnect = True
    if "ipv6" in change:
        method = change["ipv6"].get("method", "auto")
        if method not in ("auto", "link-local", "disabled", "ignore"):
            raise Fail(f"invalid IPv6 method: {method}")
        args += ["ipv6.method", method]
        reconnect = True
    if "dns" in change:
        servers4, servers6 = [], []
        for server in change["dns"].get("servers", []):
            try:
                addr = ipaddress.ip_address(server.strip())
            except ValueError:
                raise Fail(f"invalid DNS server: {server}")
            (servers4 if addr.version == 4 else servers6).append(str(addr))
        manual = bool(servers4 or servers6)
        search = [d.strip() for d in change["dns"].get("search", []) if d.strip()]
        v6method = (change.get("ipv6") or {}).get("method") or fields(
            run("nmcli", "-t", "-f", "ipv6.method", "connection", "show", "uuid", uuid)).get("ipv6.method", "auto")
        args += ["ipv4.dns", ",".join(servers4), "ipv4.ignore-auto-dns", "yes" if manual else "no",
                 "ipv4.dns-search", ",".join(search)]
        if v6method in ("auto", "manual", "dhcp"):
            args += ["ipv6.dns", ",".join(servers6), "ipv6.ignore-auto-dns", "yes" if manual else "no"]
        elif servers6:
            raise Fail("IPv6 DNS servers need IPv6 set to Automatically")
        reconnect = True
    if "mac" in change:
        mac = change["mac"]
        if mac not in ("", "permanent", "random", "stable"):
            raise Fail(f"invalid private address mode: {mac}")
        args += ["802-11-wireless.cloned-mac-address", mac]
        reconnect = True
    if "mtu" in change:
        mtu = int(change["mtu"] or 0)
        if mtu and not 576 <= mtu <= 9000:
            raise Fail("MTU must be between 576 and 9000")
        args += ["802-11-wireless.mtu", str(mtu) if mtu else "auto"]
        reconnect = True
    if "autoconnect" in change:
        args += ["connection.autoconnect", "yes" if change["autoconnect"] else "no"]

    if "proxy" in change:
        set_proxy(change["proxy"])
    if args:
        run("nmcli", "connection", "modify", "uuid", uuid, *args, check=True)
        active = fields(run("nmcli", "-t", "-f", "GENERAL.STATE", "connection", "show", "uuid", uuid)).get("GENERAL.STATE")
        if reconnect and active == "activated":
            run("nmcli", "--wait", "30", "connection", "up", "uuid", uuid, check=True, timeout=40)


def set_proxy(p):
    base = "org.gnome.system.proxy"

    def put(schema, key, value):
        if isinstance(value, bool):
            text = "true" if value else "false"
        elif isinstance(value, int):
            text = str(value)
        elif isinstance(value, list):
            text = "[" + ", ".join("'" + v.replace("'", "") + "'" for v in value) + "]"
        else:
            text = str(value)
        run("gsettings", "set", schema, key, text, check=True)

    entries = {}
    for kind in ("http", "https", "socks"):
        entry = p.get(kind) or {}
        host = (entry.get("host") or "").strip()
        port = int(entry.get("port") or 0)
        if host and not 0 < port < 65536:
            raise Fail(f"invalid {kind.upper()} proxy port")
        entries[kind] = (host, port if host else 0)
        put(f"{base}.{kind}", "host", host)
        put(f"{base}.{kind}", "port", port if host else 0)
    # "same proxy for all protocols" only while all three really are the same
    put(base, "use-same-proxy", bool(entries["http"][0]) and len(set(entries.values())) == 1)
    put(base, "autoconfig-url", (p.get("pac") or "").strip())
    put(base, "ignore-hosts", [h.strip() for h in p.get("ignore", []) if h.strip()])
    mode = p.get("mode", "none")
    if mode not in ("none", "manual", "auto"):
        raise Fail(f"invalid proxy mode: {mode}")
    put(base, "mode", mode)


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in ("get", "set", "renew"):
        sys.exit(2)
    action, uuid = sys.argv[1], sys.argv[2]
    try:
        if action == "get":
            get(uuid)
        elif action == "set":
            set_(uuid, json.load(sys.stdin))
            print(json.dumps({"ok": True}))
        else:
            run("nmcli", "--wait", "30", "connection", "up", "uuid", uuid, check=True, timeout=40)
            print(json.dumps({"ok": True}))
    except (Fail, subprocess.SubprocessError, OSError, ValueError, KeyError) as err:
        print(json.dumps({"ok": False, "error": str(err)}, ensure_ascii=False))
        sys.exit(1)


if __name__ == "__main__":
    main()
