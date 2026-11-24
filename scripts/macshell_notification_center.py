#!/usr/bin/env python3
"""Install and maintain Silky fixes for MacShell's Notification Center."""

import argparse
import os
import re
import shutil
import stat
import subprocess
import sys
from pathlib import Path
from tempfile import NamedTemporaryFile

BEGIN = "    // Silky WeChat notification activation\n"
END = "    // End Silky WeChat notification activation\n"
CALL = "        if (root.silkyActivateWeChat(id)) return true;\n"
ANCHOR = re.compile(r"^    function notifActivate\(id(?:, openApp)?\) \{\n", re.M)
HELPERS = r'''    function silkyActivateWeChat(id) {
        const index = root.notifIndex(notifHist, id);
        if (index < 0) return false;
        const record = notifHist.get(index);
        const isWeChat = value => /^(wechat|微信)(\.desktop)?$/i.test(String(value || "").trim());
        if (!isWeChat(record.app) && !isWeChat(record.desktopEntry)) return false;

        // Keep the application's action so it can select the conversation.
        const notification = root.notifRefs[id];
        let invoked = false;
        if (notification) {
            try {
                const actions = notification.actions;
                for (let i = 0; actions && i < actions.length; i++) {
                    const action = actions[i];
                    if (!action || action.identifier !== "default") continue;
                    action.invoke();
                    invoked = true;
                    break;
                }
            } catch (e) {}
        }
        root.notifToastDismiss(id);

        // Give the default action a moment to show the window before using the tray.
        silkyWeChatFocus.waitTicks = invoked ? 3 : 0;
        silkyWeChatFocus.opened = false;
        silkyWeChatFocus.ticks = 0;
        Hyprland.refreshToplevels();
        silkyWeChatFocus.restart();
        return true;
    }

    Timer {
        id: silkyWeChatFocus
        interval: 100
        repeat: true
        property int waitTicks: 0
        property int ticks: 0
        property bool opened: false
        onTriggered: {
            const main = Hyprland.toplevels.values.find(window => {
                const data = window.lastIpcObject;
                return data && (data.class === "wechat" || data.initialClass === "wechat")
                    && data.mapped && !data.hidden
                    && /^(微信|WeChat)$/i.test(data.initialTitle || data.title || window.title);
            });
            if (main && /^(0x)?[0-9a-f]+$/i.test(main.address)) {
                stop();
                const dock = root.hub && root.hub.dock;
                if (main.workspace && main.workspace.name === "special:minimized" && dock?.restoreAddress) {
                    dock.restoreAddress(main.address);
                    return;
                }
                const address = "0x" + main.address.replace(/^0x/i, "");
                Hyprland.dispatch('hl.dsp.focus({ window = "address:' + address + '" })');
                Hyprland.dispatch('hl.dsp.window.alter_zorder({ mode = "top", window = "address:' + address + '" })');
                return;
            }
            if (++ticks <= waitTicks) return;
            if (!opened) {
                opened = true;
                const tray = SystemTray.items.values.find(item => item.id === "wechat" && !item.onlyMenu);
                if (tray) tray.activate();
                else {
                    const entry = DesktopEntries.byId("wechat");
                    if (entry) entry.execute();
                    else stop();
                }
            }
            // A cold start can take several seconds. Never toggle the tray twice.
            if (ticks >= 80) stop();
        }
    }
'''


def remove_activation(text):
    if BEGIN not in text:
        return text
    if text.count(BEGIN) != 1 or text.count(END) != 1 or text.count(CALL) != 1:
        raise ValueError("Incomplete WeChat activation block in MacBar.qml")
    before, remainder = text.split(BEGIN)
    _, after = remainder.split(END)
    return (before + after).replace(CALL, "", 1)


def integrate_wechat(text):
    text = remove_activation(text)
    matches = list(ANCHOR.finditer(text))
    if len(matches) != 1 or any(part not in text for part in (
            "function notifIndex(", "function notifToastRemove(", "import Quickshell.Hyprland",
            "import Quickshell.Services.SystemTray", "property var hub:")):
        raise ValueError("MacBar notification activation code changed")
    match = matches[0]
    return text[:match.start()] + BEGIN + HELPERS + END + match[0] + CALL + text[match.end():]


