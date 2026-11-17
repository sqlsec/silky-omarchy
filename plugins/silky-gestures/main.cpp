// Silky Gestures: workspace swipes for touch screens and an end-of-list rubber band, for Hyprland 0.57.
//
//  * touch screen, one finger starting on the left / right screen edge  -> drag the workspaces 1:1
//  * touch screen, three or more fingers anywhere                       -> drag the workspaces 1:1
//  * touchpad or touch screen, four or five fingers pinching in / out -> open / close MacShell's Applications panel,
//    following the fingers: the progress is streamed to MacShell as Hyprland socket2 events, so the panel's animation
//    moves with the pinch and goes back when the fingers do (see postLaunchpad)
//  * any of those, and the touchpad workspace gesture, past the first / last workspace
//                                                                       -> the workspace follows with resistance and springs back
//  * touch screen, one finger on a floating window:
//      - its title area (bar or the app's own header, top 44 px)       -> drag to move it, like the mouse
//      - its edges and corners (16 px band)                           -> drag to resize it
//      - anywhere else, held still for 0.4 s                          -> then drag to move it
//    Every touch reaches the app at once, as without this plugin; only when it becomes one of these is the app sent a
//    touch cancel and the window taken over. Taps, scrolling and presses therefore behave exactly as before.
//  * any drag of a floating window, mouse or touch                    -> it never slides under the menu bar
//
// Everything is done from event listeners: Hyprland's function hooks only exist on x86_64 and this targets aarch64 too.

#include <algorithm>
#include <chrono>
#include <cmath>
#include <deque>
#include <format>
#include <optional>
#include <unordered_map>
#include <string>
#include <variant>
#include <vector>

#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/Compositor.hpp>
#include <hyprland/src/config/ConfigValue.hpp>
#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/desktop/state/WindowState.hpp>
#include <hyprland/src/desktop/view/window/WindowBackend.hpp>
#include <hyprland/src/desktop/state/ViewState.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/config/shared/actions/ConfigActions.hpp>
#include <hyprland/src/layout/LayoutManager.hpp>
#include <hyprland/src/managers/eventLoop/EventLoopTimer.hpp>
#include <hyprland/src/pointer/PointerController.hpp>
#include <hyprland/src/devices/IPointer.hpp>
#include <hyprland/src/devices/ITouch.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/managers/SeatManager.hpp>
#include <hyprland/src/managers/SessionLockManager.hpp>
#include <hyprland/src/managers/eventLoop/EventLoopManager.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/state/MonitorState.hpp>
#include <hyprland/src/state/WorkspaceState.hpp>
#include <hyprland/src/state/workspace/Resolver.hpp>
#include <hyprland/src/ipc/s2/S2.hpp>

// The swipe's current delta and average speed are private; they are only read / written, never restructured.
#define private public
#include <hyprland/src/managers/input/UnifiedWorkspaceSwipeGesture.hpp>
#undef private

inline HANDLE PHANDLE = nullptr;

// ── tuning ──
static constexpr double EDGE_PX          = 20.0;  // logical px from the left / right screen edge that start a one-finger swipe
static constexpr size_t MULTI_FINGERS    = 3;     // this many fingers (or more) swipe from anywhere
static constexpr double START_PX         = 10.0;  // travel before a touch swipe starts moving anything
static constexpr double FLICK_PX_PER_SEC = 450.0; // a release faster than this switches even after a short travel
static constexpr double RUBBER_LIMIT     = 0.26;  // the rubber band never stretches past this fraction of the screen width
static constexpr double RUBBER_STIFFNESS = 0.55;  // initial follow ratio of the rubber band (1 = follows the finger exactly)
static constexpr double TITLE_PX         = 44.0;  // the top of a floating window that drags it straight away
static constexpr double RESIZE_PX        = 8.0;   // resize band on each side of a floating window's edge (16 px in all)
static constexpr double CORNER_PX        = 16.0;  // corners grab from further along both edges
static constexpr int    HOLD_MS          = 400;
static constexpr size_t PINCH_FINGERS    = 4;     // this many fingers (or more) can pinch instead of swiping
static constexpr double PINCH_START      = 0.06;  // the touch screen spread changing by this fraction makes it a pinch rather than a swipe
static constexpr double PINCH_SWIPE_PX   = 28.0;  // with that many fingers a swipe needs this much sideways travel, more than the spread changed
static constexpr double TOP_GAP_PX       = 4.0;   // breathing room kept between the menu bar and a floating window   // hold still this long anywhere else in a floating window to pick it up

using Clock = std::chrono::steady_clock;

static double swipeDistance() {
    static auto PDIST = CConfigValue<Config::INTEGER>("gestures:workspace_swipe_distance");
    return std::clamp(*PDIST, sc<int64_t>(1LL), sc<int64_t>(UINT32_MAX));
}

// ── which neighbours exist (same rules as CUnifiedWorkspaceSwipeGesture::update without create_new) ──
struct SNeighbours {
    bool left  = false;
    bool right = false;
};

static SNeighbours neighbours(PHLMONITOR monitor, PHLWORKSPACE begin) {
    SNeighbours n;
    if (!monitor || !begin)
        return n;

    static auto PUSER = CConfigValue<Config::INTEGER>("gestures:workspace_swipe_use_r");
    static auto PNEW  = CConfigValue<Config::INTEGER>("gestures:workspace_swipe_create_new");

    const auto LEFT  = State::Workspace::resolver()->getWorkspaceTargetFromString(*PUSER ? "r-1" : "m-1", monitor);
    const auto RIGHT = State::Workspace::resolver()->getWorkspaceTargetFromString(*PUSER ? "r+1" : "m+1", monitor);
    if (!LEFT.valid() || !RIGHT.valid())
        return n;

    const auto BEGIN_ID = begin->numberedID();
    const auto LEFT_ID  = std::get_if<Workspace::SWorkspaceNumberedID>(&*LEFT.id);
    const auto RIGHT_ID = std::get_if<Workspace::SWorkspaceNumberedID>(&*RIGHT.id);
    const auto PLEFT    = State::Workspace::state()->find(LEFT);
    const auto PRIGHT   = State::Workspace::state()->find(RIGHT);

    n.left  = PLEFT && PLEFT != begin && !(BEGIN_ID && LEFT_ID && *BEGIN_ID <= LEFT_ID->value);
    n.right = PRIGHT && PRIGHT != begin && !(BEGIN_ID && RIGHT_ID && RIGHT_ID->value <= *BEGIN_ID);
    if (*PNEW) // with create_new the right end always opens a fresh workspace: nothing to bounce off there
        n.right = true;
    return n;
}

