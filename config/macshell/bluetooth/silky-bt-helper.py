#!/usr/bin/python3
"""Silky Omarchy Bluetooth helper for MacShell.

MacShell's Bluetooth UI reads adapter and device state through Quickshell.Bluetooth (BlueZ over D-Bus). The actions
that can fail or need the user (pair, connect, disconnect, forget) go through this helper instead, because it:

* gets BlueZ's real D-Bus error names (AuthenticationFailed, ConnectionAttemptFailed, ...) for the per-device message;
* registers its own org.bluez.Agent1 with the KeyboardDisplay capability. BlueZ asks the agent of the client that
  called Device1.Pair, so PIN / passkey / confirmation requests for pairings started from Settings come here, while
  Omarchy's default bt-agent (NoInputNoOutput) keeps handling everything else. The helper never asks to be the
  default agent.

Protocol: JSON lines. stdin takes commands, stdout carries events.

  {"op": "connect", "mac": "AA:BB:..."}          pair (if needed) + trust + connect
  {"op": "disconnect" | "forget" | "cancel", "mac": ...}
  {"op": "reply", "id": 3, "ok": true, "value": "0000"}   answer to a request event

  {"ev": "done", "op": ..., "mac": ...}
  {"ev": "error", "op": ..., "mac": ..., "code": "AuthenticationFailed", "message": "..."}
  {"ev": "request", "id": 3, "kind": "pin" | "passkey" | "confirm" | "display-pin" | "display-passkey",
   "mac": ..., "name": ..., "passkey": "123456", "entered": 0}
  {"ev": "cancel"}                               BlueZ withdrew the open request

The helper quits on stdin EOF, or after IDLE_SECONDS without work; MacShell starts it again on demand.
Needs: /usr/bin/python3 with PyGObject (python-gobject), BlueZ 5.x.
"""
import json
import sys

from gi.repository import Gio, GLib

BLUEZ = "org.bluez"
AGENT_PATH = "/org/silkyomarchy/bluetooth/agent"
IDLE_SECONDS = 120
PAIR_TIMEOUT_MS = 90_000
CONNECT_TIMEOUT_MS = 40_000

AGENT_XML = """
<node>
  <interface name="org.bluez.Agent1">
    <method name="Release"/>
    <method name="RequestPinCode"><arg type="o" direction="in"/><arg type="s" direction="out"/></method>
    <method name="DisplayPinCode"><arg type="o" direction="in"/><arg type="s" direction="in"/></method>
    <method name="RequestPasskey"><arg type="o" direction="in"/><arg type="u" direction="out"/></method>
    <method name="DisplayPasskey">
      <arg type="o" direction="in"/><arg type="u" direction="in"/><arg type="q" direction="in"/>
    </method>
    <method name="RequestConfirmation"><arg type="o" direction="in"/><arg type="u" direction="in"/></method>
    <method name="RequestAuthorization"><arg type="o" direction="in"/></method>
    <method name="AuthorizeService"><arg type="o" direction="in"/><arg type="s" direction="in"/></method>
    <method name="Cancel"/>
  </interface>
</node>
"""

bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
loop = GLib.MainLoop()
pending = {}          # request id -> (invocation, kind)
next_id = 1
active_ops = 0
idle_source = 0


