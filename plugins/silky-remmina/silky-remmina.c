/*
 * Silky Remmina: a GTK3 module loaded only into Remmina (see bin/silky-remmina).
 *
 *  - Loads silky-remmina.css on top of the system GTK theme, so the theme can
 *    keep following MacTahoe-Dark / MacTahoe-Light live (no GTK_THEME pin).
 *    The stylesheet is applied only while a MacTahoe theme is active.
 *  - Tags Remmina's main and connection windows with .silky-glass plus
 *    .silky-dark / .silky-light, and gives them an RGBA visual so Hyprland can
 *    blur what shows through the translucent backgrounds.
 *  - Exposes MacShell's accent colour as @silky_accent (macbar/settings.json).
 *  - Reworks the connection window toolbar when it is horizontal: traffic
 *    lights and the connection name on the left, a trimmed set of tools on
 *    the right, rarely used tools moved into a "⋯" menu.
 *
 * Remmina 1.4.44 / GTK 3.24. Toolbar items are matched by icon name.
 */
#include <gtk/gtk.h>
#include <librsvg/rsvg.h>
#include <string.h>

#define MODULE_NAME "silky-remmina"

static GtkCssProvider *style_provider;
static GtkCssProvider *accent_provider;
static gboolean style_applied;
static gchar *css_path;
static gchar *accent_path;
static gchar *icon_dir;
static GFileMonitor *css_monitor;
static GFileMonitor *accent_monitor;
static gboolean lang_zh;

/* ---------- appearance ---------- */

static gboolean theme_is_mac(const gchar *name)
{
    return name && g_str_has_prefix(name, "MacTahoe");
}

static gboolean theme_is_dark(const gchar *name)
{
    gchar *lower = g_ascii_strdown(name ? name : "", -1);
    gboolean dark = strstr(lower, "dark") != NULL;
    g_free(lower);
    return dark;
}

static gchar *current_theme(void)
{
    gchar *name = NULL;
    g_object_get(gtk_settings_get_default(), "gtk-theme-name", &name, NULL);
    return name;
}

static gboolean is_main_window(GtkWidget *w)
{
    if (g_strcmp0(gtk_widget_get_name(w), "remmina-main-window") == 0)
        return TRUE;
    /* The builder id is not a widget name, so recognise the main window by
     * shape: a normal application window with a header bar, not a dialog. */
    if (G_OBJECT_TYPE(w) != GTK_TYPE_WINDOW && G_OBJECT_TYPE(w) != GTK_TYPE_APPLICATION_WINDOW)
        return FALSE;
    if (gtk_window_get_window_type(GTK_WINDOW(w)) != GTK_WINDOW_TOPLEVEL ||
        gtk_window_get_type_hint(GTK_WINDOW(w)) != GDK_WINDOW_TYPE_HINT_NORMAL ||
        gtk_window_get_transient_for(GTK_WINDOW(w)))
        return FALSE;
    if (!GTK_IS_HEADER_BAR(gtk_window_get_titlebar(GTK_WINDOW(w))))
        return FALSE;
    gtk_widget_set_name(w, "remmina-main-window");
    return TRUE;
}

static gboolean is_remmina_window(GtkWidget *w)
{
    if (!GTK_IS_WINDOW(w))
        return FALSE;
    if (g_strcmp0(G_OBJECT_TYPE_NAME(w), "RemminaConnectionWindow") == 0)
        return TRUE;
    return is_main_window(w);
}

static void tag_window(GtkWidget *w)
{
    gchar *theme = current_theme();
    GtkStyleContext *sc = gtk_widget_get_style_context(w);
    gboolean dark = theme_is_dark(theme);

    gtk_style_context_add_class(sc, "silky-glass");
    if (dark) {
        gtk_style_context_add_class(sc, "silky-dark");
        gtk_style_context_remove_class(sc, "silky-light");
    } else {
        gtk_style_context_add_class(sc, "silky-light");
        gtk_style_context_remove_class(sc, "silky-dark");
    }
    g_free(theme);
}

static void load_css(void)
{
    GError *error = NULL;
    if (!gtk_css_provider_load_from_path(style_provider, css_path, &error)) {
        g_warning(MODULE_NAME ": %s", error->message);
        g_clear_error(&error);
    }
}

static void load_accent(void)
{
    gchar *accent = NULL;
    gchar *text = NULL;

    if (g_file_get_contents(accent_path, &text, NULL, NULL)) {
        /* Tiny scan for "accent": "#rrggbb"; avoids a JSON dependency. */
        const gchar *p = strstr(text, "\"accent\"");
        if (p && (p = strchr(p + 8, '#')) && strlen(p) >= 7) {
            gchar candidate[8];
            gboolean ok = TRUE;
            memcpy(candidate, p, 7);
            candidate[7] = '\0';
            for (int i = 1; i < 7; i++)
                ok = ok && g_ascii_isxdigit(candidate[i]);
            if (ok)
                accent = g_strdup(candidate);
        }
        g_free(text);
    }
    gchar *css = g_strdup_printf("@define-color silky_accent %s;", accent ? accent : "#0a84ff");
    gtk_css_provider_load_from_data(accent_provider, css, -1, NULL);
    g_free(css);
    g_free(accent);
}