NOTIFICATION_REPLACEMENTS = (
    (
        "    Timer { id: lockNotifSave; interval: 300; onTriggered: root.lockNotifWrite() }",
        "    // Publish the initial state even if no new notifications have arrived.\n"
        "    Timer { id: lockNotifSave; interval: 300; running: true; onTriggered: root.lockNotifWrite() }",
    ),
    (
        "    property bool notifOpen: false",
        "    property Item silkyNotifOwner: null\n"
        "    readonly property bool notifOpen: silkyNotifOwner !== null",
    ),
    (
        "    onNotifOpenChanged: if (!notifOpen) notifMergeFrom = ({})",
        "    onNotifOpenChanged: {\n"
        "        if (notifOpen) {\n"
        "            notifUnread = 0;\n"
        "            notifToasts.clear();\n"
        "        }\n"
        "        notifMergeFrom = ({});\n"
        "    }",
    ),
    (
        "readonly property bool toastsShown: toastScreen && notifToasts.count > 0",
        "readonly property bool toastsShown: toastScreen && !root.notifOpen && notifToasts.count > 0",
    ),
    (
        "onClicked: { root.notifActivate(toast.nid); toast.dismiss(); }",
        "onClicked: root.notifActivate(toast.nid)",
    ),
    (
        '                    root.notifOpen = (pop === "notif");\n'
        '                    if (root.notifOpen) root.notifUnread = 0;',
        '                    if (pop === "notif") {\n'
        '                        const previous = root.silkyNotifOwner;\n'
        '                        root.silkyNotifOwner = ui;\n'
        '                        if (previous && previous !== ui) previous.pop = "";\n'
        '                    } else if (root.silkyNotifOwner === ui) {\n'
        '                        root.silkyNotifOwner = null;\n'
        '                    }',
    ),
    (
        "        Item {\n"
        "            x: 14; y: 15; width: 44; height: 44\n"
        "            Rectangle {\n"
        "                anchors.fill: parent; radius: 10\n"
        "                visible: nimg.status !== Image.Ready",
        "        Item {\n"
        "            x: 14; anchors.verticalCenter: parent.verticalCenter; width: 44; height: 44\n"
        "            Rectangle {\n"
        "                anchors.fill: parent; radius: 10\n"
        "                visible: nimg.status !== Image.Ready",
    ),
)


