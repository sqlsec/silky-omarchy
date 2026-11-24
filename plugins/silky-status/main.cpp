// silky-status — Native C++ telemetry streamer for MacShell top bar and thermal monitor.
//
// Implements the always-on `bar` mode and the `/proc`-heavy `thermal` mode natively in C++
// (~1.5 MB RSS, <0.05% CPU), emitting JSON lines 100% compatible with status.py.
// Infrequent on-demand modes (`network`, `power`, `profiles`, `set-charge-limit`) exec the
// sibling `silky-status.py` directly so all hardware/D-Bus edge cases stay identical.

#include <algorithm>
#include <array>
#include <cctype>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <deque>
#include <dirent.h>
#include <fcntl.h>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits.h>
#include <map>
#include <optional>
#include <regex>
#include <sstream>
#include <string>
#include <string_view>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
#include <unordered_map>
#include <utility>
#include <vector>

namespace fs = std::filesystem;

namespace {

long g_clockTicks = 100;

bool readFile(const std::string& path, std::string& out) {
    int fd = ::open(path.c_str(), O_RDONLY | O_CLOEXEC);
    if (fd < 0)
        return false;
    out.clear();
    char    buf[4096];
    ssize_t n;
    while ((n = ::read(fd, buf, sizeof(buf))) > 0)
        out.append(buf, static_cast<size_t>(n));
    ::close(fd);
    return n >= 0;
}

std::string readTrimmed(const std::string& path) {
    std::string s;
    if (!readFile(path, s))
        return {};
    while (!s.empty() && std::isspace(static_cast<unsigned char>(s.back())))
        s.pop_back();
    size_t i = 0;
    while (i < s.size() && std::isspace(static_cast<unsigned char>(s[i])))
        ++i;
    return s.substr(i);
}

std::optional<double> readNumber(const std::string& path, double scale = 1.0) {
    std::string s = readTrimmed(path);
    if (s.empty())
        return std::nullopt;
    char*     end = nullptr;
    long long v   = std::strtoll(s.c_str(), &end, 10);
    if (end == s.c_str() || *end != '\0')
        return std::nullopt;
    return static_cast<double>(v) / scale;
}

std::string jsonEscape(std::string_view s) {
    std::string out;
    out.reserve(s.size() + 2);
    out.push_back('"');
    for (unsigned char c : s) {
        switch (c) {
            case '"': out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\b': out += "\\b"; break;
            case '\f': out += "\\f"; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            default:
                if (c < 0x20) {
                    char buf[8];
                    std::snprintf(buf, sizeof(buf), "\\u%04x", c);
                    out += buf;
                } else {
                    out.push_back(static_cast<char>(c));
                }
        }
    }
    out.push_back('"');
    return out;
}

std::string jsonOptDouble(std::optional<double> v) {
    if (!v.has_value() || !std::isfinite(*v))
        return "null";
    char buf[64];
    std::snprintf(buf, sizeof(buf), "%.6g", *v);
    return buf;
}

double monotonicSec() {
    struct timespec ts{};
    ::clock_gettime(CLOCK_MONOTONIC, &ts);
    return static_cast<double>(ts.tv_sec) + static_cast<double>(ts.tv_nsec) * 1e-9;
}

double boottimeSec() {
    struct timespec ts{};
    ::clock_gettime(CLOCK_BOOTTIME, &ts);
    return static_cast<double>(ts.tv_sec) + static_cast<double>(ts.tv_nsec) * 1e-9;
}

bool startsWithCaseInsensitive(std::string_view s, std::string_view prefix) {
    if (s.size() < prefix.size())
        return false;
    for (size_t i = 0; i < prefix.size(); ++i)
        if (std::tolower(static_cast<unsigned char>(s[i])) != std::tolower(static_cast<unsigned char>(prefix[i])))
            return false;
    return true;
}

bool containsCaseInsensitive(std::string_view hay, std::string_view needle) {
    if (needle.empty() || hay.size() < needle.size())
        return false;
    for (size_t i = 0; i + needle.size() <= hay.size(); ++i) {
        bool ok = true;
        for (size_t j = 0; j < needle.size(); ++j) {
            if (std::tolower(static_cast<unsigned char>(hay[i + j])) != std::tolower(static_cast<unsigned char>(needle[j]))) {
                ok = false;
                break;
            }
        }
        if (ok)
            return true;
    }
    return false;
}

std::vector<std::string> listDirSorted(const std::string& dirPath, const char* prefix = nullptr) {
    std::vector<std::string> out;
    DIR*                     d = ::opendir(dirPath.c_str());
    if (!d)
        return out;
    const size_t   plen = prefix ? std::strlen(prefix) : 0;
    struct dirent* ent;
    while ((ent = ::readdir(d)) != nullptr) {
        if (ent->d_name[0] == '.')
            continue;
        if (prefix && std::strncmp(ent->d_name, prefix, plen) != 0)
            continue;
        out.emplace_back(ent->d_name);
    }
    ::closedir(d);
    std::sort(out.begin(), out.end());
    return out;
}

// ── network counters ──────────────────────────────────────────────────────────────────────────────
using NetMap = std::unordered_map<std::string, std::pair<uint64_t, uint64_t>>;

NetMap readNetCounters() {
    std::string text;
    if (!readFile("/proc/net/dev", text))
        return {};
    NetMap             all;
    std::istringstream iss(text);
    std::string        line;
    int                lineNo = 0;
    while (std::getline(iss, line)) {
        if (++lineNo <= 2)
            continue;
        auto colon = line.find(':');
        if (colon == std::string::npos)
            continue;
        std::string iface = line.substr(0, colon);
        while (!iface.empty() && std::isspace(static_cast<unsigned char>(iface.front())))
            iface.erase(iface.begin());
        while (!iface.empty() && std::isspace(static_cast<unsigned char>(iface.back())))
            iface.pop_back();
        if (iface == "lo" || iface.empty())
            continue;
        std::istringstream fss(line.substr(colon + 1));
        uint64_t           rx = 0, dummy = 0, tx = 0;
        if (!(fss >> rx))
            continue;
        for (int k = 1; k < 8; ++k)
            fss >> dummy;
        if (!(fss >> tx))
            continue;
        all[iface] = {rx, tx};
    }

    NetMap physical;
    for (const auto& [name, vals] : all) {
        struct stat sb{};
        std::string devPath = "/sys/class/net/" + name + "/device";
        if (::stat(devPath.c_str(), &sb) == 0) {
            std::string state = readTrimmed("/sys/class/net/" + name + "/operstate");
            if (state != "down" && state != "notpresent" && state != "lowerlayerdown")
                physical[name] = vals;
        }
    }
    if (!physical.empty())
        return physical;

    NetMap fallback;
    for (const auto& [name, vals] : all) {
        if (readTrimmed("/sys/class/net/" + name + "/operstate") != "down")
            fallback[name] = vals;
    }
    return fallback;
}

// ── CPU temperature ───────────────────────────────────────────────────────────────────────────────
std::optional<double> readMaxCpuTemp() {
    std::optional<double> maxT;
    for (const auto& name : listDirSorted("/sys/class/thermal", "thermal_zone")) {
        std::string base = "/sys/class/thermal/" + name;
        std::string type = readTrimmed(base + "/type");
        if (startsWithCaseInsensitive(type, "cpu")
            || startsWithCaseInsensitive(type, "x86_pkg_temp")
            || startsWithCaseInsensitive(type, "soc_thermal")
            || startsWithCaseInsensitive(type, "tegra")) {
            auto t = readNumber(base + "/temp", 1000.0);
            if (t && *t > -20.0 && *t < 150.0)
                maxT = maxT ? std::max(*maxT, *t) : *t;
        }
    }
    if (maxT)
        return maxT;

    for (const auto& dev : listDirSorted("/sys/class/hwmon", "hwmon")) {
        std::string base = "/sys/class/hwmon/" + dev;
        std::string name = readTrimmed(base + "/name");
        if (name == "coretemp" || name == "k10temp" || name == "zenpower" || name == "cpu_thermal" || name == "cpu-thermal") {
            for (const auto& f : listDirSorted(base, "temp")) {
                if (f.size() > 6 && f.ends_with("_input")) {
                    auto t = readNumber(base + "/" + f, 1000.0);
                    if (t && *t > -20.0 && *t < 150.0)
                        maxT = maxT ? std::max(*maxT, *t) : *t;
                }
            }
        }
    }
    return maxT;
}

// ── battery power & health logging ────────────────────────────────────────────────────────────────
bool isInternalBattery(const std::string& devPath) {
    return readTrimmed(devPath + "/type") == "Battery"
           && readTrimmed(devPath + "/scope") != "Device"
           && readTrimmed(devPath + "/present") != "0";
}

bool externalPowerOnline() {
    for (const auto& name : listDirSorted("/sys/class/power_supply")) {
        std::string base = "/sys/class/power_supply/" + name;
        if (readTrimmed(base + "/type") != "Battery" && readTrimmed(base + "/online") == "1")
            return true;
    }
    return false;
}

struct BatterySample {
    std::string status;
    double      watts = 0.0;
    bool        onBattery = false;
};

std::optional<BatterySample> readBatteryPowerSample() {
    for (const auto& name : listDirSorted("/sys/class/power_supply")) {
        std::string base = "/sys/class/power_supply/" + name;
        if (!isInternalBattery(base))
            continue;
        std::string st = readTrimmed(base + "/status");
        bool        onBat = !externalPowerOnline();
        if (st == "Charging" || st == "Discharging") {
            auto watts = readNumber(base + "/power_now", 1e6);
            if (!watts) {
                auto v = readNumber(base + "/voltage_now", 1e6);
                auto c = readNumber(base + "/current_now", 1e6);
                if (v && c)
                    watts = (*v) * (*c);
            }
            if (watts)
                return BatterySample{st, std::abs(*watts), onBat};
            return std::nullopt;
        }
        if (st == "Not charging" || st == "Full")
            return BatterySample{"Idle", 0.0, onBat};
    }
    return std::nullopt;
}

std::string stateHomeDir() {
    const char* xdg = std::getenv("XDG_STATE_HOME");
    if (xdg && *xdg)
        return xdg;
    const char* home = std::getenv("HOME");
    return std::string(home ? home : "") + "/.local/state";
}

void logBatteryHealth(std::unordered_map<std::string, std::pair<std::string, std::string>>& logged, bool& loaded) {
    const std::string logPath = stateHomeDir() + "/silky/battery-health.csv";
    if (!loaded) {
        loaded = true;
        std::ifstream in(logPath);
        std::string   line;
        bool          first = true;
        while (std::getline(in, line)) {
            if (first) {
                first = false;
                continue;
            }
            std::vector<std::string> fields;
            std::stringstream        ss(line);
            std::string              tok;
            while (std::getline(ss, tok, ','))
                fields.push_back(tok);
            if (fields.size() == 7 && fields[0].size() >= 10)
                logged[fields[1]] = {fields[0].substr(0, 10), fields[3]};
        }
    }

    std::time_t t = std::time(nullptr);
    struct tm   tmBuf{};
    ::localtime_r(&t, &tmBuf);
    char nowStr[32];
    std::strftime(nowStr, sizeof(nowStr), "%Y-%m-%dT%H:%M:%S", &tmBuf);
    std::string today(nowStr, 10);

    std::vector<std::string> rows;
    for (const auto& name : listDirSorted("/sys/class/power_supply")) {
        std::string base = "/sys/class/power_supply/" + name;
        if (!isInternalBattery(base))
            continue;
        auto eFull   = readNumber(base + "/energy_full", 1e6);
        auto full    = eFull ? eFull : readNumber(base + "/charge_full", 1e6);
        auto design  = eFull ? readNumber(base + "/energy_full_design", 1e6) : readNumber(base + "/charge_full_design", 1e6);
        if (!full || !design || *full <= 0 || *design <= 0)
            continue;
        char fullBuf[32], designBuf[32], healthBuf[32];
        std::snprintf(fullBuf, sizeof(fullBuf), "%.3f", *full);
        std::snprintf(designBuf, sizeof(designBuf), "%.3f", *design);
        std::snprintf(healthBuf, sizeof(healthBuf), "%.2f", 100.0 * (*full) / (*design));
        std::string fullText(fullBuf);
        auto        it = logged.find(name);
        if (it != logged.end() && it->second.first == today && it->second.second == fullText)
            continue;
        std::string model = readTrimmed(base + "/model_name");
        std::replace(model.begin(), model.end(), ',', ' ');
        std::string cycles = readTrimmed(base + "/cycle_count");
        rows.push_back(std::string(nowStr) + "," + name + "," + model + "," + fullText + "," + designBuf + "," + healthBuf + "," + cycles);
        logged[name] = {today, fullText};
    }
    if (rows.empty())
        return;

    std::error_code ec;
    fs::create_directories(fs::path(logPath).parent_path(), ec);
    bool          isNew = !fs::exists(logPath, ec);
    std::ofstream out(logPath, std::ios::app);
    if (!out)
        return;
    if (isNew)
        out << "time,battery,model,full_wh,design_wh,health_pct,cycles\n";
    for (const auto& r : rows)
        out << r << "\n";
}

// ── wallpaper accent (runs `magick` ONLY when wallpaper realpath or mtime changes) ────────────────
struct AccentCache {
    std::string key;
    std::string jsonVal = "null";
};

std::string hlsToHex(double h, double l, double s) {
    auto hue2rgb = [](double p, double q, double t) {
        if (t < 0.0) t += 1.0;
        if (t > 1.0) t -= 1.0;
        if (t < 1.0 / 6.0) return p + (q - p) * 6.0 * t;
        if (t < 1.0 / 2.0) return q;
        if (t < 2.0 / 3.0) return p + (q - p) * (2.0 / 3.0 - t) * 6.0;
        return p;
    };
    double r, g, b;
    if (s == 0.0) {
        r = g = b = l;
    } else {
        double q = l < 0.5 ? l * (1.0 + s) : l + s - l * s;
        double p = 2.0 * l - q;
        r        = hue2rgb(p, q, h + 1.0 / 3.0);
        g        = hue2rgb(p, q, h);
        b        = hue2rgb(p, q, h - 1.0 / 3.0);
    }
    char buf[16];
    std::snprintf(buf, sizeof(buf), "#%02x%02x%02x",
                  static_cast<int>(std::lround(r * 255.0)),
                  static_cast<int>(std::lround(g * 255.0)),
                  static_cast<int>(std::lround(b * 255.0)));
    return buf;
}

std::string readWallpaperAccentJson(AccentCache& cache) {
    const std::string link = stateHomeDir() + "/omarchy/current/background";
    char              resolved[PATH_MAX];
    if (!::realpath(link.c_str(), resolved))
        return "null";
    struct stat sb{};
    if (::stat(resolved, &sb) != 0)
        return "null";
    std::string key = std::string(resolved) + ":" + std::to_string(sb.st_mtim.tv_sec) + "." + std::to_string(sb.st_mtim.tv_nsec);
    if (cache.key == key)
        return cache.jsonVal;

    cache.key     = key;
    cache.jsonVal = "null";

    int pipefd[2];
    if (::pipe(pipefd) != 0)
        return cache.jsonVal;
    pid_t pid = ::fork();
    if (pid == 0) {
        ::close(pipefd[0]);
        ::dup2(pipefd[1], STDOUT_FILENO);
        ::close(pipefd[1]);
        int devnull = ::open("/dev/null", O_WRONLY);
        if (devnull >= 0) {
            ::dup2(devnull, STDERR_FILENO);
            ::close(devnull);
        }
        std::string arg0 = std::string(resolved) + "[0]";
        ::execlp("magick", "magick", arg0.c_str(), "-thumbnail", "96x96!", "-colors", "16", "-depth", "8",
                 "-format", "%c", "histogram:info:-", static_cast<char*>(nullptr));
        ::_exit(127);
    }
    ::close(pipefd[1]);
    std::string hist;
    if (pid > 0) {
        char    buf[4096];
        ssize_t n;
        while ((n = ::read(pipefd[0], buf, sizeof(buf))) > 0)
            hist.append(buf, static_cast<size_t>(n));
        int st = 0;
        ::waitpid(pid, &st, 0);
    }
    ::close(pipefd[0]);

    static const std::regex re(R"((\d+):\s*\(\s*(\d+),\s*(\d+),\s*(\d+))");
    double                  bestScore = -1.0, bestChroma = 0.0;
    std::array<double, 3>   bestRgb{0, 0, 0};
    for (std::sregex_iterator it(hist.begin(), hist.end(), re), end; it != end; ++it) {
        double cnt = std::stod((*it)[1].str());
        double r   = std::stod((*it)[2].str()) / 255.0;
        double g   = std::stod((*it)[3].str()) / 255.0;
        double b   = std::stod((*it)[4].str()) / 255.0;
        double mx  = std::max({r, g, b});
        double mn  = std::min({r, g, b});
        double ch  = mx - mn;
        double sc  = cnt * ch * ch;
        if (sc > bestScore) {
            bestScore  = sc;
            bestChroma = ch;
            bestRgb    = {r, g, b};
        }
    }
    if (bestScore >= 0.0 && bestChroma >= 0.12) {
        double r = bestRgb[0], g = bestRgb[1], b = bestRgb[2];
        double mx = std::max({r, g, b}), mn = std::min({r, g, b});
        double l = (mx + mn) / 2.0;
        double d = mx - mn;
        double h = 0.0, s = 0.0;
        if (d > 0.0) {
            s = l > 0.5 ? d / (2.0 - mx - mn) : d / (mx + mn);
            if (mx == r)
                h = (g - b) / d + (g < b ? 6.0 : 0.0);
            else if (mx == g)
                h = (b - r) / d + 2.0;
            else
                h = (r - g) / d + 4.0;
            h /= 6.0;
        }
        s = std::clamp(s, 0.5, 0.85);
        cache.jsonVal = "{\"dark\":" + jsonEscape(hlsToHex(h, 0.72, s))
                        + ",\"light\":" + jsonEscape(hlsToHex(h, 0.38, s)) + "}";
    }
    return cache.jsonVal;
}

// ── thermal mode: /proc scanner + hwmon overview + system usage ───────────────────────────────────
struct ProcKey {
    int      pid;
    uint64_t start;
    bool     operator==(const ProcKey& o) const = default;
};
struct ProcKeyHash {
    size_t operator()(const ProcKey& k) const noexcept {
        return std::hash<int>{}(k.pid) ^ (std::hash<uint64_t>{}(k.start) * 0x9e3779b97f4a7c15ULL);
    }
};
using ProcMap = std::unordered_map<ProcKey, std::pair<std::string, uint64_t>, ProcKeyHash>;

bool isDigits(const char* s) {
    if (!s || !*s)
        return false;
    for (; *s; ++s)
        if (*s < '0' || *s > '9')
            return false;
    return true;
}

ProcMap readCpuProcesses() {
    ProcMap out;
    DIR*    d = ::opendir("/proc");
    if (!d)
        return out;
    char           path[64];
    char           buf[1024];
    struct dirent* ent;
    while ((ent = ::readdir(d)) != nullptr) {
        if (!isDigits(ent->d_name))
            continue;
        int pid = std::atoi(ent->d_name);
        std::snprintf(path, sizeof(path), "/proc/%d/stat", pid);
        int fd = ::open(path, O_RDONLY | O_CLOEXEC);
        if (fd < 0)
            continue;
        ssize_t n = ::read(fd, buf, sizeof(buf) - 1);
        ::close(fd);
        if (n <= 0)
            continue;
        buf[n] = '\0';

        const char* lparen = std::strchr(buf, '(');
        const char* rparen = std::strrchr(buf, ')');
        if (!lparen || !rparen || rparen <= lparen || rparen[1] != ' ')
            continue;
        std::string name(lparen + 1, static_cast<size_t>(rparen - lparen - 1));
        const char* p = rparen + 2;

        // field 0 = state; 11 = utime; 12 = stime; 19 = starttime
        int      idx = 0;
        char     state = 0;
        uint64_t utime = 0, stime = 0, start = 0;
        bool     gotStart = false;
        while (*p) {
            while (*p == ' ')
                ++p;
            if (!*p)
                break;
            const char* tok = p;
            while (*p && *p != ' ')
                ++p;
            if (idx == 0) {
                state = *tok;
                if (state == 'Z' || state == 'X')
                    break;
            } else if (idx == 11) {
                utime = std::strtoull(tok, nullptr, 10);
            } else if (idx == 12) {
                stime = std::strtoull(tok, nullptr, 10);
            } else if (idx == 19) {
                start    = std::strtoull(tok, nullptr, 10);
                gotStart = true;
                break;
            }
            ++idx;
        }
        if (gotStart)
            out.emplace(ProcKey{pid, start}, std::make_pair(std::move(name), utime + stime));
    }
    ::closedir(d);
    return out;
}

std::optional<std::pair<uint64_t, uint64_t>> readCpuTimes() {
    std::string text;
    if (!readFile("/proc/stat", text))
        return std::nullopt;
    auto               nl = text.find('\n');
    std::istringstream iss(nl == std::string::npos ? text : text.substr(0, nl));
    std::string        tag;
    uint64_t           v[8] = {0};
    if (!(iss >> tag) || tag != "cpu")
        return std::nullopt;
    for (int i = 0; i < 8; ++i)
        if (!(iss >> v[i]))
            return std::nullopt;
    uint64_t total = 0;
    for (int i = 0; i < 8; ++i)
        total += v[i];
    return std::make_pair(total, v[3] + v[4]);
}

std::optional<double> percentage(double used, double total) {
    if (total <= 0.0)
        return std::nullopt;
    return std::clamp(100.0 * used / total, 0.0, 100.0);
}

std::string buildHardwareOverviewJson() {
    struct Cat {
        const char* name;
        bool (*match)(std::string_view);
    };
    static const Cat cats[] = {
        {"GPU", [](std::string_view n) {
            return startsWithCaseInsensitive(n, "gpu") || startsWithCaseInsensitive(n, "amdgpu")
                   || startsWithCaseInsensitive(n, "nouveau") || startsWithCaseInsensitive(n, "i915")
                   || (startsWithCaseInsensitive(n, "xe") && (n.size() == 2 || !std::isalnum(static_cast<unsigned char>(n[2]))));
        }},
        {"SSD", [](std::string_view n) { return startsWithCaseInsensitive(n, "nvme"); }},
        {"Wi-Fi", [](std::string_view n) {
            return startsWithCaseInsensitive(n, "ath") || startsWithCaseInsensitive(n, "iwlwifi")
                   || startsWithCaseInsensitive(n, "mt76");
        }},
        {"Memory", [](std::string_view n) {
            return startsWithCaseInsensitive(n, "mem_thermal") || startsWithCaseInsensitive(n, "mem-thermal")
                   || startsWithCaseInsensitive(n, "spd") || startsWithCaseInsensitive(n, "jc42");
        }},
        {"Battery", [](std::string_view n) {
            return containsCaseInsensitive(n, "battery") || containsCaseInsensitive(n, "battmgr-bat")
                   || containsCaseInsensitive(n, "battmgr_bat") || containsCaseInsensitive(n, "battmgr bat");
        }},
    };

    std::unordered_map<std::string, double> temps;
    std::optional<double>                   maxFan;
    for (const auto& dev : listDirSorted("/sys/class/hwmon", "hwmon")) {
        std::string base = "/sys/class/hwmon/" + dev;
        std::string name = readTrimmed(base + "/name");
        for (const auto& f : listDirSorted(base)) {
            if (f.starts_with("fan") && f.ends_with("_input")) {
                auto spd = readNumber(base + "/" + f);
                if (spd)
                    maxFan = maxFan ? std::max(*maxFan, *spd) : *spd;
            }
        }
        for (const auto& c : cats) {
            if (!c.match(name))
                continue;
            for (const auto& f : listDirSorted(base, "temp")) {
                if (!f.ends_with("_input"))
                    continue;
                auto v = readNumber(base + "/" + f, 1000.0);
                if (v && *v > -20.0 && *v < 150.0) {
                    auto it = temps.find(c.name);
                    temps[c.name] = (it == temps.end()) ? *v : std::max(it->second, *v);
                }
            }
        }
    }

    std::string out = "[";
    bool        first = true;
    for (const auto& c : cats) {
        auto it = temps.find(c.name);
        if (it == temps.end())
            continue;
        if (!first) out += ",";
        first = false;
        out += "[" + jsonEscape(c.name) + "," + jsonOptDouble(it->second) + "," + jsonEscape("°C") + "]";
    }
    if (maxFan) {
        if (!first) out += ",";
        out += "[\"Fan\"," + jsonOptDouble(*maxFan) + ",\"RPM\"]";
    }
    out += "]";
    return out;
}

std::string buildResourceUsageJson(std::optional<std::pair<uint64_t, uint64_t>> curCpu,
                                   std::optional<std::pair<uint64_t, uint64_t>> prevCpu) {
    std::optional<double> cpuPct;
    if (curCpu && prevCpu) {
        double dt   = static_cast<double>(curCpu->first - prevCpu->first);
        double idle = static_cast<double>(curCpu->second - prevCpu->second);
        cpuPct      = percentage(dt - idle, dt);
    }

    std::optional<double> memPct;
    std::string           memText;
    if (readFile("/proc/meminfo", memText)) {
        uint64_t           total = 0, avail = 0;
        bool               gotT = false, gotA = false;
        std::istringstream iss(memText);
        std::string        line;
        while (std::getline(iss, line)) {
            if (line.starts_with("MemTotal:")) {
                std::istringstream ls(line.substr(9));
                ls >> total;
                gotT = true;
            } else if (line.starts_with("MemAvailable:")) {
                std::istringstream ls(line.substr(13));
                ls >> avail;
                gotA = true;
            }
            if (gotT && gotA)
                break;
        }
        if (gotT && gotA && total > 0)
            memPct = percentage(static_cast<double>(total - avail), static_cast<double>(total));
    }

    std::optional<double> diskPct;
    struct statvfs        sv{};
    if (::statvfs("/", &sv) == 0) {
        double used = static_cast<double>(sv.f_blocks - sv.f_bfree);
        diskPct     = percentage(used, used + static_cast<double>(sv.f_bavail));
    }

    return "{\"cpu\":" + jsonOptDouble(cpuPct)
           + ",\"memory\":" + jsonOptDouble(memPct)
           + ",\"disk\":" + jsonOptDouble(diskPct) + "}";
}

void runBarMode() {
    std::optional<NetMap>                    prevNet;
    double                                   prevAt = 0.0;
    std::deque<std::optional<double>>        trendDown, trendUp, trendTemp;
    std::deque<std::optional<BatterySample>> batHistory;
    std::optional<double>                    batSampleAt;
    std::unordered_map<std::string, std::pair<std::string, std::string>> healthLogged;
    bool        healthLoaded = false;
    AccentCache accentCache;

    auto pushTrend = [](std::deque<std::optional<double>>& q, std::optional<double> v) {
        if (q.size() >= 40)
            q.pop_front();
        q.push_back(v);
    };
    auto fmtTrend = [](const std::deque<std::optional<double>>& q) {
        std::string s = "[";
        for (size_t i = 0; i < q.size(); ++i) {
            if (i) s += ",";
            s += jsonOptDouble(q[i]);
        }
        s += "]";
        return s;
    };

    struct timespec sleepTs{1, 500000000L};
    while (true) {
        NetMap                counters = readNetCounters();
        double                now      = monotonicSec();
        std::optional<double> down, up;
        if (prevNet && now > prevAt) {
            double dt = now - prevAt;
            double dSum = 0.0, uSum = 0.0;
            for (const auto& [name, cur] : counters) {
                auto it = prevNet->find(name);
                if (it != prevNet->end()) {
                    if (cur.first >= it->second.first)
                        dSum += static_cast<double>(cur.first - it->second.first) / dt;
                    if (cur.second >= it->second.second)
                        uSum += static_cast<double>(cur.second - it->second.second) / dt;
                }
            }
            down = dSum;
            up   = uSum;
        }
        auto temp = readMaxCpuTemp();
        pushTrend(trendDown, down);
        pushTrend(trendUp, up);
        pushTrend(trendTemp, temp);

        double bt = boottimeSec();
        if (!batSampleAt || bt - *batSampleAt >= 3.0) {
            if (batSampleAt) {
                int missing = std::min(100, std::max(0, static_cast<int>(std::llround((bt - *batSampleAt) / 3.0)) - 1));
                for (int i = 0; i < missing; ++i) {
                    if (batHistory.size() >= 100) batHistory.pop_front();
                    batHistory.push_back(std::nullopt);
                }
            }
            if (batHistory.size() >= 100)
                batHistory.pop_front();
            batHistory.push_back(readBatteryPowerSample());
            if (!batSampleAt || static_cast<long long>(bt / 600.0) != static_cast<long long>(*batSampleAt / 600.0))
                logBatteryHealth(healthLogged, healthLoaded);
            batSampleAt = bt;
        }

        std::string batJson = "[";
        for (size_t i = 0; i < batHistory.size(); ++i) {
            if (i) batJson += ",";
            if (!batHistory[i]) {
                batJson += "null";
            } else {
                batJson += "[" + jsonEscape(batHistory[i]->status) + "," + jsonOptDouble(batHistory[i]->watts)
                           + "," + (batHistory[i]->onBattery ? "true" : "false") + "]";
            }
        }
        batJson += "]";

        std::string accentJson = readWallpaperAccentJson(accentCache);

        std::cout << "{\"down\":" << jsonOptDouble(down)
                  << ",\"up\":" << jsonOptDouble(up)
                  << ",\"temp\":" << jsonOptDouble(temp)
                  << ",\"trend\":{\"down\":" << fmtTrend(trendDown)
                  << ",\"up\":" << fmtTrend(trendUp)
                  << ",\"temp\":" << fmtTrend(trendTemp) << "}"
                  << ",\"batteryPowerHistory\":" << batJson
                  << ",\"wallpaperAccent\":" << accentJson << "}\n"
                  << std::flush;

        prevNet = std::move(counters);
        prevAt  = now;
        ::nanosleep(&sleepTs, nullptr);
    }
}

void runThermalMode() {
    std::optional<ProcMap>                        prevProcs;
    std::optional<std::pair<uint64_t, uint64_t>>  prevCpu;
    double                                        prevAt = 0.0;
    struct timespec                               sleepTs{1, 500000000L};

    while (true) {
        ProcMap curProcs = readCpuProcesses();
        auto    curCpu   = readCpuTimes();
        double  now      = monotonicSec();

        struct Row {
            int         pid;
            std::string name;
            double      pct;
        };
        std::vector<Row> rows;
        if (prevProcs && now > prevAt) {
            double denom = static_cast<double>(g_clockTicks) * (now - prevAt);
            for (const auto& [key, val] : curProcs) {
                auto it = prevProcs->find(key);
                if (it != prevProcs->end() && val.second > it->second.second) {
                    double pct = 100.0 * static_cast<double>(val.second - it->second.second) / denom;
                    rows.push_back({key.pid, val.first, pct});
                }
            }
            std::sort(rows.begin(), rows.end(), [](const Row& a, const Row& b) {
                if (a.pct != b.pct) return a.pct > b.pct;
                return a.pid < b.pid;
            });
            if (rows.size() > 10)
                rows.resize(10);
        }

        std::string topJson = "[";
        for (size_t i = 0; i < rows.size(); ++i) {
            if (i) topJson += ",";
            topJson += "[" + std::to_string(rows[i].pid) + "," + jsonEscape(rows[i].name) + "," + jsonOptDouble(rows[i].pct) + "]";
        }
        topJson += "]";

        std::cout << "{\"cpuTop\":" << topJson
                  << ",\"sampling\":" << (prevProcs ? "false" : "true")
                  << ",\"overview\":" << buildHardwareOverviewJson()
                  << ",\"usage\":" << buildResourceUsageJson(curCpu, prevCpu) << "}\n"
                  << std::flush;

        prevProcs = std::move(curProcs);
        prevCpu   = curCpu;
        prevAt    = now;
        ::nanosleep(&sleepTs, nullptr);
    }
}

void execPythonFallback(int argc, char** argv) {
    char    selfPath[PATH_MAX];
    ssize_t n = ::readlink("/proc/self/exe", selfPath, sizeof(selfPath) - 1);
    std::string dir = ".";
    if (n > 0) {
        selfPath[n] = '\0';
        dir = fs::path(selfPath).parent_path().string();
    }
    std::string pyScript = dir + "/silky-status.py";
    std::vector<char*> args;
    args.push_back(const_cast<char*>("/usr/bin/python3"));
    args.push_back(const_cast<char*>("-I"));
    args.push_back(const_cast<char*>(pyScript.c_str()));
    for (int i = 1; i < argc; ++i)
        args.push_back(argv[i]);
    args.push_back(nullptr);
    ::execv("/usr/bin/python3", args.data());
    std::perror("execv python3");
    std::exit(127);
}

} // namespace

int main(int argc, char** argv) {
    g_clockTicks = ::sysconf(_SC_CLK_TCK);
    if (g_clockTicks <= 0)
        g_clockTicks = 100;

    if (argc == 2 && std::strcmp(argv[1], "bar") == 0) {
        runBarMode();
        return 0;
    }
    if (argc == 2 && std::strcmp(argv[1], "thermal") == 0) {
        runThermalMode();
        return 0;
    }
    execPythonFallback(argc, argv);
    return 0;
}
