#!/usr/bin/env python3
"""Bridge WowType and vinput recording events to the Silky Voice overlay.

WowType (fcitx5) looks for a program that owns io.github.gloridust.WowType.VoiceOverlay on the session bus.
When one does, it stops drawing its plain text hint in the candidate box and instead broadcasts a State signal
every 50 ms while you dictate: (state, label, level, x, y, w, h, relative, scale). The overlay has to answer
each shown state with an Ack, otherwise WowType falls back to the text hint for that utterance.

The vinput subscription uses its session bus events and never opens a microphone stream.
"""
import json
import sys

from gi.repository import Gio, GLib

BUS_NAME = "io.github.gloridust.WowType.VoiceOverlay"
OBJECT_PATH = "/io/github/gloridust/WowType"
INTERFACE = "io.github.gloridust.WowType.Voice1"
STATE_HIDE = 0
VINPUT_NAME = "org.fcitx.Vinput"
VINPUT_PATH = "/org/fcitx/Vinput"
VINPUT_INTERFACE = "org.fcitx.Vinput.Service"
VINPUT_PHASES = {"idle": 0, "recording": 1, "inferring": 2, "postprocessing": 2, "error": 4}
vinput_phase = STATE_HIDE
vinput_level = 0
vinput_has_meter = False
vinput_heartbeat = 0

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
    if vinput_phase == STATE_HIDE and not emit({"s": state, "t": label[:256], "l": level}):
        return
    if state != STATE_HIDE:
        try:
            conn.emit_signal(sender, OBJECT_PATH, INTERFACE, "Ack", GLib.Variant("(u)", (state,)))
        except GLib.Error as error:
            print(f"ack failed: {error.message}", file=sys.stderr)


def publish_vinput():
    active = vinput_phase in (1, 2)
    emit({"s": vinput_phase, "l": vinput_level if vinput_phase == 1 else 0,
          "pulse": vinput_phase == 1 and not vinput_has_meter})
    return active


def set_vinput_phase(phase):
    global vinput_phase, vinput_level, vinput_heartbeat
    if phase == vinput_phase:
        return
    vinput_phase = phase
    vinput_level = 0
    publish_vinput()
    if phase in (1, 2):
        if not vinput_heartbeat:
            vinput_heartbeat = GLib.timeout_add(400, publish_vinput)
    elif vinput_heartbeat:
        GLib.source_remove(vinput_heartbeat)
        vinput_heartbeat = 0


def on_vinput_signal(_conn, _sender, _path, _iface, member, params):
    global vinput_has_meter, vinput_level
    if member == "StatusChanged":
        phase = VINPUT_PHASES.get(params.unpack()[0])
        if phase is not None:
            set_vinput_phase(phase)
    elif member == "RecognitionResult" and vinput_phase in (1, 2):
        set_vinput_phase(3)
    elif member == "AudioLevel" and vinput_phase == 1:
        vinput_has_meter = True
        vinput_level = min(100, params.unpack()[0])
        publish_vinput()


def on_vinput_vanished(_conn, _name):
    global vinput_has_meter
    vinput_has_meter = False
    if vinput_phase != STATE_HIDE:
        set_vinput_phase(STATE_HIDE)


def on_lost(_conn, _name):
    print(f"{BUS_NAME} is owned by another overlay", file=sys.stderr)
    loop.quit()


conn = Gio.bus_get_sync(Gio.BusType.SESSION, None)
conn.signal_subscribe(None, INTERFACE, "State", OBJECT_PATH, None, Gio.DBusSignalFlags.NONE, on_state)
Gio.bus_own_name_on_connection(conn, BUS_NAME, Gio.BusNameOwnerFlags.NONE, None, on_lost)
conn.signal_subscribe(VINPUT_NAME, VINPUT_INTERFACE, None, VINPUT_PATH, None,
                      Gio.DBusSignalFlags.NONE, on_vinput_signal)
Gio.bus_watch_name_on_connection(conn, VINPUT_NAME, Gio.BusNameWatcherFlags.NONE, None, on_vinput_vanished)
emit({"ready": True})
loop.run()
sys.exit(1)