def emit(**event):
    sys.stdout.write(json.dumps(event, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def touch_idle():
    global idle_source
    if idle_source:
        GLib.source_remove(idle_source)
    idle_source = GLib.timeout_add_seconds(IDLE_SECONDS, on_idle)


def on_idle():
    global idle_source
    idle_source = 0
    if active_ops == 0 and not pending:
        loop.quit()
        return False
    touch_idle()
    return False


def error_parts(err):
    code = Gio.DBusError.get_remote_error(err) or ""
    if code.startswith("org.bluez.Error."):
        code = code[len("org.bluez.Error."):]
    elif code.startswith("org.freedesktop.DBus.Error."):
        code = code[len("org.freedesktop.DBus.Error."):]
    Gio.DBusError.strip_remote_error(err)
    return code or "Failed", err.message or ""


def managed_objects():
    reply = bus.call_sync(BLUEZ, "/", "org.freedesktop.DBus.ObjectManager", "GetManagedObjects",
                          None, GLib.VariantType("(a{oa{sa{sv}}})"), Gio.DBusCallFlags.NONE, 5000, None)
    return reply.unpack()[0]


def device_info(path):
    try:
        props = managed_objects().get(path, {}).get("org.bluez.Device1", {})
    except GLib.Error:
        props = {}
    return props.get("Address", ""), props.get("Alias", "") or props.get("Name", "")


def find_device(mac):
    mac = (mac or "").upper()
    for path, ifaces in managed_objects().items():
        dev = ifaces.get("org.bluez.Device1")
        if dev and dev.get("Address", "").upper() == mac:
            return path, dev
    return None, None


def call(path, iface, method, params, timeout, done):
    bus.call(BLUEZ, path, iface, method, params, None, Gio.DBusCallFlags.NONE, timeout, None,
             lambda conn, res: finish(conn, res, done))


def finish(conn, res, done):
    try:
        conn.call_finish(res)
    except GLib.Error as err:
        done(err)
        return
    done(None)


def run_op(op, mac):
    global active_ops
    try:
        path, dev = find_device(mac)
    except GLib.Error as err:
        code, message = error_parts(err)
        emit(ev="error", op=op, mac=mac, code=code, message=message)
        return
    if not path:
        emit(ev="error", op=op, mac=mac, code="DoesNotExist", message="Device not found")
        return

    active_ops += 1
    touch_idle()

    def end(err):
        global active_ops
        active_ops -= 1
        touch_idle()
        if err is None:
            emit(ev="done", op=op, mac=mac)
        else:
            code, message = error_parts(err)
            emit(ev="error", op=op, mac=mac, code=code, message=message)

    if op == "disconnect":
        call(path, "org.bluez.Device1", "Disconnect", None, 15_000, end)
    elif op == "cancel":
        call(path, "org.bluez.Device1", "CancelPairing", None, 5000, end)
    elif op == "forget":
        call(dev.get("Adapter", "/org/bluez/hci0"), "org.bluez.Adapter1", "RemoveDevice",
             GLib.Variant("(o)", (path,)), 10_000, end)
    elif op == "connect":
        def connect(_err=None):
            call(path, "org.bluez.Device1", "Connect", None, CONNECT_TIMEOUT_MS, end)

        def trust(err):
            if err is not None:
                end(err)
                return
            # Trusted devices reconnect on their own and skip the service authorization prompt.
            call(path, "org.freedesktop.DBus.Properties", "Set",
                 GLib.Variant("(ssv)", ("org.bluez.Device1", "Trusted", GLib.Variant("b", True))), 5000, connect)

        if dev.get("Paired") or dev.get("Bonded"):
            connect()
        else:
            call(path, "org.bluez.Device1", "Pair", None, PAIR_TIMEOUT_MS, trust)
    else:
        active_ops -= 1
        emit(ev="error", op=op, mac=mac, code="InvalidArguments", message="Unknown operation")


def ask(invocation, kind, device_path, passkey="", entered=0, wait=True):
    global next_id
    mac, name = device_info(device_path)
    request_id = next_id
    next_id += 1
    if wait:
        pending[request_id] = (invocation, kind)
    emit(ev="request", id=request_id, kind=kind, mac=mac, name=name, passkey=passkey, entered=entered)
    touch_idle()


def on_agent_call(_conn, _sender, _path, _iface, method, params, invocation):
    args = params.unpack()
    if method == "RequestPinCode":
        ask(invocation, "pin", args[0])
    elif method == "RequestPasskey":
        ask(invocation, "passkey", args[0])
    elif method == "RequestConfirmation":
        ask(invocation, "confirm", args[0], passkey="%06d" % args[1])
    elif method == "DisplayPinCode":
        ask(invocation, "display-pin", args[0], passkey=args[1], wait=False)
        invocation.return_value(None)
    elif method == "DisplayPasskey":
        ask(invocation, "display-passkey", args[0], passkey="%06d" % args[1], entered=args[2], wait=False)
        invocation.return_value(None)
    elif method == "Cancel":
        pending.clear()
        emit(ev="cancel")
        invocation.return_value(None)
    else:
        # Release, RequestAuthorization and AuthorizeService only reach this agent for pairings the user started
        # from Settings, so they are accepted.
        invocation.return_value(None)


def reply(request_id, ok, value):
    entry = pending.pop(request_id, None)
    if entry is None:
        return
    invocation, kind = entry
    if not ok:
        invocation.return_dbus_error("org.bluez.Error.Canceled", "Canceled by the user")
    elif kind == "pin":
        invocation.return_value(GLib.Variant("(s)", (str(value)[:16],)))
    elif kind == "passkey":
        try:
            number = int(str(value).strip())
        except ValueError:
            invocation.return_dbus_error("org.bluez.Error.Rejected", "Invalid passkey")
            return
        invocation.return_value(GLib.Variant("(u)", (max(0, min(number, 999999)),)))
    else:
        invocation.return_value(None)


def on_stdin(channel, _condition):
    line = channel.readline()
    if not line:       # MacShell closed the pipe (shell reload or exit)
        loop.quit()
        return False
    try:
        cmd = json.loads(line)
    except ValueError:
        return True
    op = cmd.get("op", "")
    if op == "reply":
        reply(int(cmd.get("id", 0)), bool(cmd.get("ok")), cmd.get("value", ""))
    elif op in ("connect", "disconnect", "forget", "cancel"):
        run_op(op, cmd.get("mac", ""))
    touch_idle()
    return True


def main():
    node = Gio.DBusNodeInfo.new_for_xml(AGENT_XML)
    registration = bus.register_object(AGENT_PATH, node.interfaces[0], on_agent_call, None, None)
    agent_registered = False
    try:
        bus.call_sync(BLUEZ, "/org/bluez", "org.bluez.AgentManager1", "RegisterAgent",
                      GLib.Variant("(os)", (AGENT_PATH, "KeyboardDisplay")), None, Gio.DBusCallFlags.NONE, 5000, None)
        agent_registered = True
    except GLib.Error as err:
        code, message = error_parts(err)
        emit(ev="agent-error", code=code, message=message)

    channel = GLib.IOChannel.unix_new(sys.stdin.fileno())
    GLib.io_add_watch(channel, GLib.PRIORITY_DEFAULT,
                      GLib.IOCondition.IN | GLib.IOCondition.HUP | GLib.IOCondition.ERR, on_stdin)
    touch_idle()
    emit(ev="ready")
    try:
        loop.run()
    except KeyboardInterrupt:
        pass
    finally:
        for invocation, _kind in pending.values():
            invocation.return_dbus_error("org.bluez.Error.Canceled", "Helper exited")
        if agent_registered:
            try:
                bus.call_sync(BLUEZ, "/org/bluez", "org.bluez.AgentManager1", "UnregisterAgent",
                              GLib.Variant("(o)", (AGENT_PATH,)), None, Gio.DBusCallFlags.NONE, 2000, None)
            except GLib.Error:
                pass
        bus.unregister_object(registration)


if __name__ == "__main__":
    main()