// ── rubber band ──
// delta is in swipe units (workspace_swipe_distance = one screen), negative = towards the left workspace.
static double rubberOffset(PHLMONITOR monitor, double delta) {
    const double WIDTH = monitor->m_size.x;
    const double RAW   = std::abs(delta) / swipeDistance() * WIDTH;
    const double LIMIT = WIDTH * RUBBER_LIMIT;
    const double PX    = LIMIT * (1.0 - 1.0 / (RAW * RUBBER_STIFFNESS / LIMIT + 1.0));
    return delta < 0 ? PX : -PX;
}

static void setOffset(PHLMONITOR monitor, PHLWORKSPACE workspace, double x) {
    if (!monitor || !workspace)
        return;
    workspace->m_renderOffset->setValueAndWarp(Vector2D(x, 0.0));
    g_pHyprRenderer->damageMonitor(monitor);
}

static void springBack(PHLMONITOR monitor, PHLWORKSPACE workspace, double fromX) {
    if (!monitor || !workspace)
        return;
    workspace->m_renderOffset->setValueAndWarp(Vector2D(fromX, 0.0));
    *workspace->m_renderOffset = Vector2D(0.0, 0.0); // animated with the "workspaces" animation
    g_pHyprRenderer->damageMonitor(monitor);
}

// ══════════════ touchpad: rubber band at the ends ══════════════
static struct {
    double          over = 0; // travel past the end, in swipe units
    // the spring-back has to start after Hyprland's own end-of-swipe handling, which snaps the workspace to 0
    PHLMONITORREF   pendingMonitor;
    PHLWORKSPACEREF pendingWorkspace;
    double          pendingFrom = 0;
} g_pad;

static void applyPendingSpring() {
    const auto MONITOR   = g_pad.pendingMonitor.lock();
    const auto WORKSPACE = g_pad.pendingWorkspace.lock();
    g_pad.pendingMonitor.reset();
    g_pad.pendingWorkspace.reset();
    if (MONITOR && WORKSPACE && MONITOR->m_activeWorkspace == WORKSPACE && !g_pUnifiedWorkspaceSwipe->isGestureInProgress())
        springBack(MONITOR, WORKSPACE, g_pad.pendingFrom);
}

static void onSwipeUpdate(const IPointer::SSwipeUpdateEvent& e, Event::SCallbackInfo& info) {
    auto& swipe = *g_pUnifiedWorkspaceSwipe;
    if (!swipe.isGestureInProgress()) {
        g_pad.over = 0;
        return;
    }

    const auto MONITOR   = swipe.m_monitor.lock();
    const auto WORKSPACE = swipe.m_workspaceBegin;
    if (!MONITOR || !WORKSPACE)
        return;

    static auto  PINVERT = CConfigValue<Config::INTEGER>("gestures:workspace_swipe_invert");
    const double D       = *PINVERT ? -e.delta.x : e.delta.x;
    if (D == 0)
        return;

    if (g_pad.over == 0) {
        if (swipe.m_delta != 0)
            return; // a neighbour is on screen: Hyprland drives this
        const auto N = neighbours(MONITOR, WORKSPACE);
        if ((D < 0 && N.left) || (D > 0 && N.right))
            return;
        g_pad.over = D;
    } else {
        const double NEXT = g_pad.over + D;
        if (NEXT == 0 || (NEXT < 0) != (g_pad.over < 0)) {
            // back at the resting position: hand the gesture back to Hyprland
            g_pad.over = 0;
            setOffset(MONITOR, WORKSPACE, 0.0);
            return;
        }
        g_pad.over = NEXT;
    }

    info.cancelled = true;
    setOffset(MONITOR, WORKSPACE, rubberOffset(MONITOR, g_pad.over));
}

static void onSwipeEnd(const IPointer::SSwipeEndEvent& e, Event::SCallbackInfo& info) {
    auto& swipe = *g_pUnifiedWorkspaceSwipe;
    if (g_pad.over != 0 && swipe.isGestureInProgress()) {
        const auto MONITOR = swipe.m_monitor.lock();
        if (MONITOR && swipe.m_workspaceBegin) {
            g_pad.pendingMonitor   = MONITOR;
            g_pad.pendingWorkspace = swipe.m_workspaceBegin;
            g_pad.pendingFrom      = rubberOffset(MONITOR, g_pad.over);
            g_pEventLoopManager->doLater([] { applyPendingSpring(); });
        }
    }
    g_pad.over = 0;
}

// ══════════════ floating windows stay below the menu bar ══════════════
// Hyprland keeps tiled windows out of the reserved area at the top (the menu bar's exclusive zone), but a floating
// window can be dragged straight under the bar. After every drag step, mouse or touch, and when the drag ends, a
// window whose top (titlebar included) is above the reserved area is put back just below it. A resize from the top
// edge stops there instead.
static PHLWINDOWREF g_lastDragged;

static void keepBelowMenuBar(PHLWINDOW window, bool resizing) {
    if (!window || !window->mapped() || !window->isFloating() || !window->layoutTarget())
        return;
    const auto MONITOR = window->m_monitor.lock();
    if (!MONITOR || MONITOR->m_reservedArea.top() <= 0)
        return;

    const double LIMIT = MONITOR->m_position.y + MONITOR->m_reservedArea.top() + TOP_GAP_PX;
    const CBox   FULL  = window->getWindowBoxUnified(Desktop::View::RESERVED_EXTENTS); // titlebar included
    const double OVER  = LIMIT - FULL.y;
    if (OVER <= 0.5)
        return;

    const auto TARGET = window->layoutTarget();
    CBox       box    = TARGET->position();
    box.y += OVER;
    if (resizing)
        box.h = std::max(1.0, box.h - OVER); // resizing from the top: the edge stops, the bottom stays put
    g_layoutManager->setTargetGeom(box, TARGET);
    TARGET->warpPositionSize();
}

