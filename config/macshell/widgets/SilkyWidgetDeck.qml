// Widgets under the notifications in the notification centre (macOS-style), with an edit mode and a gallery.
//   layout + settings: ~/.config/silky/widgets.json   data: assets/silky-widgets.py (weather, stocks, screen time, system)
//   Edit Widgets: tap a widget to cycle Small → Medium → Large, drag to reorder, − to remove; the gallery adds new ones.
//   Right-click any widget: size, weather city, stock symbols (codes, tickers or names, any market), remove.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "SilkyWidgetsFormat.js" as F

Item {
    id: deck
    property var theme: null                // the panel palette (MacBar's `pal`)
    property string fam: "sans-serif"
    property string bold: "sans-serif"
    property color accent: "#6cb8ff"
    property Component glass: null          // liquid-glass background for cards and the menu (see SilkyWidget.glass)
    property bool open: false               // the notification centre is open
    property real maxHeight: 600
    // the part of the deck the surrounding scroll shows (deck coordinates); viewHeight 0 = everything is in view
    property real viewTop: 0
    property real viewHeight: 0
    function edgeFade(top, h) {
        if (viewHeight <= 0 || h <= 1) return 1;
        var seen = (Math.min(top + h, viewTop + viewHeight) - Math.max(top, viewTop)) / h;
        var t = Math.max(0, Math.min(1, seen));       // the share of the card still in view
        return t * t * (3 - 2 * t);
    }
    property bool editing: false
    readonly property bool wantsKeyboard: menuOpen && (menuKind === "weather" || menuKind === "stocks")

    // palette for SilkyWLabel (host: deck)
    readonly property bool dark: theme ? theme.dark : true
    readonly property color fg: theme ? theme.fg : "white"
    readonly property color fg2: theme ? theme.fg2 : Qt.rgba(1, 1, 1, 0.62)
    readonly property color fg3: theme ? theme.fg3 : Qt.rgba(1, 1, 1, 0.34)
    readonly property color track: theme ? theme.track : Qt.rgba(1, 1, 1, 0.2)

    width: 356
    // while the right-click menu is open the deck is at least as tall as the menu, so the panel never clips it
    height: Math.max(Math.min(col.height, maxHeight), menuOpen ? menuBox.height + 8 : 0)
    onOpenChanged: {
        if (open) {
            info = latest;
            send("refresh-ai");
        } else { editing = false; closeMenu(); }
    }
    onEditingChanged: closeMenu()

    // ───────────── data (shared single backend across all monitors) ─────────────
    property bool isProcessOwner: false
    property var info: null
    property var latest: null
    readonly property string script: decodeURIComponent(Qt.resolvedUrl("assets/silky-widgets.py").toString().substring(7))
    Component.onCompleted: F.registerWidgetDeck(deck)
    Component.onDestruction: F.unregisterWidgetDeck(deck)
    Process {
        id: proc
        running: deck.isProcessOwner
        stdinEnabled: true
        command: ["/usr/bin/python3", "-I", deck.script]
        stdout: SplitParser {
            onRead: line => {
                try {
                    F.broadcastWidgetSample(JSON.parse(line));
                } catch (error) {
                    console.warn("Silky widgets:", error);
                }
            }
        }
        onExited: if (deck.isProcessOwner) restart.restart()
    }
    Timer { id: restart; interval: 5000; onTriggered: if (deck.isProcessOwner) proc.running = true }
    function sendLocal(line) { if (proc.running) proc.write(line + "\n"); }
    function send(line) { F.sendWidgetCommand(line); }
    // screen time pauses after 2 idle minutes (video players' idle inhibitors keep it counting)
    IdleMonitor {
        enabled: deck.isProcessOwner
        timeout: 120
        respectInhibitors: true
        onIsIdleChanged: deck.send("idle " + (isIdle ? 1 : 0))
    }

    // ───────────── layout + settings ─────────────
    readonly property var defaults: [
        { kind: "weather", size: "small" }, { kind: "calendar", size: "small" },
        { kind: "stocks", size: "medium" }, { kind: "screentime", size: "medium" },
        { kind: "battery", size: "small" }, { kind: "system", size: "small" }
    ]
    property string city: ""
    property var symbols: ["sh000001", "sz399001", "hkHSI", "usIXIC", "usAAPL", "usNVDA"]
    property bool upRed: F.zh()
    property bool saving: false
    property int uidSeed: 0
    ListModel { id: wmodel }

    function apply(text) {
        var o = {};
        try { o = JSON.parse(text) || {}; } catch (e) { o = {}; }
        var list = Array.isArray(o.widgets) ? o.widgets : defaults;
        wmodel.clear();
        for (var i = 0; i < list.length; i++) {
            var w = list[i];
            if (!w || F.kinds.every(k => k.kind !== w.kind)) continue;
            wmodel.append({ uid: ++uidSeed, kind: w.kind, size: ["small", "medium", "large"].indexOf(w.size) >= 0 ? w.size : "small" });
        }
        city = typeof o.city === "string" ? o.city : "";
        if (Array.isArray(o.stocks)) symbols = o.stocks;
        upRed = o.upColor === "green" ? false : o.upColor === "red" ? true : F.zh();
    }
    function save() {
        var list = [];
        for (var i = 0; i < wmodel.count; i++) list.push({ kind: wmodel.get(i).kind, size: wmodel.get(i).size });
        saving = true;
        cfg.setText(JSON.stringify({ widgets: list, city: city, stocks: symbols, upColor: upRed ? "red" : "green" }, null, 2) + "\n");
        send("refresh");
    }
    FileView {
        id: cfg
        path: Quickshell.env("HOME") + "/.config/silky/widgets.json"
        printErrors: false
        watchChanges: true
        onFileChanged: { if (deck.saving) deck.saving = false; else reload(); }
        onLoaded: deck.apply(text())
        onLoadFailed: deck.apply("")
    }

    // ───────────── gallery state ─────────────
    property string pickKind: "weather"
    property string pickSize: "small"

    // the flickable reaches 8 px past the deck's top and sides so the edit-mode − badges are not clipped
    Flickable {
        id: flick
        x: -8; y: -8
        width: parent.width + 16
        height: parent.height + 8
        contentWidth: width
        contentHeight: col.height + 8
        clip: true
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col
            x: 8; y: 8
            width: deck.width
            spacing: 12

            Flow {
                id: flow
                width: parent.width
                spacing: 12
                move: Transition { NumberAnimation { properties: "x,y"; duration: 380; easing.type: Easing.OutCubic } }
                Repeater {
                    id: rep
                    model: wmodel
                    delegate: Item {
                        id: slot
                        required property int index
                        required property int uid
                        required property string kind
                        required property string size
                        property bool dragging: false
                        property real dragX: 0
                        property real dragY: 0
                        width: card.width
                        height: card.height
                        z: dragging ? 10 : 0
                        opacity: dragging ? 1 : deck.edgeFade(y, height)

                        SilkyWidget {
                            id: card
                            kind: slot.kind
                            size: slot.size
                            info: deck.info
                            pal: deck.theme
                            fam: deck.fam
                            bold: deck.bold
                            accent: deck.accent
                            upRed: deck.upRed
                            glass: deck.glass
                            scale: slot.dragging ? 1.04 : 1
                            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                            transform: Translate { x: slot.dragging ? slot.dragX - slot.x : 0; y: slot.dragging ? slot.dragY - slot.y : 0 }
                            // the macOS edit-mode wiggle
                            SequentialAnimation on rotation {
                                running: deck.editing && !slot.dragging
                                loops: Animation.Infinite
                                NumberAnimation { to: -0.7; duration: 130 + (slot.uid % 3) * 20; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 0.7; duration: 130 + (slot.uid % 3) * 20; easing.type: Easing.InOutSine }
                                onRunningChanged: if (!running) card.rotation = 0
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            preventStealing: deck.editing
                            cursorShape: !deck.editing ? Qt.ArrowCursor : slot.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                            property point grab
                            onPressed: m => {
                                if (m.button === Qt.RightButton) {
                                    deck.openMenu(slot.index, mapToItem(deck, m.x, m.y));
                                    return;
                                }
                                if (!deck.editing) { m.accepted = false; return; }
                                grab = Qt.point(m.x, m.y);
                                slot.dragging = false;
                            }
                            onPositionChanged: m => {
                                if (!deck.editing || !(pressedButtons & Qt.LeftButton)) return;
                                var p = mapToItem(flow, m.x, m.y);
                                if (!slot.dragging && Math.abs(m.x - grab.x) + Math.abs(m.y - grab.y) > 8) slot.dragging = true;
                                if (!slot.dragging) return;
                                slot.dragX = p.x - grab.x;
                                slot.dragY = p.y - grab.y;
                                if (cooldown.running) return;
                                var target = deck.slotAt(p, slot.index);
                                if (target >= 0) { wmodel.move(slot.index, target, 1); cooldown.restart(); }
                            }
                            onReleased: m => {
                                if (m.button !== Qt.LeftButton || !deck.editing) return;
                                if (slot.dragging) { slot.dragging = false; deck.save(); return; }
                                deck.cycleSize(slot.index);
                            }
                            onCanceled: slot.dragging = false
                        }
                        Timer { id: cooldown; interval: 420 }
                        // remove badge
                        Rectangle {
                            visible: deck.editing && !slot.dragging
                            x: -6; y: -6; width: 22; height: 22; radius: 11
                            color: deck.dark ? "#5b5b60" : "#d9d9de"
                            border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.12)
                            Rectangle { anchors.centerIn: parent; width: 10; height: 2; radius: 1; color: deck.fg }
                            MouseArea {
                                anchors.fill: parent; anchors.margins: -4
                                cursorShape: Qt.PointingHandCursor
                                onClicked: deck.removeAt(slot.index)
                            }
                        }
                    }
                }
            }
            SilkyWLabel {
                visible: deck.editing && wmodel.count > 0
                anchors.horizontalCenter: parent.horizontalCenter
                host: deck; dim: true; px: 11
                text: F.tr("Tap a widget to change its size · drag to reorder")
            }

            // Edit Widgets / Done
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: editLabel.implicitWidth + 28; height: 28; radius: 14
                color: deck.editing ? deck.accent : deck.glass ? "transparent"
                    : editMouse.containsMouse ? (deck.theme ? deck.theme.btnHover : "#555") : (deck.theme ? deck.theme.btnOff : "#444")
                Loader {
                    anchors.fill: parent
                    active: deck.glass !== null && !deck.editing
                    sourceComponent: deck.glass
                    onLoaded: item.r = 14
                }
                Rectangle {
                    visible: deck.glass !== null && !deck.editing && editMouse.containsMouse
                    anchors.fill: parent
                    radius: 14
                    color: deck.dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.06)
                }
                SilkyWLabel {
                    id: editLabel
                    anchors.centerIn: parent
                    host: deck; strong: true; px: 12
                    color: deck.editing ? "white" : deck.fg
                    text: deck.editing ? F.tr("Done") : F.tr("Edit Widgets")
                }
                MouseArea {
                    id: editMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: deck.editing = !deck.editing
                }
            }

            // ───────────── gallery ─────────────
            Column {
                visible: deck.editing
                width: parent.width
                spacing: 10

                Rectangle { width: parent.width; height: 1; color: deck.theme ? deck.theme.sep : Qt.rgba(1, 1, 1, 0.12) }
                SilkyWLabel { host: deck; strong: true; px: 15; text: F.tr("Add Widget") }

                Flow {
                    width: parent.width
                    spacing: 6
                    Repeater {
                        model: F.kinds
                        Rectangle {
                            required property var modelData
                            readonly property bool on: deck.pickKind === modelData.kind
                            width: chip.implicitWidth + 22; height: 26; radius: 13
                            color: on ? deck.accent : chipMouse.containsMouse ? (deck.theme ? deck.theme.btnHover : "#555") : (deck.theme ? deck.theme.btnOff : "#444")
                            SilkyWLabel {
                                id: chip
                                anchors.centerIn: parent
                                host: deck; px: 12; strong: parent.on
                                color: parent.on ? "white" : deck.fg
                                text: F.tr(modelData.name)
                            }
                            MouseArea {
                                id: chipMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: deck.pickKind = modelData.kind
                            }
                        }
                    }
                }
                SilkyWLabel {
                    host: deck; dim: true; px: 12
                    text: F.tr((F.kinds.filter(k => k.kind === deck.pickKind)[0] || {}).note || "")
                }

                // size picker
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 6
                    Repeater {
                        model: ["small", "medium", "large"]
                        Rectangle {
                            required property string modelData
                            readonly property bool on: deck.pickSize === modelData
                            width: 64; height: 26; radius: 13
                            color: on ? deck.accent : sizeMouse.containsMouse ? (deck.theme ? deck.theme.btnHover : "#555") : (deck.theme ? deck.theme.btnOff : "#444")
                            SilkyWLabel {
                                anchors.centerIn: parent
                                host: deck; px: 12; strong: parent.on
                                color: parent.on ? "white" : deck.fg
                                text: F.tr(modelData.charAt(0).toUpperCase() + modelData.slice(1))
                            }
                            MouseArea {
                                id: sizeMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: deck.pickSize = modelData
                            }
                        }
                    }
                }

                // live preview; click it (or the button) to add
                Item {
                    width: parent.width
                    height: preview.height
                    SilkyWidget {
                        id: preview
                        anchors.horizontalCenter: parent.horizontalCenter
                        kind: deck.pickKind
                        size: deck.pickSize
                        info: deck.info
                        pal: deck.theme
                        fam: deck.fam
                        bold: deck.bold
                        accent: deck.accent
                        upRed: deck.upRed
                        glass: deck.glass
                    }
                    MouseArea {
                        anchors.fill: preview
                        cursorShape: Qt.PointingHandCursor
                        onClicked: deck.add()
                    }
                }
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: addLabel.implicitWidth + 32; height: 30; radius: 15
                    color: deck.accent
                    SilkyWLabel { id: addLabel; anchors.centerIn: parent; host: deck; strong: true; px: 13; color: "white"
                                  text: "＋ " + F.tr("Add Widget") }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: deck.add() }
                }

                Item { width: 1; height: 4 }
            }
        }
    }
    readonly property string cityHint: F.zh() ? "例如 上海、Toronto" : "e.g. Shanghai, Toronto"

    function slotAt(p, self) {
        for (var i = 0; i < rep.count; i++) {
            var it = rep.itemAt(i);
            if (i === self || !it) continue;
            if (p.x >= it.x && p.x <= it.x + it.width && p.y >= it.y && p.y <= it.y + it.height) return i;
        }
        return -1;
    }
    // run in the deck's scope: a delegate's own context is gone once its row is removed
    function removeAt(i) {
        if (i < 0 || i >= wmodel.count) return;
        wmodel.remove(i);
        save();
    }
    function cycleSize(i) {
        var sizes = ["small", "medium", "large"];
        wmodel.setProperty(i, "size", sizes[(sizes.indexOf(wmodel.get(i).size) + 1) % 3]);
        save();
    }
    function add() {
        wmodel.append({ uid: ++uidSeed, kind: pickKind, size: pickSize });
        save();
        flick.contentY = 0;
    }
    // ───────────── right-click menu ─────────────
    property int menuIndex: -1
    property string menuKind: ""
    property string menuSize: ""
    property real menuX: 0
    property real menuY: 0
    readonly property bool menuOpen: menuIndex >= 0
    function openMenu(index, point) {
        menuIndex = index;
        menuKind = wmodel.get(index).kind;
        menuSize = wmodel.get(index).size;
        menuX = point.x;
        menuY = point.y;
        menuField.text = menuKind === "weather" ? city : "";
        if (menuKind === "stocks") syncSymbols();
    }
    function closeMenu() {
        if (menuIndex < 0) return;
        if (menuKind === "weather") commitCity();
        menuIndex = -1;
        menuField.focus = false;
    }
    function setSize(size) {
        if (menuIndex < 0) return;
        menuSize = size;
        wmodel.setProperty(menuIndex, "size", size);
        save();
    }
    function removeMenuWidget() {
        var i = menuIndex;
        menuIndex = -1;
        removeAt(i);
    }
    function commitCity() {
        var c = menuField.text.trim();
        if (c !== city) { city = c; save(); }
    }
    ListModel { id: symModel }          // the menu's copy of `symbols`, so rows keep their identity while dragged
    function syncSymbols() {
        symModel.clear();
        for (var i = 0; i < symbols.length; i++) symModel.append({ entry: symbols[i] });
    }
    function commitOrder() {
        var list = [];
        for (var i = 0; i < symModel.count; i++) list.push(symModel.get(i).entry);
        symbols = list;
        save();
    }
    function addSymbols(text) {
        var added = text.split(/[,，;；]+/).map(s => s.trim()).filter(s => s && symbols.indexOf(s) < 0);
        if (!added.length) return;
        symbols = symbols.concat(added).slice(0, 12);
        syncSymbols();
        save();
    }
    function removeSymbol(entry) {
        symbols = symbols.filter(s => s !== entry);
        syncSymbols();
        save();
    }
    function stockLabel(entry) {
        var list = info && info.stocks ? info.stocks : [];
        for (var i = 0; i < list.length; i++)
            if (list[i].entry === entry || list[i].symbol === entry) return list[i].price !== null && list[i].price !== undefined ? list[i].name : "";
        return "";
    }

    // a click anywhere else in the widget area closes the menu
    MouseArea {
        anchors.fill: parent
        visible: deck.menuOpen
        z: 50
        acceptedButtons: Qt.AllButtons
        onPressed: deck.closeMenu()
    }
    Rectangle {
        id: menuBox
        z: 51
        visible: deck.menuOpen
        width: 244
        height: menuCol.height + 20
        x: Math.max(0, Math.min(deck.menuX, deck.width - width))
        y: Math.max(0, Math.min(deck.menuY, deck.height - height))
        radius: 16
        // frosted: the panel's liquid glass plus a veil so the text stays readable over the widgets behind it
        color: deck.dark ? Qt.rgba(0.08, 0.07, 0.10, deck.glass ? 0.42 : 0.82) : Qt.rgba(1, 1, 1, deck.glass ? 0.45 : 0.88)
        border.width: deck.glass ? 0 : 1
        border.color: deck.dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.10)
        Loader {
            z: -1
            anchors.fill: parent
            active: deck.glass !== null && menuBox.visible
            sourceComponent: deck.glass
            onLoaded: item.r = 16
        }
        opacity: visible ? 1 : 0
        scale: visible ? 1 : 0.94
        transformOrigin: Item.TopLeft
        Behavior on opacity { NumberAnimation { duration: 140 } }
        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }     // clicks inside stay inside
        Keys.onEscapePressed: deck.closeMenu()

        Column {
            id: menuCol
            x: 10; y: 10
            width: parent.width - 20
            spacing: 8

            SilkyWLabel { host: deck; strong: true; px: 13; text: F.kindName(deck.menuKind) }

            // size
            Row {
                spacing: 6
                Repeater {
                    model: ["small", "medium", "large"]
                    Rectangle {
                        required property string modelData
                        readonly property bool on: deck.menuSize === modelData
                        width: (menuCol.width - 12) / 3; height: 26; radius: 8
                        color: on ? deck.accent : menuSizeMouse.containsMouse ? (deck.theme ? deck.theme.btnHover : "#555") : (deck.theme ? deck.theme.btnOff : "#444")
                        SilkyWLabel {
                            anchors.centerIn: parent; host: deck; px: 12; strong: parent.on
                            color: parent.on ? "white" : deck.fg
                            text: F.tr(modelData.charAt(0).toUpperCase() + modelData.slice(1))
                        }
                        MouseArea { id: menuSizeMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: deck.setSize(modelData) }
                    }
                }
            }

            // weather: city
            SilkyWLabel {
                visible: deck.menuKind === "weather"
                host: deck; dim: true; px: 11
                text: F.tr("City (empty = locate by IP)")
            }
            // stocks: the followed symbols
            SilkyWLabel {
                visible: deck.menuKind === "stocks"
                host: deck; dim: true; px: 11
                text: F.tr("Symbols you follow") + "  " + deck.symbols.length + "/12 · " + F.tr("drag to reorder")
            }
            // drag a row (or its ≡ handle) up or down to set the order the widget shows them in
            Column {
                id: symCol
                visible: deck.menuKind === "stocks"
                width: parent.width
                move: Transition { NumberAnimation { properties: "y"; duration: 160; easing.type: Easing.OutCubic } }
                Repeater {
                    model: symModel
                    Rectangle {
                        id: symRow
                        required property string entry
                        required property int index
                        readonly property string modelData: entry
                        width: menuCol.width; height: 24; radius: 6
                        color: rowMouse.pressed ? (deck.theme ? deck.theme.btnHover : "#444")
                             : rowMouse.containsMouse ? (deck.theme ? deck.theme.hover : "#333") : "transparent"
                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            preventStealing: true
                            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                            property bool moved: false
                            onPressed: moved = false
                            onPositionChanged: m => {
                                if (!pressed) return;
                                var y = mapToItem(symCol, m.x, m.y).y;
                                var target = Math.max(0, Math.min(symModel.count - 1, Math.floor(y / 24)));
                                if (target !== symRow.index) { symModel.move(symRow.index, target, 1); moved = true; }
                            }
                            onReleased: if (moved) deck.commitOrder()
                        }
                        Column {
                            x: 6; anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            Repeater {
                                model: 3
                                Rectangle { width: 9; height: 1.4; radius: 0.7; color: deck.fg3 }
                            }
                        }
                        SilkyWLabel {
                            x: 22; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 50
                            host: deck; px: 12
                            readonly property string label: deck.stockLabel(modelData)
                            text: label ? label + "  ·  " + modelData : modelData
                        }
                        Rectangle {
                            anchors.right: parent.right; anchors.rightMargin: 4; anchors.verticalCenter: parent.verticalCenter
                            width: 18; height: 18; radius: 9
                            color: xMouse.containsMouse ? (deck.dark ? "#ff6b61" : "#d1332b") : (deck.theme ? deck.theme.btnOff : "#444")
                            Rectangle { anchors.centerIn: parent; width: 8; height: 1.6; radius: 1; color: xMouse.containsMouse ? "white" : deck.fg }
                            MouseArea { id: xMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: deck.removeSymbol(modelData) }
                        }
                    }
                }
            }
            Rectangle {
                visible: deck.menuKind === "weather" || (deck.menuKind === "stocks" && deck.symbols.length < 12)
                width: parent.width; height: 30; radius: 8
                color: deck.theme ? deck.theme.btnOff : "#444"
                border.width: menuField.activeFocus ? 2 : 0
                border.color: deck.accent
                TextInput {
                    id: menuField
                    anchors.fill: parent
                    anchors.leftMargin: 9; anchors.rightMargin: 9
                    verticalAlignment: TextInput.AlignVCenter
                    color: deck.fg
                    selectionColor: deck.accent
                    font.family: deck.fam; font.pixelSize: 13
                    clip: true
                    onAccepted: {
                        if (deck.menuKind === "weather") { deck.commitCity(); deck.closeMenu(); }
                        else { deck.addSymbols(text); text = ""; }
                    }
                    Keys.onEscapePressed: deck.closeMenu()
                    Text {
                        visible: !menuField.text
                        anchors.verticalCenter: parent.verticalCenter
                        color: deck.fg3
                        font: menuField.font
                        text: deck.menuKind === "weather" ? deck.cityHint : F.tr("Add a code or name, Enter")
                    }
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.IBeamCursor
                            onPressed: m => { menuField.forceActiveFocus(); m.accepted = false; } }
            }
            SilkyWLabel {
                visible: deck.menuKind === "weather" && deck.info && deck.info.weather
                host: deck; dim: true; px: 11; width: parent.width
                text: visible ? F.tr("Now showing") + " " + deck.info.weather.city : ""
            }
            Text {
                visible: deck.menuKind === "stocks"
                width: parent.width
                wrapMode: Text.WordWrap
                color: deck.fg2
                font.family: deck.fam; font.pixelSize: 10
                text: F.tr("A-shares 600519 · HK 00700 · US AAPL · Tokyo 7203.T · Europe SAP.DE · indices ^N225 ^GDAXI · crypto BTC-USD · gold GC=F · or a name")
            }
            Row {
                visible: deck.menuKind === "stocks"
                spacing: 6
                Repeater {
                    model: [true, false]
                    Rectangle {
                        required property bool modelData
                        readonly property bool on: deck.upRed === modelData
                        width: (menuCol.width - 6) / 2; height: 24; radius: 8
                        color: on ? deck.accent : (deck.theme ? deck.theme.btnOff : "#444")
                        SilkyWLabel {
                            anchors.centerIn: parent; host: deck; px: 11; color: parent.on ? "white" : deck.fg
                            text: modelData ? F.tr("Red up · green down") : F.tr("Green up · red down")
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { deck.upRed = modelData; deck.save(); } }
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: deck.theme ? deck.theme.sep : Qt.rgba(1, 1, 1, 0.12) }
            Rectangle {
                width: parent.width; height: 26; radius: 6
                color: removeMouse.containsMouse ? (deck.theme ? deck.theme.hover : "#333") : "transparent"
                SilkyWLabel { x: 6; anchors.verticalCenter: parent.verticalCenter; host: deck; px: 13
                              color: deck.dark ? "#ff6b61" : "#d1332b"; text: F.tr("Remove Widget") }
                MouseArea { id: removeMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: deck.removeMenuWidget() }
            }
        }
    }
}
