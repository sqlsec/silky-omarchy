"""Read local Linux telemetry and stream JSON lines to MacShell."""
import colorsys
import ipaddress
import json
import os
import re
import subprocess
import sys
import time
from collections import defaultdict, deque
from pathlib import Path

SYS = Path("/sys/class")
PROC = Path("/proc")
CLOCK_TICKS = os.sysconf("SC_CLK_TCK")
QCOM_BATTERY = SYS / "power_supply/qcom-battmgr-bat"
QCOM_LIMIT = QCOM_BATTERY / "charge_control_end_threshold"
QCOM_START = QCOM_BATTERY / "charge_control_start_threshold"
CHARGE_LIMIT_HELPER = Path("/usr/local/bin/silky-charge-limit")
LIMIT_MIN, LIMIT_MAX, LIMIT_DELTA = 55, 100, 5
WALLPAPER = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "omarchy/current/background"


def read(path):
    try:
        return path.read_text(errors="replace").strip()
    except OSError:
        return ""


def number(path, scale=1):
    try:
        return int(read(path)) / scale
    except ValueError:
        return None


def command(*args):
    try:
        return subprocess.check_output(args, text=True, errors="replace",
                                       stderr=subprocess.DEVNULL, timeout=1.5)
    except (OSError, subprocess.SubprocessError):
        return ""


def net_counters():
    counters = {}
    for line in read(Path("/proc/net/dev")).splitlines()[2:]:
        interface, data = line.split(":", 1)
        if interface.strip() != "lo":
            fields = data.split()
            counters[interface.strip()] = (int(fields[0]), int(fields[8]))
    physical = {name: values for name, values in counters.items()
                if (SYS / "net" / name / "device").exists()
                and read(SYS / "net" / name / "operstate") not in {"down", "notpresent", "lowerlayerdown"}}
    return physical or {name: values for name, values in counters.items()
                        if read(SYS / "net" / name / "operstate") != "down"}


def rate(current, previous, seconds):
    return [max(0, newer - older) / seconds for newer, older in zip(current, previous)]


def cpu_temperatures():
    temps = []
    for zone in sorted((SYS / "thermal").glob("thermal_zone*")):
        name = read(zone / "type")
        if re.match(r"^(cpu|x86_pkg_temp|soc_thermal|tegra)", name, re.I):
            temp = number(zone / "temp", 1000)
            if temp is not None and -20 < temp < 150:
                temps.append((name, temp))
    if temps:
        return temps
    for device in sorted((SYS / "hwmon").glob("hwmon*")):
        name = read(device / "name")
        if name in {"coretemp", "k10temp", "zenpower", "cpu_thermal", "cpu-thermal"}:
            for channel in sorted(device.glob("temp*_input")):
                temp = number(channel, 1000)
                if temp is not None and -20 < temp < 150:
                    label = read(channel.with_name(channel.name.replace("_input", "_label")))
                    temps.append((name + " · " + (label or channel.stem), temp))
    return temps


def hardware_overview():
    categories = {
        "GPU": r"^(gpu|amdgpu|nouveau|i915|xe\b)",
        "SSD": r"^nvme",
        "Wi-Fi": r"^(ath|iwlwifi|mt76)",
        "Memory": r"^(mem[_-]thermal|spd|jc42)",
        "Battery": r"battery|battmgr[-_ ]bat",
    }
    temperatures = {}
    fans = []
    for device in (SYS / "hwmon").glob("hwmon*"):
        name = read(device / "name")
        for channel in device.glob("fan*_input"):
            speed = number(channel)
            if speed is not None:
                fans.append(speed)
        for category, pattern in categories.items():
            if not re.search(pattern, name, re.I):
                continue
            for channel in device.glob("temp*_input"):
                value = number(channel, 1000)
                if value is not None and -20 < value < 150:
                    temperatures[category] = max(value, temperatures.get(category, value))
    overview = [(category, temperatures[category], "°C") for category in categories if category in temperatures]
    if fans:
        overview.append(("Fan", max(fans), "RPM"))
    return overview


def cpu_processes():
    processes = {}
    for path in PROC.glob("[0-9]*/stat"):
        prefix, closing, tail = read(path).rpartition(") ")
        if not closing:
            continue
        # The executable name can contain spaces or parentheses. Fields after it start at state (field 3).
        _, _, name = prefix.partition(" (")
        fields = tail.split()
        if len(fields) >= 20 and fields[0] not in {"Z", "X"}:
            pid = int(path.parent.name)
            start = int(fields[19])
            ticks = int(fields[11]) + int(fields[12])
            processes[(pid, start)] = (name, ticks)
    return processes


