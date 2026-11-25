#!/usr/bin/env python3
"""Install and maintain Silky fixes for MacShell notifications and tray actions."""

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

        root.silkyShowWeChat(null, invoked ? 3 : 0);
        return true;
    }

    function silkyShowWeChat(open, waitTicks) {
        silkyWeChatFocus.waitTicks = waitTicks;
        silkyWeChatFocus.open = open;
        silkyWeChatFocus.opened = false;
        silkyWeChatFocus.ticks = 0;
        Hyprland.refreshToplevels();
        silkyWeChatFocus.restart();
    }

    Timer {
        id: silkyWeChatFocus
        interval: 100
        repeat: true
        property int waitTicks: 0
        property int ticks: 0
        property bool opened: false
        property var open: null
        onTriggered: {
            const main = Hyprland.toplevels.values.find(window => {
                const data = window.lastIpcObject;
                const isMainTitle = title => /^(微信|WeChat)$/i.test(title || "");
                return data && (data.class === "wechat" || data.initialClass === "wechat")
                    && data.mapped && !data.hidden
                    && (isMainTitle(data.initialTitle) || isMainTitle(data.title));
            });
            if (root.silkyFocusTrayWindow(main)) {
                open = null;
                stop();
                return;
            }
            if (++ticks <= waitTicks) return;
            if (!opened) {
                opened = true;
                if (open) {
                    const action = open;
                    open = null;
                    action();
                } else {
                    const tray = SystemTray.items.values.find(item => item.id === "wechat" && !item.onlyMenu);
                    if (tray) tray.activate();
                    else {
                        const entry = DesktopEntries.byId("wechat");
                        if (entry) entry.execute();
                        else stop();
                    }
                }
            }
            // A cold start can take several seconds. Never toggle the tray twice.
            if (ticks >= 80) stop();
        }
    }

    function silkyFocusTrayWindow(window) {
        if (!window || !/^(0x)?[0-9a-f]+$/i.test(window.address)) return false;
        const dock = root.hub && root.hub.dock;
        if (window.lastIpcObject.workspace?.name === "special:minimized" && dock?.restoreAddress) {
            dock.restoreAddress(window.address);
        } else {
            const address = "0x" + window.address.replace(/^0x/i, "");
            Hyprland.dispatch(
                '(function() '
                + 'local prev = hl.get_config("cursor.no_warps"); '
                + 'if not prev then pcall(hl.config, { cursor = { no_warps = true } }) end; '
                + 'hl.dispatch(hl.dsp.focus({ window = "address:' + address + '" })); '
                + 'if not prev then pcall(hl.config, { cursor = { no_warps = false } }) end; '
                + 'return hl.dsp.window.alter_zorder({ mode = "top", window = "address:' + address + '" }) '
                + 'end)()'
            );
        }
        return true;
    }

    function silkyFocusTrayApp(windowClass, appIds) {
        const appId = value => String(value || "").toLowerCase().replace(/\.desktop$/, "");
        let recent = null;
        for (const window of Hyprland.toplevels.values) {
            const data = window.lastIpcObject;
            if (!data || !data.mapped || data.hidden || data.acceptsInput === false) continue;
            const matches = windowClass ? windowClass.test(data.class)
                : appIds.includes(appId(data.class)) || appIds.includes(appId(data.initialClass));
            if (!matches) continue;
            if (!recent || data.focusHistoryID < recent.lastIpcObject.focusHistoryID)
                recent = window;
        }
        return root.silkyFocusTrayWindow(recent);
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


WECHAT_TRAY_REPLACEMENTS = (
    (
        '                                        if (mouse.button === Qt.RightButton || (mouse.button === Qt.LeftButton && tray.modelData.onlyMenu))',
        '                                        const item = tray.modelData;\n'
        '                                        if (mouse.button === Qt.LeftButton && item.id === "wechat") {\n'
        '                                            ui.pop = "";\n'
        '                                            root.silkyShowWeChat(() => item.activate(), 0);\n'
        '                                        } else if (mouse.button === Qt.RightButton || (mouse.button === Qt.LeftButton && tray.modelData.onlyMenu))',
    ),
    (
        '                                                te.modelData.triggered();\n'
        '                                                ui.pop = "";',
        '                                                const action = te.modelData;\n'
        '                                                const label = trayPop.clean(action.text).replace(/&/g, "").trim();\n'
        '                                                if (ui.trayItem?.id === "wechat" && ui.trayStack.length === 0\n'
        '                                                        && /^(显示|顯示|Show)$/i.test(label)) {\n'
        '                                                    root.silkyShowWeChat(() => action.triggered(), 0);\n'
        '                                                } else {\n'
        '                                                    action.triggered();\n'
        '                                                }\n'
        '                                                ui.pop = "";',
    ),
)


TRAY_SHORTCUTS = r'''                QsMenuOpener {
                    id: trayShortcutMenu
                    menu: trayShortcut.item?.menu ?? null
                }

                Timer {
                    id: trayShortcut
                    interval: 80
                    repeat: true
                    running: item !== null
                    property var item: null
                    property var action: null
                    property var identities: []
                    property real anchorX: 0
                    property int attempts: 0
                    readonly property var actions: ({
                        clash: { windowClass: /^clash-verge$/i, label: /^(仪表[板盘]|儀表[板盤]|Dashboard)$/i },
                        remmina: {
                            windowClass: /^(org\.remmina\.)?remmina$/i,
                            label: /^(打开主窗口|開啟主視窗|Open Main Window)(\s*\([a-z]\))?$/i
                        },
                        clippy: { label: /^Open Clippy$/i },
                        claude: { windowClass: /^(com\.anthropic\.)?claude$/i, label: /^Show App$/i },
                        antigravity: { windowClass: /^antigravity$/i, label: /^(Open Antigravity|打开\s*Antigravity|開啟\s*Antigravity)$/i },
                        chatgpt: { windowClass: /^chatgpt$/i, desktopId: "chatgpt" },
                        chrome: { windowClass: /^google-chrome$/i, desktopId: "google-chrome" }
                    })

                    function startFor(trayItem, kind, x) {
                        // WeChat also uses its tray activation to restore notifications and hidden windows.
                        if (trayItem.id.toLowerCase() === "wechat") return false;
                        ui.pop = "";
                        anchorX = x;
                        attempts = 0;
                        action = actions[kind] || {};
                        identities = [trayItem.title, trayItem.tooltipTitle, trayItem.id]
                            .map(value => String(value || "").trim().replace(/\.desktop$/i, ""))
                            .filter(value => value.length > 0);
                        Hyprland.refreshToplevels();
                        item = trayItem;
                        return true;
                    }

                    function isOpenAction(entry) {
                        if (entry.isSeparator || entry.hasChildren || !entry.enabled) return false;
                        const label = trayPop.clean(entry.text).replace(/&/g, "").trim();
                        if (action.label?.test(label)) return true;
                        if (/^(open|show|open app|show app|open main window|show main window|打开|开启|显示|顯示|開啟|開啓|打开主窗口|显示主窗口|開啟主視窗|顯示主視窗)(?:\s*\([a-z]\))?$/i.test(label))
                            return true;
                        const named = /^(?:open|show)\s+(.+)$|^(?:打开|开启|显示|顯示|開啟|開啓)\s*(.+)$/i.exec(label);
                        if (!named) return false;
                        const name = (named[1] || named[2]).toLowerCase();
                        return identities.some(value => value.toLowerCase() === name);
                    }

                    function desktopEntry() {
                        const ids = action.desktopId ? [action.desktopId] : identities;
                        for (const id of ids) {
                            const entry = DesktopEntries.byId(id) || DesktopEntries.byId(id.toLowerCase());
                            if (entry) return entry;
                        }
                        return null;
                    }

                    onTriggered: {
                        if (!item) return;
                        const appIds = identities.map(value => value.toLowerCase());
                        if (root.silkyFocusTrayApp(action.windowClass, appIds)) {
                            item = null;
                            return;
                        }
                        const entries = trayShortcutMenu.children?.values ?? [];
                        const menuAction = entries.find(entry => trayShortcut.isOpenAction(entry));
                        if (menuAction) {
                            menuAction.triggered();
                            item = null;
                            return;
                        }
                        if (item.hasMenu && entries.length === 0 && ++attempts < 12) return;

                        const trayItem = item;
                        item = null;
                        const entry = desktopEntry();
                        if (entry) entry.execute();
                        else if (trayItem.onlyMenu) ui.openTray(trayItem, anchorX);
                        else trayItem.activate();
                    }
                }

'''


# The original per-app shortcuts used the same menu opener without this marker.
LEGACY_TRAY_SHORTCUTS = re.compile(
    r"^ {16}QsMenuOpener \{\n {20}id: trayShortcutMenu\n.*?"
    r"(?=^ {16}function openTray\(item, x\) \{\n)",
    re.M | re.S,
)
TRAY_SHORTCUT_MARKER = "                // Default tray opening actions\n"

TRAY_SHORTCUT_REPLACEMENTS = (
    (
        '                function openTray(item, x) {\n',
        TRAY_SHORTCUT_MARKER + TRAY_SHORTCUTS + '                function openTray(item, x) {\n'
        '                    trayShortcut.item = null;\n',
    ),
    (
        '                                    color: (ui.pop === "tray" && ui.trayItem === tray.modelData) ? bpal.hover : "transparent"\n'
        '                                }\n',
        '                                    color: (ui.pop === "tray" && ui.trayItem === tray.modelData) || trayMouse.pressed || tray.silkyClickFlash ? bpal.hover : "transparent"\n'
        '                                    Behavior on color { ColorAnimation { duration: 120 } }\n'
        '                                }\n'
        '                                property bool silkyClickFlash: false\n'
        '                                Timer { id: silkyClickFlashTimer; interval: 180; onTriggered: tray.silkyClickFlash = false }\n',
    ),
    (
        '                                MouseArea {\n'
        '                                    anchors.fill: parent\n'
        '                                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton\n',
        '                                MouseArea {\n'
        '                                    id: trayMouse\n'
        '                                    anchors.fill: parent\n'
        '                                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton\n',
    ),
    (
        '                                        if (root.hub && root.hub.overview && root.hub.overview.shown) root.hub.overview.dismiss(true);\n'
        '                                        var p = tray.mapToItem(ui, 0, 0);\n',
        '                                        if (root.hub && root.hub.overview && root.hub.overview.shown) root.hub.overview.dismiss(true);\n'
        '                                        if (mouse.button !== Qt.RightButton) {\n'
        '                                            tray.silkyClickFlash = true;\n'
        '                                            silkyClickFlashTimer.restart();\n'
        '                                        }\n'
        '                                        var p = tray.mapToItem(ui, 0, 0);\n',
    ),
    (
        '                                        var p = tray.mapToItem(ui, 0, 0);\n',
        '                                        var p = tray.mapToItem(ui, 0, 0);\n'
        '                                        if (mouse.button === Qt.LeftButton\n'
        '                                                && trayShortcut.startFor(tray.modelData, tray.silkyTrayApp, p.x)) return;\n',
    ),
    (
        '                                id: tray\n',
        '                                id: tray\n'
        '                                readonly property string silkyTrayApp: {\n'
        '                                    const id = tray.modelData.id.toLowerCase();\n'
        '                                    if (id.startsWith("claude") || id === "com.anthropic.claude") return "claude";\n'
        '                                    if (id.startsWith("antigravity")) return "antigravity";\n'
        '                                    const title = (tray.modelData.tooltipTitle || tray.modelData.title || "").trim().toLowerCase();\n'
        '                                    if (id === "chrome_status_icon_1") {\n'
        '                                        if (title === "chatgpt") return "chatgpt";\n'
        '                                        if (title === "google chrome") return "chrome";\n'
        '                                    }\n'
        '                                    if (id === "tray-icon tray app clash-verge-rev-tray") return "clash";\n'
        '                                    if (id === "remmina-icon") return "remmina";\n'
        '                                    if (id === "clippy") return "clippy";\n'
        '                                    // LocalSend registers under a random id each launch; its title is stable.\n'
        '                                    if (title.includes("localsend")) return "localsend";\n'
        '                                    return "";\n'
        '                                }\n',
    ),
)

# The tray app block as installed before LocalSend got its glyph; upgraded in place so it is not inserted twice.
TRAY_APP_LOCALSEND = (
    '                                    if (id === "clippy") return "clippy";\n'
    '                                    return "";\n'
    '                                }\n'
    '                                required property var modelData\n',
    '                                    if (id === "clippy") return "clippy";\n'
    '                                    // LocalSend registers under a random id each launch; its title is stable.\n'
    '                                    if (title.includes("localsend")) return "localsend";\n'
    '                                    return "";\n'
    '                                }\n'
    '                                required property var modelData\n',
)

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
)