static void onDragMotion() {
    const auto& DRAG   = g_layoutManager->dragController();
    const auto  TARGET = DRAG ? DRAG->target() : nullptr;
    if (!TARGET || !TARGET->window())
        return;
    g_lastDragged = TARGET->window();
    keepBelowMenuBar(TARGET->window(), DRAG->mode() != MBIND_MOVE);
}

static void onDragEnded() {
    // once more after the drag has fully settled, whatever order the layout finished it in
    g_pEventLoopManager->doLater([] {
        keepBelowMenuBar(g_lastDragged.lock(), false);
        g_lastDragged.reset();
    });
}

// ══════════════ touch screen ══════════════
struct SFinger {
    int32_t id = 0;
    double  x  = 0; // layout px
    double  y  = 0;
};

enum eTouchMode : uint8_t {
    TOUCH_NONE = 0,
    TOUCH_EDGE,
    TOUCH_MULTI,
    TOUCH_WINDOW, // one finger on a floating window: waiting to see whether it moves / resizes it, or doing so
};

enum eWindowGrab : uint8_t {
    GRAB_TITLE = 0, // move once the finger travels
    GRAB_EDGE,      // resize once the finger travels
    GRAB_HOLD,      // move once the finger has been held still; travelling first gives the touch back to the app
};

static struct {
    std::vector<SFinger> fingers;
    eTouchMode           mode       = TOUCH_NONE;
    bool                 finished   = false; // the swipe ended but fingers are still down: keep swallowing them
    int32_t              edgeFinger = 0;
    ITouch::SDownEvent   edgeDown;           // kept so a tap or a vertical drag on the edge can still be given to the app
    double               edgeDownY = 0;
    bool                 replaying = false;
    PHLMONITORREF        monitor;
    PHLWORKSPACEREF      workspace;
    SNeighbours          around;
    double               refX    = 0; // where the tracked point was when the swipe began
    bool                 started = false;
    double               delta   = 0; // swipe units, negative = towards the left workspace
    double               rubber  = 0; // != 0 while past an end
    uint64_t             session = 0;
    std::deque<std::pair<Clock::time_point, double>> trail; // recent positions, for the release speed
    double               pinchRef = 0; // the fingers' spread when the current set of (>= PINCH_FINGERS) fingers was down, 0 = no pinch
    bool                 pinching = false; // a launchpad pinch is being streamed

    // TOUCH_WINDOW
    PHLWINDOWREF          window;
    eWindowGrab           grab     = GRAB_TITLE;
    Layout::eRectCorner   corner   = Layout::CORNER_NONE;
    Vector2D              downAt;            // layout px
    bool                  dragging = false;  // the layout's drag is running
    SP<CEventLoopTimer>   holdTimer;

    // Every finger whose touch-down was held back from the app. Its later motion / up must be held back too, until it
    // lifts, unless it was handed back (replayed): an app that gets motion or up for a touch it never saw go down can
    // crash (Qt does). Tracked apart from the gesture state, so no reset in between can ever leak such an event.
    std::vector<int32_t>  swallowed;
} g_touch;

static bool isSwallowed(int32_t id) {
    return std::ranges::find(g_touch.swallowed, id) != g_touch.swallowed.end();
}

static void forget(int32_t id) {
    std::erase(g_touch.swallowed, id);
}

// ── touches on Omarchy's own titlebar (omarchy-hyprland-titlebars) ──
// That plugin drags a window by touch itself, but built for tiled workspaces: it floats and pins the window when the
// drag starts and tiles it again on release. On a floating window that turns it tiled and leaves it pinned. Its
// listeners cannot be kept from the touch, so the drag is left to it and its release is undone right after, before
// the next frame: the window floats again where it was dropped, and keeps the pin state it had.
static struct {
    bool         active = false;
    int32_t      id     = 0;
    PHLWINDOWREF window;
    bool         wasPinned = false;
    CBox         box;
} g_bar;

static bool windowPinned(PHLWINDOW window) {
    const std::string JSON = HyprlandAPI::invokeHyprctlCommand("clients", "", "j");
    const std::string ADDR = std::format("\"address\": \"0x{:x}\"", (uintptr_t)window.get());
    const auto        AT   = JSON.find(ADDR);
    if (AT == std::string::npos)
        return false;
    const auto END    = JSON.find("\n}", AT);
    const auto PINNED = JSON.find("\"pinned\": true", AT);
    return PINNED != std::string::npos && (END == std::string::npos || PINNED < END);
}

static void restoreAfterTitlebarDrag() {
    const auto WINDOW = g_bar.window.lock();
    const bool WASPINNED = g_bar.wasPinned;
    const CBox BOX       = g_bar.box;
    if (!WINDOW)
        return;
    g_pEventLoopManager->doLater([weak = PHLWINDOWREF{WINDOW}, WASPINNED, BOX] {
        const auto W = weak.lock();
        if (!W || !W->mapped())
            return;
        if (!W->isFloating()) {
            (void)Config::Actions::floatWindow(Config::Actions::TOGGLE_ACTION_ENABLE, W);
            if (W->layoutTarget() && BOX.w > 0 && BOX.h > 0) {
                g_layoutManager->setTargetGeom(BOX, W->layoutTarget());
                W->layoutTarget()->warpPositionSize();
            }
        }
        if (!WASPINNED && windowPinned(W))
            (void)Config::Actions::pinWindow(Config::Actions::TOGGLE_ACTION_DISABLE, W);
    });
}

