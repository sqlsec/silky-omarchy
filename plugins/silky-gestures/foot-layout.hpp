// The title bar is owned by Hyprland, so keep its input and drag detection in the compositor.
static std::vector<std::string> g_windowLayoutApps;

static bool windowLayoutApp(PHLWINDOW window) {
    return window && std::ranges::find(g_windowLayoutApps, window->metadata().appID()) != g_windowLayoutApps.end();
}

static PHLWINDOWREF g_footGreen;
static SP<CEventLoopTimer> g_footHold;
static bool g_footMenuOpened = false;
static bool g_footGreenMoved = false;
static Vector2D g_footGreenOrigin;
static bool g_footRightDown = false;
static std::optional<int32_t> g_footTouch;
static Vector2D g_footTouchPoint;
static PHLMONITORREF g_footTouchMonitor;
static std::string g_footSnap;

static void footEvent(const std::string& data) {
    IPC::Socket2::sock()->postEvent({.event = "custom", .data = data});
}

static std::string footAddress(PHLWINDOW window) {
    return std::format("{:#x}", reinterpret_cast<uintptr_t>(window.get()));
}

static int windowLayoutLimits(lua_State* lua) {
    const std::string_view address = luaL_checkstring(lua, 1);
    const auto& windows = Desktop::windowState()->windows();
    const auto it = std::ranges::find_if(windows, [&](const auto& window) {
        return windowLayoutApp(window) && window->mapped() && footAddress(window) == address;
    });
    if (it == windows.end())
        return 0;
    const auto min = (*it)->minSize().value_or(Vector2D{});
    const auto max = (*it)->maxSize().value_or(Vector2D{});
    lua_pushnumber(lua, min.x);
    lua_pushnumber(lua, min.y);
    lua_pushnumber(lua, max.x);
    lua_pushnumber(lua, max.y);
    return 4;
}

static PHLMONITOR monitorAt(const Vector2D& point) {
    return State::monitorState()->query().vec(point).run();
}

static bool footWindow(PHLWINDOW window) {
    return windowLayoutApp(window) && window->mapped() && !window->isHidden() && window->isFloating();
}

static PHLWINDOW footGreenAt(const Vector2D& point) {
    if (g_windowLayoutApps.empty() || g_pSessionLockManager->isSessionLocked() || g_pInputManager->isConstrained())
        return {};
    const auto monitor = monitorAt(point);
    if (!monitor)
        return {};
    auto tester = Desktop::viewState()->hitTest();
    for (auto layer : {ZWLR_LAYER_SHELL_V1_LAYER_TOP, ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY}) {
        PHLLS surface;
        Vector2D coords;
        tester.layerSurfaceAt(point, &monitor->m_layerSurfaceLayers[layer], &coords, &surface);
        if (surface)
            return {};
    }
    auto window = tester.windowAt(point, Desktop::View::RESERVED_EXTENTS | Desktop::View::INPUT_EXTENTS | Desktop::View::ALLOW_FLOATING);
    if (!footWindow(window))
        return {};
    const auto main = window->getWindowMainSurfaceBox();
    const auto full = window->getWindowBoxUnified(Desktop::View::RESERVED_EXTENTS);
    const double height = main.y - full.y;
    // Same offsets as the three traffic lights registered in silky-macos.lua.
    const auto green = CBox{full.x + 52, full.y + std::floor((height - 12) / 2), 20, 12};
    return height >= 12 && green.containsPoint(point) ? window : PHLWINDOW{};
}

static void showFootMenu(PHLWINDOW window) {
    const auto monitor = window->m_monitor.lock();
    if (!monitor)
        return;
    const auto box = window->getWindowMainSurfaceBox();
    footEvent(std::format("silky-foot-menu,{},{},{},{}", footAddress(window), monitor->m_name,
                          std::lround(box.x - monitor->m_position.x + 40), std::lround(box.y - monitor->m_position.y - 5)));
}

static void cancelFootHold() {
    if (g_footHold)
        g_pEventLoopManager->removeTimer(g_footHold);
    g_footHold.reset();
}