NOTIF_READABILITY_REPLACEMENTS = (
    (
        "        width: parent ? parent.width : 340\n"
        "        height: Math.max(74, textCol.height + 30)\n\n"
        "        readonly property string agoText: {\n"
        "            var m = Math.floor((nb.nowMs - nb.stamp) / 60000);\n"
        '            return m < 1 ? "now" : (m < 60 ? m + "m ago" : (m < 1440 ? Math.floor(m / 60) + "h ago" : Math.floor(m / 1440) + "d ago"));\n'
        "        }",
        "        width: parent ? parent.width : 340\n"
        "        height: Math.max(72, textCol.height + 28)\n\n"
        '        readonly property bool hideDupApp: nb.urgency !== 2 && nb.app.trim() !== ""\n'
        "            && nb.summary.trim().toLowerCase() === nb.app.trim().toLowerCase()\n"
        "        readonly property real topRightPad: nb.showClose ? 28 : (nb.showTime ? agoLabel.implicitWidth + 10 : 0)\n"
        "        readonly property string agoText: {\n"
        "            var m = Math.floor((nb.nowMs - nb.stamp) / 60000);\n"
        '            return m < 1 ? "now" : (m < 60 ? m + "m ago" : (m < 1440 ? Math.floor(m / 60) + "h ago" : Math.floor(m / 1440) + "d ago"));\n'
        "        }",
    ),
    (
        "            x: 70; y: 14\n"
        "            width: parent.width - 70 - 44\n"
        "            spacing: 1\n"
        "            Text {\n"
        "                width: parent.width\n"
        '                text: nb.urgency === 2 ? I18n.tr("TIME SENSITIVE") : nb.app\n'
        "                horizontalAlignment: /[\\u0590-\\u08ff]/.test(text) ? Text.AlignRight : Text.AlignLeft\n"
        '                visible: text !== ""\n'
        "                color: nb.urgency === 2 ? nb.t.fg2 : nb.t.fg\n"
        "                font.family: root.fontForWeight(Font.DemiBold, nb.t.fam); font.pixelSize: nb.urgency === 2 ? 12 : 14\n"
        "                font.weight: Font.DemiBold\n"
        "                font.letterSpacing: nb.urgency === 2 ? 0.4 : 0\n"
        "                elide: Text.ElideRight\n"
        "            }\n"
        "            Text {\n"
        "                width: parent.width\n"
        "                text: nb.summary\n"
        "                horizontalAlignment: /[\\u0590-\\u08ff]/.test(text) ? Text.AlignRight : Text.AlignLeft\n"
        '                visible: text !== ""\n'
        "                color: nb.t.fg\n"
        "                font.family: root.fontForWeight(Font.Bold, nb.t.fam); font.pixelSize: 14; font.weight: Font.Bold\n"
        "                wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight\n"
        "            }\n"
        "            Text {\n"
        "                width: parent.width\n"
        "                text: nb.body\n"
        "                horizontalAlignment: /[\\u0590-\\u08ff]/.test(text) ? Text.AlignRight : Text.AlignLeft\n"
        '                visible: text !== ""\n'
        "                color: nb.t.fg\n"
        "                font.family: root.fontForWeight(Font.Normal, nb.t.fam); font.pixelSize: 13\n"
        "                wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight\n"
        "            }\n"
        "        }\n"
        "        Text {\n"
        "            visible: nb.showTime && !nb.showClose\n"
        "            anchors.right: parent.right; anchors.rightMargin: 14\n"
        "            y: 15\n"
        "            text: nb.agoText\n"
        "            color: nb.t.fg2\n"
        "            font.family: root.fontForWeight(Font.Normal, nb.t.fam); font.pixelSize: 12\n"
        "        }",
        "            x: 70\n"
        "            anchors.verticalCenter: parent.verticalCenter\n"
        "            width: parent.width - 70 - 16\n"
        "            spacing: 2\n"
        "            Text {\n"
        "                width: Math.max(40, parent.width - nb.topRightPad)\n"
        '                text: nb.urgency === 2 ? I18n.tr("TIME SENSITIVE") : nb.app\n'
        "                horizontalAlignment: /[\\u0590-\\u08ff]/.test(text) ? Text.AlignRight : Text.AlignLeft\n"
        '                visible: text !== "" && !nb.hideDupApp\n'
        '                color: nb.urgency === 2 ? (nb.t.dark ? "#FFD60A" : "#B25000") : (nb.t.dark ? Qt.rgba(1, 1, 1, 0.80) : Qt.rgba(0.08, 0.08, 0.10, 0.72))\n'
        "                font.family: root.fontForWeight(Font.DemiBold, nb.t.fam); font.pixelSize: nb.urgency === 2 ? 11 : 12\n"
        "                font.weight: Font.DemiBold\n"
        "                font.letterSpacing: nb.urgency === 2 ? 0.4 : 0.1\n"
        "                elide: Text.ElideRight\n"
        "            }\n"
        "            Text {\n"
        "                width: nb.hideDupApp ? Math.max(40, parent.width - nb.topRightPad) : parent.width\n"
        "                text: nb.summary\n"
        "                horizontalAlignment: /[\\u0590-\\u08ff]/.test(text) ? Text.AlignRight : Text.AlignLeft\n"
        '                visible: text !== ""\n'
        '                color: nb.t.dark ? "#FFFFFF" : "#121214"\n'
        "                font.family: root.fontForWeight(Font.Bold, nb.t.fam); font.pixelSize: 14; font.weight: Font.Bold\n"
        "                lineHeight: 1.14\n"
        "                wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight\n"
        "            }\n"
        "            Text {\n"
        "                width: parent.width\n"
        "                text: nb.body\n"
        "                horizontalAlignment: /[\\u0590-\\u08ff]/.test(text) ? Text.AlignRight : Text.AlignLeft\n"
        '                visible: text !== ""\n'
        "                color: nb.t.dark ? Qt.rgba(1, 1, 1, 0.93) : Qt.rgba(0.08, 0.08, 0.10, 0.88)\n"
        "                font.family: root.fontForWeight(Font.Medium, nb.t.fam); font.pixelSize: 13; font.weight: Font.Medium\n"
        "                lineHeight: 1.20\n"
        "                wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight\n"
        "            }\n"
        "        }\n"
        "        Text {\n"
        "            id: agoLabel\n"
        "            visible: nb.showTime && !nb.showClose\n"
        "            anchors.right: parent.right; anchors.rightMargin: 14\n"
        "            y: Math.max(13, Math.round(textCol.y) + 1)\n"
        "            text: nb.agoText\n"
        "            color: nb.t.dark ? Qt.rgba(1, 1, 1, 0.74) : Qt.rgba(0.10, 0.10, 0.12, 0.66)\n"
        "            font.family: root.fontForWeight(Font.Medium, nb.t.fam); font.pixelSize: 12; font.weight: Font.Medium\n"
        "        }",
    ),
    (
        "                                    rimTint: 1\n"
        "                                    ringW: 0.9\n"
        "                                    shadowAmt: 0.35\n"
        "                                }\n"
        "                                MenuBorder {",
        "                                    rimTint: 1\n"
        "                                    ringW: 0.9\n"
        "                                    shadowAmt: 0.35\n"
        "                                }\n"
        "                                Rectangle {\n"
        "                                    visible: tslab.silkyOwned\n"
        "                                    anchors.fill: tslab\n"
        "                                    anchors.margins: 1\n"
        "                                    radius: Math.max(0, tslab.cornerR - 1)\n"
        "                                    gradient: Gradient {\n"
        "                                        GradientStop { position: 0.0; color: root.effDark ? Qt.rgba(0.06, 0.06, 0.08, 0.40) : Qt.rgba(0.99, 0.99, 1.0, 0.52) }\n"
        "                                        GradientStop { position: 1.0; color: root.effDark ? Qt.rgba(0.04, 0.04, 0.06, 0.46) : Qt.rgba(0.97, 0.97, 0.99, 0.44) }\n"
        "                                    }\n"
        "                                }\n"
        "                                MenuBorder {",
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
    if TRAY_SHORTCUT_MARKER not in text:
        text, count = LEGACY_TRAY_SHORTCUTS.subn("", text)
        if count == 1:
            text = text.replace(
                "                function openTray(item, x) {\n                    trayShortcut.item = null;\n",
                "                function openTray(item, x) {\n",
                1,
            )
        elif count != 0:
            raise ValueError("Multiple tray shortcut blocks in MacBar.qml")
    text = (
        text.replace(
            "GradientStop { position: 0.0; color: root.effDark ? Qt.rgba(0.06, 0.06, 0.08, 0.25) : Qt.rgba(0.99, 0.99, 1.0, 0.38) }",
            "GradientStop { position: 0.0; color: root.effDark ? Qt.rgba(0.06, 0.06, 0.08, 0.40) : Qt.rgba(0.99, 0.99, 1.0, 0.52) }",
        ).replace(
            "GradientStop { position: 1.0; color: root.effDark ? Qt.rgba(0.04, 0.04, 0.06, 0.31) : Qt.rgba(0.97, 0.97, 0.99, 0.30) }",
            "GradientStop { position: 1.0; color: root.effDark ? Qt.rgba(0.04, 0.04, 0.06, 0.46) : Qt.rgba(0.97, 0.97, 0.99, 0.44) }",
        )
    )
    legacy_tray_app, tray_app = TRAY_APP_LOCALSEND
    if text.count(legacy_tray_app) == 1 and tray_app not in text:
        text = text.replace(legacy_tray_app, tray_app, 1)
    replacements = (WECHAT_TRAY_REPLACEMENTS + TRAY_SHORTCUT_REPLACEMENTS
                    + NOTIFICATION_REPLACEMENTS + TOAST_MOTION_REPLACEMENTS
                    + NOTIF_READABILITY_REPLACEMENTS)
    for original, updated in replacements:
        if text.count(updated) == 1:
            continue
        if text.count(original) != 1:
            raise ValueError(f"MacBar code changed near {original.strip().splitlines()[0]}")
        text = text.replace(original, updated, 1)
    icon_kind = "                                readonly property string silkyIconKind: {\n"
    tray_ink = "                                    if (tray.silkyTrayApp) return tray.silkyTrayApp;\n"
    if icon_kind in text and icon_kind + tray_ink not in text:
        text = text.replace(icon_kind, icon_kind + tray_ink, 1)
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