static double trackedX() {
    if (g_touch.mode == TOUCH_EDGE) {
        for (const auto& f : g_touch.fingers) {
            if (f.id == g_touch.edgeFinger)
                return f.x;
        }
        return g_touch.refX;
    }
    if (g_touch.fingers.empty())
        return g_touch.refX;
    double sum = 0;
    for (const auto& f : g_touch.fingers)
        sum += f.x;
    return sum / g_touch.fingers.size();
}

// average distance of the fingers from their centre: shrinks on a pinch in, grows on a spread
static double fingerSpread() {
    if (g_touch.fingers.size() < 2)
        return 0;
    double cx = 0, cy = 0;
    for (const auto& f : g_touch.fingers) {
        cx += f.x;
        cy += f.y;
    }
    cx /= g_touch.fingers.size();
    cy /= g_touch.fingers.size();
    double sum = 0;
    for (const auto& f : g_touch.fingers)
        sum += std::hypot(f.x - cx, f.y - cy);
    return sum / g_touch.fingers.size();
}

static void resetPinch() {
    g_touch.pinchRef = g_touch.fingers.size() >= PINCH_FINGERS ? fingerSpread() : 0;
}

// ── Launchpad pinch → MacShell ──
// socket2 lines "silkylaunchpad>>begin", "silkylaunchpad>>update,<amount>", "silkylaunchpad>>end[,cancel]".
// amount = how far the fingers pinched in: 1 - scale (0 at the start, > 0 pinching in, < 0 spreading out).
static void postLaunchpad(const std::string& data) {
    IPC::Socket2::sock()->postEvent({.event = "silkylaunchpad", .data = data});
}

static void postLaunchpadAmount(double scale) {
    postLaunchpad(std::format("update,{:.4f}", 1.0 - scale));
}

// touch screen: four or five fingers, before any swipe started, whose spread changes enough → a pinch from now on
static bool checkPinch() {
    if (g_touch.pinching) {
        postLaunchpadAmount(fingerSpread() / g_touch.pinchRef);
        return true;
    }
    if (g_touch.started || g_touch.finished || g_touch.fingers.size() < PINCH_FINGERS || g_touch.pinchRef <= 1)
        return false;
    const double RATIO = fingerSpread() / g_touch.pinchRef;
    if (std::abs(RATIO - 1.0) < PINCH_START)
        return false;
    g_touch.pinching = true;
    postLaunchpad("begin");
    postLaunchpadAmount(RATIO);
    return true;
}

static void endPinch(bool cancelled) {
    if (!g_touch.pinching)
        return;
    g_touch.pinching = false;
    g_touch.finished = true; // the rest of this touch is swallowed
    postLaunchpad(cancelled ? "end,cancel" : "end");
}

// touchpad: libinput's own pinch with four or five fingers (two- and three-finger pinches stay with the apps / Hyprland)
static struct {
    bool active = false;
} g_padPinch;

static void onPinchBegin(const IPointer::SPinchBeginEvent& e, Event::SCallbackInfo& info) {
    // every touchpad pinch announces its finger count ("silkypinch>>4"), so a pinch that does nothing can be diagnosed
    // with socat - UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock
    IPC::Socket2::sock()->postEvent({.event = "silkypinch", .data = std::to_string(e.fingers)});
    if (e.fingers < PINCH_FINGERS || g_pSessionLockManager->isSessionLocked())
        return;
    g_padPinch.active = true;
    info.cancelled    = true;
    postLaunchpad("begin");
}

static void onPinchUpdate(const IPointer::SPinchUpdateEvent& e, Event::SCallbackInfo& info) {
    if (!g_padPinch.active)
        return;
    info.cancelled = true;
    postLaunchpadAmount(e.scale);
}

static void onPinchEnd(const IPointer::SPinchEndEvent& e, Event::SCallbackInfo& info) {
    if (!g_padPinch.active)
        return;
    g_padPinch.active = false;
    info.cancelled    = true;
    postLaunchpad(e.cancelled ? "end,cancel" : "end");
}

static bool ownsSwipe() {
    return g_touch.session && g_pUnifiedWorkspaceSwipe->isGestureInProgress() && g_pUnifiedWorkspaceSwipe->sessionID() == g_touch.session;
}

static void beginTouchSwipe(eTouchMode mode, PHLMONITOR monitor) {
    g_touch.mode      = mode;
    g_touch.finished  = false;
    g_touch.monitor   = monitor;
    g_touch.workspace = monitor->m_activeWorkspace;
    g_touch.around    = neighbours(monitor, monitor->m_activeWorkspace);
    g_touch.refX      = trackedX();
    g_touch.started   = false;
    g_touch.delta     = 0;
    g_touch.rubber    = 0;
    g_touch.session   = 0;
    g_touch.trail.clear();
    resetPinch();
}

static void driveTouchSwipe() {
    const auto MONITOR   = g_touch.monitor.lock();
    const auto WORKSPACE = g_touch.workspace.lock();
    if (g_touch.finished || !MONITOR || !WORKSPACE || MONITOR->m_activeWorkspace != WORKSPACE || MONITOR->m_size.x <= 0)
        return;

    const double X   = trackedX();
    const auto   NOW = Clock::now();
    g_touch.trail.emplace_back(NOW, X);
    while (g_touch.trail.size() > 2 && NOW - g_touch.trail.front().first > std::chrono::milliseconds(120))
        g_touch.trail.pop_front();

    double dx = X - g_touch.refX;
    if (!g_touch.started) {
        if (std::abs(dx) < START_PX)
            return;
        // enough fingers to pinch: only a clearly sideways movement is a swipe
        if (g_touch.pinchRef > 0 && g_touch.fingers.size() >= PINCH_FINGERS &&
            (std::abs(dx) < PINCH_SWIPE_PX || std::abs(fingerSpread() - g_touch.pinchRef) > std::abs(dx)))
            return;
        g_touch.started = true;
        g_touch.refX += dx < 0 ? -START_PX : START_PX; // no jump when the swipe engages
        dx = X - g_touch.refX;
    }

    // the workspaces follow the finger: moving right reveals the left workspace
    const double DELTA   = std::clamp(-dx / MONITOR->m_size.x * swipeDistance(), -swipeDistance(), swipeDistance());
    const bool   OUTWARD = (DELTA < 0 && !g_touch.around.left) || (DELTA > 0 && !g_touch.around.right);
    g_touch.delta        = DELTA;

    if (OUTWARD) {
        if (ownsSwipe())
            g_pUnifiedWorkspaceSwipe->update(0); // put the neighbours away
        g_touch.rubber = DELTA;
        setOffset(MONITOR, WORKSPACE, rubberOffset(MONITOR, DELTA));
        return;
    }

    if (g_touch.rubber != 0) {
        g_touch.rubber = 0;
        setOffset(MONITOR, WORKSPACE, 0.0);
    }
    if (DELTA == 0 && !ownsSwipe())
        return;
    if (!ownsSwipe()) {
        if (g_pUnifiedWorkspaceSwipe->isGestureInProgress() || !g_pUnifiedWorkspaceSwipe->begin(MONITOR))
            return;
        g_touch.session = g_pUnifiedWorkspaceSwipe->sessionID();
    }
    g_pUnifiedWorkspaceSwipe->update(DELTA);
}

