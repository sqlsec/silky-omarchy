.pragma library
.import "I18n.js" as I18n

var chinese = {
    "Weather": "天气", "Stocks": "股市", "Screen Time": "屏幕使用时间", "Batteries": "电池",
    "Calendar": "日历", "System": "系统",
    "Current conditions and forecast": "当前天气与预报",
    "Indices and stocks you follow": "关注的指数和股票",
    "Time spent in apps today": "今天在各个应用上的时间",
    "Laptop and connected devices": "本机和已连接的设备",
    "Today, lunar date and the month": "今天、农历和本月",
    "CPU, memory and disk": "CPU、内存和磁盘",
    "Small": "小", "Medium": "中", "Large": "大",
    "Edit Widgets": "编辑小组件", "Done": "完成", "Add Widget": "添加小组件", "Widgets": "小组件",
    "City (empty = locate by IP)": "城市（留空按 IP 定位）",
    "Symbols, comma separated": "代码，用逗号分隔",
    "e.g. sh000001, hkHSI, usAAPL": "如 sh000001, hkHSI, usAAPL",
    "Tap a widget to change its size · drag to reorder": "点小组件切换尺寸 · 拖动调整顺序 · 右键更多设置",
    "Loading…": "正在加载…", "No data": "暂无数据", "Offline": "无法连接",
    "Now": "现在", "Today": "今天", "Yesterday": "昨天", "Feels like": "体感", "Humidity": "湿度", "Wind": "风速",
    "Sunrise": "日出", "Sunset": "日落", "H": "最高", "L": "最低",
    "Daily average": "日均", "vs yesterday": "比昨天", "Most used": "最常使用", "No screen time yet": "今天还没有使用记录",
    "This week": "本周",
    "CPU": "CPU", "Memory": "内存", "Disk": "磁盘", "Uptime": "已运行", "Load": "负载",
    "Charging": "充电中", "This laptop": "本机", "No battery": "没有电池",
    "Intraday": "今日走势", "1 month": "近一月",
    "Sunny": "晴", "Clear": "晴朗", "Mostly Sunny": "大部晴朗", "Mostly Clear": "大部晴朗", "Partly Cloudy": "多云",
    "Cloudy": "阴", "Foggy": "雾", "Drizzle": "毛毛雨", "Freezing Drizzle": "冻毛毛雨", "Light Rain": "小雨",
    "Rain": "中雨", "Heavy Rain": "大雨", "Freezing Rain": "冻雨", "Light Snow": "小雪", "Snow": "中雪",
    "Heavy Snow": "大雪", "Showers": "阵雨", "Heavy Showers": "强阵雨", "Snow Showers": "阵雪",
    "Thunderstorms": "雷阵雨", "No events today": "今天没有日程",
    "AI Usage": "AI 用量", "AI usage today": "今日 AI 用量", "Claude Code, Codex and Antigravity": "Claude Code、Codex 和 Antigravity 用量",
    "No logs": "没有记录", "tokens today": "今日 tokens",
    "Quota unavailable": "暂无额度", "Gemini models": "Gemini 模型",
    "Tokens per hour": "每小时 tokens",
    "Fresh window": "窗口已重置", "Limit reached": "已达上限", "Weekly quota left": "本周剩余", "resets": "重置", "Requests": "请求", "Output": "输出",
    "5-hour quota left": "5 小时剩余", "Week left": "本周剩余", "7d": "周",
    "Codex 5-hour quota": "Codex 5 小时", "Codex weekly quota": "Codex 本周", "left": "剩余",
    "Symbols you follow": "关注的代码", "drag to reorder": "拖动排序", "Add a code or name, Enter": "输入代码或名称，回车添加",
    "Now showing": "当前显示", "Remove Widget": "移除小组件",
    "Red up · green down": "红涨绿跌", "Green up · red down": "绿涨红跌",
    "A-shares 600519 · HK 00700 · US AAPL · Tokyo 7203.T · Europe SAP.DE · indices ^N225 ^GDAXI · crypto BTC-USD · gold GC=F · or a name":
        "A 股 600519 · 港股 00700 · 美股 AAPL · 东京 7203.T · 欧洲 SAP.DE · 指数 ^N225 ^GDAXI · 加密 BTC-USD · 黄金 GC=F · 也可输入名称"
};

function zh() {
    return /^zh(?:-|$)/i.test(I18n.code());
}

function tr(text) {
    return zh() ? (chinese[text] || text) : text;
}

var kinds = [
    { kind: "weather", name: "Weather", note: "Current conditions and forecast" },
    { kind: "stocks", name: "Stocks", note: "Indices and stocks you follow" },
    { kind: "screentime", name: "Screen Time", note: "Time spent in apps today" },
    { kind: "battery", name: "Batteries", note: "Laptop and connected devices" },
    { kind: "calendar", name: "Calendar", note: "Today, lunar date and the month" },
    { kind: "system", name: "System", note: "CPU, memory and disk" },
    { kind: "ai", name: "AI Usage", note: "Claude Code, Codex and Antigravity" }
];

function kindName(kind) {
    for (var i = 0; i < kinds.length; i++)
        if (kinds[i].kind === kind) return tr(kinds[i].name);
    return kind;
}