static void apply_appearance(void)
{
    GtkSettings *settings = gtk_settings_get_default();
    GdkScreen *screen = gdk_screen_get_default();
    gchar *theme = current_theme();
    gboolean mac = theme_is_mac(theme);

    if (mac && !style_applied) {
        gtk_style_context_add_provider_for_screen(screen, GTK_STYLE_PROVIDER(accent_provider),
                                                  GTK_STYLE_PROVIDER_PRIORITY_APPLICATION + 10);
        gtk_style_context_add_provider_for_screen(screen, GTK_STYLE_PROVIDER(style_provider),
                                                  GTK_STYLE_PROVIDER_PRIORITY_APPLICATION + 20);
        style_applied = TRUE;
    } else if (!mac && style_applied) {
        gtk_style_context_remove_provider_for_screen(screen, GTK_STYLE_PROVIDER(style_provider));
        gtk_style_context_remove_provider_for_screen(screen, GTK_STYLE_PROVIDER(accent_provider));
        style_applied = FALSE;
    }

    /* The theme name decides light or dark. Remmina's own "dark theme" switch
     * would otherwise load gtk-dark.css and stick after a live switch. */
    if (mac) {
        gboolean prefer_dark = FALSE;
        g_object_get(settings, "gtk-application-prefer-dark-theme", &prefer_dark, NULL);
        if (prefer_dark)
            g_object_set(settings, "gtk-application-prefer-dark-theme", FALSE, NULL);
    }

    GList *tops = gtk_window_list_toplevels();
    for (GList *l = tops; l; l = l->next)
        if (is_remmina_window(l->data))
            tag_window(l->data);
    g_list_free(tops);
    g_free(theme);
}

static void on_theme_changed(GObject *o, GParamSpec *p, gpointer u)
{
    apply_appearance();
}

static void on_file_changed(GFileMonitor *m, GFile *f, GFile *o, GFileMonitorEvent ev, gpointer which)
{
    if (ev != G_FILE_MONITOR_EVENT_CHANGES_DONE_HINT && ev != G_FILE_MONITOR_EVENT_CREATED)
        return;
    if (which == (gpointer)accent_path)
        load_accent();
    else
        load_css();
}

static GFileMonitor *watch(const gchar *path, gpointer which)
{
    GFile *file = g_file_new_for_path(path);
    GFileMonitor *mon = g_file_monitor_file(file, G_FILE_MONITOR_NONE, NULL, NULL);
    g_object_unref(file);
    if (mon)
        g_signal_connect(mon, "changed", G_CALLBACK(on_file_changed), which);
    return mon;
}


/* ---------- toolbar icons ---------- */

/* Remmina's own toolbar icons are heavy 24 px glyphs with puzzling metaphors.
 * Swap them for a thin 16 px line set (config/remmina/icons) drawn in the
 * button's current CSS colour, so hover, checked, disabled and light / dark
 * all follow the stylesheet. Tooltips get plain wording; Remmina's shortcut
 * hint, e.g. "(Control_R + F)", is kept. */
typedef struct {
    const gchar *remmina_icon;
    const gchar *svg;
    const gchar *zh;
    const gchar *en;
} IconMap;

static const IconMap icon_map[] = {
    { "view-more-symbolic", "add", "打开其他连接", "Open another connection" },
    { "org.remmina.Remmina-go-home-symbolic", "connections", "连接列表", "Connection list" },
    { "org.remmina.Remmina-fit-window-symbolic", "fit-window", "窗口贴合远程分辨率", "Fit window to remote screen" },
    { "org.remmina.Remmina-fullscreen-symbolic", "fullscreen", "全屏", "Full screen" },
    { "org.remmina.Remmina-dynres-symbolic", "dynamic-resolution", "远程分辨率跟随窗口", "Resize remote screen with window" },
    { "org.remmina.Remmina-scale-symbolic", "scale", "缩放画面以适应窗口", "Scale to window" },
    { "org.remmina.Remmina-keyboard-symbolic", "keyboard", "捕获键盘（快捷键发给远程）", "Capture keyboard" },
    { "org.remmina.Remmina-insert-object-symbolic", "command", "发送组合键", "Send key combination" },
    { "org.remmina.Remmina-preferences-system-symbolic", "sliders", "画质与连接选项", "Quality and session options" },
    { "org.remmina.Remmina-system-run-symbolic", "tools", "远程操作", "Remote actions" },
    { "org.remmina.Remmina-camera-photo-symbolic", "screenshot", "截屏", "Screenshot" },
    { "org.remmina.Remmina-disconnect-symbolic", "disconnect", "断开连接", "Disconnect" },
};

static GHashTable *svg_cache; /* svg name -> template text */

static const gchar *svg_template(const gchar *name)
{
    if (!svg_cache)
        svg_cache = g_hash_table_new_full(g_str_hash, g_str_equal, g_free, g_free);
    gchar *text = g_hash_table_lookup(svg_cache, name);
    if (!text) {
        gchar *file = g_strdup_printf("%s/%s.svg", icon_dir, name);
        if (!g_file_get_contents(file, &text, NULL, NULL))
            text = g_strdup("");
        g_free(file);
        g_hash_table_insert(svg_cache, g_strdup(name), text);
    }
    return *text ? text : NULL;
}

