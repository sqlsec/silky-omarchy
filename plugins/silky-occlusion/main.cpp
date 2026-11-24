// silky-occlusion — windows that are completely covered stop redrawing.
//
// Hyprland 0.57 skips drawing a surface that opaque windows cover, but it still answers that surface's
// wl_surface.frame callback every frame (CSurfacePassElement::discard -> presentFeedback -> frame). A covered
// browser, chat client or Electron app therefore keeps rendering at the full refresh rate, burns CPU / GPU and
// keeps scheduling compositor frames that nobody sees.
//
// How it works (aarch64-safe: no function hooks, only the public render-stage event):
//   1. At RENDER_PRE of every monitor frame, before Hyprland sends any frame callback for that monitor, the
//      windows of the monitor's active workspace are walked from the top of the stack down. A window counts as
//      covered when the opaque parts of the windows above it hide its whole content box. A window above only
//      hides what it declares opaque (wl_surface opaque region or an alpha-less buffer), shrunk by its corner
//      radius, and only at full opacity: glass, blur and translucent windows never hide anything.
//   2. The pending frame callbacks of a covered window (and its subsurfaces) are taken out of the surface before
//      Hyprland can answer them, so the client waits, exactly as if the window were on a hidden workspace.
//   3. As soon as any part of the window shows again, the held callbacks are answered on the spot and the client
//      draws its next frame. A keepalive answers them once a second while the window stays covered, so thumbnails
//      and the app's own frame-driven timers never go fully stale.
//   4. Nothing is held while a window capture is pending (overview / Dock snapshots, window screen sharing), on a
//      monitor with a special workspace open, a fullscreen window, or a workspace slide in progress, or for a
//      window tagged "silky-live".
//
// hyprctl silkyocclusion              statistics and the currently covered windows
// hyprctl silkyocclusion all          every tracked window with its box and the area it hides
// hyprctl silkyocclusion on|off       enable / disable at runtime (off answers everything held right away)
// hyprctl silkyocclusion keepalive N  keepalive period in ms (0 = hold until uncovered)

#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/Compositor.hpp>
#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/desktop/state/WindowState.hpp>
#include <hyprland/src/desktop/rule/windowRule/WindowRuleApplicator.hpp>
#include <hyprland/src/desktop/view/WLSurface.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/desktop/view/window/WindowMetadata.hpp>
#include <hyprland/src/desktop/view/window/WindowPresentation.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/managers/fullscreen/FullscreenController.hpp>
#include <hyprland/src/managers/screenshare/ScreenshareManager.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <hyprland/src/protocols/core/Compositor.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/render/Texture.hpp>
#include <hyprland/src/render/WindowRenderPresentation.hpp>
#include <hyprland/src/state/MonitorState.hpp>
#include <hyprland/src/workspace/HLWorkspace.hpp>

#include <chrono>
#include <format>
#include <string>
#include <unordered_map>
#include <vector>

inline HANDLE PHANDLE = nullptr;

namespace {
    using Clock = std::chrono::steady_clock;

    struct SWinState {
        PHLWINDOWREF                         window;
        std::vector<SP<CWLCallbackResource>> held;
        bool                                 covered     = false;
        CBox                                 content;    // last evaluated content box (for `hyprctl silkyocclusion all`)
        CBox                                 hides;      // extents of what it hid of the windows below
        Time::steady_tp                      lastRelease = {};
    };

    std::unordered_map<const void*, SWinState>     g_windows;
    std::vector<CHyprSignalListener>               g_listeners;
    SP<IPC::Socket1::SCommand>                     g_cmd;

    bool                                           g_enabled     = true;
    int                                            g_keepaliveMs = 1000;
    Time::steady_tp                                g_lastCapture = {};
    constexpr auto                                 CAPTURE_GRACE = std::chrono::milliseconds(1500);

    struct {
        uint64_t frames = 0, held = 0, answered = 0, keepalives = 0, captureSkips = 0;
    } g_stats;

    void answer(SWinState& st, const Time::steady_tp& now) {
        for (auto& cb : st.held) {
            if (cb && cb->good())
                cb->send(now);
        }
        g_stats.answered += st.held.size();
        st.held.clear();
        st.lastRelease = now;
    }

    void answerAll(const Time::steady_tp& now) {
        for (auto& [k, st] : g_windows) {
            answer(st, now);
            st.covered = false;
        }
    }

    // Takes every pending frame callback of the window's surface tree out of Hyprland's hands.
    void hold(const PHLWINDOW& w, SWinState& st) {
        const auto surface = w->wlSurface();
        const auto res     = surface ? surface->resource() : nullptr;
        if (!res)
            return;
        res->breadthfirst(
            [&st](SP<CWLSurfaceResource> s, const Vector2D&, void*) {
                auto& cbs = s->m_current.callbacks;
                if (cbs.empty())
                    return;
                g_stats.held += cbs.size();
                st.held.insert(st.held.end(), std::make_move_iterator(cbs.begin()), std::make_move_iterator(cbs.end()));
                cbs.clear();
            },
            nullptr);
    }

