// Native compositor-rendered snap preview overlay (replaces the fullscreen transparent QML layer
// in FolioSnapPreview.qml with zero cross-process IPC and zero fullscreen Vulkan surface overhead).
struct SSnapPreview {
    using Clock = std::chrono::steady_clock;

    std::string       output;
    CBox              fromBox;
    CBox              toBox;
    CBox              lastDamaged;
    Clock::time_point moveStart{};
    float             fromAlpha = 0.0f;
    float             toAlpha = 0.0f;
    Clock::time_point alphaStart{};
    bool              active = false;
    bool              hasBox = false;

    static constexpr double MOVE_MS = 90.0;
    static constexpr double FADE_IN_MS = 65.0;
    static constexpr double FADE_OUT_MS = 45.0;

    static double elapsedMs(Clock::time_point t0, Clock::time_point now) {
        return std::chrono::duration<double, std::milli>(now - t0).count();
    }

    static double easeOutCubic(double t) {
        t = std::clamp(t, 0.0, 1.0);
        const double inv = 1.0 - t;
        return 1.0 - inv * inv * inv;
    }

    float currentAlpha(Clock::time_point now) const {
        if (!active)
            return 0.0f;
        const double dur = toAlpha > fromAlpha ? FADE_IN_MS : FADE_OUT_MS;
        const double t   = std::clamp(elapsedMs(alphaStart, now) / dur, 0.0, 1.0);
        return static_cast<float>(fromAlpha + (toAlpha - fromAlpha) * t);
    }

    CBox currentBox(Clock::time_point now) const {
        if (!hasBox)
            return {};
        const double t = easeOutCubic(elapsedMs(moveStart, now) / MOVE_MS);
        return {
            fromBox.x + (toBox.x - fromBox.x) * t,
            fromBox.y + (toBox.y - fromBox.y) * t,
            fromBox.w + (toBox.w - fromBox.w) * t,
            fromBox.h + (toBox.h - fromBox.h) * t,
        };
    }

    bool animating(Clock::time_point now) const {
        if (!active)
            return false;
        const double alphaDur = toAlpha > fromAlpha ? FADE_IN_MS : FADE_OUT_MS;
        return elapsedMs(alphaStart, now) < alphaDur || elapsedMs(moveStart, now) < MOVE_MS;
    }
};

static SSnapPreview g_snapPreview;

static void damageSnapMonitor(const std::string& monName, const CBox& logicalBox) {
    if (monName.empty() || logicalBox.w <= 0 || logicalBox.h <= 0)
        return;
    for (auto& m : State::monitorState()->monitors()) {
        if (m && m->m_name == monName) {
            CBox globalBox = logicalBox.copy().translate(m->m_position).expand(8);
            g_pHyprRenderer->damageBox(globalBox);
            break;
        }
    }
}

static void showSnapPreview(const std::string& output, double x, double y, double w, double h) {
    const auto now = SSnapPreview::Clock::now();
    const CBox target{x + 4.0, y + 4.0, std::max(0.0, w - 8.0), std::max(0.0, h - 8.0)};
    const bool sameOutput = g_snapPreview.active && g_snapPreview.output == output && g_snapPreview.hasBox;

    if (g_snapPreview.active && g_snapPreview.output != output)
        damageSnapMonitor(g_snapPreview.output, g_snapPreview.lastDamaged);

    g_snapPreview.fromAlpha  = g_snapPreview.currentAlpha(now);
    g_snapPreview.toAlpha    = 1.0f;
    g_snapPreview.alphaStart = now;

    if (sameOutput && g_snapPreview.fromAlpha > 0.01f) {
        g_snapPreview.fromBox   = g_snapPreview.currentBox(now);
        g_snapPreview.toBox     = target;
        g_snapPreview.moveStart = now;
    } else {
        g_snapPreview.fromBox   = target;
        g_snapPreview.toBox     = target;
        g_snapPreview.moveStart = now - std::chrono::milliseconds(200);
    }

    g_snapPreview.output = output;
    g_snapPreview.hasBox = true;
    g_snapPreview.active = true;
    damageSnapMonitor(output, g_snapPreview.fromBox);
    damageSnapMonitor(output, target);
}