static void finishTouchSwipe(bool cancelled) {
    if (g_touch.finished)
        return;
    g_touch.finished = true;

    const auto MONITOR   = g_touch.monitor.lock();
    const auto WORKSPACE = g_touch.workspace.lock();

    if (g_touch.rubber != 0) {
        if (ownsSwipe())
            g_pUnifiedWorkspaceSwipe->end(); // nothing moved: this only tidies up
        if (MONITOR && WORKSPACE && MONITOR->m_activeWorkspace == WORKSPACE)
            springBack(MONITOR, WORKSPACE, rubberOffset(MONITOR, g_touch.rubber));
        g_touch.rubber = 0;
        return;
    }

    if (!ownsSwipe())
        return;

    if (cancelled) {
        g_pUnifiedWorkspaceSwipe->m_avgSpeed = 0;
        g_pUnifiedWorkspaceSwipe->m_delta    = std::clamp(g_pUnifiedWorkspaceSwipe->m_delta, -2.0, 2.0);
        g_pUnifiedWorkspaceSwipe->end();
        return;
    }

    // a quick flick in the direction of travel switches even when the finger did not get half-way
    bool flick = false;
    if (g_touch.trail.size() >= 2) {
        const auto&  A  = g_touch.trail.front();
        const auto&  B  = g_touch.trail.back();
        const double DT = std::chrono::duration<double>(B.first - A.first).count();
        if (DT > 0.005) {
            const double SPEED = (B.second - A.second) / DT; // px/s, positive = finger moving right
            flick              = std::abs(SPEED) > FLICK_PX_PER_SEC && ((SPEED > 0) == (g_touch.delta < 0));
        }
    }
    static auto PFORCE = CConfigValue<Config::INTEGER>("gestures:workspace_swipe_min_speed_to_force");
    g_pUnifiedWorkspaceSwipe->m_avgSpeed = flick && *PFORCE != 0 ? *PFORCE + 1.F : 0.F;
    g_pUnifiedWorkspaceSwipe->end();
}

static void resetTouch() {
    g_touch.mode     = TOUCH_NONE;
    g_touch.finished = false;
    g_touch.started  = false;
    g_touch.session  = 0;
    g_touch.rubber   = 0;
    g_touch.monitor.reset();
    g_touch.workspace.reset();
    g_touch.trail.clear();
    g_touch.pinchRef = 0;
    g_touch.pinching = false;
    g_touch.edgeDown = {};
    if (g_touch.holdTimer) {
        g_touch.holdTimer->cancel();
        g_pEventLoopManager->removeTimer(g_touch.holdTimer);
        g_touch.holdTimer.reset();
    }
    g_touch.window.reset();
    g_touch.dragging = false;
    g_touch.corner   = Layout::CORNER_NONE;
}

// The edge finger turned out not to be a workspace swipe: deliver its touch-down to the app after all.
static void giveEdgeFingerToApp() {
    const auto DOWN = g_touch.edgeDown;
    forget(DOWN.touchID);
    resetTouch();
    g_touch.replaying = true;
    g_pInputManager->onTouchDown(DOWN);
    g_touch.replaying = false;
    // close the frame now: a down and an up in one wl_touch frame is dropped by Chromium-based apps
    g_pSeatManager->sendTouchFrame();
}


// ══════════════ touch screen: moving and resizing floating windows ══════════════
// Hyprland drops xdg_toplevel move / resize requests that carry a touch serial, so apps cannot start a drag from a
// finger. These drive the same layout drag the mouse uses (snapping included), fed with the finger position.

static Vector2D windowFingerPos() {
    for (const auto& f : g_touch.fingers) {
        if (f.id == g_touch.edgeFinger)
            return {f.x, f.y};
    }
    return g_touch.downAt;
}

static void stopHoldTimer() {
    if (!g_touch.holdTimer)
        return;
    g_touch.holdTimer->cancel();
    g_pEventLoopManager->removeTimer(g_touch.holdTimer);
    g_touch.holdTimer.reset();
}

// The app has had this finger since it came down: take it back before the window starts moving.
static void takeOverFromApp() {
    g_pSeatManager->sendTouchCancel();
    g_pSeatManager->sendTouchFrame();
    if (!isSwallowed(g_touch.edgeFinger))
        g_touch.swallowed.push_back(g_touch.edgeFinger);
}

static void startWindowDrag() {
    const auto WINDOW = g_touch.window.lock();
    if (!WINDOW || !WINDOW->mapped() || !WINDOW->layoutTarget()) {
        resetTouch();
        return;
    }
    stopHoldTimer();
    takeOverFromApp();
    // the layout reads where the drag began from the pointer: put it under the finger first
    Pointer::pointerController()->warpTo(g_touch.downAt, true);
    if (g_touch.grab == GRAB_EDGE)
        g_layoutManager->beginDragTarget(WINDOW->layoutTarget(), MBIND_RESIZE, g_touch.corner);
    else
        g_layoutManager->beginDragTarget(WINDOW->layoutTarget(), MBIND_MOVE);
    g_touch.dragging = true;
    g_layoutManager->moveMouse(windowFingerPos());
}