static gboolean draw_icon(GtkWidget *w, cairo_t *cr, gpointer data)
{
    const gchar *tmpl = svg_template(data);
    GtkStyleContext *sc = gtk_widget_get_style_context(w);
    GdkRGBA c;
    gint width = gtk_widget_get_allocated_width(w), height = gtk_widget_get_allocated_height(w);
    gint size = MIN(width, height);

    if (!tmpl)
        return FALSE;
    gtk_style_context_get_color(sc, gtk_style_context_get_state(sc), &c);
    gchar alpha[G_ASCII_DTOSTR_BUF_SIZE], colour[96];
    g_ascii_formatd(alpha, sizeof alpha, "%.3f", c.alpha);
    g_snprintf(colour, sizeof colour, "#%02x%02x%02x\" stroke-opacity=\"%s\"",
               (int)(c.red * 255 + 0.5), (int)(c.green * 255 + 0.5), (int)(c.blue * 255 + 0.5), alpha);
    GString *svg = g_string_new(tmpl);
    g_string_replace(svg, "currentColor\"", colour, 1);
    RsvgHandle *h = rsvg_handle_new_from_data((const guint8 *)svg->str, svg->len, NULL);
    if (h) {
        RsvgRectangle vp = { (width - size) / 2.0, (height - size) / 2.0, size, size };
        rsvg_handle_render_document(h, cr, &vp, NULL);
        g_object_unref(h);
    }
    g_string_free(svg, TRUE);
    return FALSE;
}

static GtkWidget *line_icon(const gchar *svg, gint size)
{
    GtkWidget *area = gtk_drawing_area_new();
    /* A GtkDrawingArea normally gets its own GdkWindow, which would take the
     * press over the icon away from the button: clicks in the middle of a
     * button did nothing. Draw into the button's window instead. */
    gtk_widget_set_has_window(area, FALSE);
    gtk_widget_set_size_request(area, size, size);
    gtk_widget_set_halign(area, GTK_ALIGN_CENTER);
    gtk_widget_set_valign(area, GTK_ALIGN_CENTER);
    gtk_style_context_add_class(gtk_widget_get_style_context(area), "silky-icon");
    g_signal_connect(area, "draw", G_CALLBACK(draw_icon), (gpointer)svg);
    gtk_widget_show(area);
    return area;
}

static void restyle_item(GtkToolItem *item)
{
    if (GTK_IS_TOOL_BUTTON(item)) {
        const gchar *icon = gtk_tool_button_get_icon_name(GTK_TOOL_BUTTON(item));
        for (gsize i = 0; icon && i < G_N_ELEMENTS(icon_map); i++) {
            const IconMap *m = &icon_map[i];
            if (g_strcmp0(m->remmina_icon, icon) != 0 || !svg_template(m->svg))
                continue;
            gtk_tool_button_set_icon_widget(GTK_TOOL_BUTTON(item), line_icon(m->svg, 16));
            gchar *old = gtk_widget_get_tooltip_text(GTK_WIDGET(item));
            const gchar *hint = old ? strstr(old, " (") : NULL;
            gchar *tip = g_strconcat(lang_zh ? m->zh : m->en, hint ? hint : "", NULL);
            gtk_tool_item_set_tooltip_text(item, tip);
            g_free(tip);
            g_free(old);
            return;
        }
        return;
    }
    /* The small dropdowns beside full screen and scaling: a chevron, not a hamburger. */
    GtkWidget *child = gtk_bin_get_child(GTK_BIN(item));
    if (GTK_IS_TOGGLE_BUTTON(child) && GTK_IS_IMAGE(gtk_bin_get_child(GTK_BIN(child))) && svg_template("chevron")) {
        gtk_container_remove(GTK_CONTAINER(child), gtk_bin_get_child(GTK_BIN(child)));
        gtk_container_add(GTK_CONTAINER(child), line_icon("chevron", 12));
        gtk_style_context_add_class(gtk_widget_get_style_context(child), "silky-dropdown");
        if (!gtk_widget_get_tooltip_text(child))
            gtk_widget_set_tooltip_text(child, lang_zh ? "选项" : "Options");
    }
}

/* ---------- connection window toolbar ---------- */

typedef enum { KEEP, MOVE_TO_MENU, DROP, HIDE_WHEN_INSENSITIVE } Fate;

typedef struct {
    const gchar *icon;
    Fate fate;
    const gchar *zh;
    const gchar *en;
} ToolRule;

static const ToolRule rules[] = {
    { "org.remmina.Remmina-duplicate-symbolic", MOVE_TO_MENU, "复制当前连接", "Duplicate connection" },
    { "org.remmina.Remmina-password-reveal-symbolic", MOVE_TO_MENU, "仅查看模式", "View only" },
    { "input-mouse-symbolic", MOVE_TO_MENU, "反转滚动方向", "Invert scroll direction" },
    { "org.remmina.Remmina-document-properties-symbolic", MOVE_TO_MENU, "编辑连接设置", "Edit connection" },
    { "org.remmina.Remmina-go-bottom-symbolic", MOVE_TO_MENU, "最小化窗口", "Minimize window" },
    { "org.remmina.Remmina-reconnect-symbolic", MOVE_TO_MENU, "重新连接", "Reconnect" },
    /* Tabs are shown whenever there is more than one, so the tab menu is redundant. */
    { "org.remmina.Remmina-switch-page-symbolic", DROP, NULL, NULL },
    /* Plugin-specific menus: only meaningful when the protocol offers them. */
    { "org.remmina.Remmina-preferences-system-symbolic", HIDE_WHEN_INSENSITIVE, NULL, NULL },
    { "org.remmina.Remmina-system-run-symbolic", HIDE_WHEN_INSENSITIVE, NULL, NULL },
    { "org.remmina.Remmina-insert-object-symbolic", HIDE_WHEN_INSENSITIVE, NULL, NULL },
};

