// Wayland adapter for WeChat:
// 1. Drop empty wl_touch.frame callbacks so bundled Qt never dereferences an empty touch list.
// 2. Convert vertical touchscreen drags below the title bar into 1:1 wl_pointer finger scrolling
//    with VSync-driven kinetic glide and tap-to-brake (without accidental clicks).
// 3. Forward xdg_toplevel.set_minimized to omarchy-hyprland-window-minimize so the minimize button works.
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <link.h>
#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
#include <wayland-client.h>

enum {
    TITLE_HEIGHT = 54 * 256,
    SWIPE_SLOP = 6 * 256,
    SWIPE_DEADZONE = 3 * 256,
    VELOCITY_WINDOW_MS = 90,
    VELOCITY_SAMPLES = 16,
    USER_ACTION_WINDOW_MS = 500,
    XDG_TOPLEVEL_SET_MAXIMIZED = 9,
    XDG_TOPLEVEL_UNSET_MAXIMIZED = 10,
    XDG_TOPLEVEL_SET_MINIMIZED = 13,
};

static int (*add_listener)(struct wl_proxy *, void (**)(void), void *);
static void (*destroy_proxy)(struct wl_proxy *);
static void (*marshal_array)(struct wl_proxy *, uint32_t, union wl_argument *);
static struct wl_proxy *(*marshal_array_flags)(struct wl_proxy *, uint32_t,
    const struct wl_interface *, uint32_t, uint32_t, union wl_argument *);

static struct wl_pointer_listener pointer_original, pointer_listener;
static struct wl_touch_listener touch_original, touch_listener;
static struct wl_pointer *pointer_proxy;
static struct wl_touch *touch_proxy;
static void *pointer_data;
static const struct wl_interface *host_cb_iface;
static char host_wl_path[256];
static bool host_wl_resolved;

struct pointer_position {
    struct wl_surface *surface;
    uint32_t serial;
    wl_fixed_t x, y;
};

static struct pointer_position real_pointer;
static unsigned pointer_buttons;
static bool frame_has_events;
static uint64_t last_user_input_ms;

struct velocity_sample {
    uint64_t time_ms;
    double delta_px;
};

static struct {
    struct pointer_position origin;
    int32_t id;
    wl_fixed_t last_y;
    uint32_t down_time;
    uint32_t scroll_time;
    bool down, eligible, scrolling, cancelled, positioned, braked, pending_down;
    unsigned fingers;
    struct velocity_sample samples[VELOCITY_SAMPLES];
    unsigned sample_count;
} gesture;

static struct {
    bool active;
    struct pointer_position origin;
    struct wl_proxy *frame_cb;
    uint64_t last_ms;
    double vel_px_s;
    double accum_px;
} glide;

static bool touch_scroll_enabled(void)
{
    const char *env = getenv("WECHAT_TOUCH_SCROLL");
    return !env || strcmp(env, "0") != 0;
}

static double touch_scroll_scale(void)
{
    static int cached = 0;
    static double scale = 1.0;
    if (!cached) {
        cached = 1;
        const char *env = getenv("WECHAT_TOUCH_SCROLL_SCALE");
        if (env && *env) {
            char *end = NULL;
            double v = strtod(env, &end);
            if (end != env && v >= 0.25 && v <= 4.0)
                scale = v;
        }
    }
    return scale;
}

static void spawn_command(char *const argv[])
{
    pid_t pid = fork();
    if (pid < 0)
        return;
    if (pid == 0) {
        pid_t child = fork();
        if (child == 0) {
            unsetenv("LD_AUDIT");
            execvp(argv[0], argv);
            _exit(127);
        }
        _exit(0);
    }
    int status;
    while (waitpid(pid, &status, 0) < 0 && errno == EINTR)
        ;
}

static uint64_t monotonic_ms(void)
{
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0)
        return 0;
    return (uint64_t)ts.tv_sec * 1000u + (uint64_t)ts.tv_nsec / 1000000u;
}

static void note_user_input(void)
{
    last_user_input_ms = monotonic_ms();
}

