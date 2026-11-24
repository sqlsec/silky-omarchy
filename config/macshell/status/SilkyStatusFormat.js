.pragma library
.import "I18n.js" as I18n

var chinese = {
    "Network": "网络",
    "CPU Temperature": "CPU 温度",
    "Power & Battery": "电源与电池",
    "Download": "下载",
    "Upload": "上传",
    "Hottest CPU sensor": "最高 CPU 温度",
    "Battery charge": "当前电量",
    "Local IP addresses": "本机 IP 地址",
    "Copy address": "复制地址",
    "Last minute": "最近 1 分钟",
    "No active address": "暂无可用 IP 地址",
    "Top apps by traffic": "应用流量排行",
    "Sampling traffic…": "正在采样…",
    "No TCP traffic in this sample": "本轮采样暂无 TCP 流量",
    "Current user’s TCP traffic · Proxied traffic may show under the proxy": "当前用户的 TCP 流量 · 代理流量可能归到代理进程",
    "Hardware overview": "硬件概览",
    "CPU usage": "CPU 占用率",
    "Memory usage": "内存占用率",
    "System disk usage": "系统盘占用率",
    "GPU": "显卡",
    "SSD": "固态硬盘",
    "Wi-Fi": "无线网卡",
    "Memory": "内存",
    "Fan": "风扇",
    "Top 10 by CPU usage": "CPU 占用 Top 10",
    "Sampling CPU usage…": "正在采样 CPU 占用…",
    "No active processes in this sample": "本轮暂无活跃进程",
    "100% = one logical core": "100% 表示占满一个逻辑核心",
    "Battery": "电池",
    "Power source": "供电来源",
    "External power": "外接电源",
    "Power passthrough": "电源直供",
    "On battery": "电池供电",
    "Online": "已连接",
    "Status": "状态",
    "Charging": "充电中",
    "Discharging": "放电中",
    "Full": "已充满",
    "Not charging": "未充电",
    "Unknown": "未知",
    "Time remaining": "剩余续航",
    "Time to full": "充满还需",
    "Model": "型号",
    "Technology": "电池类型",
    "Health": "健康度",
    "Cycle count": "循环次数",
    "Discharging power": "放电功率",
    "Battery power": "电池功率",
    "Charging power": "充电功率",
    "System power": "整机功耗",
    "Unavailable on external power": "接电源时不可读",
    "Not reported on external power": "接电源时硬件不报告整机功耗",
    "Last 5 minutes · on battery": "最近 5 分钟 · 仅电池供电时",
    "Last 5 minutes": "最近 5 分钟",
    "Peak %1": "峰值 %1",
    "Charge limit": "充电上限",
    "Current limit %1": "当前上限 %1",
    "Current limit unavailable": "当前上限未读到",
    "Apply": "应用",
    "Applying…": "正在应用…",
    "Could not change the charge limit": "无法更改充电上限",
    "Waiting for power data…": "正在等待功率数据…",
    "Voltage": "电压",
    "Current": "电流",
    "Temperature": "电池温度",
    "Energy remaining": "剩余能量",
    "Full charge capacity": "满充容量",
    "Design capacity": "设计容量",
    "Charge remaining": "剩余电荷",
    "Start charging below": "充电起始阈值",
    "Stop charging at": "充电上限",
    "Power mode": "电源模式",
    "Could not change the power mode": "无法切换电源模式",
    "No power modes available": "暂无可用的电源模式",
    "Show battery percentage": "显示电量百分比",
    "balanced": "平衡",
    "power-saver": "省电",
    "performance": "高性能",
    "USB": "USB",
    "Mains": "电源适配器",
    "Wireless": "无线充电",
    "Reading…": "正在读取…",
    "Close": "关闭"
};

function tr(text) {
    return /^zh(?:-|$)/i.test(I18n.code()) ? (chinese[text] || text) : text;
}

function rate(bytes, compact) {
    if (!Number.isFinite(bytes)) return "—";
    var units = compact ? ["B/s", "K/s", "M/s", "G/s", "T/s"] : ["B/s", "KiB/s", "MiB/s", "GiB/s", "TiB/s"];
    var unit = 0;
    while (bytes >= (compact ? 999.5 : 1024) && unit < units.length - 1) {
        bytes /= 1024;
        unit++;
    }
    return bytes.toFixed(unit && bytes < 10 ? 1 : 0) + (compact ? "" : " ") + units[unit];
}

function quantity(value, unit, decimals) {
    return typeof value === "number" && isFinite(value) ? value.toFixed(decimals) + (unit === "%" ? "" : " ") + unit : "";
}

function duration(seconds) {
    var minutes = Math.max(1, Math.ceil(seconds / 60));
    var hours = Math.floor(minutes / 60);
    return hours > 0 ? hours + " h " + (minutes % 60) + " min" : minutes + " min";
}

// 4-tier thermal scale: cool (< 50°C) green, normal (50-64°C) cyan, warm (65-79°C) amber, hot (>= 80°C) red.
function thermalColor(temp, dark, fallback) {
    if (typeof temp !== "number" || !isFinite(temp))
        return fallback || (dark ? "#e6e8ef" : "#3b4252");
    if (temp >= 80)
        return dark ? "#ff453a" : "#c92a22";
    if (temp >= 65)
        return dark ? "#ff9f0a" : "#b85d00";
    if (temp >= 50)
        return dark ? "#64d2ff" : "#0071a4";
    return dark ? "#30d158" : "#1c8241";
}

// Menu-bar thermometer: the bar stays monochrome until the CPU runs warm (65 °C), then shares the panel's amber and red.
function barThermalColor(temp, dark, ink) {
    if (typeof temp !== "number" || !isFinite(temp) || temp < 65)
        return ink;
    return thermalColor(temp, dark, ink);
}

// 4-tier load scale (%): low (< 35%) green, normal (35-64%) cyan, high (65-84%) amber, critical (>= 85%) red.
function loadColor(percent, dark, fallback) {
    if (typeof percent !== "number" || !isFinite(percent))
        return fallback || (dark ? "#e6e8ef" : "#3b4252");
    if (percent >= 85)
        return dark ? "#ff453a" : "#c92a22";
    if (percent >= 65)
        return dark ? "#ff9f0a" : "#b85d00";
    if (percent >= 35)
        return dark ? "#64d2ff" : "#0071a4";
    return dark ? "#30d158" : "#1c8241";
}

// 4-tier semantic power palette aligned with thermal/load/quota colors (green = healthiest):
// charging or external passthrough -> green; on battery: > 65% green, 36-65% cyan, 20-35% amber, < 20% red.
function powerColor(charging, onBattery, charge, dark, neutral) {
    if (charging)
        return dark ? "#30d158" : "#1c8241";
    if (typeof charge === "number" && isFinite(charge) && charge < 20)
        return dark ? "#ff453a" : "#c92a22";
    if (!onBattery)
        return dark ? "#30d158" : "#1c8241";
    if (typeof charge === "number" && isFinite(charge)) {
        if (charge <= 35)
            return dark ? "#ff9f0a" : "#b85d00";
        if (charge <= 65)
            return dark ? "#64d2ff" : "#0071a4";
        return dark ? "#30d158" : "#1c8241";
    }
    return neutral || (dark ? "#e6e8ef" : "#3b4252");
}