def cpu_ranking(current, previous, seconds):
    if previous is None or seconds <= 0:
        return []
    rows = []
    for identity, (name, ticks) in current.items():
        if identity in previous:
            elapsed_ticks = ticks - previous[identity][1]
            if elapsed_ticks > 0:
                percent = 100 * elapsed_ticks / (CLOCK_TICKS * seconds)
                rows.append((identity[0], name, percent))
    return sorted(rows, key=lambda row: (-row[2], row[0]))[:10]


def cpu_times():
    # Guest time is already included in user and nice.
    lines = read(PROC / "stat").splitlines()
    fields = lines[0].split() if lines else []
    if len(fields) < 9 or fields[0] != "cpu":
        return None
    times = [int(field) for field in fields[1:9]]
    return sum(times), times[3] + times[4]


def percentage(used, total):
    return min(100, max(0, 100 * used / total)) if total > 0 else None


def resource_usage(current_cpu, previous_cpu):
    cpu = None
    if current_cpu and previous_cpu:
        total, idle = (current - previous for current, previous in zip(current_cpu, previous_cpu))
        cpu = percentage(total - idle, total)

    memory = {}
    for line in read(PROC / "meminfo").splitlines():
        key, _, value = line.partition(":")
        if key in {"MemTotal", "MemAvailable"}:
            memory[key] = int(value.split()[0])
    ram = (percentage(memory["MemTotal"] - memory["MemAvailable"], memory["MemTotal"])
           if {"MemTotal", "MemAvailable"} <= memory.keys() else None)

    disk = None
    try:
        filesystem = os.statvfs("/")
        used = filesystem.f_blocks - filesystem.f_bfree
        disk = percentage(used, used + filesystem.f_bavail)
    except OSError:
        pass
    return {"cpu": cpu, "memory": ram, "disk": disk}


def local_addresses():
    try:
        links = json.loads(command("ip", "-j", "address", "show", "up") or "[]")
    except json.JSONDecodeError:
        return []
    addresses = []
    for link in links:
        if link["ifname"] == "lo":
            continue
        for address in link.get("addr_info", []):
            if address.get("scope") == "host":
                continue
            addresses.append((link["ifname"], address["family"], address["local"],
                              address.get("scope") == "link"))
    return sorted(addresses, key=lambda item: (item[3], item[0], item[1], item[2]))


def loopback(endpoint):
    address = endpoint.rsplit(":", 1)[0].strip("[]").split("%", 1)[0]
    try:
        host = ipaddress.ip_address(address)
        if isinstance(host, ipaddress.IPv6Address) and host.ipv4_mapped:
            host = host.ipv4_mapped
        return host.is_loopback
    except ValueError:
        return False


def sockets():
    data = command("ss", "-HtnpieO", "state", "connected")
    entries = {}
    for line in data.splitlines():
        fields = line.split()
        owner = re.search(r'"([^"]+)",pid=(\d+)', line)
        cookie = re.search(r"\bsk:([0-9a-f]+)", line)
        if not owner or not cookie or len(fields) < 5 or loopback(fields[4]):
            continue
        received = re.search(r"\bbytes_received:(\d+)", line)
        sent = re.search(r"\bbytes_acked:(\d+)", line)
        name, pid = owner.groups()
        try:
            executable = (Path("/proc") / pid / "exe").readlink().name
        except OSError:
            executable = name
        entries[cookie[1]] = (executable[:96], int(received[1]) if received else 0,
                              int(sent[1]) if sent else 0)
    return entries


def app_rates(current, previous, seconds):
    totals = defaultdict(lambda: [0, 0])
    for cookie, (name, rx, tx) in current.items():
        if cookie in previous and previous[cookie][0] == name:
            older = previous[cookie][1:]
        else:
            # The first acknowledged sequence number represents the SYN, not payload.
            older = (0, 1)
        down, up = rate((rx, tx), older, seconds)
        if down or up:
            totals[name][0] += down
            totals[name][1] += up
    return sorted(totals.items(), key=lambda item: (-sum(item[1]), item[0]))[:6]


HEALTH_LOG = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "silky/battery-health.csv"
HEALTH_LOG_HEADER = "time,battery,model,full_wh,design_wh,health_pct,cycles"
_health_logged = None