static bool recent_user_input(void)
{
    uint64_t now = monotonic_ms();
    return last_user_input_ms != 0 && now >= last_user_input_ms &&
        (now - last_user_input_ms) <= USER_ACTION_WINDOW_MS;
}

static void handle_toplevel_request(struct wl_proxy *proxy, uint32_t opcode)
{
    if (opcode != XDG_TOPLEVEL_SET_MINIMIZED &&
        opcode != XDG_TOPLEVEL_SET_MAXIMIZED &&
        opcode != XDG_TOPLEVEL_UNSET_MAXIMIZED)
        return;
    const char *class = wl_proxy_get_class(proxy);
    if (!class || strcmp(class, "xdg_toplevel") != 0)
        return;
    // Only forward user-initiated titlebar button / double-click actions.
    // When WeChat reopens its main window from the system tray, bundled Qt
    // can emit set_maximized during toplevel setup with no in-window click.
    if (!recent_user_input())
        return;
    if (opcode == XDG_TOPLEVEL_SET_MINIMIZED) {
        char *argv[] = {"sh", "-c",
            "[ \"$(qs -c MacShell ipc call window minimizeActive 2>/dev/null)\" = true ] || exec omarchy-hyprland-window-minimize",
            NULL};
        spawn_command(argv);
    } else if (opcode == XDG_TOPLEVEL_SET_MAXIMIZED) {
        char *argv[] = {"hyprctl", "eval",
            "local w=hl.get_active_window(); if w and w.class==\"wechat\" then "
            "hl.dispatch(hl.dsp.window.fullscreen({ mode = \"maximized\", action = \"set\", "
            "window = \"address:\" .. w.address })) end",
            NULL};
        spawn_command(argv);
    } else if (opcode == XDG_TOPLEVEL_UNSET_MAXIMIZED) {
        char *argv[] = {"hyprctl", "eval",
            "local w=hl.get_active_window(); if w and w.class==\"wechat\" then "
            "hl.dispatch(hl.dsp.window.fullscreen({ mode = \"maximized\", action = \"unset\", "
            "window = \"address:\" .. w.address })) end",
            NULL};
        spawn_command(argv);
    }
}

static void flush_pointer(void)
{
    if (wl_proxy_get_version((struct wl_proxy *)pointer_proxy) >= WL_POINTER_FRAME_SINCE_VERSION)
        pointer_original.frame(pointer_data, pointer_proxy);
}

static void place_pointer(struct pointer_position from, struct pointer_position to, uint32_t time)
{
    if (from.surface == to.surface) {
        if (to.surface)
            pointer_original.motion(pointer_data, pointer_proxy, time, to.x, to.y);
    } else {
        if (from.surface)
            pointer_original.leave(pointer_data, pointer_proxy, from.serial, from.surface);
        if (to.surface)
            pointer_original.enter(pointer_data, pointer_proxy, to.serial, to.surface, to.x, to.y);
    }
    flush_pointer();
}

static void restore_pointer(uint32_t time)
{
    if (gesture.positioned) {
        gesture.positioned = false;
        if (!time)
            time = gesture.scroll_time;
        pointer_original.axis_source(pointer_data, pointer_proxy, WL_POINTER_AXIS_SOURCE_FINGER);
        pointer_original.axis_stop(pointer_data, pointer_proxy, time, WL_POINTER_AXIS_VERTICAL_SCROLL);
        flush_pointer();
        place_pointer(gesture.origin, real_pointer, time);
    }
}

static void scroll_at(struct pointer_position origin, uint32_t time, wl_fixed_t delta)
{
    if (!pointer_proxy)
        return;
    if (!gesture.positioned) {
        place_pointer(real_pointer, origin, time);
        gesture.origin = origin;
        gesture.positioned = true;
    }
    gesture.scroll_time = time;
    pointer_original.axis_source(pointer_data, pointer_proxy, WL_POINTER_AXIS_SOURCE_FINGER);
    pointer_original.axis(pointer_data, pointer_proxy, time, WL_POINTER_AXIS_VERTICAL_SCROLL, delta);
    flush_pointer();
}

static void scroll(uint32_t time, wl_fixed_t delta)
{
    scroll_at(gesture.origin, time, delta);
}