static const ToolRule *rule_for(GtkToolItem *item)
{
    if (!GTK_IS_TOOL_BUTTON(item))
        return NULL;
    const gchar *icon = gtk_tool_button_get_icon_name(GTK_TOOL_BUTTON(item));
    for (gsize i = 0; icon && i < G_N_ELEMENTS(rules); i++)
        if (g_strcmp0(rules[i].icon, icon) == 0)
            return &rules[i];
    return NULL;
}

static gboolean rehide(gpointer data)
{
    GtkWidget *w = data;
    const ToolRule *rule = rule_for(GTK_TOOL_ITEM(w));
    gboolean hide = rule && (rule->fate != HIDE_WHEN_INSENSITIVE || !gtk_widget_get_sensitive(w));
    if (hide && gtk_widget_get_visible(w))
        gtk_widget_hide(w);
    else if (rule && rule->fate == HIDE_WHEN_INSENSITIVE && !hide && !gtk_widget_get_visible(w))
        gtk_widget_show(w);
    g_object_unref(w);
    return G_SOURCE_REMOVE;
}

/* Separators are toolbar items too; keep them hidden when Remmina re-shows them. */
static gboolean rehide_separator(gpointer data)
{
    if (gtk_widget_get_visible(data))
        gtk_widget_hide(data);
    g_object_unref(data);
    return G_SOURCE_REMOVE;
}

/* Remmina toggles visibility and sensitivity as features change; keep our verdict. */
static void on_item_state(GObject *o, GParamSpec *p, gpointer u)
{
    g_idle_add(GTK_IS_SEPARATOR_TOOL_ITEM(o) ? rehide_separator : rehide, g_object_ref(o));
}

static gchar *menu_label(GtkToolItem *item, const ToolRule *rule)
{
    if (lang_zh && rule->zh)
        return g_strdup(rule->zh);
    gchar *tip = gtk_widget_get_tooltip_text(GTK_WIDGET(item));
    if (tip && *tip) {
        gchar *cut = strstr(tip, " (");
        if (cut)
            *cut = '\0';
        return tip;
    }
    g_free(tip);
    return g_strdup(rule->en);
}

static void on_menu_item(GtkMenuItem *mi, gpointer data)
{
    GtkToolItem *item = data;
    if (GTK_IS_TOGGLE_TOOL_BUTTON(item)) {
        GtkToggleToolButton *t = GTK_TOGGLE_TOOL_BUTTON(item);
        gtk_toggle_tool_button_set_active(t, !gtk_toggle_tool_button_get_active(t));
    } else {
        g_signal_emit_by_name(item, "clicked");
    }
}

static gboolean destroy_menu(gpointer menu)
{
    gtk_widget_destroy(menu);
    return G_SOURCE_REMOVE;
}

static void destroy_later(GtkWidget *menu)
{
    g_idle_add(destroy_menu, menu);
}

static void on_more_clicked(GtkButton *button, gpointer data)
{
    GtkToolbar *toolbar = data;
    GtkWidget *menu = gtk_menu_new();
    gint n = gtk_toolbar_get_n_items(toolbar);

    gtk_style_context_add_class(gtk_widget_get_style_context(menu), "silky-more-menu");
    for (gint i = 0; i < n; i++) {
        GtkToolItem *item = gtk_toolbar_get_nth_item(toolbar, i);
        const ToolRule *rule = rule_for(item);
        if (!rule || rule->fate != MOVE_TO_MENU)
            continue;
        gchar *label = menu_label(item, rule);
        GtkWidget *mi;
        if (GTK_IS_TOGGLE_TOOL_BUTTON(item)) {
            mi = gtk_check_menu_item_new_with_label(label);
            gtk_check_menu_item_set_active(GTK_CHECK_MENU_ITEM(mi),
                gtk_toggle_tool_button_get_active(GTK_TOGGLE_TOOL_BUTTON(item)));
        } else {
            mi = gtk_menu_item_new_with_label(label);
        }
        g_free(label);
        gtk_widget_set_sensitive(mi, gtk_widget_get_sensitive(GTK_WIDGET(item)));
        g_signal_connect(mi, "activate", G_CALLBACK(on_menu_item), item);
        gtk_menu_shell_append(GTK_MENU_SHELL(menu), mi);
    }
    gtk_widget_show_all(menu);
    /* GtkMenuShell deactivates the menu before it activates the chosen item,
     * so destroying it right away would drop the click. */
    g_signal_connect(menu, "deactivate", G_CALLBACK(destroy_later), NULL);
    gtk_menu_attach_to_widget(GTK_MENU(menu), GTK_WIDGET(button), NULL);
    gtk_menu_popup_at_widget(GTK_MENU(menu), GTK_WIDGET(button),
                             GDK_GRAVITY_SOUTH_EAST, GDK_GRAVITY_NORTH_EAST, NULL);
}