def wallpaper_accent(cache={}):
    """Most vivid dominant color of the current Omarchy wallpaper, toned for dark and light menus."""
    try:
        path = WALLPAPER.resolve(strict=True)
        key = (str(path), path.stat().st_mtime_ns)
    except OSError:
        return None
    if cache.get("key") == key:
        return cache["value"]
    value = None
    try:
        histogram = subprocess.run(["magick", f"{path}[0]", "-thumbnail", "96x96!", "-colors", "16", "-depth", "8",
                                    "-format", "%c", "histogram:info:-"],
                                   capture_output=True, text=True, timeout=20).stdout
    except (OSError, subprocess.SubprocessError):
        histogram = ""
    best = None
    for count, *channels in re.findall(r"(\d+):\s*\(\s*(\d+),\s*(\d+),\s*(\d+)", histogram):
        rgb = [int(channel) / 255 for channel in channels]
        chroma = max(rgb) - min(rgb)
        # Weight by area and by chroma squared, so a large grey sky loses to a smaller vivid region.
        score = int(count) * chroma ** 2
        if best is None or score > best[0]:
            best = (score, chroma, rgb)
    if best and best[1] >= 0.12:
        hue, _, saturation = colorsys.rgb_to_hls(*best[2])
        saturation = min(max(saturation, 0.5), 0.85)

        def tone(lightness):
            return "#" + "".join(f"{round(c * 255):02x}" for c in colorsys.hls_to_rgb(hue, lightness, saturation))
        value = {"dark": tone(0.72), "light": tone(0.38)}
    cache.update(key=key, value=value)
    return value


def log_battery_health():
    """Append a row per internal battery once a day, and whenever the gauge's full capacity changes."""
    global _health_logged
    if _health_logged is None:
        _health_logged = {}
        try:
            for line in HEALTH_LOG.read_text().splitlines()[1:]:
                fields = line.split(",")
                if len(fields) == 7:
                    _health_logged[fields[1]] = (fields[0][:10], fields[3])
        except OSError:
            pass
    rows = []
    now = time.strftime("%Y-%m-%dT%H:%M:%S")
    for device in sorted((SYS / "power_supply").glob("*")):
        if not internal_battery(device):
            continue
        full = number(device / "energy_full", 1e6) or number(device / "charge_full", 1e6)
        design = (number(device / "energy_full_design", 1e6) if number(device / "energy_full", 1e6)
                  else number(device / "charge_full_design", 1e6))
        if not full or not design:
            continue
        full_text = f"{full:.3f}"
        if _health_logged.get(device.name) == (now[:10], full_text):
            continue
        cycles = read(device / "cycle_count")
        rows.append(f"{now},{device.name},{read(device / 'model_name').replace(',', ' ')},"
                    f"{full_text},{design:.3f},{100 * full / design:.2f},{cycles}")
        _health_logged[device.name] = (now[:10], full_text)
    if not rows:
        return
    try:
        HEALTH_LOG.parent.mkdir(parents=True, exist_ok=True)
        new = not HEALTH_LOG.exists()
        with HEALTH_LOG.open("a") as log:
            log.write((HEALTH_LOG_HEADER + "\n" if new else "") + "\n".join(rows) + "\n")
    except OSError:
        pass


def internal_battery(device):
    return (read(device / "type") == "Battery" and read(device / "scope") != "Device"
            and read(device / "present") != "0")


def battery_watts(device, voltage, current):
    watts = number(device / "power_now", 1e6)
    if watts is None and voltage and current is not None:
        watts = voltage * current
    return abs(watts) if watts is not None else None


def external_power_online():
    return any(read(device / "online") == "1" for device in (SYS / "power_supply").glob("*")
               if read(device / "type") != "Battery")


def battery_power_sample():
    """(status, battery watts, on battery). On battery, the discharge rate is the whole system's draw."""
    for device in sorted((SYS / "power_supply").glob("*")):
        if not internal_battery(device):
            continue
        status = read(device / "status")
        on_battery = not external_power_online()
        if status in {"Charging", "Discharging"}:
            watts = battery_watts(device, number(device / "voltage_now", 1e6),
                                  number(device / "current_now", 1e6))
            return (status, watts, on_battery) if watts is not None else None
        if status in {"Not charging", "Full"}:
            return ("Idle", 0, on_battery)
    return None