static void endWindowDrag() {
    if (g_touch.dragging)
        g_layoutManager->endDragTarget();
    g_touch.dragging = false;
}

// A single finger came down: is it on a floating window's title area, edge, or body?
static bool grabFloatingWindow(const ITouch::SDownEvent& e, PHLMONITOR monitor) {
    const Vector2D P{g_touch.fingers.back().x, g_touch.fingers.back().y};
    const auto     WINDOW = Desktop::viewState()->hitTest().windowAt(
        P, Desktop::View::RESERVED_EXTENTS | Desktop::View::INPUT_EXTENTS | Desktop::View::ALLOW_FLOATING);
    if (!WINDOW || !WINDOW->mapped() || WINDOW->isHidden() || !WINDOW->isFloating() || !WINDOW->layoutTarget())
        return false;

    const CBox MAIN = WINDOW->getWindowMainSurfaceBox();
    const CBox FULL = WINDOW->getWindowBoxUnified(Desktop::View::RESERVED_EXTENTS); // includes a titlebar
    // a floating window covering the whole monitor (fullscreen-sized) is left to the app
    if (MAIN.w >= monitor->m_size.x - 1 && MAIN.h >= monitor->m_size.y - 1)
        return false;

    // On Omarchy's titlebar: this plugin drags it like any title area. The titlebar plugin only reacts to touch while
    // the mouse pointer is over that window, and then re-tiles and pins the window on release; g_bar watches the
    // touch so that is undone right after (see restoreAfterTitlebarDrag).
    if (MAIN.y - FULL.y > 1 && P.y >= FULL.y && P.y < MAIN.y && P.x >= FULL.x && P.x < FULL.x + FULL.w) {
        g_bar.active    = true;
        g_bar.id        = e.touchID;
        g_bar.window    = WINDOW;
        g_bar.wasPinned = windowPinned(WINDOW);
        g_bar.box       = MAIN;
    }

    const double L = P.x - FULL.x, R = FULL.x + FULL.w - P.x, T = P.y - FULL.y, B = FULL.y + FULL.h - P.y;
    const auto   near = [](double d, double band) { return d > -band && d < band; };
    int          corner = Layout::CORNER_NONE;
    const bool   nearLR = near(L, CORNER_PX) || near(R, CORNER_PX), nearTB = near(T, CORNER_PX) || near(B, CORNER_PX);
    if (nearLR && nearTB) { // a corner: generous along both edges
        corner |= (L < R ? Layout::CORNER_LEFT : Layout::CORNER_RIGHT);
        corner |= (T < B ? Layout::CORNER_TOP : Layout::CORNER_BOTTOM);
    } else {
        if (near(L, RESIZE_PX)) corner |= Layout::CORNER_LEFT;
        else if (near(R, RESIZE_PX)) corner |= Layout::CORNER_RIGHT;
        if (near(T, RESIZE_PX)) corner |= Layout::CORNER_TOP;
        else if (near(B, RESIZE_PX)) corner |= Layout::CORNER_BOTTOM;
    }

    if (corner != Layout::CORNER_NONE)
        g_touch.grab = GRAB_EDGE;
    else if (P.y < MAIN.y + TITLE_PX && P.y >= FULL.y)
        g_touch.grab = GRAB_TITLE;
    else if (MAIN.containsPoint(P))
        g_touch.grab = GRAB_HOLD;
    else
        return false;

    g_touch.mode       = TOUCH_WINDOW;
    g_touch.finished   = false;
    g_touch.monitor    = monitor;
    g_touch.window     = WINDOW;
    g_touch.corner     = sc<Layout::eRectCorner>(corner);
    g_touch.downAt     = P;
    g_touch.dragging   = false;
    g_touch.edgeFinger = e.touchID;
    g_touch.edgeDown   = e;

    if (g_touch.grab == GRAB_HOLD) {
        g_touch.holdTimer = makeShared<CEventLoopTimer>(
            std::chrono::milliseconds(HOLD_MS),
            [](SP<CEventLoopTimer>, void*) {
                if (g_touch.mode == TOUCH_WINDOW && g_touch.grab == GRAB_HOLD && !g_touch.dragging)
                    startWindowDrag();
            },
            nullptr);
        g_pEventLoopManager->addTimer(g_touch.holdTimer);
    }
    return true;
}

static PHLMONITOR touchMonitor(const SP<ITouch>& device) {
    PHLMONITOR monitor;
    if (device && !device->m_boundOutput.empty())
        monitor = State::monitorState()->query().name(device->m_boundOutput).run();
    return monitor ? monitor : Desktop::focusState()->monitor();
}