TOAST_MOTION_REPLACEMENTS = (
    (
        '        property bool showTime: false\n'
        '        signal closeClicked()',
        '        property bool showTime: false\n'
        '        property bool animateTextUpdates: true\n'
        '        signal closeClicked()',
    ),
    (
        '                target: nb\n'
        '                function onSummaryChanged() { refocusAnim.restart(); }\n'
        '                function onBodyChanged() { refocusAnim.restart(); }',
        '                target: nb\n'
        '                enabled: nb.animateTextUpdates\n'
        '                function onSummaryChanged() { refocusAnim.restart(); }\n'
        '                function onBodyChanged() { refocusAnim.restart(); }',
    ),
    (
        "                // notifications arriving with no panel open: measure what's behind the banners\n"
        '                onToastsShownChanged: if (toastsShown && pop === "") root.measureTone(win.modelData.x + ui.width - 374, win.modelData.y + root.barH + 8, 364, 90)',
        '                // Banners use the appearance palette. No screen readback on arrival.',
    ),
    (
        '                    y: popBottom > 0 ? popBottom + 12 : root.barH + 8\n'
        '                    Behavior on y { NumberAnimation { duration: 770; easing.type: Easing.OutQuint } }',
        '                    readonly property int enterDuration: root.reduceMotion ? 0 : 350\n'
        '                    readonly property int exitDuration: root.reduceMotion ? 0 : 230\n'
        '                    readonly property int cardGap: 10\n'
        '                    y: popBottom > 0 ? popBottom + 12 : root.barH + 8\n'
        '                    Behavior on y { NumberAnimation { duration: toastArea.enterDuration; easing.type: Easing.OutCubic } }',
    ),
    (
        '                        id: toastCol\n'
        '                        width: parent.width\n'
        '                        spacing: 10\n'
        '                        // the rest of the stack glides to its new place instead of jumping\n'
        '                        move: Transition { NumberAnimation { properties: "y"; duration: 770; easing.type: Easing.OutQuint } }',
        '                        id: toastCol\n'
        '                        width: parent.width\n'
        '                        // Each slot animates its own height and gap, moving the rest of the stack with it.',
    ),
    (
        '                                Behavior on t { NumberAnimation { duration: 770; easing.type: toast.leaving ? Easing.OutCubic : Easing.OutQuint } }\n'
        '                                readonly property real tc: Math.max(0, Math.min(1, t))\n'
        '                                width: toastCol.width\n'
        '                                // the slot grows with the card, so the stack below makes room smoothly\n'
        '                                height: tbody.height * (0.35 + 0.65 * tc) + (toastCol.spacing * (tc - 1))\n'
        '                                opacity: Math.min(1, tc * 2.2)',
        '                                Behavior on t {\n'
        '                                    NumberAnimation {\n'
        '                                        duration: toast.leaving ? toastArea.exitDuration : toastArea.enterDuration\n'
        '                                        easing.type: Easing.OutCubic\n'
        '                                    }\n'
        '                                }\n'
        '                                readonly property real tc: Math.max(0, Math.min(1, t))\n'
        '                                width: toastCol.width\n'
        '                                height: (tbody.height + toastArea.cardGap) * tc\n'
        '                                opacity: tc * (2 - tc)',
    ),
    (
        '                                Timer { interval: 790; id: goneTimer; onTriggered: root.notifToastRemove(toast.nid) }',
        '                                Timer {\n'
        '                                    id: goneTimer\n'
        '                                    interval: toastArea.exitDuration + 20\n'
        '                                    running: toast.leaving\n'
        '                                    onTriggered: root.notifToastRemove(toast.nid)\n'
        '                                }',
    ),
    (
        '                                    width: toast.width * (0.42 + 0.58 * toast.tc)\n'
        '                                    height: Math.max(36, toast.height)',
        '                                    width: toast.width * (0.42 + 0.58 * toast.tc)\n'
        '                                    height: Math.min(toast.height, tbody.height * (0.35 + 0.65 * toast.tc))',
    ),
    (
        '                                // the slab reveals the content (clip), and inside it the content comes into focus. The blur sits on an\n'
        '                                // inner layer with room to spread (auto padding), so it is soft all round instead of a cut-off smear,\n'
        '                                // and it eases out gradually as the card settles.\n'
        '                                Item {\n'
        '                                    id: tcontent\n'
        '                                    x: tslab.x; width: tslab.width; height: toast.height\n'
        '                                    clip: toast.tc < 0.999\n'
        '                                    opacity: Math.pow(toast.tc, 1.3)\n'
        '                                Item {\n'
        '                                    width: toast.width; height: toast.height\n'
        '                                    x: tslab.width - width\n'
        '                                    layer.enabled: toast.tc < 0.999\n'
        '                                    layer.smooth: true\n'
        '                                    layer.effect: MultiEffect { blurEnabled: true; blurMax: 56; blur: Math.pow(1 - toast.tc, 0.8); autoPaddingEnabled: true }\n'
        '                                NotifBody {\n'
        '                                    id: tbody\n'
        '                                    t: pal\n'
        '                                    width: toast.width\n'
        '                                    app: toast.app; summary: toast.summary; body: toast.body; icon: toast.icon\n'
        '                                    urgency: toast.urgency; stamp: toast.time; nowMs: clock.date.getTime()\n'
        '                                    showClose: thov.hovered\n'
        '                                    onCloseClicked: toast.dismiss()\n'
        '                                }\n'
        '                                }\n'
        '                                }',
        '                                Item {\n'
        '                                    x: tslab.x\n'
        '                                    width: tslab.width\n'
        '                                    height: tslab.height\n'
        '                                    clip: true\n'
        '\n'
        '                                    NotifBody {\n'
        '                                        id: tbody\n'
        '                                        x: parent.width - width\n'
        '                                        width: toast.width\n'
        '                                        t: pal\n'
        '                                        app: toast.app; summary: toast.summary; body: toast.body; icon: toast.icon\n'
        '                                        urgency: toast.urgency; stamp: toast.time; nowMs: clock.date.getTime()\n'
        '                                        animateTextUpdates: false\n'
        '                                        showClose: thov.hovered\n'
        '                                        onCloseClicked: toast.dismiss()\n'
        '                                    }\n'
        '                                }',
    ),
    (
        '            notifToasts.insert(0, rec);',
        '            notifToasts.insert(0, Object.assign({ leaving: false }, rec));',
    ),
    (
        '        try { n.closed.connect(function () { root.notifToastRemove(id); }); } catch (e) {}',
        '        try { n.closed.connect(function () { root.notifToastDismiss(id); }); } catch (e) {}',
    ),
    (
        '    function notifToastRemove(id) {',
        '    function notifToastDismiss(id) {\n'
        '        var i = notifIndex(notifToasts, id);\n'
        '        if (i >= 0) notifToasts.setProperty(i, "leaving", true);\n'
        '    }\n'
        '    function notifToastRemove(id) {',
    ),
    (
        '    function notifDelete(id) {\n'
        '        notifToastRemove(id);',
        '    function notifDelete(id) {\n'
        '        notifToastDismiss(id);',
    ),
    (
        '        notifToastRemove(id);\n'
        '        return activated;',
        '        notifToastDismiss(id);\n'
        '        return activated;',
    ),
    (
        '                                property bool shown: false\n'
        '                                property bool leaving: false',
        '                                required property bool leaving\n'
        '                                property bool shown: false',
    ),
    (
        '                                function dismiss() { if (leaving) return; leaving = true; goneTimer.restart(); }',
        '                                function dismiss() { root.notifToastDismiss(nid); }',
    ),
    (
        '                                        root.notifMergeFrom = m;\n'
        '                                        toast.leaving = true;\n'
        '                                        toast.visible = false;',
        '                                        root.notifMergeFrom = m;\n'
        '                                        toast.visible = false;',
    ),
    (
        '                                MouseArea {\n'
        '                                    anchors.fill: parent\n'
        '                                    onClicked: root.notifActivate(toast.nid)',
        '                                MouseArea {\n'
        '                                    anchors.fill: tslab\n'
        '                                    enabled: !toast.leaving\n'
        '                                    onClicked: root.notifActivate(toast.nid)',
    ),
)


