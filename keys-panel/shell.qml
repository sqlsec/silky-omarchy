// Silky Keys: the Super+K keyboard-shortcut panel, in MacShell's macOS 27 look, with search.
//
// The list comes from config/hypr/silky-keys-registry.lua (it records every bind while Hyprland loads the config);
// Return or a click runs the chosen shortcut exactly as pressing its keys would.
//
//   qs -c SilkyKeys                           run it (Hyprland starts it at login, see config/hypr/silky-keys.lua)
//   qs -c SilkyKeys ipc call keys toggle      show / hide (Super+K)
//
// Search: any words, in any order, against the action (Chinese and English), the keys ("super k", "⌘K", "ctrl
// shift") and the group name. Up / Down (or Ctrl+N / Ctrl+P) pick, Return runs, Esc clears the search, then closes.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    property bool open: false
    property var all: []          // every shortcut, grouped and ordered
    property var shown: []        // the ones matching the search
    property int sel: 0
    property string query: ""
    property point lastPointer: Qt.point(-1, -1)
    property bool pointerArmed: false      // the first hover event after opening only records where the pointer rests

    // ── look: follows MacShell (Settings → Appearance), ~/.config/macbar/settings.json ──
    property bool dark: true
    property color accent: "#0A84FF"
    property string fontFamily: "Open Runde"
    readonly property string uiFont: fontFamily === "Open Runde" && runde.status === FontLoader.Ready ? runde.name : fontFamily
    readonly property string uiFontBold: fontFamily === "Open Runde" && rundeBold.status === FontLoader.Ready ? rundeBold.name : uiFont
    readonly property color fg: dark ? Qt.rgba(1, 1, 1, 0.92) : Qt.rgba(0, 0, 0, 0.86)
    readonly property color fg2: dark ? Qt.rgba(1, 1, 1, 0.55) : Qt.rgba(0, 0, 0, 0.5)
    readonly property color fg3: dark ? Qt.rgba(1, 1, 1, 0.34) : Qt.rgba(0, 0, 0, 0.32)
    readonly property color hairline: dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.07)

    readonly property string home: Quickshell.env("HOME")
    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    readonly property string dumpPath: runtimeDir + "/silky-keys.json"
    readonly property string omarchyPath: Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"

    FontLoader { id: runde; source: "file://" + root.home + "/.config/quickshell/MacShell/assets/fonts/OpenRunde-Regular.otf" }
    FontLoader { id: rundeBold; source: "file://" + root.home + "/.config/quickshell/MacShell/assets/fonts/OpenRunde-Semibold.otf" }

    FileView {
        path: root.home + "/.config/macbar/settings.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                var o = JSON.parse(text());
                if (o.darkMode !== undefined) root.dark = o.darkMode;
                if (o.accent) root.accent = o.accent;
                if (o.fontFamily) root.fontFamily = o.fontFamily.indexOf("Inter") === 0 ? "Open Runde" : o.fontFamily;
            } catch (e) {}
        }
    }

    // ── Omarchy's translations of the bind descriptions (default/i18n/<lang>/keybindings.json) ──
    property var catalog: ({})
    Process {
        running: true
        command: ["sh", "-c", "omarchy-language 2>/dev/null || echo en"]
        stdout: StdioCollector {
            onStreamFinished: {
                var lang = text.trim() || "en";
                if (lang !== "en") catalogFile.path = root.omarchyPath + "/default/i18n/" + lang + "/keybindings.json";
            }
        }
    }
    FileView {
        id: catalogFile
        printErrors: false
        onLoaded: { try { root.catalog = JSON.parse(text()); root.rebuild(); } catch (e) {} }
    }

    function translate(desc) {
        var c = catalog[desc];
        if (typeof c === "string" && c !== "") return c;
        var nums = desc.match(/[0-9]+/g);
        if (!nums) return desc;
        var i = 0;
        var pattern = desc.replace(/[0-9]+/g, function () { i++; return "%" + i; });
        c = catalog[pattern];
        if (typeof c !== "string" || c === "") return desc;
        for (var k = 0; k < nums.length; k++) c = c.replace("%" + (k + 1), nums[k]);
        return c;
    }

    // ── keys as macOS draws them ──
    readonly property var modGlyph: ({ SUPER: "⌘", SHIFT: "⇧", CTRL: "⌃", ALT: "⌥" })
    readonly property var codeKeys: ({ "10": "1", "11": "2", "12": "3", "13": "4", "14": "5", "15": "6", "16": "7", "17": "8",
                                       "18": "9", "19": "0", "20": "-", "21": "=", "34": "[", "35": "]", "47": ";", "48": "'",
                                       "49": "`", "51": "\\", "59": ",", "60": ".", "61": "/" })
    readonly property var keyNames: ({
        RETURN: "↩", ENTER: "↩", SPACE: "空格", ESCAPE: "esc", TAB: "⇥", BACKSPACE: "⌫", DELETE: "⌦",
        LEFT: "←", RIGHT: "→", UP: "↑", DOWN: "↓", HOME: "home", END: "end", PRINT: "PrtSc",
        GRAVE: "`", COMMA: ",", PERIOD: ".", MINUS: "-", EQUAL: "=", SLASH: "/", BACKSLASH: "\\", SEMICOLON: ";",
        BRACKETLEFT: "[", BRACKETRIGHT: "]", APOSTROPHE: "'",
        MOUSE_DOWN: "滚轮 ↓", MOUSE_UP: "滚轮 ↑", "MOUSE:272": "左键", "MOUSE:273": "右键", "MOUSE:274": "中键",
        XF86AUDIORAISEVOLUME: "音量 +", XF86AUDIOLOWERVOLUME: "音量 −", XF86AUDIOMUTE: "静音", XF86AUDIOMICMUTE: "麦克风",
        XF86MONBRIGHTNESSUP: "亮度 +", XF86MONBRIGHTNESSDOWN: "亮度 −", XF86KBDBRIGHTNESSUP: "键盘灯 +",
        XF86KBDBRIGHTNESSDOWN: "键盘灯 −", XF86KBDLIGHTONOFF: "键盘灯", XF86AUDIOPLAY: "▶︎ 播放", XF86AUDIOPAUSE: "❙❙ 暂停",
        XF86AUDIONEXT: "▶︎▶︎ 下一首", XF86AUDIOPREV: "◀︎◀︎ 上一首", XF86AUDIOSTOP: "■ 停止", XF86CALCULATOR: "计算器",
        XF86POWEROFF: "电源", XF86TOUCHPADTOGGLE: "触控板"
    })
    function keyLabel(key) {
        var m = /^code:([0-9]+)$/i.exec(key);
        if (m) return codeKeys[m[1]] || ("键码 " + m[1]);
        var up = key.toUpperCase();
        if (keyNames[up] !== undefined) return keyNames[up];
        if (/^XF86/i.test(key)) return key.replace(/^XF86/i, "");
        return key.length === 1 ? up : key;
    }
    // macOS order: ⌃ ⌥ ⇧ ⌘
    function modCaps(mods) {
        var order = ["CTRL", "ALT", "SHIFT", "SUPER"], out = [];
        for (var i = 0; i < order.length; i++) if (mods.indexOf(order[i]) >= 0) out.push(modGlyph[order[i]]);
        return out;
    }

    // ── groups ──
    readonly property var groupOrder: ["MacShell", "常用", "应用", "窗口", "工作区", "截屏与录制", "系统与工具", "媒体与硬件", "输入", "我的快捷键"]
    readonly property var common: ["Keybindings", "Omarchy menu", "Terminal", "Browser", "File manager", "System menu", "Theme menu",
                                   "Full screen", "Close window", "Lock system", "Toggle window floating", "Universal copy", "Universal paste"]
    function groupOf(b) {
        var d = b.desc, src = b.src.split("/").pop();
        if (/MacShell|MacLock/.test(d)) return "MacShell";
        if (common.indexOf(d) >= 0) return "常用";
        if (/screenshot|screenrecord|color picker|ocr|截图|录屏/i.test(d)) return "截屏与录制";
        if (src === "applications.lua") return "应用";
        if (src === "tiling.lua") return /workspace|scratchpad|monitor/i.test(d) ? "工作区" : "窗口";
        if (src === "media.lua" || /^XF86/i.test(b.key)) return "媒体与硬件";
        if (src === "clipboard.lua" || src === "input-method.lua" || src === "dictation.lua" || src === "jis.lua") return "输入";
        if (src === "utilities.lua") return "系统与工具";
        if (b.src.indexOf(root.omarchyPath) === 0) return "系统与工具";
        return "我的快捷键";
    }

    function rebuild() {
        var raw;
        try { raw = JSON.parse(dumpFile.text()); } catch (e) { return; }
        var seen = {}, list = [];
        for (var i = 0; i < raw.length; i++) {
            var b = raw[i];
            if (b.key === "code:201") continue;                  // the Copilot key repeats another bind
            var id = b.mods.join(" ") + "|" + b.key.toUpperCase() + "|" + b.desc;
            if (seen[id]) continue;
            seen[id] = true;
            var title = translate(b.desc);
            var caps = modCaps(b.mods).concat([keyLabel(b.key)]);
            var group = groupOf(b);
            list.push({
                n: b.n, title: group === "MacShell" ? title.replace(/\s*\((MacShell|MacLock)\)$/, "") : title, en: b.desc, caps: caps, group: group, runnable: !b.mouse && !/^mouse:/i.test(b.key),
                order: i,
                hay: (title + " " + b.desc + " " + b.mods.join(" ") + " " + b.key + " " + caps.join("") + " " + caps.join(" ")
                      + " " + group + " " + (b.mods.indexOf("SUPER") >= 0 ? "win cmd command" : "")
                      + " " + (b.mods.indexOf("CTRL") >= 0 ? "control" : "") + " " + (b.mods.indexOf("ALT") >= 0 ? "option opt" : "")).toLowerCase()
            });
        }
        list.sort(function (a, b) {
            var ga = groupOrder.indexOf(a.group), gb = groupOrder.indexOf(b.group);
            if (ga !== gb) return ga - gb;
            if (a.group === "常用") return common.indexOf(a.en) - common.indexOf(b.en) || a.order - b.order;
            return a.order - b.order;
        });
        all = list;
        filter();
    }

    function filter() {
        var words = query.toLowerCase().replace(/\+/g, " ").split(/\s+/).filter(function (w) { return w !== ""; });
        var out = [];
        for (var i = 0; i < all.length; i++) {
            var e = all[i], ok = true;
            for (var w = 0; w < words.length && ok; w++) ok = e.hay.indexOf(words[w]) >= 0;
            if (ok) out.push(e);       // results keep the group order, so the section headers stay meaningful
        }
        shown = out;
        sel = 0;
        list.positionViewAtBeginning();
    }

    FileView {
        id: dumpFile
        path: root.dumpPath
        printErrors: false
        blockLoading: true
        onLoaded: root.rebuild()
    }

    // Ask Hyprland for the current binds every time the panel opens (cheap: one Lua call, no parsing of hyprctl output).
    Process {
        id: dumper
        command: ["hyprctl", "dispatch", "function() silky_keys.dump(\"" + root.dumpPath + "\") end"]
        onExited: dumpFile.reload()
    }

    // Run a shortcut once the panel is gone and focus is back on the window it was meant for.
    property int pendingRun: -1
    Timer {
        id: runTimer
        interval: 140
        onTriggered: {
            if (root.pendingRun < 0) return;
            runner.command = ["hyprctl", "dispatch", "function() silky_keys.run(" + root.pendingRun + ") end"];
            runner.running = true;
            root.pendingRun = -1;
        }
    }
    Process { id: runner }

    function show() {
        if (open) return;
        query = "";
        pointerArmed = false;
        armTimer.restart();
        input.text = "";
        dumper.running = true;
        open = true;
        focusTimer.restart();
    }
    function hide() { open = false; }
    function runSelected() {
        var e = shown[sel];
        if (!e || !e.runnable) return;
        pendingRun = e.n;
        hide();
        runTimer.restart();
    }

    IpcHandler {
        target: "keys"
        function toggle(): void { root.open ? root.hide() : root.show(); }
        function open(): void { root.show(); }
        function close(): void { root.hide(); }
        // open with a search already typed in, e.g.  qs -c SilkyKeys ipc call keys search 截图
        function search(text: string): void { root.show(); input.text = text; }
    }

    Timer { id: armTimer; interval: 320; onTriggered: root.pointerArmed = true }
    Timer { id: focusTimer; interval: 30; onTriggered: input.forceActiveFocus() }

    PanelWindow {
        id: win
        anchors { left: true; right: true; top: true; bottom: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "silky-keys"
        WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        visible: root.open || card.opacity > 0.01
        mask: Region { item: root.open ? catcher : nothing }
        Item { id: nothing; width: 0; height: 0 }

        // a click outside the card closes it
        MouseArea { id: catcher; anchors.fill: parent; onPressed: root.hide() }

        Item {
            id: card
            width: Math.min(720, parent.width - 80)
            height: Math.min(600, parent.height - 120)
            x: Math.round((parent.width - width) / 2)
            y: Math.round(parent.height * 0.44 - height / 2)
            opacity: root.open ? 1 : 0
            scale: root.open ? 1 : 0.965
            Behavior on opacity { NumberAnimation { duration: root.open ? 220 : 150; easing.type: root.open ? Easing.OutCubic : Easing.InCubic } }
            Behavior on scale { NumberAnimation { duration: root.open ? 260 : 150; easing.type: root.open ? Easing.OutBack : Easing.InCubic; easing.overshoot: 0.6 } }

            MouseArea { anchors.fill: parent }    // clicks on the card itself stay in it

            // Liquid-glass slab: Hyprland blurs what is behind it (layer rule "silky-keys"); a tint, a hairline rim
            // and a brighter top edge make the glass.
            Rectangle {
                id: slab
                anchors.fill: parent
                radius: 28
                color: root.dark ? Qt.rgba(0.11, 0.11, 0.12, 0.58) : Qt.rgba(0.97, 0.97, 0.98, 0.66)
                border.width: 1
                border.color: root.dark ? Qt.rgba(1, 1, 1, 0.13) : Qt.rgba(1, 1, 1, 0.7)
            }
            Rectangle {      // specular sheen along the top edge
                anchors.fill: parent
                anchors.margins: 1
                radius: 27
                gradient: Gradient {
                    GradientStop { position: 0.0; color: root.dark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(1, 1, 1, 0.45) }
                    GradientStop { position: 0.12; color: "transparent" }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }
            Rectangle {      // outer dark rim, like macOS windows over bright backgrounds
                anchors.fill: parent
                anchors.margins: -1
                radius: 29
                color: "transparent"
                border.width: 1
                border.color: root.dark ? Qt.rgba(0, 0, 0, 0.45) : Qt.rgba(0, 0, 0, 0.12)
            }

            // ── search field ──
            Item {
                id: header
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                height: 50

                Rectangle {
                    anchors.fill: parent
                    radius: 25
                    color: root.dark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(0, 0, 0, 0.045)
                    border.width: 1
                    border.color: input.activeFocus ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.0) : "transparent"
                }

                Canvas {     // magnifying glass
                    id: lens
                    x: 18; anchors.verticalCenter: parent.verticalCenter
                    width: 18; height: 18
                    property color tint: root.fg2
                    onTintChanged: requestPaint()
                    onPaint: {
                        var c = getContext("2d");
                        c.reset();
                        c.strokeStyle = tint;
                        c.lineWidth = 2;
                        c.lineCap = "round";
                        c.beginPath(); c.arc(7.5, 7.5, 5.8, 0, Math.PI * 2); c.stroke();
                        c.beginPath(); c.moveTo(12, 12); c.lineTo(16.5, 16.5); c.stroke();
                    }
                }

                Text {
                    x: input.x
                    anchors.verticalCenter: parent.verticalCenter
                    visible: input.text === ""
                    text: "搜索快捷键"
                    color: root.fg3
                    font.family: root.uiFont; font.pixelSize: 19
                }
                TextInput {
                    id: input
                    x: 46
                    width: parent.width - x - countText.width - 30
                    anchors.verticalCenter: parent.verticalCenter
                    clip: true
                    color: root.fg
                    selectionColor: root.accent
                    selectedTextColor: "white"
                    font.family: root.uiFont; font.pixelSize: 19
                    onTextChanged: { root.query = text; root.filter(); }
                    Keys.onPressed: event => {
                        var k = event.key, ctrl = event.modifiers & Qt.ControlModifier;
                        if (k === Qt.Key_Escape) {
                            if (text !== "") text = ""; else root.hide();
                        } else if (k === Qt.Key_Down || (ctrl && k === Qt.Key_N) || k === Qt.Key_Tab) {
                            root.sel = Math.min(root.shown.length - 1, root.sel + 1);
                        } else if (k === Qt.Key_Up || (ctrl && k === Qt.Key_P) || k === Qt.Key_Backtab) {
                            root.sel = Math.max(0, root.sel - 1);
                        } else if (k === Qt.Key_PageDown) {
                            root.sel = Math.min(root.shown.length - 1, root.sel + 10);
                        } else if (k === Qt.Key_PageUp) {
                            root.sel = Math.max(0, root.sel - 10);
                        } else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
                            root.runSelected();
                        } else {
                            return;
                        }
                        event.accepted = true;
                        list.positionViewAtIndex(root.sel, ListView.Contain);
                    }
                }
                Text {
                    id: countText
                    anchors { right: parent.right; rightMargin: 20; verticalCenter: parent.verticalCenter }
                    text: root.query === "" ? root.all.length + " 个快捷键" : root.shown.length + " 个结果"
                    color: root.fg3
                    font.family: root.uiFont; font.pixelSize: 13
                }
            }

            // ── list ──
            ListView {
                id: list
                anchors { left: parent.left; right: parent.right; top: header.bottom; bottom: footer.top; topMargin: 8; leftMargin: 10; rightMargin: 10 }
                clip: true
                model: root.shown
                currentIndex: root.sel
                boundsBehavior: Flickable.StopAtBounds
                highlightMoveDuration: 0
                reuseItems: true
                section.property: "group"
                section.criteria: ViewSection.FullString
                section.delegate: Item {
                    required property string section
                    width: list.width
                    height: 34
                    Text {
                        x: 14; anchors.bottom: parent.bottom; anchors.bottomMargin: 7
                        text: section
                        color: root.fg2
                        font.family: root.uiFontBold; font.pixelSize: 12; font.weight: Font.DemiBold
                        font.letterSpacing: 0.3
                    }
                }

                delegate: Item {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool selected: index === root.sel
                    width: list.width
                    height: 40

                    Rectangle {
                        anchors.fill: parent
                        anchors.leftMargin: 4; anchors.rightMargin: 4
                        radius: 10
                        color: row.selected ? root.accent : "transparent"
                    }
                    Text {
                        x: 16
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - caps.width - 48
                        text: row.modelData.title
                        elide: Text.ElideRight
                        color: row.selected ? "white" : root.fg
                        font.family: root.uiFont; font.pixelSize: 15
                    }
                    Row {
                        id: caps
                        anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                        spacing: 4
                        Repeater {
                            model: row.modelData.caps
                            delegate: Rectangle {
                                required property string modelData
                                height: 24
                                width: Math.max(24, capText.implicitWidth + 14)
                                radius: 6
                                color: row.selected ? Qt.rgba(1, 1, 1, 0.2)
                                                    : (root.dark ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(0, 0, 0, 0.055))
                                border.width: 1
                                border.color: row.selected ? Qt.rgba(1, 1, 1, 0.25)
                                                           : (root.dark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(0, 0, 0, 0.06))
                                Text {
                                    id: capText
                                    anchors.centerIn: parent
                                    text: modelData
                                    color: row.selected ? "white" : root.fg
                                    font.family: root.uiFontBold; font.pixelSize: 13; font.weight: Font.DemiBold
                                }
                            }
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: row.modelData.runnable ? Qt.PointingHandCursor : Qt.ArrowCursor
                        // only a real mouse move selects: rows scrolling under a resting pointer must not steal the keyboard selection
                        onPositionChanged: mouse => {
                            var g = mapToGlobal(mouse.x, mouse.y);
                            // the card scales in while it opens, so a resting pointer still reports tiny moves: until the open
                            // animation is over, and for moves under 2 px, only remember where the pointer is
                            var still = Math.abs(g.x - root.lastPointer.x) < 2 && Math.abs(g.y - root.lastPointer.y) < 2;
                            if (!root.pointerArmed || still) { if (!still) root.lastPointer = g; return; }
                            root.lastPointer = g;
                            root.sel = row.index;
                        }
                        onClicked: { root.sel = row.index; root.runSelected(); }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: root.shown.length === 0 && root.all.length > 0
                    text: "没有匹配“" + root.query + "”的快捷键"
                    color: root.fg2
                    font.family: root.uiFont; font.pixelSize: 15
                }
            }

            // ── footer ──
            Item {
                id: footer
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 40
                Rectangle { anchors.top: parent.top; x: 20; width: parent.width - 40; height: 1; color: root.hairline }
                Text {
                    anchors { left: parent.left; leftMargin: 24; verticalCenter: parent.verticalCenter }
                    text: "↑↓ 选择　↩ 执行　esc 关闭"
                    color: root.fg3
                    font.family: root.uiFont; font.pixelSize: 12
                }
                Text {
                    anchors { right: parent.right; rightMargin: 24; verticalCenter: parent.verticalCenter }
                    text: "⌘ Super　⌥ Alt　⌃ Ctrl　⇧ Shift"
                    color: root.fg3
                    font.family: root.uiFont; font.pixelSize: 12
                }
            }
        }
    }
}