static void toggle_maximize(GtkWindow *win)
{
    if (gtk_window_is_maximized(win))
        gtk_window_unmaximize(win);
    else
        gtk_window_maximize(win);
}

static void on_close(GtkButton *b, gpointer win) { gtk_window_close(GTK_WINDOW(win)); }
static void on_zoom(GtkButton *b, gpointer win) { toggle_maximize(GTK_WINDOW(win)); }

/* GTK3 buttons let their press propagate, so a press that reached a
 * toolbar or tab row may have started on a button. Starting a move there
 * hands the pointer to the compositor and the button never sees its
 * release, which swallows the click. Only drag from bare space. */
static gboolean pressed_on_control(GtkWidget *handler, GdkEventButton *ev)
{
    for (GtkWidget *w = gtk_get_event_widget((GdkEvent *)ev); w && w != handler; w = gtk_widget_get_parent(w))
        if (GTK_IS_BUTTON(w) || GTK_IS_ENTRY(w) || GTK_IS_RANGE(w))
            return TRUE;
    return FALSE;
}

static gboolean on_title_press(GtkWidget *w, GdkEventButton *ev, gpointer win)
{
    if (ev->button != GDK_BUTTON_PRIMARY || pressed_on_control(w, ev))
        return FALSE;
    if (ev->type == GDK_2BUTTON_PRESS) {
        toggle_maximize(GTK_WINDOW(win));
        return TRUE;
    }
    if (ev->type == GDK_BUTTON_PRESS) {
        gtk_window_begin_move_drag(GTK_WINDOW(win), ev->button, (gint)ev->x_root, (gint)ev->y_root, ev->time);
        return TRUE;
    }
    return FALSE;
}

static GtkWidget *light(const gchar *cls, const gchar *icon, GCallback cb, GtkWidget *win)
{
    GtkWidget *b = gtk_button_new_from_icon_name(icon, GTK_ICON_SIZE_MENU);
    GtkStyleContext *sc = gtk_widget_get_style_context(b);
    gtk_image_set_pixel_size(GTK_IMAGE(gtk_button_get_image(GTK_BUTTON(b))), 8);
    gtk_style_context_add_class(sc, "silky-light-button");
    gtk_style_context_add_class(sc, cls);
    gtk_widget_set_valign(b, GTK_ALIGN_CENTER);
    gtk_widget_set_focus_on_click(b, FALSE);
    gtk_widget_set_can_focus(b, FALSE);
    g_signal_connect(b, "clicked", cb, win);
    return b;
}

static GtkToolItem *title_item(GtkWidget *win)
{
    GtkToolItem *item = gtk_tool_item_new();
    GtkWidget *box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
    GtkWidget *lights = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    GtkWidget *ebox = gtk_event_box_new();
    GtkWidget *label = gtk_label_new(NULL);

    gtk_style_context_add_class(gtk_widget_get_style_context(lights), "silky-lights");
    gtk_box_pack_start(GTK_BOX(lights), light("close", "window-close-symbolic", G_CALLBACK(on_close), win), FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(lights), light("maximize", "list-add-symbolic", G_CALLBACK(on_zoom), win), FALSE, FALSE, 0);

    gtk_style_context_add_class(gtk_widget_get_style_context(label), "silky-title");
    gtk_label_set_ellipsize(GTK_LABEL(label), PANGO_ELLIPSIZE_END);
    gtk_label_set_width_chars(GTK_LABEL(label), 8);
    gtk_label_set_max_width_chars(GTK_LABEL(label), 32);
    g_object_bind_property(win, "title", label, "label", G_BINDING_SYNC_CREATE);
    gtk_container_add(GTK_CONTAINER(ebox), label);
    gtk_event_box_set_visible_window(GTK_EVENT_BOX(ebox), FALSE);
    g_signal_connect(ebox, "button-press-event", G_CALLBACK(on_title_press), win);

    gtk_box_pack_start(GTK_BOX(box), lights, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(box), ebox, FALSE, FALSE, 0);
    gtk_container_add(GTK_CONTAINER(item), box);
    gtk_style_context_add_class(gtk_widget_get_style_context(GTK_WIDGET(item)), "silky-title-item");
    gtk_widget_show_all(GTK_WIDGET(item));
    return item;
}

/* Empty toolbar space drags the window, like a macOS unified toolbar. */
static gboolean on_spacer_press(GtkWidget *w, GdkEventButton *ev, gpointer win)
{
    return on_title_press(w, ev, win);
}

static GtkToolItem *spacer_item(GtkWidget *win)
{
    GtkToolItem *item = gtk_tool_item_new();
    GtkWidget *ebox = gtk_event_box_new();
    gtk_event_box_set_visible_window(GTK_EVENT_BOX(ebox), FALSE);
    g_signal_connect(ebox, "button-press-event", G_CALLBACK(on_spacer_press), win);
    gtk_container_add(GTK_CONTAINER(item), ebox);
    gtk_tool_item_set_expand(item, TRUE);
    gtk_widget_show_all(GTK_WIDGET(item));
    return item;
}


/* Empty space in the tab row (shown with two or more sessions) drags the
 * window too. GtkNotebook stops the emission when a tab is clicked, so this
 * after-handler only sees presses on bare header space; presses inside the
 * remote screen are excluded by position. */
