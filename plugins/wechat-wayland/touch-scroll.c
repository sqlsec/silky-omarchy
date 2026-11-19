// Convert touchscreen drags to Wayland finger scrolling for the existing WeChat Wayland launcher.
#define _GNU_SOURCE
#include <link.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <wayland-client.h>

enum {
    TITLE_HEIGHT = 54 * 256,
    SWIPE_SLOP = 12 * 256,
};

static int (*add_listener)(struct wl_proxy *, void (**)(void), void *);
static void (*destroy_proxy)(struct wl_proxy *);
static struct wl_proxy *(*marshal_array_flags)(struct wl_proxy *, uint32_t,
    const struct wl_interface *, uint32_t, uint32_t, union wl_argument *);

static struct wl_pointer_listener pointer_original, pointer_listener;
static struct wl_touch_listener touch_original, touch_listener;
static struct wl_pointer *pointer_proxy;
static struct wl_touch *touch_proxy;
static void *pointer_data;

struct pointer_position {
    struct wl_surface *surface;
    uint32_t serial;
    wl_fixed_t x, y;
};

static struct pointer_position real_pointer;
static unsigned pointer_buttons;

static struct {
    struct pointer_position origin;
    int32_t id;
    wl_fixed_t last_y;
    uint32_t scroll_time;
    bool down, eligible, scrolling, cancelled, positioned;
    unsigned fingers;
} gesture;

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

static void scroll(uint32_t time, wl_fixed_t delta)
{
    if (!gesture.positioned) {
        place_pointer(real_pointer, gesture.origin, time);
        gesture.positioned = true;
    }
    gesture.scroll_time = time;
    pointer_original.axis_source(pointer_data, pointer_proxy, WL_POINTER_AXIS_SOURCE_FINGER);
    pointer_original.axis(pointer_data, pointer_proxy, time, WL_POINTER_AXIS_VERTICAL_SCROLL, delta);
    flush_pointer();
}

static void pointer_enter(void *data, struct wl_pointer *pointer, uint32_t serial,
                          struct wl_surface *surface, wl_fixed_t x, wl_fixed_t y)
{
    restore_pointer(0);
    real_pointer = (struct pointer_position){surface, serial, x, y};
    pointer_original.enter(data, pointer, serial, surface, x, y);
}

static void pointer_leave(void *data, struct wl_pointer *pointer, uint32_t serial,
                          struct wl_surface *surface)
{
    restore_pointer(0);
    real_pointer = (struct pointer_position){0};
    pointer_buttons = 0;
    pointer_original.leave(data, pointer, serial, surface);
}

static void pointer_motion(void *data, struct wl_pointer *pointer, uint32_t time,
                           wl_fixed_t x, wl_fixed_t y)
{
    restore_pointer(time);
    real_pointer.x = x;
    real_pointer.y = y;
    pointer_original.motion(data, pointer, time, x, y);
}

static void pointer_button(void *data, struct wl_pointer *pointer, uint32_t serial,
                           uint32_t time, uint32_t button, uint32_t state)
{
    restore_pointer(time);
    if (state == WL_POINTER_BUTTON_STATE_PRESSED)
        ++pointer_buttons;
    else if (pointer_buttons)
        --pointer_buttons;
    pointer_original.button(data, pointer, serial, time, button, state);
}

static void pointer_axis_source(void *data, struct wl_pointer *pointer, uint32_t source)
{
    restore_pointer(0);
    pointer_original.axis_source(data, pointer, source);
}

static void touch_down(void *data, struct wl_touch *touch, uint32_t serial, uint32_t time,
                       struct wl_surface *surface, int32_t id, wl_fixed_t x, wl_fixed_t y)
{
    if (!gesture.fingers) {
        gesture.origin = (struct pointer_position){surface, serial, x, y};
        gesture.id = id;
        gesture.last_y = y;
        gesture.down = true;
        gesture.eligible = surface && y >= TITLE_HEIGHT;
    } else {
        gesture.eligible = false;
        restore_pointer(time);
    }
    ++gesture.fingers;
    if (!gesture.cancelled)
        touch_original.down(data, touch, serial, time, surface, id, x, y);
}

