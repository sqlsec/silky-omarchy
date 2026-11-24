// silky-desktop-priority — C++ rewrite of bin/silky-desktop-priority.
//
// Gives desktop UI processes (Hyprland, Xwayland, MacShell, fcitx5) CPU priority
// (nice + uclamp.min via sched_setattr) and an optional AC-power GPU devfreq floor.
// Drop-in replacement for the Python daemon with 100% compatible CLI and config.

#include <algorithm>
#include <atomic>
#include <cctype>
#include <cerrno>
#include <csignal>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <dirent.h>
#include <fcntl.h>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <linux/sched.h>
#include <sched.h>
#include <sstream>
#include <string>
#include <string_view>
#include <sys/resource.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace {

constexpr const char* DEFAULT_CONFIG = "/etc/silky/desktop-priority.conf";
constexpr const char* GPU_DEVFREQ_DIR = "/sys/class/devfreq";
constexpr const char* POWER_SUPPLY_DIR = "/sys/class/power_supply";
constexpr uint64_t    SILKY_SCHED_FLAG_UTIL_CLAMP_MIN = 0x20;

struct SchedAttr {
    uint32_t size;
    uint32_t sched_policy;
    uint64_t sched_flags;
    int32_t  sched_nice;
    uint32_t sched_priority;
    uint64_t sched_runtime;
    uint64_t sched_deadline;
    uint64_t sched_period;
    uint32_t sched_util_min;
    uint32_t sched_util_max;
};
static_assert(sizeof(SchedAttr) == 56, "SchedAttr must be 56 bytes (SCHED_ATTR_SIZE_VER1)");

struct Target {
    std::string comm;
    int         nice = 0;
    uint32_t    uclamp = 0;
};

struct Config {
    double                                  interval = 2.0;
    uid_t                                   minUid = 1000;
    uint64_t                                gpuAcMinMhz = 0;
    std::unordered_map<std::string, Target> targets;
    std::vector<std::string>                targetOrder;
};

std::atomic<bool> g_running{true};

void onSignal(int) {
    g_running.store(false, std::memory_order_relaxed);
}

std::string trim(std::string_view sv) {
    while (!sv.empty() && std::isspace(static_cast<unsigned char>(sv.front())))
        sv.remove_prefix(1);
    while (!sv.empty() && std::isspace(static_cast<unsigned char>(sv.back())))
        sv.remove_suffix(1);
    return std::string(sv);
}

bool readSmallFile(const char* path, char* buf, size_t cap, size_t& outLen) {
    int fd = ::open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0)
        return false;
    ssize_t n = ::read(fd, buf, cap - 1);
    ::close(fd);
    if (n < 0)
        return false;
    while (n > 0 && (buf[n - 1] == '\n' || buf[n - 1] == '\r' || buf[n - 1] == ' ' || buf[n - 1] == '\t'))
        --n;
    buf[n] = '\0';
    outLen = static_cast<size_t>(n);
    return true;
}

bool readSmallString(const std::string& path, std::string& out) {
    char   buf[1024];
    size_t len = 0;
    if (!readSmallFile(path.c_str(), buf, sizeof(buf), len))
        return false;
    out.assign(buf, len);
    return true;
}

bool isDigits(const char* s) {
    if (!s || !*s)
        return false;
    for (; *s; ++s)
        if (*s < '0' || *s > '9')
            return false;
    return true;
}