static void onTouchDownImpl(const ITouch::SDownEvent& e, Event::SCallbackInfo& info) {
    if (!e.device || g_touch.replaying)
        return;

    const auto MONITOR = g_touch.mode != TOUCH_NONE ? g_touch.monitor.lock() : touchMonitor(e.device);
    if (!MONITOR || MONITOR->m_size.x <= 0) {
        if (g_touch.mode != TOUCH_NONE)
            info.cancelled = true;
        return;
    }

    std::erase_if(g_touch.fingers, [&e](const auto& f) { return f.id == e.touchID; });
    const double BEFORE = trackedX();
    g_touch.fingers.emplace_back(SFinger{
        .id = e.touchID,
        .x  = MONITOR->m_position.x + e.pos.x * MONITOR->m_size.x,
        .y  = MONITOR->m_position.y + e.pos.y * MONITOR->m_size.y,
    });

    if (g_touch.mode == TOUCH_WINDOW && !g_touch.dragging) {
        // a second finger (a pinch, say): this is the app's gesture, the app already has the first finger
        resetTouch();
        return;
    }

    if (g_touch.mode != TOUCH_NONE) {
        info.cancelled = true;
        if (g_touch.mode == TOUCH_MULTI) {
            g_touch.refX += trackedX() - BEFORE; // another finger must not move the workspaces
            if (!g_touch.pinching)
                resetPinch();                     // the pinch is measured from the full set of fingers
        }
        return;
    }

    static auto PNATIVE = CConfigValue<Config::INTEGER>("gestures:workspace_swipe_touch");
    if (g_pSessionLockManager->isSessionLocked() || !MONITOR->m_activeWorkspace || g_pUnifiedWorkspaceSwipe->isGestureInProgress())
        return;

    const double LOCAL_X = e.pos.x * MONITOR->m_size.x;
    if (g_touch.fingers.size() == 1 && !*PNATIVE && (LOCAL_X < EDGE_PX || LOCAL_X > MONITOR->m_size.x - EDGE_PX)) {
        g_touch.edgeFinger = e.touchID;
        g_touch.edgeDown   = e;
        g_touch.edgeDownY  = g_touch.fingers.back().y;
        beginTouchSwipe(TOUCH_EDGE, MONITOR);
        info.cancelled = true;
        return;
    }

    if (g_touch.fingers.size() == 1 && grabFloatingWindow(e, MONITOR))
        return; // the app gets this touch now; the window is only taken over if it turns into a move / resize


    if (g_touch.fingers.size() >= MULTI_FINGERS) {
        g_pSeatManager->sendTouchCancel(); // the first fingers already reached the app: take them back
        beginTouchSwipe(TOUCH_MULTI, MONITOR);
        info.cancelled = true;
    }
}

static void onTouchMotionImpl(const ITouch::SMotionEvent& e, Event::SCallbackInfo& info) {
    // positions are tracked for every finger, so a swipe that starts with the third finger starts from where they are now
    const auto MONITOR = g_touch.mode != TOUCH_NONE ? g_touch.monitor.lock() : Desktop::focusState()->monitor();
    if (MONITOR) {
        for (auto& f : g_touch.fingers) {
            if (f.id != e.touchID)
                continue;
            f.x = MONITOR->m_position.x + e.pos.x * MONITOR->m_size.x;
            f.y = MONITOR->m_position.y + e.pos.y * MONITOR->m_size.y;
        }
    }
    if (g_touch.mode == TOUCH_NONE)
        return;

    info.cancelled = true;
    if (!MONITOR)
        return;

    if (g_touch.mode == TOUCH_WINDOW) {
        if (e.touchID != g_touch.edgeFinger)
            return;
        const Vector2D P = windowFingerPos();
        if (g_touch.dragging) {
            g_layoutManager->moveMouse(P);
            return;
        }
        info.cancelled = false; // until the window is taken over, the app follows the finger as usual
        if (P.distance(g_touch.downAt) < START_PX)
            return;
        if (g_touch.grab == GRAB_HOLD) {
            // it moved before the hold time: an ordinary drag inside the app (scrolling, selecting)
            resetTouch();
            return;
        }
        startWindowDrag();
        info.cancelled = true;
        return;
    }

    if (g_touch.mode == TOUCH_EDGE && e.touchID == g_touch.edgeFinger && !g_touch.started && !g_touch.finished && g_touch.fingers.size() == 1) {
        // moving along the edge instead of away from it (a scroll bar, say): this is the app's touch, not a swipe
        const double DY = std::abs(g_touch.fingers.front().y - g_touch.edgeDownY);
        const double DX = std::abs(g_touch.fingers.front().x - g_touch.refX);
        if (DY > START_PX && DY > DX) {
            giveEdgeFingerToApp();
            info.cancelled = false;
            return;
        }
    }

    if (g_touch.mode == TOUCH_MULTI && checkPinch())
        return;
    if (g_touch.mode == TOUCH_MULTI || e.touchID == g_touch.edgeFinger)
        driveTouchSwipe();
}

// Touch-down already sets focus. Raise that same window once the gesture resolves to a tap.
static void raiseTappedWindow(const PHLWINDOW& window) {
    if (window && window->mapped() && !window->isHidden() && window->isFloating() &&
        window == Desktop::focusState()->window() && !g_pSessionLockManager->isSessionLocked())
        Desktop::windowState()->raise(window);
}

static void liftFingerImpl(int32_t id, bool cancelled, Event::SCallbackInfo& info) {
    const double BEFORE = trackedX();
    const bool   KNOWN  = std::erase_if(g_touch.fingers, [id](const auto& f) { return f.id == id; }) > 0;
    if (g_touch.mode == TOUCH_NONE)
        return;

    info.cancelled = true;
    if (!KNOWN)
        return;

    if (g_touch.mode == TOUCH_WINDOW) {
        if (id != g_touch.edgeFinger)
            return;
        if (g_touch.dragging) {
            endWindowDrag();
            resetTouch();
            return;
        }
        const auto WINDOW = g_touch.window.lock();
        if (!cancelled && g_touch.fingers.empty() && WINDOW == g_pInputManager->m_touchData.touchFocusWindow.lock())
            raiseTappedWindow(WINDOW);
        // a tap (or a cancel): the app had the whole touch, let its end through too
        resetTouch();
        info.cancelled = false;
        return;
    }

    if (g_touch.mode == TOUCH_EDGE && id == g_touch.edgeFinger && !g_touch.started && !g_touch.finished && !cancelled && g_touch.fingers.empty()) {
        // a tap on the edge: the app gets its touch-down now and this touch-up right after
        giveEdgeFingerToApp();
        raiseTappedWindow(g_pInputManager->m_touchData.touchFocusWindow.lock());
        info.cancelled = false;
        return;
    }

    if (g_touch.pinching) {
        endPinch(cancelled);
        if (g_touch.fingers.empty())
            resetTouch();
        return;
    }

    if (g_touch.mode == TOUCH_EDGE && id == g_touch.edgeFinger)
        finishTouchSwipe(cancelled);
    else if (g_touch.mode == TOUCH_MULTI) {
        if (g_touch.fingers.empty() || cancelled)
            finishTouchSwipe(cancelled);
        else {
            g_touch.refX += trackedX() - BEFORE;
            resetPinch();
        }
    }

    if (g_touch.fingers.empty()) {
        finishTouchSwipe(cancelled);
        resetTouch();
    }
}

