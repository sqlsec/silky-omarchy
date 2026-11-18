#!/usr/bin/env python3
"""Wallpaper portal backend for the Omarchy desktop."""

import os
import sys
from pathlib import Path

from gi import require_version

require_version("Gtk", "4.0")
require_version("Gdk", "4.0")
require_version("GdkWayland", "4.0")
require_version("GdkPixbuf", "2.0")
from gi.repository import GdkPixbuf, Gio, GLib


FRONTEND = "org.freedesktop.portal.Desktop"
SERVICE = "org.freedesktop.impl.portal.desktop.silky_wallpaper"
WALLPAPER = "org.freedesktop.impl.portal.Wallpaper"
PORTAL_PATH = "/org/freedesktop/portal/desktop"
WALLPAPER_XML = Path("/usr/share/dbus-1/interfaces") / f"{WALLPAPER}.xml"
REQUEST = Gio.DBusNodeInfo.new_for_xml(
    '<node><interface name="org.freedesktop.impl.portal.Request">'
    '<method name="Close"/></interface></node>'
)


class WallpaperPortal:
    def __init__(self):
        self.loop = GLib.MainLoop()
        self.protocol = Gio.DBusNodeInfo.new_for_xml(WALLPAPER_XML.read_text())

    def export(self, connection, _name):
        connection.register_object(
            PORTAL_PATH, self.protocol.lookup_interface(WALLPAPER), self.set_wallpaper
        )

    def set_wallpaper(self, connection, sender, _path, _iface, _method, args, invocation):
        try:
            owner, = connection.call_sync(
                "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
                "GetNameOwner", GLib.Variant("(s)", (FRONTEND,)),
                GLib.VariantType.new("(s)"), Gio.DBusCallFlags.NONE, 1000, None,
            ).unpack()
        except GLib.Error:
            owner = None
        if sender != owner:
            invocation.return_dbus_error(
                "org.freedesktop.DBus.Error.AccessDenied", "Portal frontend required"
            )
            return

        handle, _app_id, parent, uri, options = args.unpack()
        if options.get("set-on", "background") != "background":
            self.reply(invocation, 2)
            return
        path = Gio.File.new_for_uri(uri).get_path()
        if not path or not os.path.isfile(path):
            self.reply(invocation, 2)
            return
        try:
            preview = GdkPixbuf.Pixbuf.new_from_file_at_scale(path, 640, 360, True)
        except GLib.Error as error:
            print(error, file=sys.stderr)
            self.reply(invocation, 2)
            return

        if options.get("show-preview", False):
            self.confirm(connection, sender, handle, parent, path, preview, invocation)
        else:
            self.apply(path, invocation)

    def confirm(self, connection, sender, handle, parent, path, preview, invocation):
        # Loading GTK may query the Settings portal, so defer it until the frontend is running.
        from gi.repository import Gdk, GdkWayland, Gtk

        if not Gtk.init_check():
            self.reply(invocation, 2)
            return
        dialog = Gtk.Window(title="设置桌面背景", modal=True, resizable=False)
        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        for side in ("top", "bottom", "start", "end"):
            content.set_property(f"margin-{side}", 16)
        pixel_format = Gdk.MemoryFormat.R8G8B8A8 if preview.get_has_alpha() else Gdk.MemoryFormat.R8G8B8
        texture = Gdk.MemoryTexture.new(
            preview.get_width(), preview.get_height(), pixel_format,
            preview.read_pixel_bytes(), preview.get_rowstride(),
        )
        picture = Gtk.Picture.new_for_paintable(texture)
        content.append(picture)
        label = Gtk.Label(label=os.path.basename(path), wrap=True, selectable=True)
        label.set_max_width_chars(60)
        content.append(label)
        buttons = Gtk.Box(spacing=8, halign=Gtk.Align.END)
        cancel = Gtk.Button(label="取消")
        accept = Gtk.Button(label="设为桌面背景")
        accept.add_css_class("suggested-action")
        buttons.append(cancel)
        buttons.append(accept)
        content.append(buttons)
        dialog.set_child(content)

        def finish(accepted=False):
            connection.unregister_object(request_id)
            dialog.destroy()
            if accepted:
                self.apply(path, invocation)
            else:
                self.reply(invocation, 1)

        def close_window(_dialog):
            finish()
            return True

        def close_request(_conn, caller, _path, _iface, _method, _args, close_invocation):
            if caller != sender:
                close_invocation.return_dbus_error(
                    "org.freedesktop.DBus.Error.AccessDenied", "Portal frontend required"
                )
                return
            close_invocation.return_value(None)
            finish()

        request_id = connection.register_object(handle, REQUEST.interfaces[0], close_request)
        dialog.connect("close-request", close_window)
        cancel.connect("clicked", lambda _button: finish())
        accept.connect("clicked", lambda _button: finish(accepted=True))
        escape = Gtk.ShortcutController()
        escape.add_shortcut(Gtk.Shortcut.new(
            Gtk.KeyvalTrigger.new(Gdk.KEY_Escape, 0),
            Gtk.CallbackAction.new(lambda *_: close_window(dialog)),
        ))
        dialog.add_controller(escape)
        dialog.set_focus(cancel)
        dialog.realize()
        surface = dialog.get_surface()
        if parent.startswith("wayland:") and isinstance(surface, GdkWayland.WaylandToplevel):
            surface.set_transient_for_exported(parent.removeprefix("wayland:"))
        dialog.present()

    def apply(self, path, invocation):
        def completed(process, result):
            try:
                process.wait_check_finish(result)
            except GLib.Error as error:
                print(error, file=sys.stderr)
                self.reply(invocation, 2)
            else:
                self.reply(invocation, 0)

        try:
            process = Gio.Subprocess.new(
                ["omarchy", "theme", "bg", "set", path], Gio.SubprocessFlags.NONE
            )
        except GLib.Error as error:
            print(error, file=sys.stderr)
            self.reply(invocation, 2)
        else:
            process.wait_check_async(None, completed)

    @staticmethod
    def reply(invocation, response):
        invocation.return_value(GLib.Variant("(u)", (response,)))

    def run(self):
        Gio.bus_own_name(
            Gio.BusType.SESSION, SERVICE, Gio.BusNameOwnerFlags.NONE,
            self.export, None, lambda *_: self.loop.quit(),
        )
        self.loop.run()


if __name__ == "__main__":
    WallpaperPortal().run()