static void trackFootGreenMotion(const Vector2D& point) {
    if (g_footGreen && !g_footGreenMoved && point.distance(g_footGreenOrigin) >= START_PX) {
        g_footGreenMoved = true;
        cancelFootHold();
    }
}

static void footGreenDown(PHLWINDOW window, const Vector2D& point) {
    cancelFootHold();
    g_footGreen = window;
    g_footMenuOpened = false;
    g_footGreenMoved = false;
    g_footGreenOrigin = point;
    Desktop::focusState()->fullWindowFocus(window, Desktop::FOCUS_REASON_CLICK);
    Desktop::windowState()->raise(window);
    g_footHold = makeShared<CEventLoopTimer>(std::chrono::milliseconds(500), [](SP<CEventLoopTimer>, void*) {
        const auto target = g_footGreen.lock();
        const auto point = g_footTouch ? g_footTouchPoint : g_pInputManager->getMouseCoordsInternal();
        if (target && footGreenAt(point) == target) {
            g_footMenuOpened = true;
            showFootMenu(target);
        }
    }, nullptr);
    g_pEventLoopManager->addTimer(g_footHold);
}

static void releaseFootGreen(const Vector2D& point, bool cancelled) {
    const auto window = g_footGreen.lock();
    trackFootGreenMotion(point);
    cancelFootHold();
    g_footGreen.reset();
    if (!cancelled && window && !g_footMenuOpened && !g_footGreenMoved && footGreenAt(point) == window)
        footEvent("silky-foot-action," + footAddress(window) + ",fullscreen");
}

static bool handleFootMouse(const IPointer::SButtonEvent& event, Event::SCallbackInfo& info) {
    if (g_footTouch || (event.button != BTN_LEFT && event.button != BTN_RIGHT))
        return false;
    const auto point = g_pInputManager->getMouseCoordsInternal();
    if (event.state == WL_POINTER_BUTTON_STATE_PRESSED) {
        const auto window = footGreenAt(point);
        if (!window)
            return false;
        if (event.button == BTN_RIGHT) {
            g_footRightDown = true;
            showFootMenu(window);
        } else {
            footGreenDown(window, point);
        }
    } else if (event.button == BTN_RIGHT) {
        if (!std::exchange(g_footRightDown, false))
            return false;
    } else {
        if (g_footTouch || !g_footGreen)
            return false;
        releaseFootGreen(point, false);
    }
    info.cancelled = true;
    return true;
}

static bool footTouchDown(int32_t id, const Vector2D& point, PHLMONITOR monitor) {
    if (g_footTouch || g_footGreen)
        return false;
    const auto window = footGreenAt(point);
    if (!window)
        return false;
    g_footTouch = id;
    g_footTouchMonitor = monitor;
    g_footTouchPoint = point;
    footGreenDown(window, point);
    return true;
}

static bool footTouchUp(int32_t id, bool cancelled) {
    if (g_footTouch != id)
        return false;
    g_footTouch.reset();
    releaseFootGreen(g_footTouchPoint, cancelled);
    return true;
}

static void trackFootSnap(PHLWINDOW window, bool moving) {
    std::string next;
    if (moving && footWindow(window)) {
        const auto cursor = g_pInputManager->getMouseCoordsInternal();
        if (const auto monitor = monitorAt(cursor)) {
            const auto pos = cursor - monitor->m_position;
            const auto size = monitor->m_size;
            const auto side = pos.x < 28 ? "left" : pos.x >= size.x - 28 ? "right" : "";
            if (*side)
                next = std::format("{},{},{}{}", footAddress(window), monitor->m_name,
                                   pos.y < size.y / 4 ? "top-" : pos.y >= size.y * .75 ? "bottom-" : "", side);
        }
    }
    if (next != g_footSnap) {
        g_footSnap = std::move(next);
        footEvent(g_footSnap.empty() ? "silky-foot-snap,hide" : "silky-foot-snap," + g_footSnap);
    }
}

static void finishFootSnap() {
    if (g_footSnap.empty())
        return;
    footEvent("silky-foot-drop," + g_footSnap);
    g_footSnap.clear();
}