static gboolean on_tabs_press(GtkWidget *nb, GdkEventButton *ev, gpointer u)
{
    GtkWidget *page = gtk_notebook_get_nth_page(GTK_NOTEBOOK(nb), gtk_notebook_get_current_page(GTK_NOTEBOOK(nb)));
    GtkAllocation nba, pa;
    gint x, y;

    if (!page || !gtk_notebook_get_show_tabs(GTK_NOTEBOOK(nb)))
        return FALSE;
    gtk_widget_get_allocation(nb, &nba);
    gtk_widget_get_allocation(page, &pa);
    if (!gtk_widget_translate_coordinates(nb, gtk_widget_get_toplevel(nb), (gint)ev->x, (gint)ev->y, &x, &y))
        return FALSE;
    /* Header above the page (top tabs) only. */
    if (y >= pa.y || y < nba.y)
        return FALSE;
    return on_title_press(nb, ev, gtk_widget_get_toplevel(nb));
}

/* Tabs only with two or more sessions, whatever always_show_tab says;
 * Remmina re-applies its own choice when pages come and go. */
static void sync_tabs(GtkNotebook *nb)
{
    gboolean want = gtk_notebook_get_n_pages(nb) > 1;
    if (g_strcmp0(g_getenv("SILKY_REMMINA_TOOLBAR"), "native") != 0 && gtk_notebook_get_show_tabs(nb) != want)
        gtk_notebook_set_show_tabs(nb, want);
}

static void on_tabs_changed(GtkNotebook *nb) { sync_tabs(nb); }

static void drag_from_tabs(GtkWidget *w, gpointer u)
{
    if (GTK_IS_NOTEBOOK(w) && !g_object_get_data(G_OBJECT(w), MODULE_NAME)) {
        g_object_set_data(G_OBJECT(w), MODULE_NAME, GINT_TO_POINTER(1));
        gtk_widget_add_events(w, GDK_BUTTON_PRESS_MASK);
        g_signal_connect_after(w, "button-press-event", G_CALLBACK(on_tabs_press), NULL);
        g_signal_connect(w, "notify::show-tabs", G_CALLBACK(on_tabs_changed), NULL);
        g_signal_connect_after(w, "page-added", G_CALLBACK(on_tabs_changed), NULL);
        g_signal_connect_after(w, "page-removed", G_CALLBACK(on_tabs_changed), NULL);
        sync_tabs(GTK_NOTEBOOK(w));
    }
}

static GtkToolItem *more_item(GtkToolbar *toolbar)
{
    GtkToolItem *item = gtk_tool_item_new();
    GtkWidget *b = gtk_button_new();
    if (svg_template("more"))
        gtk_container_add(GTK_CONTAINER(b), line_icon("more", 16));
    else
        gtk_button_set_image(GTK_BUTTON(b), gtk_image_new_from_icon_name("view-more-symbolic", GTK_ICON_SIZE_SMALL_TOOLBAR));
    gtk_button_set_relief(GTK_BUTTON(b), GTK_RELIEF_NONE);
    gtk_widget_set_focus_on_click(b, FALSE);
    gtk_widget_set_tooltip_text(b, lang_zh ? "更多操作" : "More");
    gtk_style_context_add_class(gtk_widget_get_style_context(b), "flat");
    gtk_style_context_add_class(gtk_widget_get_style_context(b), "image-button");
    g_signal_connect(b, "clicked", G_CALLBACK(on_more_clicked), toolbar);
    gtk_container_add(GTK_CONTAINER(item), b);
    gtk_style_context_add_class(gtk_widget_get_style_context(GTK_WIDGET(item)), "silky-more");
    gtk_widget_show_all(GTK_WIDGET(item));
    return item;
}

/* Remmina only reads toolbar_placement from remmina.pref at startup and
 * rewrites that file when it quits, so a placement set by the installer can
 * be lost. Put a windowed connection toolbar across the top regardless:
 * toolbar in row 0, notebook in row 1 of Remmina's grid.
 * SILKY_REMMINA_TOOLBAR=native keeps Remmina's own placement. */
static void place_on_top(GtkToolbar *toolbar)
{
    GtkWidget *grid = gtk_widget_get_parent(GTK_WIDGET(toolbar));
    if (!GTK_IS_GRID(grid) || g_strcmp0(g_getenv("SILKY_REMMINA_TOOLBAR"), "native") == 0)
        return;
    gtk_orientable_set_orientation(GTK_ORIENTABLE(toolbar), GTK_ORIENTATION_HORIZONTAL);
    gtk_widget_set_hexpand(GTK_WIDGET(toolbar), TRUE);
    gtk_widget_set_vexpand(GTK_WIDGET(toolbar), FALSE);
    gtk_container_child_set(GTK_CONTAINER(grid), GTK_WIDGET(toolbar),
                            "left-attach", 0, "top-attach", 0, "width", 1, "height", 1, NULL);
    GList *kids = gtk_container_get_children(GTK_CONTAINER(grid));
    for (GList *l = kids; l; l = l->next) {
        if (l->data == (gpointer)toolbar)
            continue;
        gtk_container_child_set(GTK_CONTAINER(grid), l->data,
                                "left-attach", 0, "top-attach", 1, "width", 1, "height", 1, NULL);
    }
    g_list_free(kids);
}