Config loadConfig(const std::string& path) {
    std::ifstream in(path);
    if (!in) {
        std::cerr << "Cannot read config: " << path << "\n";
        std::exit(1);
    }
    Config      cfg;
    std::string section;
    std::string line;
    while (std::getline(in, line)) {
        // Strip inline comments (# or ;)
        for (size_t i = 0; i < line.size(); ++i) {
            if (line[i] == '#' || line[i] == ';') {
                line.resize(i);
                break;
            }
        }
        std::string t = trim(line);
        if (t.empty())
            continue;
        if (t.front() == '[' && t.back() == ']') {
            section = trim(std::string_view(t).substr(1, t.size() - 2));
            continue;
        }
        auto eq = t.find('=');
        if (eq == std::string::npos)
            continue;
        std::string key = trim(std::string_view(t).substr(0, eq));
        std::string val = trim(std::string_view(t).substr(eq + 1));

        if (section == "general") {
            if (key == "interval")
                cfg.interval = std::max(0.2, std::stod(val));
            else if (key == "min_uid")
                cfg.minUid = static_cast<uid_t>(std::stoul(val));
        } else if (section == "gpu") {
            if (key == "ac_min_freq_mhz")
                cfg.gpuAcMinMhz = static_cast<uint64_t>(std::stoull(val));
        } else if (section == "targets") {
            std::istringstream iss(val);
            int                nice = 0;
            uint32_t           uclamp = 0;
            if (!(iss >> nice)) {
                std::cerr << key << ": invalid nice value\n";
                std::exit(1);
            }
            iss >> uclamp;
            if (nice < -15 || nice > 0) {
                std::cerr << key << ": nice must be between -15 and 0\n";
                std::exit(1);
            }
            if (uclamp > 1024) {
                std::cerr << key << ": uclamp_min must be between 0 and 1024\n";
                std::exit(1);
            }
            std::string comm = key.substr(0, 15);
            if (!cfg.targets.count(comm))
                cfg.targetOrder.push_back(comm);
            cfg.targets[comm] = Target{comm, nice, uclamp};
        }
    }
    return cfg;
}

int setThread(pid_t tid, int nice, uint32_t uclampMin) {
#ifdef SYS_sched_setattr
    SchedAttr attr{};
    attr.size           = sizeof(SchedAttr);
    attr.sched_policy   = SCHED_OTHER;
    attr.sched_flags    = SILKY_SCHED_FLAG_UTIL_CLAMP_MIN;
    attr.sched_nice     = nice;
    attr.sched_util_min = uclampMin;
    attr.sched_util_max = 1024;
    if (::syscall(SYS_sched_setattr, tid, &attr, 0) != 0)
        return errno;
    return 0;
#else
    if (::setpriority(PRIO_PROCESS, static_cast<id_t>(tid), nice) != 0)
        return errno;
    return 0;
#endif
}

bool getUclampMin(pid_t tid, uint32_t& out) {
#ifdef SYS_sched_getattr
    SchedAttr attr{};
    if (::syscall(SYS_sched_getattr, tid, &attr, sizeof(attr), 0) != 0)
        return false;
    out = attr.sched_util_min;
    return true;
#else
    (void)tid;
    (void)out;
    return false;
#endif
}

struct ThreadState {
    uint64_t starttime = 0;
    int      nice = 0;
    int      policy = 0;
};

bool readThreadState(pid_t pid, pid_t tid, ThreadState& st) {
    char path[64];
    std::snprintf(path, sizeof(path), "/proc/%d/task/%d/stat", pid, tid);
    char   buf[1024];
    size_t len = 0;
    if (!readSmallFile(path, buf, sizeof(buf), len))
        return false;
    const char* rparen = std::strrchr(buf, ')');
    if (!rparen || !rparen[1] || !rparen[2])
        return false;
    const char* p = rparen + 2;
    // After ") ", field 0 is state (field 3 overall); nice is field 16 (field 19 overall); starttime is field 19 (field 22 overall).
    int      fieldIdx = 0;
    int      niceVal = 0;
    uint64_t startVal = 0;
    bool     gotNice = false, gotStart = false;
    while (*p) {
        while (*p == ' ')
            ++p;
        if (!*p)
            break;
        const char* start = p;
        while (*p && *p != ' ')
            ++p;
        if (fieldIdx == 16) {
            niceVal = std::atoi(start);
            gotNice = true;
        } else if (fieldIdx == 19) {
            startVal = std::strtoull(start, nullptr, 10);
            gotStart = true;
            break;
        }
        ++fieldIdx;
    }
    if (!gotNice || !gotStart)
        return false;
    int policy = ::sched_getscheduler(tid);
    if (policy < 0)
        return false;
    st.starttime = startVal;
    st.nice      = niceVal;
    st.policy    = policy;
    return true;
}

class Booster {
  public:
    Booster(const Config& cfg, bool dryRun) : m_cfg(cfg), m_dryRun(dryRun) {}