SCROLL_BEGIN = "                        // Silky Notification Center scrolling\n"
SCROLL_END = "                        // End Silky Notification Center scrolling\n"
SCROLL_ANCHOR = re.compile(r"^                    Flickable \{\n                        id: nfl\n", re.M)
SCROLL = '''                        flickableDirection: Flickable.VerticalFlick
                        synchronousDrag: true
                        maximumFlickVelocity: 3600
                        flickDeceleration: 1250

                        property real silkyScrollTarget: originY
                        property double silkyPadUntil: 0
                        function silkyClampScroll(y) {
                            const end = originY + Math.max(0, contentHeight - height);
                            return Math.max(originY, Math.min(end, y));
                        }
                        function silkyScrollWheel(event, touchpad) {
                            const angle = event.angleDelta.y;
                            const pixels = event.pixelDelta.y;
                            if (angle === 0 && pixels === 0) return;
                            event.accepted = true;

                            // Qt Wayland may report wheel notches with both pixel deltas and a touchpad device.
                            // Keep quantized events in an ongoing fine-scroll gesture on the pixel path.
                            const now = Date.now();
                            const wholeNotch = angle !== 0 && angle % 120 === 0;
                            const precise = touchpad ? (!wholeNotch || now < silkyPadUntil) : (!wholeNotch && pixels !== 0);
                            if (touchpad && precise) silkyPadUntil = now + 110;
                            const delta = precise ? (pixels || angle / 8) * 2.2 : angle * (160 / 120);

                            if (!silkyScrollFrame.running) {
                                cancelFlick();
                                silkyScrollTarget = contentY;
                            }
                            silkyScrollTarget = silkyClampScroll(silkyScrollTarget - delta);
                            if (root.reduceMotion) {
                                silkyScrollFrame.stop();
                                contentY = silkyScrollTarget;
                            } else {
                                silkyScrollFrame.response = precise ? 55 : 32;
                                silkyScrollFrame.start();
                            }
                        }

                        WheelHandler {
                            target: null
                            acceptedDevices: PointerDevice.Mouse
                            orientation: Qt.Vertical
                            enabled: nfl.contentHeight > nfl.height && !nfl.dragging
                            onWheel: event => nfl.silkyScrollWheel(event, false)
                        }
                        WheelHandler {
                            target: null
                            acceptedDevices: PointerDevice.TouchPad
                            orientation: Qt.Vertical
                            enabled: nfl.contentHeight > nfl.height && !nfl.dragging
                            onWheel: event => nfl.silkyScrollWheel(event, true)
                        }
                        PointHandler {
                            target: null
                            acceptedDevices: PointerDevice.TouchScreen
                            onActiveChanged: if (active) silkyScrollFrame.stop()
                        }
                        onDragStarted: silkyScrollFrame.stop()
                        Connections {
                            target: ui
                            function onPopChanged() {
                                if (ui.pop === "notif") return;
                                nfl.silkyPadUntil = 0;
                                silkyScrollFrame.stop();
                                nfl.cancelFlick();
                            }
                        }
                        FrameAnimation {
                            id: silkyScrollFrame
                            property real response: 32
                            onTriggered: {
                                const target = nfl.silkyClampScroll(nfl.silkyScrollTarget);
                                const step = 1 - Math.exp(-Math.min(frameTime, 0.05) * response);
                                let y = nfl.contentY + (target - nfl.contentY) * step;
                                if (Math.abs(target - y) < 0.5) {
                                    y = target;
                                    stop();
                                }
                                nfl.contentY = nfl.silkyClampScroll(y);
                            }
                        }
'''


