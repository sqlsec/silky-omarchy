import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

Scope {
    id: root
    property string address: ""
    property string output: ""
    property point origin
    property var availablePlacements: []
    readonly property var target: Hyprland.toplevels.values.find(toplevel =>
        String(toplevel.address).replace(/^0x/, "") === address.replace(/^0x/, ""))
    readonly property bool fullscreen: (target?.lastIpcObject?.fullscreen ?? 0) >= 2
    readonly property var active: Hyprland.activeToplevel
    readonly property var activeInfo: active?.lastIpcObject
    readonly property var fullscreenApps: ["foot", "omacalc", "omacut", "omaview", "omawrite", "io.github.elberacasa.omalogi"]
    required property bool light
    required property string language
    readonly property bool chinese: (language === "auto" ? Qt.locale().name : language).startsWith("zh")
    readonly property color foreground: light ? "#242428" : "#f2f2f7"
    readonly property color background: light ? "#f7f7f8" : "#2b2b2e"
    property bool opened: false

    // The bar's global coordinates are resolved in the compositor before sending the event.
    function dispatch(action, args) {
        Hyprland.dispatch("function() o.silky_foot_" + action + "(" + args.map(arg => JSON.stringify(arg)).join(",") + ") end")
    }
    function windowId(value) {
        const hex = String(value).replace(/^0x/, "")
        return /^[0-9a-f]+$/.test(hex) ? "0x" + hex : ""
    }

    function openMenu(windowAddress, screenName, x, y, placements) {
        address = windowId(windowAddress)
        if (!address)
            return
        output = screenName
        origin = Qt.point(x, y)
        availablePlacements = placements
        opened = true
    }

    function choose(action) {
        opened = false
        if (action === "fullscreen")
            dispatch(action, [address])
        else
            dispatch("place", [address, action, output])
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "fullscreen")
                Hyprland.refreshToplevels()
            if (root.opened && (event.name === "workspacev2" ||
                (event.name === "closewindow" && root.windowId(event.data) === root.address)))
                root.opened = false
            if (event.name !== "custom")
                return
            const fields = event.data.split(",")
            switch (fields[0]) {
            case "silky-foot-menu":
                if (fields.length !== 5 || !/^0x[0-9a-f]+$/.test(fields[1]))
                    return
                root.dispatch("menu", [fields[1], fields[2], Number(fields[3]), Number(fields[4])])
                break
            case "silky-window-menu":
                if (fields.length >= 5)
                    root.openMenu(fields[1], fields[2], Number(fields[3]), Number(fields[4]), fields.slice(5))
                break
            case "silky-foot-action":
                if (fields.length === 3)
                    root.dispatch("fullscreen", [fields[1]])
                break
            case "silky-foot-snap":
                root.dispatch("preview", fields.length === 4 ? fields.slice(1) : [])
                break
            case "silky-foot-drop":
                if (fields.length === 4)
                    root.dispatch("place", [fields[1], fields[3], fields[2]])
                root.dispatch("preview", [])
                break
            }
        }
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: fullBar
            required property var modelData
            screen: modelData
            visible: root.fullscreenApps.includes(root.activeInfo?.class) && root.activeInfo.fullscreen >= 2
                && root.activeInfo.monitor === Hyprland.monitorFor(modelData)?.id && !root.opened
            anchors { top: true; left: true }
            implicitWidth: 112
            implicitHeight: 44
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            mask: Region { item: inputRegion }
            WlrLayershell.namespace: "silky-foot-fullscreen"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Item {
                id: inputRegion
                width: fullBar.width
                height: hover.hovered ? fullBar.height : 4
                HoverHandler { id: hover }

                Rectangle {
                    anchors.fill: parent
                    visible: hover.hovered
                    color: root.background
                    radius: 10

                    Row {
                        anchors.centerIn: parent
                        spacing: 8
                        HoverHandler { id: controlsHover }
                        Repeater {
                            model: ["#ff5f57", root.light ? "#ababac" : "#686868", "#28c840"]
                            delegate: AbstractButton {
                                id: light
                                required property string modelData
                                required property int index
                                implicitWidth: 12
                                implicitHeight: 12
                                padding: 0
                                enabled: index !== 1
                                text: index === 0 ? (root.chinese ? "关闭" : qsTr("Close"))
                                    : (root.chinese ? "退出全屏" : qsTr("Exit Full Screen"))
                                background: Rectangle { radius: 6; color: light.modelData }
                                contentItem: Item {
                                    Shape {
                                        anchors.centerIn: parent
                                        width: 8
                                        height: 8
                                        visible: light.enabled && (controlsHover.hovered || light.visualFocus)
                                        preferredRendererType: Shape.CurveRenderer
                                        ShapePath {
                                            fillColor: light.index === 2 ? "#bf004d00" : "transparent"
                                            strokeColor: light.index === 0 ? "#bf4d0000" : "transparent"
                                            strokeWidth: light.index === 0 ? 1.1 : 0
                                            capStyle: ShapePath.RoundCap
                                            PathSvg {
                                                path: light.index === 0
                                                    ? "M1.5 1.5L6.5 6.5 M6.5 1.5L1.5 6.5"
                                                    : "M3.75 3.75H0.55L3.75 0.55Z M4.25 4.25H7.45L4.25 7.45Z"
                                            }
                                        }
                                    }
                                }
                                hoverEnabled: true
                                property bool held: false
                                onPressed: held = false
                                onPressAndHold: {
                                    if (index === 2) {
                                        held = true
                                        showLayouts()
                                    }
                                }
                                onClicked: {
                                    if (held) return
                                    const address = root.windowId(root.active.address)
                                    if (!address) return
                                    if (index === 0)
                                        Hyprland.dispatch("hl.dsp.window.close({window=" + JSON.stringify("address:" + address) + "})")
                                    else
                                        root.dispatch("fullscreen", [address])
                                }
                                function showLayouts() {
                                    root.openMenu(String(root.active.address), fullBar.modelData.name, 12, 43, [])
                                }
                                TapHandler {
                                    enabled: light.index === 2
                                    acceptedButtons: Qt.RightButton
                                    onTapped: light.showLayouts()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: panel
            required property var modelData
            screen: modelData
            visible: root.opened && root.output === modelData.name
            color: "transparent"
            anchors { top: true; left: true; right: true; bottom: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "silky-foot-layout"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            onVisibleChanged: if (visible) full.forceActiveFocus(Qt.TabFocusReason)

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onClicked: root.opened = false
            }

            Rectangle {
                id: menu
                x: Math.max(6, Math.min(root.origin.x, panel.width - width - 6))
                y: Math.max(6, Math.min(root.origin.y, panel.height - height - 6))
                width: choices.implicitWidth + 16
                height: choices.implicitHeight + 16
                color: root.background
                border.color: Qt.alpha(root.foreground, 0.19)
                radius: 12

                MouseArea { anchors.fill: parent }

                ColumnLayout {
                    id: choices
                    anchors.centerIn: parent
                    spacing: 5

                    GridLayout {
                        columns: 4
                        rowSpacing: 3
                        columnSpacing: 3
                        Repeater {
                            model: [
                                { action: "left", label: root.chinese ? "左半屏" : qsTr("Left Half"), rect: Qt.rect(0, 0, 0.5, 1) },
                                { action: "right", label: root.chinese ? "右半屏" : qsTr("Right Half"), rect: Qt.rect(0.5, 0, 0.5, 1) },
                                { action: "top", label: root.chinese ? "上半屏" : qsTr("Top Half"), rect: Qt.rect(0, 0, 1, 0.5) },
                                { action: "bottom", label: root.chinese ? "下半屏" : qsTr("Bottom Half"), rect: Qt.rect(0, 0.5, 1, 0.5) },
                                { action: "top-left", label: root.chinese ? "左上角" : qsTr("Top Left Quarter"), rect: Qt.rect(0, 0, 0.5, 0.5) },
                                { action: "top-right", label: root.chinese ? "右上角" : qsTr("Top Right Quarter"), rect: Qt.rect(0.5, 0, 0.5, 0.5) },
                                { action: "bottom-left", label: root.chinese ? "左下角" : qsTr("Bottom Left Quarter"), rect: Qt.rect(0, 0.5, 0.5, 0.5) },
                                { action: "bottom-right", label: root.chinese ? "右下角" : qsTr("Bottom Right Quarter"), rect: Qt.rect(0.5, 0.5, 0.5, 0.5) }
                            ]
                            delegate: AbstractButton {
                                id: tile
                                required property var modelData
                                implicitWidth: 44
                                implicitHeight: 36
                                hoverEnabled: true
                                enabled: !root.fullscreen && root.availablePlacements.includes(modelData.action)
                                text: modelData.label
                                Accessible.name: text
                                onClicked: root.choose(modelData.action)
                                Keys.onReturnPressed: root.choose(modelData.action)
                                ToolTip.visible: hovered || visualFocus
                                ToolTip.delay: 550
                                ToolTip.text: text
                                background: Rectangle {
                                    radius: 7
                                    color: tile.hovered || tile.down || tile.visualFocus ? "#343b9eff" : "transparent"
                                }
                                contentItem: Item {
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 24
                                        height: 17
                                        radius: 3
                                        color: "transparent"
                                        border.color: root.foreground
                                        opacity: tile.enabled ? 1 : 0.35
                                        Rectangle {
                                            readonly property rect area: tile.modelData.rect
                                            x: 3 + 18 * area.x
                                            y: 3 + 11 * area.y
                                            width: 18 * area.width
                                            height: 11 * area.height
                                            radius: 1
                                            color: root.foreground
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 1
                        color: Qt.alpha(root.foreground, 0.14)
                    }

                    AbstractButton {
                        id: full
                        Layout.fillWidth: true
                        implicitHeight: 30
                        hoverEnabled: true
                        text: root.fullscreen ? (root.chinese ? "退出全屏" : qsTr("Exit Full Screen"))
                            : (root.chinese ? "进入全屏" : qsTr("Full Screen"))
                        onClicked: root.choose("fullscreen")
                        Keys.onReturnPressed: root.choose("fullscreen")
                        background: Rectangle {
                            radius: 7
                            color: full.hovered || full.down || full.visualFocus ? "#343b9eff" : "transparent"
                        }
                        contentItem: Text {
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            color: root.foreground
                            text: full.text
                        }
                    }
                }
            }

            Shortcut {
                enabled: panel.visible
                sequence: "Escape"
                onActivated: root.opened = false
            }
        }
    }

}