static void hideSnapPreview(bool immediate = false) {
    if (!g_snapPreview.active)
        return;
    const auto now = SSnapPreview::Clock::now();
    if (immediate) {
        damageSnapMonitor(g_snapPreview.output, g_snapPreview.lastDamaged);
        g_snapPreview = {};
        return;
    }
    g_snapPreview.fromAlpha  = g_snapPreview.currentAlpha(now);
    g_snapPreview.toAlpha    = 0.0f;
    g_snapPreview.alphaStart = now;
    damageSnapMonitor(g_snapPreview.output, g_snapPreview.currentBox(now));
    damageSnapMonitor(g_snapPreview.output, g_snapPreview.lastDamaged);
}

static int luaSnapPreview(lua_State* lua) {
    const std::string output = luaL_checkstring(lua, 1);
    const double      x      = luaL_checknumber(lua, 2);
    const double      y      = luaL_checknumber(lua, 3);
    const double      w      = luaL_checknumber(lua, 4);
    const double      h      = luaL_checknumber(lua, 5);
    showSnapPreview(output, x, y, w, h);
    return 0;
}

static int luaSnapPreviewHide(lua_State*) {
    hideSnapPreview(false);
    return 0;
}

static void renderSnapPreview(const Event::SRenderStageEvent& event) {
    if (!g_snapPreview.active || event.stage != RENDER_POST_WINDOWS || !event.context || !event.monitor)
        return;
    auto& ctx = event.context->get();
    if (ctx.m_renderingSnapshot || ctx.m_renderingCapture)
        return;
    if (event.monitor->m_name != g_snapPreview.output)
        return;

    const auto  now   = SSnapPreview::Clock::now();
    const float alpha = g_snapPreview.currentAlpha(now);
    const CBox  box   = g_snapPreview.currentBox(now);
    if (alpha <= 0.004f && g_snapPreview.toAlpha == 0.0f) {
        damageSnapMonitor(g_snapPreview.output, g_snapPreview.lastDamaged);
        g_snapPreview = {};
        return;
    }

    const double scale = event.monitor->m_scale;
    CBox         fbBox = box.copy().scale(scale).round();
    if (fbBox.w <= 1 || fbBox.h <= 1)
        return;

    const int radius = static_cast<int>(std::lround(13.0 * scale));
    const int border = std::max(1, static_cast<int>(std::lround(2.0 * scale)));

    CRectPassElement::SRectData fill;
    fill.box           = fbBox;
    fill.color         = CHyprColor(0x3b / 255.0f, 0x9e / 255.0f, 1.0f, (0x3d / 255.0f) * alpha);
    fill.round         = radius;
    fill.roundingPower = 2.0f;
    Render::IHyprRenderer::addPassElement(ctx, makeUnique<CRectPassElement>(fill));

    CBorderPassElement::SBorderData stroke;
    stroke.box           = fbBox;
    stroke.grad1         = Config::CGradientValueData(CHyprColor(0x66 / 255.0f, 0xb5 / 255.0f, 1.0f, (0xb8 / 255.0f) * alpha));
    stroke.round         = radius;
    stroke.borderSize    = border;
    stroke.roundingPower = 2.0f;
    stroke.a             = 1.0f;
    Render::IHyprRenderer::addPassElement(ctx, makeUnique<CBorderPassElement>(stroke));

    g_snapPreview.lastDamaged = box;
    if (g_snapPreview.animating(now)) {
        CBox dmg = box.copy().translate(event.monitor->m_position).expand(8);
        g_pHyprRenderer->damageBox(dmg);
    }
}