def remove_scroll(text):
    if SCROLL_BEGIN not in text and SCROLL_END not in text:
        return text
    if text.count(SCROLL_BEGIN) != 1 or text.count(SCROLL_END) != 1:
        raise ValueError("Incomplete Notification Center scrolling block in MacBar.qml")
    before, remainder = text.split(SCROLL_BEGIN)
    _, after = remainder.split(SCROLL_END)
    return before + after


def integrate_scroll(text):
    text = remove_scroll(text)
    matches = list(SCROLL_ANCHOR.finditer(text))
    if len(matches) != 1:
        raise ValueError("MacBar Notification Center scroll view changed")
    before, after = text[:matches[0].end()], text[matches[0].end():]
    return before + SCROLL_BEGIN + SCROLL + SCROLL_END + after


def integrate(text):
    text = integrate_wechat(text)
    for original, updated in NOTIFICATION_REPLACEMENTS + TOAST_MOTION_REPLACEMENTS:
        if text.count(updated) == 1:
            continue
        if text.count(original) != 1:
            raise ValueError(f"MacBar notification code changed near {original.strip().splitlines()[0]}")
        text = text.replace(original, updated, 1)
    return integrate_scroll(text)


def write_atomic(path, contents, mode):
    with NamedTemporaryFile(dir=path.parent, delete=False) as temporary:
        temp_path = Path(temporary.name)
        try:
            temporary.write(contents)
            temporary.flush()
            os.fchmod(temporary.fileno(), mode)
            temp_path.replace(path)
        finally:
            temp_path.unlink(missing_ok=True)


def install_units(config_home):
    libexec = Path.home() / ".local/libexec"
    units = config_home / "systemd/user"
    libexec.mkdir(parents=True, exist_ok=True)
    units.mkdir(parents=True, exist_ok=True)
    script_name = "silky-macshell-notifications"
    write_atomic(libexec / script_name, Path(__file__).read_bytes(), 0o755)
    write_atomic(units / (script_name + ".service"), b"""[Unit]
Description=Restore Silky Notification Center fixes in MacShell

[Service]
Type=oneshot
ExecStart=/usr/bin/python3 %h/.local/libexec/silky-macshell-notifications --repair %E/quickshell/MacShell

[Install]
WantedBy=default.target
""", 0o644)
    write_atomic(units / (script_name + ".path"), b"""[Unit]
Description=Watch for MacShell Notification Center updates

[Path]
PathChanged=%E/quickshell/MacShell/MacBar.qml

[Install]
WantedBy=default.target
""", 0o644)
    subprocess.run(["systemctl", "--user", "daemon-reload"], check=True)
    subprocess.run(["systemctl", "--user", "enable", "--now",
                    script_name + ".path", script_name + ".service"], check=True)


def main():
    config_home = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    default_shell = config_home / "quickshell/MacShell"
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--install", action="store_true")
    mode.add_argument("--repair", action="store_true")
    parser.add_argument("shell_dir", type=Path, nargs="?", default=default_shell)
    args = parser.parse_args()
    if args.install and args.shell_dir != default_shell:
        parser.error("--install uses the standard MacShell configuration directory")
    bar = args.shell_dir / "MacBar.qml"
    try:
        if args.repair and not bar.exists():
            return
        original = bar.read_text()
        updated = integrate(original)
        if args.check:
            print(f"Notification Center fixes are compatible with {bar}")
            return
        if args.install:
            install_units(config_home)
            original = bar.read_text()
            updated = integrate(original)
        if updated != original:
            state = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "macshell"
            state.mkdir(parents=True, exist_ok=True)
            with NamedTemporaryFile(prefix="MacBar.qml.bak.notifications-", dir=state, delete=False) as backup:
                backup_path = Path(backup.name)
            shutil.copy2(bar, backup_path)
            if bar.read_text() != original:
                raise ValueError("MacBar.qml changed while preparing the Notification Center fixes")
            write_atomic(bar, updated.encode(), stat.S_IMODE(bar.stat().st_mode))
            print(f"Updated {bar}; backup: {backup_path}")
            if args.shell_dir == default_shell and shutil.which("qs"):
                subprocess.run(["qs", "-c", "MacShell", "ipc", "call", "macshell", "reload"],
                               stdout=subprocess.DEVNULL, check=False)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(error, file=sys.stderr)
        raise SystemExit(1) from error


if __name__ == "__main__":
    main()