    void scan() {
        DIR* procDir = ::opendir("/proc");
        if (!procDir)
            return;

        m_livePids.clear();
        m_liveTids.clear();

        struct dirent* ent;
        char           path[96];
        char           commBuf[64];
        while ((ent = ::readdir(procDir)) != nullptr) {
            if (!isDigits(ent->d_name))
                continue;
            const pid_t pid = std::atoi(ent->d_name);
            m_livePids.insert(pid);

            // Fast-path: read /proc/<pid>/comm (16 bytes) before touching stat/UID.
            std::snprintf(path, sizeof(path), "/proc/%d/comm", pid);
            size_t len = 0;
            if (!readSmallFile(path, commBuf, sizeof(commBuf), len))
                continue;
            auto it = m_cfg.targets.find(std::string(commBuf, len));
            if (it == m_cfg.targets.end())
                continue;

            struct stat sb{};
            std::snprintf(path, sizeof(path), "/proc/%d", pid);
            if (::stat(path, &sb) != 0 || sb.st_uid < m_cfg.minUid)
                continue;

            const Target& target = it->second;
            m_trackedPids[pid] = &target;
            boostProcess(pid, target);
        }
        ::closedir(procDir);

        for (auto it = m_trackedPids.begin(); it != m_trackedPids.end();) {
            if (!m_livePids.count(it->first))
                it = m_trackedPids.erase(it);
            else
                ++it;
        }
        for (auto it = m_applied.begin(); it != m_applied.end();) {
            if (!m_liveTids.count(it->first))
                it = m_applied.erase(it);
            else
                ++it;
        }
    }

    void updateGpu() {
        if (m_cfg.gpuAcMinMhz == 0)
            return;
        const bool wantFloor = onAc();
        for (const auto& dev : gpuDevices()) {
            std::string availStr, current;
            if (!readSmallString(dev + "/available_frequencies", availStr)
                || !readSmallString(dev + "/min_freq", current))
                continue;
            std::vector<uint64_t> avail;
            std::istringstream    iss(availStr);
            uint64_t              f = 0;
            while (iss >> f)
                avail.push_back(f);
            if (avail.empty())
                continue;
            std::sort(avail.begin(), avail.end());
            if (wantFloor) {
                uint64_t targetHz = avail.back();
                for (uint64_t cand : avail) {
                    if (cand >= m_cfg.gpuAcMinMhz * 1000000ULL) {
                        targetHz = cand;
                        break;
                    }
                }
                const std::string targetStr = std::to_string(targetHz);
                if (current != targetStr && writeGpu(dev, targetStr)) {
                    m_gpuSaved.emplace(dev, current);
                }
            } else {
                auto it = m_gpuSaved.find(dev);
                if (it != m_gpuSaved.end()) {
                    writeGpu(dev, it->second);
                    m_gpuSaved.erase(it);
                }
            }
        }
    }

    void restore() {
        for (const auto& [pid, target] : m_trackedPids) {
            if (!target)
                continue;
            char taskPath[64];
            std::snprintf(taskPath, sizeof(taskPath), "/proc/%d/task", pid);
            DIR* dir = ::opendir(taskPath);
            if (!dir)
                continue;
            struct dirent* ent;
            while ((ent = ::readdir(dir)) != nullptr) {
                if (!isDigits(ent->d_name))
                    continue;
                pid_t       tid = std::atoi(ent->d_name);
                ThreadState st;
                if (readThreadState(pid, tid, st) && st.policy == SCHED_OTHER && st.nice == target->nice)
                    setThread(tid, 0, 0);
            }
            ::closedir(dir);
        }
        for (auto it = m_gpuSaved.begin(); it != m_gpuSaved.end();) {
            writeGpu(it->first, it->second);
            it = m_gpuSaved.erase(it);
        }
        std::cout << "restored default priorities\n" << std::flush;
    }

    static std::vector<std::string> gpuDevices() {
        std::vector<std::string> out;
        DIR*                     dir = ::opendir(GPU_DEVFREQ_DIR);
        if (!dir)
            return out;
        struct dirent* ent;
        while ((ent = ::readdir(dir)) != nullptr) {
            if (ent->d_name[0] == '.')
                continue;
            if (std::strstr(ent->d_name, "gpu") != nullptr)
                out.push_back(std::string(GPU_DEVFREQ_DIR) + "/" + ent->d_name);
        }
        ::closedir(dir);
        std::sort(out.begin(), out.end());
        return out;
    }