// ── the guard around every touch event: a finger whose touch-down the app did not get never reaches it later ──
static void onTouchDown(const ITouch::SDownEvent& e, Event::SCallbackInfo& info) {
    if (g_touch.replaying)
        return;
    forget(e.touchID); // a reused id is a new finger
    onTouchDownImpl(e, info);
    if (info.cancelled)
        g_touch.swallowed.push_back(e.touchID);
}

static void onTouchMotion(const ITouch::SMotionEvent& e, Event::SCallbackInfo& info) {
    onTouchMotionImpl(e, info);
    if (g_bar.active && e.touchID == g_bar.id) {
        if (const auto W = g_bar.window.lock(); W && W->isFloating())
            g_bar.box = W->getWindowMainSurfaceBox();
    }
    if (isSwallowed(e.touchID))
        info.cancelled = true;
}

static void liftFinger(int32_t id, bool cancelled, Event::SCallbackInfo& info) {
    liftFingerImpl(id, cancelled, info);
    if (g_bar.active && id == g_bar.id) {
        if (const auto W = g_bar.window.lock(); W && W->isFloating())
            g_bar.box = W->getWindowMainSurfaceBox();
        restoreAfterTitlebarDrag();
        g_bar = {};
    }
    if (isSwallowed(id)) {
        info.cancelled = true;
        forget(id);
    }
}

// ══════════════ clicks on a shell layer that just changed its input region ══════════════
// Hyprland only works out which surface is under the pointer when the pointer moves. A layer surface that changes its
// input region under a pointer at rest keeps the pointer focus (or never gets it): MacShell's Spotlight / Applications
// overlay takes the whole screen while open and nothing once it closes, so clicking the Dock's Applications icon
// quickly, without moving, sent every click after the second one to the closed overlay, and nothing happened until the
// mouse moved. So when a button goes down with no other button held and the pointer focus is a layer surface (or
// nothing), the surface under the pointer is looked up again first; the click then lands where it is seen to land.
static void onMouseButton(const IPointer::SButtonEvent& e, Event::SCallbackInfo& info) {
    if (e.state != WL_POINTER_BUTTON_STATE_PRESSED || g_pInputManager->hasHeldButtons() || g_pInputManager->isConstrained() ||
        g_pSessionLockManager->isSessionLocked())
        return;
    const auto FOCUS = g_pSeatManager->m_state.pointerFocus.lock();
    if (FOCUS) {
        const auto SURFACE = Desktop::View::CWLSurface::fromResource(FOCUS);
        const auto VIEW    = SURFACE ? SURFACE->view() : nullptr;
        if (!VIEW || VIEW->type() != Desktop::View::VIEW_TYPE_LAYER_SURFACE)
            return;
    }
    g_pInputManager->simulateMouseMovement();
}

// ══════════════ plugin ══════════════
static std::vector<CHyprSignalListener> g_listeners;
APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    PHANDLE = handle;

    const std::string COMPOSITOR = __hyprland_api_get_hash();
    const std::string CLIENT     = __hyprland_api_get_client_hash();
    if (COMPOSITOR != CLIENT)
        throw std::runtime_error("[silky-gestures] built for a different Hyprland: rebuild the plugin");

    auto& events = Event::bus()->m_events;
    g_listeners.emplace_back(events.gesture.swipe.begin.listen([](const IPointer::SSwipeBeginEvent& e, Event::SCallbackInfo&) {
        g_pad.over = 0;
        // the counterpart of "silkypinch": a pinch that libinput took for a swipe shows up here
        IPC::Socket2::sock()->postEvent({.event = "silkyswipe", .data = std::to_string(e.fingers)});
    }));
    g_listeners.emplace_back(events.gesture.swipe.update.listen(onSwipeUpdate));
    g_listeners.emplace_back(events.gesture.swipe.end.listen(onSwipeEnd));
    g_listeners.emplace_back(events.gesture.pinch.begin.listen(onPinchBegin));
    g_listeners.emplace_back(events.gesture.pinch.update.listen(onPinchUpdate));
    g_listeners.emplace_back(events.gesture.pinch.end.listen(onPinchEnd));
    g_listeners.emplace_back(events.input.mouse.button.listen(onMouseButton));
    g_listeners.emplace_back(events.input.touch.down.listen(onTouchDown));
    g_listeners.emplace_back(g_layoutManager->dragController()->m_events.motion.listen([] { onDragMotion(); }));
    g_listeners.emplace_back(g_layoutManager->dragController()->m_events.ended.listen([] { onDragEnded(); }));
    g_listeners.emplace_back(events.input.touch.motion.listen(onTouchMotion));
    g_listeners.emplace_back(events.input.touch.up.listen([](const ITouch::SUpEvent& e, Event::SCallbackInfo& info) { liftFinger(e.touchID, false, info); }));
    g_listeners.emplace_back(events.input.touch.cancel.listen([](const ITouch::SCancelEvent& e, Event::SCallbackInfo& info) { liftFinger(e.touchID, true, info); }));

    return {"silky-gestures", "Touch-screen workspace swipes and Launchpad pinch, rubber band, raising / moving / resizing floating windows, kept below the menu bar", "sqlsec", "0.6.1"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    endWindowDrag();
    // fingers still held back would reach apps unpaired once this is gone: tell the apps to drop every touch first
    if (!g_touch.swallowed.empty() || !g_touch.fingers.empty())
        g_pSeatManager->sendTouchCancel();
    g_touch.swallowed.clear();
    if (g_touch.pinching || g_padPinch.active)
        postLaunchpad("end,cancel");
    g_padPinch = {};
    g_listeners.clear();
    g_touch.fingers.clear();
    resetTouch();
    g_pad = {};
}
