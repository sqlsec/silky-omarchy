import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "DisplayModes.js" as Modes
import "I18n.js" as I18n

Popup {
    id: editor

    required property var t
    required property var monitors
    required property string primary
    required property var wallpaperFor
    property var base: []
    property var draft: []
    property var snap: null
    property var wallpapers: ({})
    readonly property bool changed: draft.some(box => {
        const initial = base.find(item => item.name === box.name);
        return initial && (box.x !== initial.x || box.y !== initial.y);
    })
    signal applied(var positions)

    parent: Overlay.overlay
    anchors.centerIn: parent
    width: parent ? Math.min(620, parent.width - 24) : 620
    modal: true
    focus: true
    padding: 16
    closePolicy: Popup.CloseOnEscape
    onClosed: {
        base = [];
        draft = [];
        snap = null;
    }

    function begin() {
        base = Modes.layoutBoxes(monitors);
        if (base.length < 2) return;
        draft = base;
        snap = null;
        wallpapers = {};
        open();
        if (!wallpaperQuery.running) wallpaperQuery.running = true;
    }

    function place(candidate) {
        if (candidate)
            draft = draft.map(box => box.name === candidate.name ? candidate : box);
        snap = null;
    }

    function activeWallpaper(name) {
        return wallpapers[name] || wallpaperFor(name, wallpapers.default || "") || "";
    }

    Process {
        id: wallpaperQuery
        command: ["sh", "-c",
            "awww query 2>/dev/null; swww query 2>/dev/null; hyprctl hyprpaper listactive 2>/dev/null; " +
            "p=$(readlink -f \"${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/current/background\"); " +
            "[ ! -f \"$p\" ] || printf 'default = %s\\n' \"$p\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const found = {};
                for (const line of text.split("\n")) {
                    const match = /^\s*:?\s*([^\s:]+):.*\bimage:\s*(\/.*)$/.exec(line)
                               || /^([^\s=]+)\s*=\s*(\/.*)$/.exec(line);
                    if (match && !found[match[1]]) found[match[1]] = match[2];
                }
                editor.wallpapers = found;
            }
        }
    }
    Timer {
        interval: 3000
        running: editor.opened
        repeat: true
        onTriggered: if (!wallpaperQuery.running) wallpaperQuery.running = true
    }

    background: Rectangle {
        radius: 16
        color: editor.t.card
        border.color: editor.t.buttonBorder
    }

    component FooterButton: Button {
        id: action
        height: 30
        leftPadding: 14
        rightPadding: 14
        font.family: editor.t.fam
        font.pixelSize: 12
        hoverEnabled: true
        contentItem: Text {
            text: action.text
            font: action.font
            color: action.highlighted && action.enabled ? "#ffffff" : editor.t.text
            opacity: action.enabled ? 1 : 0.5
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            radius: 8
            color: action.highlighted && action.enabled
                ? (action.down ? Qt.darker(editor.t.accent, 1.2) : editor.t.accent)
                : action.hovered ? editor.t.buttonPressed : editor.t.ctrl
            border.color: action.visualFocus ? editor.t.accent : editor.t.buttonBorder
        }
    }

    contentItem: Column {
        spacing: 11

        Text {
            width: parent.width
            text: I18n.tr("Arrange displays")
            color: editor.t.text
            font.family: editor.t.fam
            font.pixelSize: 19
            font.weight: Font.DemiBold
        }
        Text {
            width: parent.width
            text: I18n.tr("Drag the screens to match where they sit on your desk.")
            wrapMode: Text.WordWrap
            color: editor.t.text2
            font.family: editor.t.fam
            font.pixelSize: 12
        }

        Rectangle {
            id: canvas
            width: parent.width
            height: editor.parent ? Math.max(155, Math.min(332, editor.parent.height - 150)) : 300
            radius: 11
            color: editor.t.contentSolid
            border.color: editor.t.sep
            clip: true

            readonly property var extent: editor.draft.length ? Modes.bounds(editor.draft)
                : { left: 0, top: 0, right: 1, bottom: 1 }
            readonly property real mapWidth: extent.right - extent.left
            readonly property real mapHeight: extent.bottom - extent.top
            readonly property real largestWidth: Math.max(1, ...editor.draft.map(box => box.width))
            readonly property real largestHeight: Math.max(1, ...editor.draft.map(box => box.height))
            readonly property real zoom: Math.max(0.001, Math.min(
                width / (mapWidth + largestWidth * 0.7),
                height / (mapHeight + largestHeight * 1.05)))
            readonly property real originX: (width - mapWidth * zoom) / 2 - extent.left * zoom
            readonly property real originY: (height - mapHeight * zoom) / 2 - extent.top * zoom

            Rectangle {
                readonly property var target: editor.snap
                x: target ? canvas.originX + target.x * canvas.zoom : 0
                y: target ? canvas.originY + target.y * canvas.zoom : 0
                width: target ? target.width * canvas.zoom : 0
                height: target ? target.height * canvas.zoom : 0
                visible: !!target
                radius: 7
                color: Qt.rgba(editor.t.accent.r, editor.t.accent.g, editor.t.accent.b, 0.20)
                border.width: 2
                border.color: editor.t.accent
            }

            Repeater {
                model: editor.base
                delegate: Rectangle {
                    id: screenTile

                    required property var modelData
                    readonly property var box: editor.draft.find(item => item.name === modelData.name) || modelData
                    readonly property string displayType: I18n.tr(Modes.isBuiltIn(modelData.monitor) ? "Built-in display" : "External display")
                    readonly property string displayName: Modes.displayName(modelData.monitor, displayType)
                    readonly property bool main: modelData.name === editor.primary
                    readonly property string wallpaper: editor.activeWallpaper(modelData.name).replace(/^~(?=\/)/, Quickshell.env("HOME"))
                    readonly property bool video: /\.(mp4|webm|mkv|mov|m4v|avi|ogv)$/i.test(wallpaper)
                    property string poster: ""
                    property real offsetX: 0
                    property real offsetY: 0

                    x: canvas.originX + box.x * canvas.zoom + offsetX
                    y: canvas.originY + box.y * canvas.zoom + offsetY
                    z: pointer.dragging ? 2 : 1
                    width: box.width * canvas.zoom
                    height: box.height * canvas.zoom
                    radius: 6
                    color: editor.t.ctrl
                    opacity: pointer.dragging ? 0.86 : 1
                    clip: true

                    Accessible.role: Accessible.Pane
                    Accessible.name: displayName
                    Accessible.description: main ? I18n.tr("Main display") : ""
                    activeFocusOnTab: true

                    onWallpaperChanged: {
                        poster = "";
                        loadPoster();
                    }
                    Component.onCompleted: loadPoster()

                    function loadPoster() {
                        if (!video || extract.running) return;
                        extract.requested = wallpaper;
                        extract.running = true;
                    }

                    function moveBy(dx, dy) {
                        offsetX = dx;
                        offsetY = dy;
                        editor.snap = Modes.snappedPosition(editor.draft, box,
                            box.x + dx / canvas.zoom, box.y + dy / canvas.zoom, 8 / canvas.zoom);
                    }

                    function nudge(key) {
                        const neighbor = editor.draft.filter(item => item.name !== box.name).reduce((best, item) =>
                            !best || Math.hypot(item.x - box.x, item.y - box.y) < Math.hypot(best.x - box.x, best.y - box.y)
                                ? item : best, null);
                        if (!neighbor) return;
                        const x = key === Qt.Key_Left ? neighbor.x - box.width
                            : key === Qt.Key_Right ? neighbor.x + neighbor.width : neighbor.x;
                        const y = key === Qt.Key_Up ? neighbor.y - box.height
                            : key === Qt.Key_Down ? neighbor.y + neighbor.height : neighbor.y;
                        editor.place(Modes.snappedPosition(editor.draft, box, x, y, 0));
                    }

                    Keys.onLeftPressed: nudge(Qt.Key_Left)
                    Keys.onRightPressed: nudge(Qt.Key_Right)
                    Keys.onUpPressed: nudge(Qt.Key_Up)
                    Keys.onDownPressed: nudge(Qt.Key_Down)

                    Process {
                        id: extract
                        property string requested: ""
                        command: ["sh", "-c",
                            "ffmpeg -nostdin -v error -i \"$1\" -vf 'scale=480:-2' -frames:v 1 -f image2pipe -vcodec png - 2>/dev/null | base64 -w0",
                            "display-wallpaper", requested]
                        stdout: StdioCollector {
                            onStreamFinished: {
                                if (extract.requested === screenTile.wallpaper && text)
                                    screenTile.poster = "data:image/png;base64," + text;
                            }
                        }
                        onExited: if (requested !== screenTile.wallpaper) Qt.callLater(screenTile.loadPoster)
                    }

                    Image {
                        anchors.fill: parent
                        anchors.margins: 2
                        source: screenTile.video ? screenTile.poster
                            : screenTile.wallpaper && !screenTile.wallpaper.startsWith("file://")
                                ? "file://" + encodeURI(screenTile.wallpaper).replace(/#/g, "%23").replace(/\?/g, "%3F")
                                : screenTile.wallpaper
                        asynchronous: true
                        fillMode: Image.PreserveAspectCrop
                        sourceSize.width: 512
                        visible: status === Image.Ready
                    }

                    Rectangle {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 2 }
                        height: Math.min(parent.height - 4, 43)
                        gradient: Gradient {
                            GradientStop { position: 0; color: "transparent" }
                            GradientStop { position: 1; color: "#dd141820" }
                        }
                    }

                    Text {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 7 }
                        text: screenTile.displayName
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignHCenter
                        font.family: editor.t.fam
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        color: "#ffffff"
                    }

                    Rectangle {
                        visible: screenTile.main
                        x: 6; y: 6
                        width: 21; height: 4
                        radius: 2
                        color: "#ffffff"
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: screenTile.radius
                        color: "transparent"
                        border.width: screenTile.activeFocus || pointer.containsMouse ? 2 : 1
                        border.color: screenTile.activeFocus ? editor.t.accent : Qt.rgba(1, 1, 1, pointer.containsMouse ? 0.65 : 0.22)
                    }

                    MouseArea {
                        id: pointer
                        anchors.fill: parent
                        hoverEnabled: true
                        preventStealing: true
                        cursorShape: dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                        property point start
                        property bool dragging: false

                        onPressed: mouse => {
                            start = mapToItem(canvas, mouse.x, mouse.y);
                            screenTile.forceActiveFocus();
                        }
                        onPositionChanged: mouse => {
                            if (!pressed) return;
                            const position = mapToItem(canvas, mouse.x, mouse.y);
                            const dx = position.x - start.x;
                            const dy = position.y - start.y;
                            if (!dragging && Math.hypot(dx, dy) < 4) return;
                            dragging = true;
                            screenTile.moveBy(dx, dy);
                        }
                        onReleased: {
                            if (dragging) editor.place(editor.snap);
                            dragging = false;
                            screenTile.offsetX = 0;
                            screenTile.offsetY = 0;
                        }
                        onCanceled: {
                            dragging = false;
                            editor.snap = null;
                            screenTile.offsetX = 0;
                            screenTile.offsetY = 0;
                        }
                    }
                }
            }
        }

        Item {
            width: parent.width
            height: 30
            Row {
                anchors.right: parent.right
                spacing: 8
                FooterButton {
                    text: I18n.tr("Cancel")
                    onClicked: editor.close()
                }
                FooterButton {
                    text: I18n.tr("Apply")
                    enabled: editor.changed
                    highlighted: true
                    onClicked: {
                        editor.applied(editor.draft);
                        editor.close();
                    }
                }
            }
        }
    }
}