static void rework_toolbar(GtkToolbar *toolbar, GtkWidget *win)
{
    gboolean windowed = g_strcmp0(gtk_widget_get_name(win), "remmina-connection-window-fullscreen") != 0;
    if (windowed)
        place_on_top(toolbar);
    gboolean horizontal = gtk_orientable_get_orientation(GTK_ORIENTABLE(toolbar)) == GTK_ORIENTATION_HORIZONTAL;
    gint n = gtk_toolbar_get_n_items(toolbar);
    gint disconnect_at = -1;

    gtk_style_context_add_class(gtk_widget_get_style_context(GTK_WIDGET(toolbar)), "silky-toolbar");

    for (gint i = 0; i < n; i++) {
        GtkToolItem *item = gtk_toolbar_get_nth_item(toolbar, i);
        const ToolRule *rule = rule_for(item);
        if (GTK_IS_TOOL_BUTTON(item) &&
            g_strcmp0(gtk_tool_button_get_icon_name(GTK_TOOL_BUTTON(item)), "org.remmina.Remmina-disconnect-symbolic") == 0)
            disconnect_at = i;
        restyle_item(item);
        /* Separators that end up next to each other after trimming look sloppy; drop them all
         * and let spacing group the buttons. */
        if (GTK_IS_SEPARATOR_TOOL_ITEM(item)) {
            gtk_widget_hide(GTK_WIDGET(item));
            g_signal_connect(item, "notify::visible", G_CALLBACK(on_item_state), NULL);
            continue;
        }
        if (!rule)
            continue;
        g_signal_connect(item, "notify::visible", G_CALLBACK(on_item_state), NULL);
        g_signal_connect(item, "notify::sensitive", G_CALLBACK(on_item_state), NULL);
        g_object_ref(item);
        rehide(item);
    }

    if (disconnect_at >= 0)
        gtk_toolbar_insert(toolbar, more_item(toolbar), disconnect_at);
    else
        gtk_toolbar_insert(toolbar, more_item(toolbar), -1);

    if (horizontal && windowed) {
        gtk_toolbar_insert(toolbar, title_item(win), 0);
        gtk_toolbar_insert(toolbar, spacer_item(win), 1);
        gtk_style_context_add_class(gtk_widget_get_style_context(GTK_WIDGET(toolbar)), "silky-unified");
        GtkWidget *grid = gtk_widget_get_parent(GTK_WIDGET(toolbar));
        if (GTK_IS_CONTAINER(grid))
            gtk_container_foreach(GTK_CONTAINER(grid), drag_from_tabs, NULL);
    }
}

static gboolean process_toolbar(gpointer data)
{
    GtkWidget *toolbar = data;
    GtkWidget *win = gtk_widget_get_toplevel(toolbar);

    if (gtk_widget_is_toplevel(win) &&
        g_strcmp0(G_OBJECT_TYPE_NAME(win), "RemminaConnectionWindow") == 0 &&
        !g_object_get_data(G_OBJECT(toolbar), MODULE_NAME)) {
        g_object_set_data(G_OBJECT(toolbar), MODULE_NAME, GINT_TO_POINTER(1));
        rework_toolbar(GTK_TOOLBAR(toolbar), win);
    }
    g_object_set_data(G_OBJECT(toolbar), MODULE_NAME "-pending", NULL);
    g_object_unref(toolbar);
    return G_SOURCE_REMOVE;
}


/* ---------- main window list: rounded selection pill ---------- */

/* GtkTreeView paints selection per cell, so CSS cannot give a whole row one
 * rounded shape. Paint the pill underneath; the stylesheet makes selected
 * cells transparent (treeview.silky-pill-list). */
static gboolean on_list_draw(GtkWidget *w, cairo_t *cr, gpointer u)
{
    GtkTreeView *tv = GTK_TREE_VIEW(w);
    GtkTreeSelection *sel = gtk_tree_view_get_selection(tv);
    GtkTreeModel *model = NULL;
    GList *rows = gtk_tree_selection_get_selected_rows(sel, &model);
    GtkStyleContext *sc = gtk_widget_get_style_context(w);
    gboolean focused = (gtk_widget_get_state_flags(w) & GTK_STATE_FLAG_BACKDROP) == 0;
    GdkRGBA fill;
    const gdouble inset = 6, radius = 7;
    gint width = gtk_widget_get_allocated_width(w);

    if (!rows)
        return FALSE;
    if (focused) {
        if (!gtk_style_context_lookup_color(sc, "silky_accent", &fill))
            gdk_rgba_parse(&fill, "#0a84ff");
    } else {
        GdkRGBA fg;
        gtk_style_context_get_color(sc, gtk_style_context_get_state(sc), &fg);
        fill = fg;
        fill.alpha = 0.14;
    }
    for (GList *l = rows; l; l = l->next) {
        GdkRectangle area;
        gint x, y;
        gtk_tree_view_get_background_area(tv, l->data, NULL, &area);
        gtk_tree_view_convert_bin_window_to_widget_coords(tv, area.x, area.y, &x, &y);
        gdouble left = inset, top = y + 1, w2 = width - 2 * inset, h = area.height - 2;
        if (h <= 0 || w2 <= 0)
            continue;
        cairo_new_sub_path(cr);
        cairo_arc(cr, left + w2 - radius, top + radius, radius, -G_PI_2, 0);
        cairo_arc(cr, left + w2 - radius, top + h - radius, radius, 0, G_PI_2);
        cairo_arc(cr, left + radius, top + h - radius, radius, G_PI_2, G_PI);
        cairo_arc(cr, left + radius, top + radius, radius, G_PI, 3 * G_PI_2);
        cairo_close_path(cr);
        gdk_cairo_set_source_rgba(cr, &fill);
        cairo_fill(cr);
    }
    g_list_free_full(rows, (GDestroyNotify)gtk_tree_path_free);
    return FALSE;
}