def charge_threshold(device, start, end):
    if device != QCOM_BATTERY or end is None:
        return None
    try:
        if not QCOM_LIMIT.stat().st_mode & 0o200:
            return None
    except OSError:
        return None
    valid_end = end if LIMIT_MIN <= end <= LIMIT_MAX else None
    valid_start = (start if start is not None
                   and (LIMIT_MIN - LIMIT_DELTA) <= start <= (LIMIT_MAX - LIMIT_DELTA)
                   else None)
    return {"minimum": LIMIT_MIN, "maximum": LIMIT_MAX, "delta": LIMIT_DELTA,
            "end": valid_end, "start": valid_start if valid_end is not None else None}


def _write_sysfs_int(path, value):
    command_line = ["/usr/bin/tee", "--", str(path)]
    if not os.access(path, os.W_OK):
        command_line = ["/usr/bin/pkexec", "--disable-internal-agent"] + command_line
    result = subprocess.run(command_line, input=f"{value}\n", text=True,
                            stdout=subprocess.DEVNULL, timeout=60)
    return result.returncode == 0


def set_charge_limit(argument):
    if not re.fullmatch(r"[0-9]{2,3}", argument):
        return 2
    value = int(argument)
    if not LIMIT_MIN <= value <= LIMIT_MAX:
        return 2
    if not internal_battery(QCOM_BATTERY) or charge_threshold(
            QCOM_BATTERY, number(QCOM_START), number(QCOM_LIMIT)) is None:
        return 1
    start = value - LIMIT_DELTA
    try:
        if CHARGE_LIMIT_HELPER.is_file() and os.access(CHARGE_LIMIT_HELPER, os.X_OK):
            cmd = [str(CHARGE_LIMIT_HELPER), "apply", str(value)]
            if os.geteuid() != 0:
                cmd = ["/usr/bin/pkexec", "--disable-internal-agent"] + cmd
            result = subprocess.run(cmd, stdout=subprocess.DEVNULL, timeout=60)
            ok = result.returncode == 0
        else:
            ok = False
            if value == 80:
                up = subprocess.run(
                    ["/usr/bin/busctl", "--system", "call", "org.freedesktop.UPower",
                     "/org/freedesktop/UPower/devices/battery_qcom_battmgr_bat",
                     "org.freedesktop.UPower.Device", "EnableChargeThreshold", "b", "true"],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
                ok = up.returncode == 0 and number(QCOM_LIMIT) == value and number(QCOM_START) == start
            if not ok:
                # Elevate a system executable with fixed sysfs destinations, never this user-owned script.
                ok = _write_sysfs_int(QCOM_LIMIT, value)
                if ok and number(QCOM_START) != start:
                    ok = _write_sysfs_int(QCOM_START, start)
    except (OSError, subprocess.SubprocessError):
        return 1
    # The driver can return success to the write even when the firmware did not accept it.
    return 0 if ok and number(QCOM_LIMIT) == value and number(QCOM_START) == start else 1


def power_profiles():
    service = "net.hadess.PowerProfiles"
    output = command("busctl", "--system", "--json=short", "call", service, "/net/hadess/PowerProfiles",
                     "org.freedesktop.DBus.Properties", "GetAll", "s", service)
    try:
        data = json.loads(output)["data"][0]
        return {"available": [profile["Profile"]["data"] for profile in data["Profiles"]["data"]],
                "current": data["ActiveProfile"]["data"]}
    except (KeyError, IndexError, TypeError, json.JSONDecodeError):
        return {"available": [], "current": ""}


def power():
    sources, batteries = [], []
    for device in sorted((SYS / "power_supply").glob("*")):
        kind = read(device / "type")
        if kind == "Battery":
            if not internal_battery(device):
                continue
            battery = {key: number(device / key, scale) for key, scale in {
                "capacity": 1, "voltage_now": 1e6,
                "current_now": 1e6, "energy_now": 1e6, "energy_full": 1e6,
                "energy_full_design": 1e6, "charge_now": 1e6, "charge_full": 1e6,
                "charge_full_design": 1e6, "cycle_count": 1, "temp": 10,
                "charge_control_start_threshold": 1, "charge_control_end_threshold": 1,
            }.items()}
            battery.update({key: read(device / key)
                            for key in ("status", "manufacturer", "model_name", "technology")})
            battery["name"] = device.name
            voltage, current = battery["voltage_now"], battery["current_now"]
            raw_watts = number(device / "power_now", 1e6)
            watts = battery_watts(device, voltage, current)
            if current is None and voltage and watts is not None:
                current = watts / voltage
            battery["power_now"] = watts
            battery["discharging"] = (
                battery["status"] == "Discharging"
                or (battery["status"] == "Not charging" and raw_watts is not None and raw_watts < -0.5)
            )
            battery["limit"] = charge_threshold(
                device, battery["charge_control_start_threshold"], battery["charge_control_end_threshold"])
            battery["current_now"] = abs(current) if current is not None else None
            full = battery["energy_full"] or battery["charge_full"]
            design = battery["energy_full_design"] if battery["energy_full"] else battery["charge_full_design"]
            battery["health"] = 100 * full / design if full and design else None
            batteries.append(battery)
        elif (device / "online").exists():
            online = read(device / "online")
            if online in {"0", "1"}:
                port = re.search(r"^ucsi-source-psy-.*\.(\d+)$", device.name)
                usb_type = re.search(r"\[([^]]+)\]", read(device / "usb_type"))
                sources.append({"label": f"USB-C {int(port[1])}" if port else kind or device.name,
                                "port": bool(port), "online": online == "1",
                                "usbType": usb_type[1] if usb_type else "",
                                "voltage": number(device / "voltage_now", 1e6),
                                "current": number(device / "current_now", 1e6)})
    if any(source["port"] and source["online"] for source in sources):
        # Qualcomm exposes both the active UCSI port and an aggregate USB supply.
        sources = [source for source in sources if source["label"] != "USB"]
    return {"batteries": batteries, "sources": sources,
            "onBattery": not any(source["online"] for source in sources) if sources else None,
            "profile": power_profiles()["current"]}


def stream(mode):
    previous = None
    previous_at = 0
    trend = {key: deque(maxlen=40) for key in ("down", "up", "temp")}
    battery_power_history = deque(maxlen=100)
    battery_sample_at = None
    while True:
        if mode == "bar":
            counters = net_counters()
            now = time.monotonic()
            rates = [rate(values, previous[name], now - previous_at)
                     for name, values in counters.items() if previous is not None and name in previous]
            sample = {"down": sum(pair[0] for pair in rates) if previous is not None else None,
                      "up": sum(pair[1] for pair in rates) if previous is not None else None,
                      "temp": max((value for _, value in cpu_temperatures()), default=None)}
            for key, history in trend.items():
                history.append(sample[key])
            sample["trend"] = {key: list(history) for key, history in trend.items()}
            boot_time = time.clock_gettime(time.CLOCK_BOOTTIME)
            if battery_sample_at is None or boot_time - battery_sample_at >= 3:
                if battery_sample_at is not None:
                    # Leave gaps for time spent asleep instead of drawing stale readings as recent data.
                    missing = min(battery_power_history.maxlen, max(0, round((boot_time - battery_sample_at) / 3) - 1))
                    battery_power_history.extend([None] * missing)
                battery_power_history.append(battery_power_sample())
                if battery_sample_at is None or int(boot_time // 600) != int(battery_sample_at // 600):
                    log_battery_health()
                battery_sample_at = boot_time
            sample["batteryPowerHistory"] = list(battery_power_history)
            sample["wallpaperAccent"] = wallpaper_accent()
            previous = counters
        elif mode == "network":
            current = sockets()
            now = time.monotonic()
            sample = {"addresses": local_addresses(), "sampling": previous is None,
                      "apps": app_rates(current, previous, now - previous_at)
                      if previous is not None else []}
            previous = current
        elif mode == "thermal":
            current = cpu_processes()
            current_cpu = cpu_times()
            now = time.monotonic()
            previous_processes, previous_cpu = previous if previous is not None else (None, None)
            sample = {"cpuTop": cpu_ranking(current, previous_processes, now - previous_at),
                      "sampling": previous is None, "overview": hardware_overview(),
                      "usage": resource_usage(current_cpu, previous_cpu)}
            previous = current, current_cpu
        else:
            now = time.monotonic()
            sample = power_profiles() if mode == "profiles" else power()
        previous_at = now
        print(json.dumps(sample), flush=True)
        time.sleep(3 if mode == "power" else 1.5)


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "set-charge-limit":
        sys.exit(set_charge_limit(sys.argv[2]))
    if len(sys.argv) != 2 or sys.argv[1] not in {"bar", "network", "thermal", "power", "profiles"}:
        sys.exit("Usage: status.py {bar|network|thermal|power|profiles} or status.py set-charge-limit PERCENT")
    stream(sys.argv[1])
