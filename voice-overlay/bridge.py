#!/usr/bin/env python3
"""WowType voice overlay bridge.

WowType (fcitx5) looks for a program that owns io.github.gloridust.WowType.VoiceOverlay on the session bus.
When one does, it stops drawing its plain text hint in the candidate box and instead broadcasts a State signal
every 50 ms while you dictate: (state, label, level, x, y, w, h, relative, scale). The overlay has to answer
each shown state with an Ack, otherwise WowType falls back to the text hint for that utterance.

This bridge owns the name, turns every State into one JSON line on stdout for the Quickshell overlay, and acks.
"""
import json
import sys

from gi.repository import Gio, GLib

BUS_NAME = "io.github.gloridust.WowType.VoiceOverlay"
OBJECT_PATH = "/io/github/gloridust/WowType"
INTERFACE = "io.github.gloridust.WowType.Voice1"
STATE_HIDE = 0

loop = GLib.MainLoop()


def emit(obj):
    try:
        sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
        sys.stdout.flush()
        return True
    except (BrokenPipeError, ValueError):
        loop.quit()
        return False


def on_state(conn, sender, _path, _iface, _signal, params):
    args = params.unpack()
    state = int(args[0])
    label = str(args[1]) if len(args) > 1 else ""
    level = float(args[2]) if len(args) > 2 else 0.0
    if not emit({"s": state, "t": label, "l": level}):
        return
    if state != STATE_HIDE:
        try:
            conn.emit_signal(sender, OBJECT_PATH, INTERFACE, "Ack", GLib.Variant("(u)", (state,)))
        except GLib.Error as error:
            print(f"ack failed: {error.message}", file=sys.stderr)


def on_lost(_conn, _name):
    print(f"{BUS_NAME} is owned by another overlay", file=sys.stderr)
    loop.quit()


conn = Gio.bus_get_sync(Gio.BusType.SESSION, None)
conn.signal_subscribe(None, INTERFACE, "State", OBJECT_PATH, None, Gio.DBusSignalFlags.NONE, on_state)
Gio.bus_own_name_on_connection(conn, BUS_NAME, Gio.BusNameOwnerFlags.NONE, None, on_lost)
emit({"ready": True})
loop.run()
sys.exit(1)