static void record_velocity_sample(double delta_px)
{
    uint64_t now = monotonic_ms();
    unsigned keep = 0;
    for (unsigned i = 0; i < gesture.sample_count; ++i) {
        if (now >= gesture.samples[i].time_ms &&
            (now - gesture.samples[i].time_ms) <= VELOCITY_WINDOW_MS) {
            gesture.samples[keep++] = gesture.samples[i];
        }
    }
    if (keep == VELOCITY_SAMPLES) {
        memmove(&gesture.samples[0], &gesture.samples[1], (VELOCITY_SAMPLES - 1) * sizeof gesture.samples[0]);
        keep = VELOCITY_SAMPLES - 1;
    }
    gesture.samples[keep++] = (struct velocity_sample){now, delta_px};
    gesture.sample_count = keep;
}

static double measure_velocity_px_s(void)
{
    if (gesture.sample_count < 2)
        return 0.0;
    uint64_t now = monotonic_ms();
    uint64_t last_t = gesture.samples[gesture.sample_count - 1].time_ms;
    if (now < last_t || (now - last_t) > 70)
        return 0.0;
    uint64_t first_t = gesture.samples[0].time_ms;
    double span_ms = (double)(last_t > first_t ? (last_t - first_t) : 8u);
    if (span_ms < 8.0)
        span_ms = 8.0;
    double sum = 0.0;
    for (unsigned i = 1; i < gesture.sample_count; ++i)
        sum += gesture.samples[i].delta_px;
    double v = sum / span_ms * 1000.0;
    if (v > 10000.0)
        v = 10000.0;
    if (v < -10000.0)
        v = -10000.0;
    return v;
}

static void stop_glide(uint32_t time, bool restore)
{
    if (glide.frame_cb) {
        if (destroy_proxy)
            destroy_proxy(glide.frame_cb);
        glide.frame_cb = NULL;
    }
    bool was_active = glide.active;
    glide.active = false;
    glide.vel_px_s = 0.0;
    glide.accum_px = 0.0;
    glide.origin = (struct pointer_position){0};
    if (restore && (was_active || gesture.positioned))
        restore_pointer(time);
}

static void glide_frame_done(void *data, struct wl_callback *cb, uint32_t callback_time);

static const struct wl_callback_listener glide_frame_listener = {
    .done = glide_frame_done,
};

static void schedule_glide_frame(void)
{
    if (!glide.active || !glide.origin.surface || glide.frame_cb)
        return;
    if (!marshal_array_flags || !add_listener || !destroy_proxy || !host_cb_iface)
        return;
    // Allocate and bind wl_callback strictly through the host process's libwayland-client
    // (LM_ID_BASE) to avoid cross-namespace malloc/free aborts under LD_AUDIT.
    union wl_argument args[1];
    args[0].n = 0;
    struct wl_proxy *cb = marshal_array_flags(
        (struct wl_proxy *)glide.origin.surface,
        WL_SURFACE_FRAME,
        host_cb_iface,
        1,
        0,
        args);
    if (!cb)
        return;
    if (add_listener(cb, (void (**)(void))&glide_frame_listener, NULL) != 0) {
        destroy_proxy(cb);
        return;
    }
    glide.frame_cb = cb;
}

static void glide_frame_done(void *data, struct wl_callback *cb, uint32_t callback_time)
{
    (void)data;
    struct wl_proxy *cb_proxy = (struct wl_proxy *)cb;
    if (cb_proxy == glide.frame_cb)
        glide.frame_cb = NULL;
    if (cb_proxy && destroy_proxy)
        destroy_proxy(cb_proxy);

    if (!glide.active || !glide.origin.surface || !pointer_proxy) {
        stop_glide(callback_time, true);
        return;
    }

    uint64_t now = monotonic_ms();
    double dt = (now > glide.last_ms) ? (double)(now - glide.last_ms) / 1000.0 : 0.011;
    glide.last_ms = now;
    if (dt < 0.002)
        dt = 0.002;
    if (dt > 0.05)
        dt = 0.05;

    glide.accum_px += glide.vel_px_s * dt;
    glide.vel_px_s *= exp(-dt * 2.4);

    if (fabs(glide.vel_px_s) < 30.0) {
        stop_glide(callback_time, true);
        return;
    }

    wl_fixed_t delta = wl_fixed_from_double(glide.accum_px);
    if (delta != 0) {
        glide.accum_px -= wl_fixed_to_double(delta);
        schedule_glide_frame();
        scroll_at(glide.origin, callback_time, delta);
    } else {
        stop_glide(callback_time, true);
    }
}

