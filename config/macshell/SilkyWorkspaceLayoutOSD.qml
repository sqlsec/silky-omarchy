import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: root
    required property var bar
    required property bool dark
    required property string language
    property bool glassPlugin: true
    property var modes: ({})

    readonly property bool chinese: (language === "auto" ? Qt.locale().name : language).startsWith("zh")

    // Top-bar right-click layout picker menu state
    property bool menuOpen: false
    property int menuWorkspace: 1
    property string menuMonitor: ""
    property real menuX: 0
    property real menuY: 32

    function modeFor(workspaceId) {
        const key = String(workspaceId);
        return modes[key] || "floating";
    }

    function modeIndex(mode) {
        if (mode === "dwindle") return 1;
        if (mode === "scrolling") return 2;
        return 0;
    }

    function modeLabel(mode) {
        if (chinese) {
            if (mode === "dwindle") return "平铺分屏";
            if (mode === "scrolling") return "横向滚动";
            return "浮动窗口";
        }
        if (mode === "dwindle") return "Tiling";
        if (mode === "scrolling") return "Scrolling";
        return "Floating";
    }

    function evalHypr(code) {
        Quickshell.execDetached(["hyprctl", "eval", code]);
    }

    function cycleWorkspace(workspaceId) {
        menuOpen = false;
        evalHypr("if o.silky_workspace_layout_cycle then o.silky_workspace_layout_cycle(" + Number(workspaceId) + ") end");
    }

    function setWorkspaceMode(workspaceId, mode) {
        menuOpen = false;
        evalHypr("if o.silky_workspace_layout_set then o.silky_workspace_layout_set("
            + Number(workspaceId) + "," + JSON.stringify(mode) + ",true) end");
    }

    function resetAllFloating(monitorName) {
        menuOpen = false;
        evalHypr("if o.silky_workspace_layout_reset_all then o.silky_workspace_layout_reset_all("
            + JSON.stringify(monitorName || "") + ") end");
    }

    function openMenu(workspaceId, screenName, x, y) {
        menuWorkspace = Number(workspaceId);
        menuMonitor = screenName || "";
        menuX = x;
        menuY = y;
        menuOpen = true;
    }

    function requestSync() {
        evalHypr("if o.silky_workspace_layout_sync then o.silky_workspace_layout_sync() end");
    }

    function triggerOsd(wsId, mode, mon) {
        if (wsId > 0) {
            const next = Object.assign({}, root.modes);
            next[String(wsId)] = mode;
            root.modes = next;
        }
        if (root.bar && root.bar.showLayoutOsd)
            root.bar.showLayoutOsd(mode || "floating");
    }

    IpcHandler {
        target: "wsLayout"
        function status(): string {
            return JSON.stringify({
                osdVisible: root.bar ? root.bar.osdVisible : false,
                osdKind: root.bar ? root.bar.osdKind : "",
                osdMode: root.bar ? root.bar.osdLayoutMode : "floating",
                modes: root.modes
            });
        }
        function present(wsId: int, mode: string, mon: string): void {
            root.triggerOsd(wsId, mode, mon);
        }
    }

    Component.onCompleted: syncKick.restart()

    Timer {
        id: syncKick
        interval: 250
        repeat: false
        onTriggered: root.requestSync()
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded") {
                syncKick.restart();
                return;
            }
            if (root.menuOpen && (event.name === "workspacev2" || event.name === "focusedmonv2"))
                root.menuOpen = false;
            if (event.name !== "custom")
                return;
            const data = String(event.data || "");
            if (data.startsWith("silky-ws-layout-map,")) {
                const body = data.slice("silky-ws-layout-map,".length);
                const next = {};
                const pairs = body.split(";");
                for (let i = 0; i < pairs.length; i++) {
                    const kv = pairs[i].split(":");
                    if (kv.length === 2 && kv[0] !== "")
                        next[kv[0]] = kv[1];
                }
                root.modes = next;
            } else if (data.startsWith("silky-ws-layout,")) {
                const parts = data.slice("silky-ws-layout,".length).split(",");
                if (parts.length < 4)
                    return;
                const wsId = Number(parts[0]);
                const mode = parts[1] || "floating";
                const mon = parts[2] || "";
                const showOsd = parts[3] === "1";
                if (showOsd) {
                    root.triggerOsd(wsId, mode, mon);
                } else if (wsId > 0) {
                    const next = Object.assign({}, root.modes);
                    next[String(wsId)] = mode;
                    root.modes = next;
                }
            }
        }
    }

    // ── Top-bar right-click layout picker popover ──
    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: menuWin
            required property var modelData
            screen: modelData
            readonly property bool activeScreen: root.menuOpen && modelData.name === root.menuMonitor
            visible: activeScreen
            anchors { left: true; right: true; top: true; bottom: true }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore

            WlrLayershell.namespace: "macosd"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: activeScreen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

            MouseArea {
                anchors.fill: parent
                onClicked: root.menuOpen = false
            }

            Item {
                anchors.fill: parent
                focus: menuWin.activeScreen
                Keys.onEscapePressed: root.menuOpen = false

                Rectangle {
                    id: popup
                    width: 172
                    height: menuCol.implicitHeight + 12
                    radius: 14
                    x: Math.max(8, Math.min(menuWin.width - width - 8, Math.round(root.menuX - width / 2)))
                    y: Math.max(28, Math.round(root.menuY))
                    color: root.dark ? Qt.rgba(0.14, 0.14, 0.16, 0.92) : Qt.rgba(0.97, 0.97, 0.98, 0.95)
                    border.width: 1
                    border.color: root.dark ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(0, 0, 0, 0.10)

                    Column {
                        id: menuCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 6
                        spacing: 2

                        Repeater {
                            model: ["floating", "dwindle", "scrolling"]
                            delegate: Rectangle {
                                required property string modelData
                                readonly property bool selected: root.modeFor(root.menuWorkspace) === modelData
                                width: menuCol.width
                                height: 28
                                radius: 8
                                color: itemMa.containsMouse
                                    ? (root.dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.08))
                                    : "transparent"

                                Row {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 8

                                    SilkyWorkspaceLayoutIcon {
                                        width: 14
                                        height: 14
                                        anchors.verticalCenter: parent.verticalCenter
                                        mode: modelData
                                        color: root.dark ? "#f5f5f7" : "#1c1c1e"
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: root.modeLabel(modelData)
                                        color: root.dark ? "#ffffff" : "#1c1c1e"
                                        font.pixelSize: 13
                                        font.weight: selected ? Font.DemiBold : Font.Normal
                                    }
                                }

                                Text {
                                    visible: selected
                                    anchors.right: parent.right
                                    anchors.rightMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "✓"
                                    color: root.dark ? "#ffffff" : "#1c1c1e"
                                    font.pixelSize: 12
                                    font.weight: Font.Bold
                                }

                                MouseArea {
                                    id: itemMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: root.setWorkspaceMode(root.menuWorkspace, modelData)
                                }
                            }
                        }

                        Rectangle {
                            width: menuCol.width - 12
                            height: 1
                            anchors.horizontalCenter: parent.horizontalCenter
                            color: root.dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.10)
                        }

                        Rectangle {
                            width: menuCol.width
                            height: 28
                            radius: 8
                            color: resetMa.containsMouse
                                ? (root.dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.08))
                                : "transparent"

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                text: root.chinese ? "全部恢复浮动" : "Reset All to Floating"
                                color: root.dark ? "#ffffff" : "#1c1c1e"
                                font.pixelSize: 13
                            }

                            MouseArea {
                                id: resetMa
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: root.resetAllFloating(root.menuMonitor)
                            }
                        }
                    }
                }
            }
        }
    }
}
