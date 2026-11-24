// Silky Omarchy: remove the outer window-frame margin around WPS Office's
// KPromeMainWindow on Linux/XWayland so floating windows match maximized ones.
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <cstring>
#include <dlfcn.h>

namespace {

struct QMargins {
  int left;
  int top;
  int right;
  int bottom;
};

using SetMarginsRefFn = void (*)(void *, const QMargins &);
using SetMargins4Fn = void (*)(void *, int, int, int, int);
using ParentWidgetFn = void *(*)(const void *);
using WindowFn = void *(*)(const void *);
using CentralWidgetFn = void *(*)(const void *);
using ClassNameFn = const char *(*)(const void *);
using MetaObjectFn = const void *(*)(const void *);

void *resolve_qt5(const char *symbol) {
  void *fn = dlvsym(RTLD_NEXT, symbol, "Qt_5");
  if (!fn) fn = dlsym(RTLD_NEXT, symbol);
  return fn;
}

bool is_prome_main_window_layout(void *layout) {
  if (!layout) return false;
  static auto parent_widget = reinterpret_cast<ParentWidgetFn>(
      resolve_qt5("_ZNK6kso_qt7QLayout12parentWidgetEv"));
  static auto window_of = reinterpret_cast<WindowFn>(
      resolve_qt5("_ZNK6kso_qt7QWidget6windowEv"));
  static auto central_widget = reinterpret_cast<CentralWidgetFn>(
      resolve_qt5("_ZNK6kso_qt11QMainWindow13centralWidgetEv"));
  static auto class_name = reinterpret_cast<ClassNameFn>(
      resolve_qt5("_ZNK6kso_qt11QMetaObject9classNameEv"));
  if (!parent_widget || !window_of || !central_widget || !class_name) return false;

  void *parent = parent_widget(layout);
  if (!parent) return false;

  void *win = window_of(parent);
  if (!win) return false;

  // Qt5 QObject vtable slot 0 is always `virtual const QMetaObject *metaObject() const`.
  auto **vtable = *reinterpret_cast<void ***>(win);
  if (!vtable || !vtable[0]) return false;
  auto meta_object = reinterpret_cast<MetaObjectFn>(vtable[0])(win);
  if (!meta_object) return false;

  const char *name = class_name(meta_object);
  if (!name || std::strcmp(name, "KPromeMainWindow") != 0) return false;

  // KPromeMainWindow sets the outer frame margin on its centralWidget()'s root layout.
  return parent == win || central_widget(win) == parent;
}

}  // namespace

extern "C" {

void _ZN6kso_qt7QLayout18setContentsMarginsERKNS_8QMarginsE(void *layout, const QMargins &margins) {
  static auto orig = reinterpret_cast<SetMarginsRefFn>(
      resolve_qt5("_ZN6kso_qt7QLayout18setContentsMarginsERKNS_8QMarginsE"));
  if (!orig) return;
  if (is_prome_main_window_layout(layout)) {
    static constexpr QMargins zero{0, 0, 0, 0};
    orig(layout, zero);
    return;
  }
  orig(layout, margins);
}

void _ZN6kso_qt7QLayout18setContentsMarginsEiiii(void *layout, int left, int top, int right, int bottom) {
  static auto orig = reinterpret_cast<SetMargins4Fn>(
      resolve_qt5("_ZN6kso_qt7QLayout18setContentsMarginsEiiii"));
  if (!orig) return;
  if (is_prome_main_window_layout(layout)) {
    orig(layout, 0, 0, 0, 0);
    return;
  }
  orig(layout, left, top, right, bottom);
}

}  // extern "C"