static void ensure_host_wayland_symbols(void)
{
    if (host_wl_resolved)
        return;
    host_wl_resolved = true;
    const char *path = host_wl_path[0] ? host_wl_path : "libwayland-client.so.0";
    void *h = dlmopen(LM_ID_BASE, path, RTLD_LAZY | RTLD_NOLOAD);
    if (!h)
        return;
    if (!host_cb_iface)
        host_cb_iface = (const struct wl_interface *)dlsym(h, "wl_callback_interface");
    if (!marshal_array_flags)
        marshal_array_flags = (__typeof__(marshal_array_flags))dlsym(h, "wl_proxy_marshal_array_flags");
    if (!add_listener)
        add_listener = (__typeof__(add_listener))dlsym(h, "wl_proxy_add_listener");
    if (!destroy_proxy)
        destroy_proxy = (__typeof__(destroy_proxy))dlsym(h, "wl_proxy_destroy");
}

static void start_glide(struct pointer_position origin, uint32_t time, double vel_px_s)
{
    stop_glide(0, false);
    ensure_host_wayland_symbols();
    if (!origin.surface || !pointer_proxy || !host_cb_iface ||
        !marshal_array_flags || !add_listener || !destroy_proxy || fabs(vel_px_s) < 90.0) {
        restore_pointer(time);
        return;
    }
    glide.active = true;
    glide.origin = origin;
    glide.vel_px_s = vel_px_s * 1.15;
    glide.accum_px = 0.0;
    glide.last_ms = monotonic_ms();

    // Emit one initial ~11 ms step and attach a frame callback so Qt's own surface commit drives VSync glide.
    double first_px = glide.vel_px_s * 0.011;
    wl_fixed_t first_delta = wl_fixed_from_double(first_px);
    if (first_delta == 0) {
        stop_glide(time, true);
        return;
    }
    schedule_glide_frame();
    if (!glide.frame_cb) {
        stop_glide(time, true);
        return;
    }
    scroll_at(origin, time, first_delta);
}

static void pointer_enter(void *data, struct wl_pointer *pointer, uint32_t serial,
                          struct wl_surface *surface, wl_fixed_t x, wl_fixed_t y)
{
    stop_glide(0, true);
    real_pointer = (struct pointer_position){surface, serial, x, y};
    pointer_original.enter(data, pointer, serial, surface, x, y);
}

static void pointer_leave(void *data, struct wl_pointer *pointer, uint32_t serial,
                          struct wl_surface *surface)
{
    stop_glide(0, true);
    real_pointer = (struct pointer_position){0};
    pointer_buttons = 0;
    pointer_original.leave(data, pointer, serial, surface);
}

static void pointer_motion(void *data, struct wl_pointer *pointer, uint32_t time,
                           wl_fixed_t x, wl_fixed_t y)
{
    stop_glide(time, true);
    real_pointer.x = x;
    real_pointer.y = y;
    pointer_original.motion(data, pointer, time, x, y);
}

static void pointer_button(void *data, struct wl_pointer *pointer, uint32_t serial,
                           uint32_t time, uint32_t button, uint32_t state)
{
    stop_glide(time, true);
    note_user_input();
    if (state == WL_POINTER_BUTTON_STATE_PRESSED)
        ++pointer_buttons;
    else if (pointer_buttons)
        --pointer_buttons;
    pointer_original.button(data, pointer, serial, time, button, state);
}

static void pointer_axis_source(void *data, struct wl_pointer *pointer, uint32_t source)
{
    stop_glide(0, true);
    pointer_original.axis_source(data, pointer, source);
}