static void redraw(GtkWidget *w) { gtk_widget_queue_draw(w); }

static void pill_lists(GtkWidget *w, gpointer u)
{
    if (GTK_IS_TREE_VIEW(w) && !g_object_get_data(G_OBJECT(w), MODULE_NAME)) {
        g_object_set_data(G_OBJECT(w), MODULE_NAME, GINT_TO_POINTER(1));
        gtk_style_context_add_class(gtk_widget_get_style_context(w), "silky-pill-list");
        gtk_tree_view_set_grid_lines(GTK_TREE_VIEW(w), GTK_TREE_VIEW_GRID_LINES_NONE);
        g_signal_connect(w, "draw", G_CALLBACK(on_list_draw), NULL);
        g_signal_connect_swapped(gtk_tree_view_get_selection(GTK_TREE_VIEW(w)), "changed", G_CALLBACK(redraw), w);
        g_signal_connect(w, "state-flags-changed", G_CALLBACK(gtk_widget_queue_draw), NULL);
    }
    if (GTK_IS_CONTAINER(w))
        gtk_container_forall(GTK_CONTAINER(w), pill_lists, NULL);
}

/* ---------- hooks ---------- */

static gboolean on_hierarchy(GSignalInvocationHint *h, guint n, const GValue *v, gpointer u)
{
    GObject *obj = g_value_get_object(&v[0]);
    if (GTK_IS_TOOLBAR(obj) && !g_object_get_data(obj, MODULE_NAME) &&
        !g_object_get_data(obj, MODULE_NAME "-pending")) {
        g_object_set_data(obj, MODULE_NAME "-pending", GINT_TO_POINTER(1));
        g_idle_add(process_toolbar, g_object_ref(obj));
    }
    return TRUE;
}

static gboolean on_show(GSignalInvocationHint *h, guint n, const GValue *v, gpointer u)
{
    GtkWidget *w = g_value_get_object(&v[0]);
    if (!is_remmina_window(w))
        return TRUE;
    if (!gtk_widget_get_realized(w)) {
        GdkVisual *rgba = gdk_screen_get_rgba_visual(gtk_widget_get_screen(w));
        if (rgba)
            gtk_widget_set_visual(w, rgba);
    }
    tag_window(w);
    if (g_strcmp0(gtk_widget_get_name(w), "remmina-main-window") == 0)
        pill_lists(w, NULL);
    return TRUE;
}

static void drop_from_env(void)
{
    /* Keep the module out of anything Remmina launches. */
    const gchar *mods = g_getenv("GTK_MODULES");
    if (!mods)
        return;
    gchar **parts = g_strsplit(mods, ":", -1);
    GString *rest = g_string_new(NULL);
    for (gchar **p = parts; *p; p++) {
        if (!**p || g_strcmp0(*p, MODULE_NAME) == 0)
            continue;
        if (rest->len)
            g_string_append_c(rest, ':');
        g_string_append(rest, *p);
    }
    if (rest->len)
        g_setenv("GTK_MODULES", rest->str, TRUE);
    else
        g_unsetenv("GTK_MODULES");
    g_string_free(rest, TRUE);
    g_strfreev(parts);
}

G_MODULE_EXPORT void gtk_module_init(gint *argc, gchar ***argv)
{
    const gchar *const *langs = g_get_language_names();
    lang_zh = langs && langs[0] && g_str_has_prefix(langs[0], "zh");

    drop_from_env();

    const gchar *env_css = g_getenv("SILKY_REMMINA_CSS");
    css_path = env_css && *env_css ? g_strdup(env_css)
                                   : g_build_filename(g_get_user_data_dir(), "silky-remmina", "silky-remmina.css", NULL);
    const gchar *env_icons = g_getenv("SILKY_REMMINA_ICONS");
    icon_dir = env_icons && *env_icons ? g_strdup(env_icons)
                                       : g_build_filename(g_get_user_data_dir(), "silky-remmina", "icons", NULL);
    accent_path = g_build_filename(g_get_user_config_dir(), "macbar", "settings.json", NULL);

    style_provider = gtk_css_provider_new();
    accent_provider = gtk_css_provider_new();
    load_accent();
    load_css();
    css_monitor = watch(css_path, css_path);
    accent_monitor = watch(accent_path, accent_path);

    g_signal_connect(gtk_settings_get_default(), "notify::gtk-theme-name", G_CALLBACK(on_theme_changed), NULL);
    apply_appearance();

    g_signal_add_emission_hook(g_signal_lookup("show", GTK_TYPE_WIDGET), 0, on_show, NULL, NULL);
    g_signal_add_emission_hook(g_signal_lookup("hierarchy-changed", GTK_TYPE_WIDGET), 0, on_hierarchy, NULL, NULL);
}

G_MODULE_EXPORT const gchar *g_module_check_init(GModule *module)
{
    /* Hooks and providers stay registered for the life of the process. */
    g_module_make_resident(module);
    return NULL;
}
