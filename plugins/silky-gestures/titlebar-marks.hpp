// The Tahoe titlebar keeps Omarchy's circles and input. These strokes match
// Folio's 8 px artwork and are rasterized once at each output's device scale.
static bool g_titlebarMarksEnabled = false;
static std::unordered_map<double, SP<Render::ITexture>> g_titlebarMarks;

static constexpr int BUTTON_SIZE = 12;
static constexpr int BUTTON_STEP = 20;
static constexpr int TITLEBAR_PADDING = 12;
static constexpr int MARK_SIZE = 8;
static constexpr int MARKS_WIDTH = 2 * BUTTON_STEP + MARK_SIZE;

static SP<Render::ITexture> makeTitlebarMarks(double scale) {
    auto* surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, std::lround(MARKS_WIDTH * scale), std::lround(MARK_SIZE * scale));
    auto* cr = cairo_create(surface);
    cairo_scale(cr, scale, scale);
    cairo_set_line_width(cr, 1.1);
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND);

    const auto line = [cr](double x1, double y1, double x2, double y2) {
        cairo_move_to(cr, x1, y1);
        cairo_line_to(cr, x2, y2);
    };
    constexpr double alpha = 191.0 / 255.0;
    cairo_set_source_rgba(cr, 77.0 / 255.0, 0, 0, alpha);
    line(1.5, 1.5, 6.5, 6.5);
    line(6.5, 1.5, 1.5, 6.5);
    cairo_stroke(cr);

    cairo_translate(cr, BUTTON_STEP, 0);
    cairo_set_source_rgba(cr, 85.0 / 255.0, 55.0 / 255.0, 0, alpha);
    line(1, 4, 7, 4);
    cairo_stroke(cr);

    cairo_translate(cr, BUTTON_STEP, 0);
    cairo_set_source_rgba(cr, 0, 77.0 / 255.0, 0, alpha);
    line(1, 4, 7, 4);
    line(4, 1, 4, 7);
    cairo_stroke(cr);

    cairo_destroy(cr);
    cairo_surface_flush(surface);
    auto texture = g_pHyprRenderer->createTexture(surface);
    cairo_surface_destroy(surface);
    return texture;
}

static void renderTitlebarMarks(const Event::SRenderStageEvent& event) {
    if (!g_titlebarMarksEnabled || event.stage != RENDER_POST_WINDOW || !event.context || !event.monitor)
        return;
    auto& ctx = event.context->get();
    const auto window = ctx.m_data.currentWindow.lock();
    if (!window || !window->mapped() || !window->isFloating() || ctx.m_renderingSnapshot || ctx.m_renderingCapture ||
        Fullscreen::controller()->isFullscreen(window, Fullscreen::FSMODE_FULLSCREEN))
        return;

    const auto bar = window->presentation().decoration(DECORATION_CUSTOM);
    if (!bar || bar->getDisplayName() != "Hyprbar" || !window->m_ruleApplicator->decorate().valueOrDefault())
        return;
    auto box = g_pDecorationPositioner->getWindowDecorationBox(bar.get());
    if (box.h < BUTTON_SIZE || box.w < TITLEBAR_PADDING + 2 * BUTTON_STEP + BUTTON_SIZE)
        return;
    if (window->m_workspace && !windowPinned(window))
        box.translate(window->m_workspace->m_renderOffset->value());

    // Omarchy's titlebar already damages this area when the hover changes.
    const auto cursor = g_pInputManager->getMouseCoordsInternal();
    const auto buttonY = box.y + std::floor((box.h - BUTTON_SIZE) / 2);
    const CBox hit = {box.x + TITLEBAR_PADDING, buttonY, 3 * BUTTON_STEP, BUTTON_SIZE};
    if (!hit.containsPoint(cursor))
        return;
    const auto underCursor = Desktop::viewState()->hitTest().windowAt(
        cursor, Desktop::View::RESERVED_EXTENTS | Desktop::View::INPUT_EXTENTS | Desktop::View::ALLOW_FLOATING);
    if (underCursor != window && (underCursor || Desktop::focusState()->window() != window))
        return;

    const double scale = event.monitor->m_scale;
    auto& texture = g_titlebarMarks[scale];
    if (!texture)
        texture = makeTitlebarMarks(scale);
    if (!texture || !texture->ok())
        return;

    const auto offset = box.pos() + window->presentation().floatingOffset() - event.monitor->m_position;
    const auto origin = (offset * scale).round();
    const CBox target = {
        origin.x + std::round((TITLEBAR_PADDING + (BUTTON_SIZE - MARK_SIZE) / 2.0) * scale),
        origin.y + std::round((box.h - MARK_SIZE) / 2.0 * scale),
        texture->m_size.x, texture->m_size.y,
    };
    CTexPassElement::SRenderData data;
    data.tex = texture;
    data.box = target;
    const auto presentation = window->presentation().renderPresentation();
    data.a = presentation.alpha * presentation.fadeAlpha;
    Render::IHyprRenderer::addPassElement(ctx, makeUnique<CTexPassElement>(std::move(data)));
}