static void flush_pending_down(void *data, struct wl_touch *touch)
{
    if (!gesture.pending_down || !gesture.origin.surface)
        return;
    gesture.pending_down = false;
    note_user_input();
    touch_original.down(data, touch, gesture.origin.serial, gesture.down_time,
                        gesture.origin.surface, gesture.id, gesture.origin.x, gesture.origin.y);
    touch_original.frame(data, touch);
}

static void touch_down(void *data, struct wl_touch *touch, uint32_t serial, uint32_t time,
                       struct wl_surface *surface, int32_t id, wl_fixed_t x, wl_fixed_t y)
{
    bool braked = false;
    if (!gesture.fingers) {
        if (glide.active) {
            // Finger touched screen during inertial glide: brake immediately and suppress accidental tap.
            stop_glide(time, true);
            braked = true;
        }
        gesture.origin = (struct pointer_position){surface, serial, x, y};
        gesture.id = id;
        gesture.last_y = y;
        gesture.down_time = time;
        gesture.down = true;
        gesture.eligible = touch_scroll_enabled() && surface && y >= TITLE_HEIGHT;
        gesture.braked = braked;
        gesture.cancelled = braked;
        gesture.pending_down = !braked && gesture.eligible;
        gesture.sample_count = 0;
    } else {
        gesture.eligible = false;
        stop_glide(time, true);
        if (!gesture.cancelled && gesture.pending_down)
            flush_pending_down(data, touch);
    }
    ++gesture.fingers;
    if (!gesture.cancelled && !gesture.pending_down && surface) {
        note_user_input();
        touch_original.down(data, touch, serial, time, surface, id, x, y);
        frame_has_events = true;
    }
}

static void touch_motion(void *data, struct wl_touch *touch, uint32_t time, int32_t id,
                         wl_fixed_t x, wl_fixed_t y)
{
    if (gesture.down && gesture.id == id && gesture.eligible && pointer_proxy &&
        wl_proxy_get_version((struct wl_proxy *)pointer_proxy) >= WL_POINTER_FRAME_SINCE_VERSION &&
        !pointer_buttons) {
        const int64_t dx = (int64_t)x - gesture.origin.x;
        const int64_t dy = (int64_t)y - gesture.origin.y;
        if (!gesture.scrolling && llabs(dx) >= SWIPE_SLOP && llabs(dx) >= llabs(dy)) {
            gesture.eligible = false;
            if (!gesture.cancelled && gesture.pending_down)
                flush_pending_down(data, touch);
        }
        if (!gesture.scrolling && gesture.eligible && llabs(dy) >= SWIPE_SLOP &&
            llabs(dy) > llabs(dx)) {
            gesture.scrolling = true;
            gesture.last_y += dy > 0 ? SWIPE_DEADZONE : -SWIPE_DEADZONE;
            if (gesture.pending_down) {
                // Never forwarded touch_down to WeChat, so drop it silently: zero accidental clicks.
                gesture.pending_down = false;
                gesture.cancelled = true;
                frame_has_events = false;
            } else if (!gesture.cancelled) {
                gesture.cancelled = true;
                frame_has_events = false;
                touch_original.cancel(data, touch);
            }
        }
        if (gesture.scrolling) {
            wl_fixed_t raw_delta = gesture.last_y - y;
            gesture.last_y = y;
            if (raw_delta) {
                double delta_px = wl_fixed_to_double(raw_delta) * touch_scroll_scale();
                wl_fixed_t scaled = wl_fixed_from_double(delta_px);
                if (scaled) {
                    record_velocity_sample(wl_fixed_to_double(scaled));
                    scroll(time, scaled);
                }
            }
        }
    }
    if (!gesture.cancelled && !gesture.pending_down) {
        touch_original.motion(data, touch, time, id, x, y);
        frame_has_events = true;
    }
}