  private:
    void boostProcess(pid_t pid, const Target& target) {
        char taskPath[64];
        std::snprintf(taskPath, sizeof(taskPath), "/proc/%d/task", pid);
        DIR* dir = ::opendir(taskPath);
        if (!dir)
            return;
        struct dirent* ent;
        while ((ent = ::readdir(dir)) != nullptr) {
            if (!isDigits(ent->d_name))
                continue;
            const pid_t tid = std::atoi(ent->d_name);
            m_liveTids.insert(tid);

            ThreadState st;
            if (!readThreadState(pid, tid, st))
                continue;
            auto ait = m_applied.find(tid);
            if (ait != m_applied.end() && ait->second == st.starttime)
                continue;
            if (st.policy != SCHED_OTHER || (st.nice != 0 && st.nice != target.nice)) {
                m_applied[tid] = st.starttime;
                continue;
            }
            if (m_dryRun) {
                std::cout << "would set " << target.comm << " pid " << pid << " tid " << tid
                          << ": nice " << st.nice << " -> " << target.nice
                          << ", uclamp.min " << target.uclamp << "\n" << std::flush;
            } else {
                int err = setThread(tid, target.nice, target.uclamp);
                if (err != 0) {
                    const std::string key = target.comm + ":" + std::to_string(err);
                    if (m_warned.insert(key).second) {
                        std::cout << "cannot boost " << target.comm << " tid " << tid
                                  << ": " << std::strerror(err) << "\n" << std::flush;
                    }
                    continue;
                }
            }
            m_applied[tid] = st.starttime;
        }
        ::closedir(dir);
    }

    bool onAc() const {
        DIR* dir = ::opendir(POWER_SUPPLY_DIR);
        if (!dir)
            return true;
        bool           hasBattery = false;
        bool           acOnline = false;
        struct dirent* ent;
        while ((ent = ::readdir(dir)) != nullptr) {
            if (ent->d_name[0] == '.')
                continue;
            std::string base = std::string(POWER_SUPPLY_DIR) + "/" + ent->d_name;
            std::string kind;
            if (readSmallString(base + "/type", kind) && kind == "Battery") {
                hasBattery = true;
            } else {
                std::string online;
                if (readSmallString(base + "/online", online) && online == "1") {
                    acOnline = true;
                    break;
                }
            }
        }
        ::closedir(dir);
        return acOnline || !hasBattery;
    }

    bool writeGpu(const std::string& dev, const std::string& value) {
        if (m_dryRun) {
            std::cout << "would set " << dev << "/min_freq = " << value << "\n" << std::flush;
            return false;
        }
        const std::string p = dev + "/min_freq";
        int               fd = ::open(p.c_str(), O_WRONLY | O_CLOEXEC);
        if (fd < 0) {
            const int         err = errno;
            const std::string key = dev + ":" + std::to_string(err);
            if (m_warned.insert(key).second)
                std::cout << "cannot set " << p << ": " << std::strerror(err) << "\n" << std::flush;
            return false;
        }
        ssize_t n = ::write(fd, value.data(), value.size());
        int     err = errno;
        ::close(fd);
        if (n < 0) {
            const std::string key = dev + ":" + std::to_string(err);
            if (m_warned.insert(key).second)
                std::cout << "cannot set " << p << ": " << std::strerror(err) << "\n" << std::flush;
            return false;
        }
        std::cout << p << " = " << value << "\n" << std::flush;
        return true;
    }

    const Config&                             m_cfg;
    bool                                      m_dryRun = false;
    std::unordered_map<pid_t, const Target*>  m_trackedPids;
    std::unordered_map<pid_t, uint64_t>       m_applied;
    std::unordered_set<pid_t>                 m_livePids;
    std::unordered_set<pid_t>                 m_liveTids;
    std::unordered_map<std::string, std::string> m_gpuSaved;
    std::unordered_set<std::string>           m_warned;
};