static void touch_motion(void *data, struct wl_touch *touch, uint32_t time, int32_t id,
                         wl_fixed_t x, wl_fixed_t y)
{
    if (gesture.down && gesture.id == id && gesture.eligible && pointer_proxy &&
        wl_proxy_get_version((struct wl_proxy *)pointer_proxy) >= WL_POINTER_FRAME_SINCE_VERSION &&
        !pointer_buttons) {
        const int64_t dx = (int64_t)x - gesture.origin.x;
        const int64_t dy = (int64_t)y - gesture.origin.y;
        if (!gesture.scrolling && llabs(dx) >= SWIPE_SLOP && llabs(dx) >= llabs(dy))
            gesture.eligible = false;
        if (!gesture.scrolling && gesture.eligible && llabs(dy) >= SWIPE_SLOP &&
            llabs(dy) > llabs(dx)) {
            gesture.scrolling = true;
            gesture.cancelled = true;
            gesture.last_y += dy > 0 ? SWIPE_SLOP : -SWIPE_SLOP;
            touch_original.cancel(data, touch);
        }
        if (gesture.scrolling) {
            wl_fixed_t delta = gesture.last_y - y;
            gesture.last_y = y;
            if (delta)
                scroll(time, delta);
        }
    }
    if (!gesture.cancelled)
        touch_original.motion(data, touch, time, id, x, y);
}

static void touch_up(void *data, struct wl_touch *touch, uint32_t serial,
                     uint32_t time, int32_t id)
{
    if (!gesture.cancelled)
        touch_original.up(data, touch, serial, time, id);
    if (gesture.down && gesture.id == id) {
        gesture.down = false;
        restore_pointer(time);
    }
    if (gesture.fingers && !--gesture.fingers)
        memset(&gesture, 0, sizeof gesture);
}

static void touch_cancel(void *data, struct wl_touch *touch)
{
    restore_pointer(0);
    if (!gesture.cancelled)
        touch_original.cancel(data, touch);
    memset(&gesture, 0, sizeof gesture);
}

static void touch_frame(void *data, struct wl_touch *touch)
{
    if (!gesture.cancelled)
        touch_original.frame(data, touch);
}

static void touch_shape(void *data, struct wl_touch *touch, int32_t id,
                        wl_fixed_t major, wl_fixed_t minor)
{
    if (!gesture.cancelled && touch_original.shape)
        touch_original.shape(data, touch, id, major, minor);
}

static void touch_orientation(void *data, struct wl_touch *touch, int32_t id,
                              wl_fixed_t orientation)
{
    if (!gesture.cancelled && touch_original.orientation)
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
    if (proxy == (struct wl_proxy *)gesture.origin.surface) {
        gesture.origin.surface = NULL;
        gesture.eligible = false;
        gesture.positioned = false;
    }
    if (proxy == (struct wl_proxy *)pointer_proxy) {
        pointer_proxy = NULL;
        pointer_buttons = 0;
        real_pointer = (struct pointer_position){0};
        gesture.positioned = false;
    }
    if (proxy == (struct wl_proxy *)touch_proxy) {
        if (pointer_proxy)
            restore_pointer(0);
        touch_proxy = NULL;
        memset(&gesture, 0, sizeof gesture);
    }
}

static void destroy(struct wl_proxy *proxy)
{
    forget(proxy);
    destroy_proxy(proxy);
}

static struct wl_proxy *marshal(struct wl_proxy *proxy, uint32_t opcode,
    const struct wl_interface *interface, uint32_t version, uint32_t flags,
    union wl_argument *args)
{
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
    return !strncmp(base, "libwayland-client.so", sizeof "libwayland-client.so" - 1)
        ? LA_FLG_BINDTO : 0;
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
    if (!strcmp(name, "wl_proxy_marshal_array_flags")) {
        marshal_array_flags = (__typeof__(marshal_array_flags))symbol->st_value;
        return (uintptr_t)marshal;
    }
    return symbol->st_value;
}