static void touch_up(void *data, struct wl_touch *touch, uint32_t serial,
                     uint32_t time, int32_t id)
{
    if (!gesture.cancelled) {
        if (gesture.pending_down && gesture.id == id)
            flush_pending_down(data, touch);
        note_user_input();
        touch_original.up(data, touch, serial, time, id);
        frame_has_events = true;
    }
    bool launch_glide = false;
    struct pointer_position glide_origin = {0};
    double glide_vel = 0.0;
    if (gesture.down && gesture.id == id) {
        gesture.down = false;
        if (gesture.scrolling && gesture.positioned) {
            glide_vel = measure_velocity_px_s();
            if (fabs(glide_vel) >= 90.0) {
                launch_glide = true;
                glide_origin = gesture.origin;
            } else {
                restore_pointer(time);
            }
        } else {
            restore_pointer(time);
        }
    }
    if (gesture.fingers && !--gesture.fingers) {
        bool keep_positioned = launch_glide;
        struct pointer_position saved_origin = gesture.origin;
        uint32_t saved_time = gesture.scroll_time;
        memset(&gesture, 0, sizeof gesture);
        if (keep_positioned) {
            gesture.positioned = true;
            gesture.origin = saved_origin;
            gesture.scroll_time = saved_time;
        }
    }
    if (launch_glide)
        start_glide(glide_origin, time, glide_vel);
}

static void touch_cancel(void *data, struct wl_touch *touch)
{
    stop_glide(0, true);
    frame_has_events = false;
    if (!gesture.cancelled && !gesture.pending_down)
        touch_original.cancel(data, touch);
    memset(&gesture, 0, sizeof gesture);
}

static void touch_frame(void *data, struct wl_touch *touch)
{
    bool send = !gesture.cancelled && frame_has_events;
    frame_has_events = false;
    if (send)
        touch_original.frame(data, touch);
}

static void touch_shape(void *data, struct wl_touch *touch, int32_t id,
                        wl_fixed_t major, wl_fixed_t minor)
{
    if (!gesture.cancelled && !gesture.pending_down && touch_original.shape)
        touch_original.shape(data, touch, id, major, minor);
}

static void touch_orientation(void *data, struct wl_touch *touch, int32_t id,
                              wl_fixed_t orientation)
{
    if (!gesture.cancelled && !gesture.pending_down && touch_original.orientation)
        touch_original.orientation(data, touch, id, orientation);
}

static int listen(struct wl_proxy *proxy, void (**callbacks)(void), void *data)
{
    const char *class = wl_proxy_get_class(proxy);
    if (!pointer_proxy && !strcmp(class, "wl_pointer")) {
        size_t count = 5;
        uint32_t version = wl_proxy_get_version(proxy);
        if (version >= WL_POINTER_FRAME_SINCE_VERSION)
            count = 9;
        if (version >= WL_POINTER_AXIS_VALUE120_SINCE_VERSION)
            count = 10;
        if (version >= WL_POINTER_AXIS_RELATIVE_DIRECTION_SINCE_VERSION)
            count = 11;
        memset(&pointer_original, 0, sizeof pointer_original);
        memcpy(&pointer_original, callbacks, count * sizeof(*callbacks));
        pointer_listener = pointer_original;
        pointer_listener.enter = pointer_enter;
        pointer_listener.leave = pointer_leave;
        pointer_listener.motion = pointer_motion;
        pointer_listener.button = pointer_button;
        pointer_listener.axis_source = pointer_axis_source;
        int result = add_listener(proxy, (void (**)(void))&pointer_listener, data);
        if (!result) {
            pointer_proxy = (struct wl_pointer *)proxy;
            pointer_data = data;
        }
        return result;
    }
    if (!touch_proxy && !strcmp(class, "wl_touch")) {
        size_t count = wl_proxy_get_version(proxy) >= WL_TOUCH_SHAPE_SINCE_VERSION ? 7 : 5;
        memset(&touch_original, 0, sizeof touch_original);
        memcpy(&touch_original, callbacks, count * sizeof(*callbacks));
        touch_listener = (struct wl_touch_listener){
            touch_down, touch_up, touch_motion, touch_frame, touch_cancel,
            touch_shape, touch_orientation,
        };
        int result = add_listener(proxy, (void (**)(void))&touch_listener, data);
        if (!result)
            touch_proxy = (struct wl_touch *)proxy;
        return result;
    }
    return add_listener(proxy, callbacks, data);
}