void printStatus(const Config& cfg) {
    std::cout << std::left << std::setw(16) << "process"
              << std::right << std::setw(8) << "pid"
              << std::setw(9) << "threads"
              << std::setw(9) << "boosted"
              << "  nice  uclamp.min\n";

    std::vector<pid_t> pids;
    if (DIR* dir = ::opendir("/proc")) {
        struct dirent* ent;
        while ((ent = ::readdir(dir)) != nullptr)
            if (isDigits(ent->d_name))
                pids.push_back(std::atoi(ent->d_name));
        ::closedir(dir);
    }
    std::sort(pids.begin(), pids.end());

    char path[96], commBuf[64];
    for (pid_t pid : pids) {
        std::snprintf(path, sizeof(path), "/proc/%d/comm", pid);
        size_t len = 0;
        if (!readSmallFile(path, commBuf, sizeof(commBuf), len))
            continue;
        std::string comm(commBuf, len);
        auto        it = cfg.targets.find(comm);
        if (it == cfg.targets.end())
            continue;
        const Target& target = it->second;

        std::snprintf(path, sizeof(path), "/proc/%d/task", pid);
        DIR* tdir = ::opendir(path);
        if (!tdir)
            continue;
        int            total = 0, boosted = 0;
        struct dirent* tent;
        while ((tent = ::readdir(tdir)) != nullptr) {
            if (!isDigits(tent->d_name))
                continue;
            ++total;
            ThreadState st;
            if (readThreadState(pid, std::atoi(tent->d_name), st) && st.nice == target.nice && target.nice != 0)
                ++boosted;
        }
        ::closedir(tdir);

        ThreadState mainSt;
        bool        hasMain = readThreadState(pid, pid, mainSt);
        uint32_t    uclamp = 0;
        bool        hasUclamp = getUclampMin(pid, uclamp);

        std::cout << std::left << std::setw(16) << comm
                  << std::right << std::setw(8) << pid
                  << std::setw(9) << total
                  << std::setw(9) << boosted << "  ";
        if (hasMain)
            std::cout << std::setw(4) << mainSt.nice;
        else
            std::cout << std::setw(4) << "?";
        std::cout << "  ";
        if (hasUclamp)
            std::cout << uclamp << "\n";
        else
            std::cout << "None\n";
    }

    for (const auto& dev : Booster::gpuDevices()) {
        std::string gov, minF, curF;
        readSmallString(dev + "/governor", gov);
        readSmallString(dev + "/min_freq", minF);
        readSmallString(dev + "/cur_freq", curF);
        std::cout << dev << ": governor=" << gov << " min=" << minF << " cur=" << curF << "\n";
    }
}

} // namespace

int main(int argc, char** argv) {
    std::string configPath = DEFAULT_CONFIG;
    bool        dryRun = false, once = false, showStatus = false;

    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg == "--config" && i + 1 < argc) {
            configPath = argv[++i];
        } else if (arg == "--dry-run") {
            dryRun = true;
        } else if (arg == "--once") {
            once = true;
        } else if (arg == "--status") {
            showStatus = true;
        } else if (arg == "-h" || arg == "--help") {
            std::cout << "Usage: silky-desktop-priority [--config PATH] [--dry-run] [--once] [--status]\n";
            return 0;
        } else {
            std::cerr << "Unknown argument: " << arg << "\n";
            return 2;
        }
    }

    Config cfg = loadConfig(configPath);
    if (showStatus) {
        printStatus(cfg);
        return 0;
    }

    Booster booster(cfg, dryRun);
    if (once || dryRun) {
        booster.scan();
        booster.updateGpu();
        return 0;
    }

    struct sigaction sa{};
    sa.sa_handler = onSignal;
    sigemptyset(&sa.sa_mask);
    ::sigaction(SIGTERM, &sa, nullptr);
    ::sigaction(SIGINT, &sa, nullptr);

    std::cout << "boosting ";
    for (size_t i = 0; i < cfg.targetOrder.size(); ++i) {
        if (i)
            std::cout << ", ";
        std::cout << cfg.targetOrder[i];
    }
    std::cout << " every " << cfg.interval << "s (native C++)\n" << std::flush;

    const auto sec  = static_cast<time_t>(cfg.interval);
    const auto nsec = static_cast<long>((cfg.interval - static_cast<double>(sec)) * 1e9);
    while (g_running.load(std::memory_order_relaxed)) {
        booster.scan();
        booster.updateGpu();
        if (!g_running.load(std::memory_order_relaxed))
            break;
        struct timespec ts{sec, nsec};
        ::nanosleep(&ts, nullptr);
    }
    booster.restore();
    return 0;
}
