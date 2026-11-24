"""Data for the Silky notification-centre widgets, streamed to MacShell as JSON lines.

stdin  : "idle 0" / "idle 1" (from QML's IdleMonitor), "refresh" (re-fetch all), "refresh-ai" (re-fetch AI usage now)
stdout : one JSON object every few seconds with weather, stocks, screen time and system usage
config : ~/.config/silky/widgets.json (written by the QML deck: placed widgets, city, stock symbols)
state  : ~/.local/state/silky/screen-time/YYYY-MM-DD.json (seconds per app and per hour, kept 30 days)
"""
from contextlib import closing
import datetime as dt
import functools
import http.client
import json
import os
import re
import socket
import sys
import threading
import time
import urllib.parse
import urllib.request
from pathlib import Path

HOME = Path.home()
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config")) / "silky/widgets.json"
STATE = Path(os.environ.get("XDG_STATE_HOME", HOME / ".local/state")) / "silky/screen-time"
CACHE = Path(os.environ.get("XDG_CACHE_HOME", HOME / ".cache")) / "silky"
CLAUDE_DIRS = [Path(os.environ["CLAUDE_CONFIG_DIR"]) / "projects"] if os.environ.get("CLAUDE_CONFIG_DIR") else \
    [HOME / ".claude/projects", Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config")) / "claude/projects"]
CLAUDE_DESKTOP_USAGE = Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config")) / "Claude/plan-usage-history.json"
CODEX_DIR = Path(os.environ.get("CODEX_HOME", HOME / ".codex"))
ANTIGRAVITY_DAEMON = HOME / ".gemini/antigravity/daemon"
AI_EVERY = 15
ANTIGRAVITY_EVERY = 15
CLAUDE_DESKTOP_MAX_AGE = 30 * 60
DEFAULT_STOCKS = ["sh000001", "sz399001", "hkHSI", "usIXIC", "usAAPL", "usNVDA"]
TICK = 5            # seconds between samples
WEATHER_EVERY = 15 * 60
STOCKS_EVERY = 60
KEEP_DAYS = 30

lock = threading.Lock()
data = {"weather": None, "stocks": [], "screenTime": None, "system": None, "ai": None, "errors": {}}
idle = False
wake = threading.Event()
refresh_all = threading.Event()
refresh_ai = threading.Event()
push = threading.Event()


def fetch(url, timeout=10):
    request = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (silky-widgets)"})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.read()


def read_config():
    try:
        config = json.loads(CONFIG.read_text())
        return config if isinstance(config, dict) else {}
    except (OSError, ValueError):
        return {}


def placed(config):
    widgets = config.get("widgets")
    # no config yet: the deck shows its default set, which includes weather and stocks
    return {w.get("kind") for w in widgets if isinstance(w, dict)} if isinstance(widgets, list) else {"weather", "stocks"}


# ───────────── weather (Open-Meteo, no key) ─────────────
def locate(city):
    if city:
        query = urllib.parse.urlencode({"name": city, "count": 1, "language": "zh", "format": "json"})
        result = json.loads(fetch("https://geocoding-api.open-meteo.com/v1/search?" + query))["results"][0]
        return result["latitude"], result["longitude"], result.get("name") or city
    where = json.loads(fetch("https://ipwho.is/"))
    if "latitude" not in where:
        raise ValueError("IP location failed")
    return where["latitude"], where["longitude"], where.get("city") or where.get("region") or ""


def weather(city):
    lat, lon, name = locate(city)
    query = urllib.parse.urlencode({
        "latitude": lat, "longitude": lon, "timezone": "auto", "forecast_days": 6,
        "current": "temperature_2m,weather_code,is_day,apparent_temperature,relative_humidity_2m,wind_speed_10m",
        "hourly": "temperature_2m,weather_code,is_day,precipitation_probability",
        "daily": "temperature_2m_max,temperature_2m_min,weather_code,sunrise,sunset",
    })
    o = json.loads(fetch("https://api.open-meteo.com/v1/forecast?" + query))
    current, hourly, daily = o["current"], o["hourly"], o["daily"]
    now = current["time"][:13]
    start = next((i for i, t in enumerate(hourly["time"]) if t[:13] == now), 0)
    hours = [{"time": hourly["time"][i][11:16], "temp": round(hourly["temperature_2m"][i]),
              "code": hourly["weather_code"][i], "day": hourly["is_day"][i] == 1,
              "rain": hourly["precipitation_probability"][i]}
             for i in range(start, min(start + 6, len(hourly["time"])))]
    days = [{"date": daily["time"][i], "lo": round(daily["temperature_2m_min"][i]),
             "hi": round(daily["temperature_2m_max"][i]), "code": daily["weather_code"][i]}
            for i in range(min(6, len(daily["time"])))]
    return {"city": name, "temp": round(current["temperature_2m"]), "feels": round(current["apparent_temperature"]),
            "humidity": current["relative_humidity_2m"], "wind": round(current["wind_speed_10m"]),
            "code": current["weather_code"], "day": current["is_day"] == 1,
            "hi": days[0]["hi"] if days else None, "lo": days[0]["lo"] if days else None,
            "sunrise": daily["sunrise"][0][11:16], "sunset": daily["sunset"][0][11:16],
            "hourly": hours, "daily": days, "at": time.time()}


# ───────────── stocks: Tencent quotes for A-shares / Hong Kong / US, Yahoo Finance for every other market ─────────────
def series(symbol, full_code):
    if symbol.startswith("us"):
        url = "https://web.ifzq.gtimg.cn/appstock/app/UsMinute/query?code=us" + full_code
        key = "us" + full_code
    else:
        url = "https://web.ifzq.gtimg.cn/appstock/app/minute/query?code=" + symbol
        key = symbol
    try:
        rows = json.loads(fetch(url))["data"][key]["data"]["data"]
        points = [float(row.split()[1]) for row in rows]
        if len(points) >= 5:
            return thin(points), "intraday"
    except (OSError, ValueError, KeyError, TypeError, IndexError):
        pass
    try:
        code = ("us" + full_code) if symbol.startswith("us") else symbol
        rows = json.loads(fetch(f"https://web.ifzq.gtimg.cn/appstock/app/fqkline/get?param={code},day,,,30,qfq"))
        days = rows["data"][code].get("qfqday") or rows["data"][code].get("day") or []
        return [float(row[2]) for row in days], "month"
    except (OSError, ValueError, KeyError, TypeError, IndexError):
        return [], ""


TENCENT = re.compile(r"(sh|sz|bj|hk|us)[A-Za-z0-9.]+", re.I)
resolved = {}          # user entry -> {"source": "tencent" | "yahoo", "symbol": ...}; failed lookups are retried next round


def resolve(entry):
    """Turn what the user typed into a quote symbol: a code, a ticker or a company / index name."""
    entry = entry.strip()
    if entry in resolved:
        return resolved[entry]
    found = None
    if TENCENT.fullmatch(entry):
        found = {"source": "tencent", "symbol": entry[:2].lower() + entry[2:]}
    elif re.fullmatch(r"\d{6}", entry):            # A-shares: 6/9 Shanghai, 0/3 Shenzhen, 4/8 Beijing
        found = {"source": "tencent", "symbol": {"6": "sh", "9": "sh", "4": "bj", "8": "bj"}.get(entry[0], "sz") + entry}
    elif re.fullmatch(r"\d{4,5}", entry):          # Hong Kong
        found = {"source": "tencent", "symbol": "hk" + entry.zfill(5)}
    elif re.fullmatch(r"[A-Za-z]{1,5}", entry):     # a bare ticker: US listing
        found = {"source": "tencent", "symbol": "us" + entry.upper()}
    elif re.fullmatch(r"[\^A-Za-z0-9.=\-]+", entry) and re.search(r"[\^.=\-]", entry):
        # Yahoo-style: ^N225, 7203.T, SAP.DE, BTC-USD, GC=F
        found = {"source": "yahoo", "symbol": entry.upper() if not entry.startswith("^") else entry}
    else:                                            # a name: Tencent's search first (Chinese names), then Yahoo's
        try:
            hint = fetch("https://smartbox.gtimg.cn/s3/?v=2&t=all&q=" + urllib.parse.quote(entry)).decode("ascii", "replace")
            first = re.search(r'v_hint="([^"^]*)', hint)
            market, code = first[1].split("~")[:2] if first and "~" in first[1] else ("", "")
            if market in {"sh", "sz", "bj", "hk"}:
                found = {"source": "tencent", "symbol": market + code}
            elif market == "us":
                found = {"source": "tencent", "symbol": "us" + code.split(".")[0].upper()}
        except (OSError, ValueError):
            pass
        if not found:
            try:
                query = urllib.parse.urlencode({"q": entry, "quotesCount": 1, "newsCount": 0})
                quotes = json.loads(fetch("https://query1.finance.yahoo.com/v1/finance/search?" + query))["quotes"]
                if quotes:
                    found = {"source": "yahoo", "symbol": quotes[0]["symbol"]}
            except (OSError, ValueError, KeyError):
                pass
    if found:
        resolved[entry] = found
    return found


def thin(points, keep=80):
    step = max(1, len(points) // keep)
    return points[::step] + ([points[-1]] if (len(points) - 1) % step else [])


def tencent_quotes(symbols):
    if not symbols:
        return {}
    text = fetch("https://qt.gtimg.cn/q=" + ",".join(symbols)).decode("gbk", "replace")
    quotes, out = dict(re.findall(r'v_([^=]+)="([^"]*)"', text)), {}
    for symbol in symbols:
        fields = quotes.get(symbol, "").split("~")
        if len(fields) < 33 or not fields[3]:
            continue
        points, span = series(symbol, fields[2])
        out[symbol] = {"name": fields[1], "code": fields[2].split(".")[0].lstrip("."),
                       "price": float(fields[3]), "prev": float(fields[4] or 0),
                       "change": float(fields[31] or 0), "percent": float(fields[32] or 0),
                       "time": fields[30], "series": points, "span": span}
    return out


def yahoo_quote(symbol):
    url = "https://query1.finance.yahoo.com/v8/finance/chart/" + urllib.parse.quote(symbol) + "?range=1d&interval=5m"
    result = json.loads(fetch(url))["chart"]["result"][0]
    meta = result["meta"]
    points = [p for p in result["indicators"]["quote"][0].get("close") or [] if p is not None]
    span = "intraday"
    if len(points) < 5:
        url = "https://query1.finance.yahoo.com/v8/finance/chart/" + urllib.parse.quote(symbol) + "?range=1mo&interval=1d"
        month = json.loads(fetch(url))["chart"]["result"][0]
        points = [p for p in month["indicators"]["quote"][0].get("close") or [] if p is not None]
        span = "month"
    price = meta["regularMarketPrice"]
    prev = meta.get("chartPreviousClose") or meta.get("previousClose") or price
    name = re.sub(r"\s{2,}.*", "", meta.get("shortName") or meta.get("longName") or symbol).strip()
    return {"name": name, "code": symbol,
            "price": price, "prev": prev, "change": price - prev,
            "percent": 100 * (price - prev) / prev if prev else 0, "currency": meta.get("currency", ""),
            "series": thin(points), "span": span}


def stocks(entries):
    entries = [str(e).strip() for e in entries if str(e).strip()][:12]
    targets = {entry: resolve(entry) for entry in entries}
    tencent = tencent_quotes([t["symbol"] for t in targets.values() if t and t["source"] == "tencent"])
    result = []
    for entry in entries:
        target = targets[entry]
        quote = None
        if target and target["source"] == "tencent":
            quote = tencent.get(target["symbol"])
        elif target:
            try:
                quote = yahoo_quote(target["symbol"])
            except (OSError, ValueError, KeyError, TypeError, IndexError):
                quote = None
        if quote:
            result.append(dict(quote, entry=entry, symbol=target["symbol"]))
        else:
            result.append({"entry": entry, "symbol": target["symbol"] if target else "", "name": entry, "price": None})
    return result


# ───────────── AI usage: Claude Code and Codex from local logs, Antigravity from its desktop service ─────────────
def local_day(stamp):
    """ISO timestamp (UTC 'Z' or with offset) -> (local date, local hour)."""
    try:
        moment = dt.datetime.fromisoformat(stamp.replace("Z", "+00:00")).astimezone()
        return moment.date(), moment.hour
    except (ValueError, AttributeError):
        return None, 0


class LogTail:
    """Reads only the lines appended since the last call; starts over when a file shrinks."""
    def __init__(self):
        self.offsets = {}

    def new_lines(self, path):
        try:
            size = path.stat().st_size
        except OSError:
            return []
        start = self.offsets.get(path, 0)
        if size < start:
            start = 0
        if size == start:
            return []
        with open(path, "rb") as handle:
            handle.seek(start)
            chunk = handle.read(size - start)
        end = chunk.rfind(b"\n") + 1
        self.offsets[path] = start + end
        lines = []
        for raw in chunk[:end].splitlines():
            try:
                lines.append(json.loads(raw))
            except ValueError:
                continue
        return lines


class AiUsage:
    def __init__(self):
        self.reset(dt.date.today())

    def reset(self, day):
        self.day = day
        self.tail = LogTail()
        self.seen = set()
        self.claude = {"tokens": 0, "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0, "requests": 0,
                       "hours": [0] * 24, "models": {}}
        self.codex_files = {}        # path -> {"base": total before today, "last": latest total}
        self.codex_hours = [0] * 24
        self.codex_limits = None
        self.codex_limits_at = ""
        self.codex_plan = ""
        self.claude_limited = None   # {"type": "five_hour", "resetsAt": epoch} from the last rejected request
        self.claude_limits_seeded = False

    def recent(self, root, pattern):
        midnight = dt.datetime.combine(self.day, dt.time()).timestamp()
        out = []
        for path in root.glob(pattern):
            try:
                if path.stat().st_mtime >= midnight:
                    out.append(path)
            except OSError:
                continue
        return out

    def seed_claude_limits(self):
        """Check the tail of Claude logs modified in the past 7 days for an active rate-limit rejection."""
        now = time.time()
        midnight = dt.datetime.combine(self.day, dt.time()).timestamp()
        cutoff = now - 7 * 86400
        for root in CLAUDE_DIRS:
            if not root.is_dir():
                continue
            for path in root.glob("**/*.jsonl"):
                try:
                    st = path.stat()
                except OSError:
                    continue
                if st.st_mtime < cutoff or st.st_mtime >= midnight:
                    continue
                try:
                    with open(path, "rb") as handle:
                        if st.st_size > 131072:
                            handle.seek(st.st_size - 131072)
                            handle.readline()
                        chunk = handle.read()
                except OSError:
                    continue
                if b"rate_limit_info" not in chunk:
                    continue
                for raw in chunk.splitlines():
                    if b"rate_limit_info" not in raw:
                        continue
                    try:
                        o = json.loads(raw)
                    except ValueError:
                        continue
                    info = (o.get("apiErrorParams") or {}).get("rate_limit_info")
                    if isinstance(info, dict) and info.get("status") == "rejected" and info.get("resetsAt") and info["resetsAt"] > now:
                        if not self.claude_limited or info["resetsAt"] >= self.claude_limited["resetsAt"]:
                            self.claude_limited = {"type": info.get("rateLimitType") or "five_hour", "resetsAt": info["resetsAt"]}

    def scan_claude(self):
        if not self.claude_limits_seeded:
            self.seed_claude_limits()
            self.claude_limits_seeded = True
        for root in CLAUDE_DIRS:
            if not root.is_dir():
                continue
            for path in self.recent(root, "**/*.jsonl"):
                for o in self.tail.new_lines(path):
                    # Claude Code records the plan limit only when a request is refused for hitting it
                    info = (o.get("apiErrorParams") or {}).get("rate_limit_info")
                    if isinstance(info, dict) and info.get("status") == "rejected" and info.get("resetsAt"):
                        if not self.claude_limited or info["resetsAt"] >= self.claude_limited["resetsAt"]:
                            self.claude_limited = {"type": info.get("rateLimitType") or "five_hour", "resetsAt": info["resetsAt"]}
                    message = o.get("message")
                    if not isinstance(message, dict) or not isinstance(message.get("usage"), dict):
                        continue
                    day, hour = local_day(o.get("timestamp", ""))
                    if day != self.day:
                        continue
                    key = (message.get("id"), o.get("requestId"))
                    if key in self.seen:
                        continue
                    self.seen.add(key)
                    u = message["usage"]
                    parts = [u.get("input_tokens") or 0, u.get("output_tokens") or 0,
                             u.get("cache_read_input_tokens") or 0, u.get("cache_creation_input_tokens") or 0]
                    c = self.claude
                    c["input"] += parts[0]; c["output"] += parts[1]; c["cacheRead"] += parts[2]; c["cacheWrite"] += parts[3]
                    c["tokens"] += sum(parts)
                    c["requests"] += 1
                    c["hours"][hour] += sum(parts)
                    model = message.get("model") or "?"
                    c["models"][model] = c["models"].get(model, 0) + sum(parts)
        return any(root.is_dir() for root in CLAUDE_DIRS)

    def scan_codex(self):
        roots = [CODEX_DIR / "sessions", CODEX_DIR / "archived_sessions"]
        for root in roots:
            if not root.is_dir():
                continue
            for path in self.recent(root, "**/*.jsonl"):
                state = self.codex_files.setdefault(path, {"base": 0, "last": 0})
                for o in self.tail.new_lines(path):
                    payload = o.get("payload") or {}
                    if o.get("type") != "event_msg" or payload.get("type") != "token_count":
                        continue
                    stamp = o.get("timestamp", "")
                    day, hour = local_day(stamp)
                    info = payload.get("info") or {}
                    total = (info.get("total_token_usage") or {}).get("total_tokens")
                    if isinstance(total, int):
                        if day == self.day:
                            if total > state["last"]:
                                self.codex_hours[hour] += total - max(state["last"], state["base"])
                            state["last"] = max(state["last"], total)
                        elif day and day < self.day:
                            state["base"] = state["last"] = max(state["base"], total)
                    limits = payload.get("rate_limits")
                    if (isinstance(limits, dict)
                            and limits.get("limit_id") in (None, "codex")
                            and (isinstance(limits.get("primary"), dict) or isinstance(limits.get("secondary"), dict))
                            and stamp >= self.codex_limits_at):
                        self.codex_limits, self.codex_limits_at = limits, stamp
                        self.codex_plan = limits.get("plan_type") or self.codex_plan
        return CODEX_DIR.is_dir()

    def summary(self):
        if dt.date.today() != self.day:
            self.reset(dt.date.today())
        has_claude = self.scan_claude()
        has_codex = self.scan_codex()
        limits = self.codex_limits or {}

        def window(name):
            # Codex writes its limits only after a reply; once a window's reset time has passed, that window
            # starts again at 0% used even though the log still holds the old figure.
            w = limits.get(name)
            if not isinstance(w, dict):
                return None
            used, resets = w.get("used_percent"), w.get("resets_at")
            fresh = isinstance(resets, (int, float)) and resets <= time.time()
            used = 0.0 if fresh or not isinstance(used, (int, float)) else float(used)
            return {"used": used, "left": 100.0 - used, "minutes": w.get("window_minutes"),
                    "resetsAt": None if fresh else resets}
        desktop_quota = claude_desktop_quota()
        claude = dict(self.claude, models=sorted(self.claude["models"].items(), key=lambda i: -i[1])[:3]) \
            if has_claude or desktop_quota else None
        if claude is not None:
            limited = self.claude_limited
            claude["limited"] = limited if limited and limited["resetsAt"] > time.time() else None
            claude["quota"] = desktop_quota
        codex = {"tokens": sum(max(0, f["last"] - f["base"]) for f in self.codex_files.values()),
                 "hours": self.codex_hours, "primary": window("primary"), "secondary": window("secondary"),
                 "plan": self.codex_plan} if has_codex else None
        return {"claude": claude, "codex": codex}


def claude_desktop_quota():
    """Read the latest percentages used from Claude Desktop's local usage history."""
    try:
        history = json.loads(CLAUDE_DESKTOP_USAGE.read_text())
        if history["version"] not in (1, 2):
            return None
        sample = history["samples"][-1]
        age = time.time() - sample["t"] / 1000
        limits = sample["u"] if history["version"] == 2 else sample
    except (OSError, ValueError, KeyError, IndexError, TypeError):
        return None
    if not 0 <= age <= CLAUDE_DESKTOP_MAX_AGE or not isinstance(limits, dict):
        return None
    windows = {}
    for name, field in (("primary", "fh"), ("secondary", "sd")):
        used = limits.get(field)
        if type(used) in (int, float) and 0 <= used <= 100:
            windows[name] = {"left": 100 - used}
    return windows or None


def antigravity_windows(response):
    windows = {"primary": None, "secondary": None}
    buckets = {"gemini-5h": "primary", "gemini-weekly": "secondary"}
    for group in response["response"]["groups"]:
        for bucket in group["buckets"]:
            window = buckets.get(bucket.get("bucketId"))
            left = bucket.get("remainingFraction")
            if window is None or bucket.get("disabled") or type(left) not in (int, float) or not 0 <= left <= 1:
                continue
            reset = bucket.get("resetTime")
            try:
                reset = dt.datetime.fromisoformat(reset).timestamp() if reset else None
            except (ValueError, TypeError, OverflowError):
                reset = None
            windows[window] = {"left": left * 100, "resetsAt": reset}
    return windows if any(windows.values()) else None


def antigravity_quota():
    """Read the Gemini model-group quota from the running Antigravity desktop daemon."""
    for record in ANTIGRAVITY_DAEMON.glob("hub_*.json"):
        try:
            if record.stat().st_uid != os.getuid():
                continue
            endpoint = json.loads(record.read_text())
            pid, port, csrf = endpoint["pid"], endpoint["httpPort"], endpoint["csrfToken"]
            if type(pid) is not int or pid <= 0 or type(port) is not int or not 1 <= port <= 65535:
                continue
            proc = Path("/proc") / str(pid)
            if proc.stat().st_uid != os.getuid() or (proc / "exe").resolve(strict=True).name != "language_server":
                continue
            if not isinstance(csrf, str) or not csrf.isascii() or not csrf or any(c in csrf for c in "\r\n"):
                continue
            # Use the same loopback service as the app, without proxies or access to Google login files.
            with closing(http.client.HTTPConnection("127.0.0.1", port, timeout=2)) as conn:
                conn.request("POST", "/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary",
                             "{}", {"Content-Type": "application/json", "Connect-Protocol-Version": "1",
                                    "x-codeium-csrf-token": csrf})
                reply = conn.getresponse()
                if reply.status == 200:
                    quota = antigravity_windows(json.loads(reply.read(1024 * 1024)))
                    if quota is not None:
                        return quota
        except (OSError, ValueError, TypeError, KeyError, AttributeError, http.client.HTTPException):
            continue
    return None


def fetcher():
    last_weather = last_stocks = last_ai = last_antigravity = 0
    weather_key = stocks_key = None
    ai = AiUsage()
    antigravity = None
    cached = CACHE / "widgets-weather.json"
    try:
        with lock:
            data["weather"] = json.loads(cached.read_text())
    except (OSError, ValueError):
        pass
    while True:
        config = read_config()
        kinds = placed(config)
        now = time.time()
        city = str(config.get("city") or "").strip()
        symbols = config.get("stocks") if isinstance(config.get("stocks"), list) else DEFAULT_STOCKS
        if "ai" in kinds and now - last_ai >= AI_EVERY:
            try:
                value = ai.summary()
            except OSError as error:
                value = None
                with lock:
                    data["errors"]["ai"] = str(error)
            if now - last_antigravity >= ANTIGRAVITY_EVERY:
                antigravity = antigravity_quota()
                last_antigravity = now
            if value is not None:
                updated = dict(value, antigravity=antigravity)
                with lock:
                    changed = updated != data["ai"]
                    data["ai"] = updated
                if changed:
                    push.set()
            last_ai = now
        if "weather" in kinds and (now - last_weather >= WEATHER_EVERY or city != weather_key):
            try:
                value = weather(city)
                with lock:
                    data["weather"] = value
                    data["errors"].pop("weather", None)
                CACHE.mkdir(parents=True, exist_ok=True)
                cached.write_text(json.dumps(value))
                last_weather, weather_key = now, city
            except (OSError, ValueError, KeyError, TypeError, IndexError) as error:
                with lock:
                    data["errors"]["weather"] = str(error) or type(error).__name__
                last_weather, weather_key = now - WEATHER_EVERY + 60, city    # retry in a minute
        if "stocks" in kinds and (now - last_stocks >= STOCKS_EVERY or symbols != stocks_key):
            try:
                value = stocks(symbols)
                with lock:
                    data["stocks"] = value
                    data["errors"].pop("stocks", None)
            except (OSError, ValueError) as error:
                with lock:
                    data["errors"]["stocks"] = str(error) or type(error).__name__
            last_stocks, stocks_key = now, symbols
        wake.wait(5)
        if wake.is_set():
            wake.clear()
            if refresh_all.is_set():
                refresh_all.clear()
                last_weather = last_stocks = last_ai = last_antigravity = 0
            if refresh_ai.is_set():
                refresh_ai.clear()
                last_ai = last_antigravity = 0


# ───────────── screen time (focused Hyprland window while not idle or locked) ─────────────
def hypr(command):
    runtime = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    path = Path(runtime) / "hypr" / os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "") / ".socket.sock"
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
        sock.settimeout(1)
        sock.connect(str(path))
        sock.sendall(command.encode())
        chunks = []
        while chunk := sock.recv(65536):
            chunks.append(chunk)
    return json.loads(b"".join(chunks) or b"null")


def locked():
    for comm in Path("/proc").glob("[0-9]*/comm"):
        try:
            if comm.read_text().strip() in {"hyprlock", "swaylock", "gtklock"}:
                return True
        except OSError:
            continue
    return False


def day_file(day):
    return STATE / f"{day.isoformat()}.json"


def load_day(day):
    try:
        record = json.loads(day_file(day).read_text())
        if isinstance(record.get("apps"), dict) and isinstance(record.get("hours"), list) and len(record["hours"]) == 24:
            return record
    except (OSError, ValueError, AttributeError):
        pass
    return {"apps": {}, "hours": [0] * 24}


@functools.lru_cache(maxsize=16)
def past_total(day):
    return round(sum(load_day(day)["apps"].values()))


def save_day(day, record):
    STATE.mkdir(parents=True, exist_ok=True)
    tmp = day_file(day).with_suffix(".tmp")
    tmp.write_text(json.dumps(record))
    tmp.replace(day_file(day))


def prune():
    cutoff = (dt.date.today() - dt.timedelta(days=KEEP_DAYS)).isoformat()
    for path in STATE.glob("*.json"):
        if path.stem < cutoff:
            path.unlink(missing_ok=True)


def screen_summary(today, record):
    week = []
    for back in range(6, -1, -1):
        day = today - dt.timedelta(days=back)
        seconds = round(sum(record["apps"].values())) if back == 0 else past_total(day)
        week.append({"date": day.isoformat(), "seconds": seconds})
    apps = sorted(record["apps"].items(), key=lambda item: -item[1])[:8]
    return {"date": today.isoformat(), "total": round(sum(record["apps"].values())),
            "hours": [round(h) for h in record["hours"]],
            "apps": [{"app": app, "seconds": round(seconds)} for app, seconds in apps],
            "yesterday": week[-2]["seconds"], "week": week}


# ───────────── system usage ─────────────
def cpu_times():
    fields = [int(v) for v in Path("/proc/stat").read_text().split("\n", 1)[0].split()[1:]]
    return sum(fields), fields[3] + fields[4]


def system(previous):
    total, idle_time = cpu_times()
    cpu = None
    if previous and total > previous[0]:
        cpu = 100 * (1 - (idle_time - previous[1]) / (total - previous[0]))
    mem = {}
    for line in Path("/proc/meminfo").read_text().splitlines():
        key, value = line.split(":", 1)
        mem[key] = int(value.split()[0]) * 1024
    disk = os.statvfs("/")
    disk_total = disk.f_blocks * disk.f_frsize
    disk_used = disk_total - disk.f_bavail * disk.f_frsize
    uptime = float(Path("/proc/uptime").read_text().split()[0])
    used = mem["MemTotal"] - mem["MemAvailable"]
    return (total, idle_time), {
        "cpu": cpu, "memory": 100 * used / mem["MemTotal"], "memUsed": used, "memTotal": mem["MemTotal"],
        "disk": 100 * disk_used / disk_total if disk_total else None, "diskUsed": disk_used, "diskTotal": disk_total,
        "load": os.getloadavg()[0], "cores": os.cpu_count(), "uptime": uptime}


def reader():
    global idle
    for line in sys.stdin:
        words = line.split()
        if words[:1] == ["idle"] and len(words) == 2:
            idle = words[1] == "1"
        elif words == ["refresh"]:
            refresh_all.set()
            wake.set()
        elif words == ["refresh-ai"]:
            refresh_ai.set()
            wake.set()


def main():
    threading.Thread(target=fetcher, daemon=True).start()
    threading.Thread(target=reader, daemon=True).start()
    prune()
    today = dt.date.today()
    record = load_day(today)
    cpu_previous = None
    last_tick = time.monotonic()
    last_save = last_tick
    while True:
        now = time.monotonic()
        elapsed = min(now - last_tick, 2 * TICK)      # a suspend in between does not count as use
        last_tick = now
        stamp = dt.datetime.now()
        if stamp.date() != today:
            save_day(today, record)
            today, record = stamp.date(), load_day(stamp.date())
            prune()
        if not idle:
            try:
                window = hypr("j/activewindow")
                app = (window or {}).get("class") or ""
            except (OSError, ValueError):
                app = ""
            if app and not locked():
                record["apps"][app] = record["apps"].get(app, 0) + elapsed
                record["hours"][stamp.hour] += elapsed
        if now - last_save >= 60:
            save_day(today, record)
            last_save = now
        cpu_previous, usage = system(cpu_previous)
        with lock:
            if usage["cpu"] is None and data["system"]:
                usage["cpu"] = data["system"].get("cpu")
            data["screenTime"] = screen_summary(today, record)
            data["system"] = usage
            line = json.dumps(data)
        print(line, flush=True)
        push.wait(TICK)
        push.clear()


if __name__ == "__main__":
    try:
        main()
    except (KeyboardInterrupt, BrokenPipeError):
        pass