static void forget(struct wl_proxy *proxy)
{
    if (proxy == (struct wl_proxy *)real_pointer.surface)
        real_pointer = (struct pointer_position){0};
    if (proxy == (struct wl_proxy *)glide.origin.surface)
        stop_glide(0, false);
    if (proxy == (struct wl_proxy *)gesture.origin.surface) {
        gesture.origin.surface = NULL;
        gesture.eligible = false;
        gesture.positioned = false;
    }
    if (proxy == (struct wl_proxy *)pointer_proxy) {
        stop_glide(0, false);
        pointer_proxy = NULL;
        pointer_buttons = 0;
        real_pointer = (struct pointer_position){0};
        gesture.positioned = false;
    }
    if (proxy == (struct wl_proxy *)touch_proxy) {
        stop_glide(0, pointer_proxy != NULL);
        touch_proxy = NULL;
        frame_has_events = false;
        memset(&gesture, 0, sizeof gesture);
    }
}

static void destroy(struct wl_proxy *proxy)
{
    forget(proxy);
    destroy_proxy(proxy);
}

static void marshal_arr(struct wl_proxy *proxy, uint32_t opcode, union wl_argument *args)
{
    handle_toplevel_request(proxy, opcode);
    marshal_array(proxy, opcode, args);
}

static struct wl_proxy *marshal(struct wl_proxy *proxy, uint32_t opcode,
    const struct wl_interface *interface, uint32_t version, uint32_t flags,
    union wl_argument *args)
{
    if (!host_cb_iface && interface && interface->name && !strcmp(interface->name, "wl_callback"))
        host_cb_iface = interface;
    handle_toplevel_request(proxy, opcode);
    if (flags & WL_MARSHAL_FLAG_DESTROY)
        forget(proxy);
    return marshal_array_flags(proxy, opcode, interface, version, flags, args);
}

unsigned int la_version(unsigned int version)
{
    (void)version;
    return LAV_CURRENT;
}

unsigned int la_objopen(struct link_map *map, Lmid_t ns, uintptr_t *cookie)
{
    (void)cookie;
    if (ns != LM_ID_BASE)
        return 0;
    if (!map->l_name[0]) {
        char executable[sizeof "/opt/wechat/wechat"];
        ssize_t length = readlink("/proc/self/exe", executable, sizeof executable);
        if (length == (ssize_t)sizeof executable - 1 &&
            !memcmp(executable, "/opt/wechat/wechat", (size_t)length))
            return LA_FLG_BINDFROM;
    }
    const char *base = strrchr(map->l_name, '/');
    base = base ? base + 1 : map->l_name;
    if (!strncmp(base, "libwayland-client.so", sizeof "libwayland-client.so" - 1)) {
        if (!host_wl_path[0] && map->l_name[0])
            snprintf(host_wl_path, sizeof host_wl_path, "%s", map->l_name);
        return LA_FLG_BINDTO;
    }
    return 0;
}

uintptr_t la_symbind64(Elf64_Sym *symbol, unsigned int index, uintptr_t *from,
                       uintptr_t *to, unsigned int *flags, const char *name)
{
    (void)index;
    (void)from;
    (void)to;
    *flags |= LA_SYMB_NOPLTENTER | LA_SYMB_NOPLTEXIT;
    if (!strcmp(name, "wl_proxy_add_listener")) {
        add_listener = (__typeof__(add_listener))symbol->st_value;
        return (uintptr_t)listen;
    }
    if (!strcmp(name, "wl_proxy_destroy")) {
        destroy_proxy = (__typeof__(destroy_proxy))symbol->st_value;
        return (uintptr_t)destroy;
    }
    if (!strcmp(name, "wl_proxy_marshal_array")) {
        marshal_array = (__typeof__(marshal_array))symbol->st_value;
        return (uintptr_t)marshal_arr;
    }
    if (!strcmp(name, "wl_proxy_marshal_array_flags")) {
        marshal_array_flags = (__typeof__(marshal_array_flags))symbol->st_value;
        return (uintptr_t)marshal;
    }
    return symbol->st_value;
}