// WMO weather code -> condition text and a WeatherIcon kind
function wmo(code, day) {
    switch (code) {
    case 0: return day ? { t: "Sunny", k: "sun" } : { t: "Clear", k: "moon" };
    case 1: return day ? { t: "Mostly Sunny", k: "sun" } : { t: "Mostly Clear", k: "moon" };
    case 2: return { t: "Partly Cloudy", k: day ? "partly" : "partlyNight" };
    case 3: return { t: "Cloudy", k: "cloud" };
    case 45: case 48: return { t: "Foggy", k: "fog" };
    case 51: case 53: case 55: return { t: "Drizzle", k: "rain" };
    case 56: case 57: return { t: "Freezing Drizzle", k: "rain" };
    case 61: return { t: "Light Rain", k: "rain" };
    case 63: return { t: "Rain", k: "rain" };
    case 65: return { t: "Heavy Rain", k: "rain" };
    case 66: case 67: return { t: "Freezing Rain", k: "rain" };
    case 71: return { t: "Light Snow", k: "snow" };
    case 73: return { t: "Snow", k: "snow" };
    case 75: case 77: return { t: "Heavy Snow", k: "snow" };
    case 80: case 81: return { t: "Showers", k: "rain" };
    case 82: return { t: "Heavy Showers", k: "rain" };
    case 85: case 86: return { t: "Snow Showers", k: "snow" };
    case 95: case 96: case 99: return { t: "Thunderstorms", k: "storm" };
    }
    return { t: "Cloudy", k: "cloud" };
}

function weekday(iso, index) {
    if (index === 0) return tr("Today");
    var d = new Date(parseInt(iso.substr(0, 4)), parseInt(iso.substr(5, 2)) - 1, parseInt(iso.substr(8, 2)));
    return zh() ? "周" + "日一二三四五六"[d.getDay()] : ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][d.getDay()];
}

function duration(seconds) {
    var minutes = Math.round((seconds || 0) / 60);
    var hours = Math.floor(minutes / 60);
    minutes = minutes % 60;
    if (zh()) return hours > 0 ? hours + " 小时 " + minutes + " 分" : minutes + " 分钟";
    return hours > 0 ? hours + "h " + minutes + "m" : minutes + "m";
}

function bytes(value) {
    if (!(value >= 0)) return "—";
    var units = ["B", "KB", "MB", "GB", "TB"], unit = 0;
    while (value >= 1000 && unit < units.length - 1) { value /= 1024; unit++; }
    return value.toFixed(value < 10 && unit > 0 ? 1 : 0) + " " + units[unit];
}

function price(value) {
    if (typeof value !== "number" || !isFinite(value)) return "—";
    return value >= 1000 ? value.toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ",") : value.toFixed(2);
}

function signed(value, digits, suffix) {
    if (typeof value !== "number" || !isFinite(value)) return "";
    return (value > 0 ? "+" : "") + value.toFixed(digits) + (suffix || "");
}

function uptime(seconds) {
    var days = Math.floor(seconds / 86400), hours = Math.floor(seconds % 86400 / 3600), minutes = Math.floor(seconds % 3600 / 60);
    if (zh()) return days > 0 ? days + " 天 " + hours + " 小时" : hours + " 小时 " + minutes + " 分";
    return days > 0 ? days + "d " + hours + "h" : hours + "h " + minutes + "m";
}

function compact(n) {
    if (typeof n !== "number" || !isFinite(n)) return "—";
    var units = ["", "K", "M", "B"], unit = 0;
    while (Math.abs(n) >= 1000 && unit < units.length - 1) { n /= 1000; unit++; }
    return (unit && n < 100 ? n.toFixed(1) : Math.round(n)) + units[unit];
}

// Multi-monitor process deduplication: MacBar instantiates one SilkyWidgetDeck per screen,
// so keep a single silky-widgets.py backend alive across all screens and broadcast samples.
var _widgetDecks = [];
var _widgetOwner = null;
var _widgetLatest = null;

function registerWidgetDeck(deck) {
    if (_widgetDecks.indexOf(deck) === -1) _widgetDecks.push(deck);
    if (!_widgetOwner) {
        _widgetOwner = deck;
        deck.isProcessOwner = true;
    }
    if (_widgetLatest !== null) {
        deck.latest = _widgetLatest;
        if (deck.open) deck.info = _widgetLatest;
    }
}

function unregisterWidgetDeck(deck) {
    var i = _widgetDecks.indexOf(deck);
    if (i >= 0) _widgetDecks.splice(i, 1);
    if (_widgetOwner === deck) {
        deck.isProcessOwner = false;
        _widgetOwner = _widgetDecks.length > 0 ? _widgetDecks[0] : null;
        if (_widgetOwner) _widgetOwner.isProcessOwner = true;
    }
}

function broadcastWidgetSample(sample) {
    _widgetLatest = sample;
    for (var i = 0; i < _widgetDecks.length; i++) {
        var d = _widgetDecks[i];
        d.latest = sample;
        if (d.open) d.info = sample;
    }
}

function sendWidgetCommand(line) {
    if (_widgetOwner && typeof _widgetOwner.sendLocal === "function")
        _widgetOwner.sendLocal(line);
}