    bool captureActive(const Time::steady_tp& now) {
        const auto& mgr = Screenshare::mgr();
        if (mgr) {
            for (const auto& m : State::monitorState()->monitors()) {
                if (mgr->outputCopyFBState(m).pendingWindowFrames > 0) {
                    g_lastCapture = now;
                    break;
                }
            }
        }
        return g_lastCapture != Time::steady_tp{} && now - g_lastCapture < CAPTURE_GRACE;
    }

    // What the window hides of the windows below it, in global logical coordinates.
    CRegion opaqueRegion(const PHLWINDOW& w, const CBox& content, const Render::SWindowRenderPresentation& pres) {
        if (pres.alpha * pres.fadeAlpha < 0.999F || !pres.alphaVisible)
            return {};
        const auto surface = w->wlSurface();
        const auto res     = surface ? surface->resource() : nullptr;
        if (!res)
            return {};
        const auto surfBox = w->surfaceLogicalBox();
        if (!surfBox)
            return {};
        const Vector2D origin = surfBox->pos() + pres.floatingOffset + pres.workspaceOffset;

        CRegion opaque;
        if (res->m_current.texture && res->m_current.texture->m_opaque)
            opaque = CRegion(CBox{origin, res->m_current.size});
        else if (!res->m_current.opaque.empty())
            opaque = res->m_current.opaque.copy().translate(origin);
        else
            return {};

        const double radius = w->presentation().rounding();
        CBox         inner  = content;
        inner.expand(-radius);
        if (inner.width <= 0 || inner.height <= 0)
            return {};
        return opaque.intersect(CRegion(inner));
    }

    void evaluate(const PHLMONITOR& mon, const Time::steady_tp& now) {
        const auto ws = mon->m_activeWorkspace;

        // Windows this monitor shows: everything on its active workspace plus pinned floating windows.
        auto onThisMonitor = [&](const PHLWINDOW& w) {
            if (!w || !w->mapped() || w->isHidden())
                return false;
            if (w->m_workspace == ws)
                return true;
            return w->isFloating() && (w->m_state & Desktop::View::WINDOW_STATE_PINNED) && w->m_monitor.lock() == mon;
        };

        auto releaseMonitor = [&] {
            for (auto& [k, st] : g_windows) {
                const auto w = st.window.lock();
                if (!w || w->m_monitor.lock() == mon || (ws && w->m_workspace == ws)) {
                    answer(st, now);
                    st.covered = false;
                }
            }
        };

        if (!ws || mon->m_activeSpecialWorkspace || Fullscreen::controller()->hasFullscreen(ws)) {
            releaseMonitor();
            return;
        }

        // Render order (IHyprRenderer::renderWorkspaceWindows): tiled with the focused one last, then floating,
        // then pinned floating.
        const auto               focused = Desktop::focusState()->window();
        std::vector<PHLWINDOW>   order;
        PHLWINDOW                focusedTiled;
        std::vector<PHLWINDOW>   pinned;
        for (const auto& w : Desktop::windowState()->windows()) {
            if (!onThisMonitor(w) || w->isFloating())
                continue;
            if (w == focused)
                focusedTiled = w;
            else
                order.push_back(w);
        }
        if (focusedTiled)
            order.push_back(focusedTiled);
        for (const auto& w : Desktop::windowState()->windows()) {
            if (!onThisMonitor(w) || !w->isFloating())
                continue;
            if (w->m_state & Desktop::View::WINDOW_STATE_PINNED)
                pinned.push_back(w);
            else
                order.push_back(w);
        }
        order.insert(order.end(), pinned.begin(), pinned.end());

        CRegion monitors;
        for (const auto& m : State::monitorState()->monitors())
            monitors.add(m->logicalBox());

        CRegion covered;
        for (auto it = order.rbegin(); it != order.rend(); ++it) {
            const auto& w    = *it;
            const auto  pres = w->presentation().renderPresentation();
            if (pres.workspaceOffsetAnimating || pres.workspaceOffset != Vector2D{}) {
                releaseMonitor(); // a workspace slide: everything moves, nothing is held
                return;
            }

            CBox content = w->getWindowMainSurfaceBox();
            content.translate(pres.floatingOffset + pres.workspaceOffset);

            CRegion shown = CRegion(content).intersect(monitors);
            const bool exempt = w->m_ruleApplicator && w->m_ruleApplicator->m_tagKeeper.isTagged("silky-live");
            const bool isCovered = !exempt && !shown.empty() && shown.subtract(covered).empty();

            auto& st  = g_windows[w.get()];
            st.window = w;
            if (isCovered) {
                if (!st.covered)
                    st.lastRelease = now; // the keepalive counts from the moment it got covered
                st.covered = true;
                if (g_keepaliveMs > 0 && now - st.lastRelease >= std::chrono::milliseconds(g_keepaliveMs)) {
                    if (!st.held.empty())
                        g_stats.keepalives++;
                    answer(st, now);
                } else
                    hold(w, st);
            } else {
                st.covered = false;
                if (!st.held.empty())
                    answer(st, now);
            }

            const auto hides = opaqueRegion(w, content, pres);
            st.content       = content;
            st.hides         = hides.copy().getExtents();
            covered.add(hides);
        }
    }

    void onRenderPre(const Event::SRenderStageEvent& e) {
        if (e.stage != RENDER_PRE || !e.monitor)
            return;
        const auto now = Time::steadyNow();
        g_stats.frames++;

        // drop the state of closed windows; answer windows that left every visible workspace
        for (auto it = g_windows.begin(); it != g_windows.end();) {
            const auto w = it->second.window.lock();
            if (!w || !w->mapped()) {
                it = g_windows.erase(it);
                continue;
            }
            if (!it->second.held.empty() && (!w->m_workspace || !w->m_workspace->visible()))
                answer(it->second, now), it->second.covered = false;
            ++it;
        }

        if (!g_enabled) {
            answerAll(now);
            return;
        }
        if (captureActive(now)) {
            g_stats.captureSkips++;
            answerAll(now);
            return;
        }
        evaluate(e.monitor, now);
    }

    std::string status(bool all = false) {
        std::string out = std::format("enabled={} keepalive={}ms frames={} held={} answered={} keepalives={} captureSkips={}\n", g_enabled,
                                      g_keepaliveMs, g_stats.frames, g_stats.held, g_stats.answered, g_stats.keepalives, g_stats.captureSkips);
        for (const auto& [k, st] : g_windows) {
            const auto w = st.window.lock();
            if (!w || (!st.covered && !all))
                continue;
            out += std::format("  {} {:#x} {} \"{}\" waiting={}", st.covered ? "covered" : "shown", reinterpret_cast<uintptr_t>(w.get()),
                               w->metadata().appID(), w->metadata().title().substr(0, 48), st.held.size());
            if (all)
                out += std::format(" box={:.0f},{:.0f} {:.0f}x{:.0f} hides={:.0f},{:.0f} {:.0f}x{:.0f}", st.content.x, st.content.y, st.content.width,
                                   st.content.height, st.hides.x, st.hides.y, st.hides.width, st.hides.height);
            out += "\n";
        }
        return out;
    }

    IPC::Socket1::SResponse onCommand(const IPC::Socket1::SRequest& req) {
        std::string args = req.command;
        if (const auto sp = args.find(' '); sp != std::string::npos)
            args = args.substr(sp + 1);
        else
            args.clear();
        const auto now = Time::steadyNow();
        if (args == "all")
            return IPC::Socket1::SResponse{status(true)};
        if (args == "on")
            g_enabled = true;
        else if (args == "off") {
            g_enabled = false;
            answerAll(now);
        } else if (args.starts_with("keepalive ")) {
            try {
                g_keepaliveMs = std::max(0, std::stoi(args.substr(10)));
            } catch (...) { return IPC::Socket1::SResponse{"usage: hyprctl silkyocclusion keepalive <ms>\n"}; }
        } else if (!args.empty())
            return IPC::Socket1::SResponse{"usage: hyprctl silkyocclusion [on|off|keepalive <ms>]\n"};
        for (const auto& m : State::monitorState()->monitors())
            g_pHyprRenderer->damageMonitor(m);
        return IPC::Socket1::SResponse{status()};
    }
}

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    PHANDLE = handle;
    if (__hyprland_api_get_hash() != std::string(__hyprland_api_get_client_hash()))
        throw std::runtime_error("[silky-occlusion] built for a different Hyprland: rebuild the plugin");
    g_listeners.emplace_back(Event::bus()->m_events.render.stage.listen([](const Event::SRenderStageEvent& e) { onRenderPre(e); }));
    g_cmd = HyprlandAPI::registerHyprCtlCommand(PHANDLE, IPC::Socket1::SCommand{"silkyocclusion", IPC::Socket1::COMMAND_MATCH_PREFIX, onCommand});
    return {"silky-occlusion", "Completely covered windows stop redrawing until they show again", "sqlsec", "0.1.0"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    if (g_cmd) {
        HyprlandAPI::unregisterHyprCtlCommand(PHANDLE, g_cmd);
        g_cmd.reset();
    }
    g_listeners.clear();
    answerAll(Time::steadyNow());
    g_windows.clear();
    Log::logger->log(Log::INFO, std::format("[silky-occlusion] frames: {}, callbacks held: {}, answered: {}, keepalives: {}", g_stats.frames, g_stats.held,
                                            g_stats.answered, g_stats.keepalives));
}
