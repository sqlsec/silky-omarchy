        // ── Network ──
        Component {
            id: paneNetwork
            Column {
                id: netPane
                spacing: 10
                property var services: []
                property var vpns: []
                property string busyId: ""
                property string busyOp: ""       // "connect" | "disconnect"
                property var errors: ({})

                readonly property string helperPath: Qt.resolvedUrl("assets/silky-network.py").toString().replace(/^file:\/\//, "")

                function paneIndex(paneId) {
                    for (var i = 0; i < prefsWindow.panes.length; i++) {
                        if (prefsWindow.panes[i].id === paneId) return i;
                    }
                    return -1;
                }

                function statusColor(kind) {
                    if (kind === "connected") return "#30D158";
                    if (kind === "connecting") return "#FF9F0A";
                    if (kind === "unplugged") return "#FF453A";
                    return pal.text3;
                }

                function serviceTitle(s) {
                    if (s.type === "wifi") return I18n.tr("Wi-Fi");
                    if (s.type === "ethernet") return I18n.tr("Ethernet");
                    return s.dev;
                }

                function serviceSubtitle(s) {
                    var st = s.statusKind === "connected" ? I18n.tr("Connected")
                        : s.statusKind === "connecting" ? I18n.tr("Connecting…")
                        : s.statusKind === "off" ? I18n.tr("Off")
                        : s.statusKind === "unplugged" ? I18n.tr("Cable unplugged")
                        : I18n.tr("Not Connected");
                    var parts = [st];
                    if (s.statusKind === "connected" && s.con) parts.push(s.con);
                    if (s.statusKind === "connected" && s.ip) parts.push(s.ip);
                    if (s.type === "ethernet" && s.statusKind === "connected" && parseInt(s.speed) > 0)
                        parts.push(s.speed + I18n.tr(" Mb/s"));
                    return parts.join(" · ");
                }

                function vpnStatusKind(v) {
                    if (busyId === v.id) return "connecting";
                    return v.statusKind;
                }

                function vpnSubtitle(v) {
                    var err = errors[v.id] || "";
                    if (err !== "") return err;
                    var st = busyId === v.id
                        ? (busyOp === "disconnect" ? I18n.tr("Disconnecting…") : I18n.tr("Connecting…"))
                        : v.statusKind === "connected" ? I18n.tr("Connected")
                        : v.statusKind === "connecting" ? I18n.tr("Connecting…")
                        : I18n.tr("Not Connected");
                    var parts = [st];
                    if (v.detail) parts.push(v.detail);
                    if (v.statusKind === "connected" && v.ip) parts.push(v.ip);
                    return parts.join(" · ");
                }

                function refresh() {
                    if (!netProc.running) netProc.running = true;
                }

                function toggleVpn(v, enable) {
                    if (!v || !v.controllable || vpnAct.running) return;
                    var nextErr = Object.assign({}, errors);
                    delete nextErr[v.id];
                    errors = nextErr;
                    busyId = v.id;
                    busyOp = enable ? "connect" : "disconnect";
                    if (v.backend === "nm" && v.uuid) {
                        vpnAct.command = ["nmcli", "connection", enable ? "up" : "down", "uuid", v.uuid];
                        vpnAct.running = true;
                    } else if (v.backend === "tailscale") {
                        vpnAct.command = ["tailscale", enable ? "up" : "down"];
                        vpnAct.running = true;
                    } else {
                        busyId = "";
                        busyOp = "";
                    }
                }

                Component.onCompleted: refresh()
                Timer { interval: 4000; repeat: true; running: prefsWindow.visible; onTriggered: netPane.refresh() }

                Process {
                    id: netProc
                    command: ["python3", "-I", netPane.helperPath]
                    stdout: StdioCollector {
                        onStreamFinished: {
                            try {
                                var data = JSON.parse(text);
                                netPane.services = data.services || [];
                                netPane.vpns = data.vpns || [];
                            } catch (e) {}
                        }
                    }
                }

                Process {
                    id: vpnAct
                    property string errText: ""
                    stderr: StdioCollector { onStreamFinished: vpnAct.errText = text.trim() }
                    onExited: (code) => {
                        if (code !== 0 && netPane.busyId !== "") {
                            var nextErr = Object.assign({}, netPane.errors);
                            nextErr[netPane.busyId] = vpnAct.errText !== ""
                                ? vpnAct.errText.split("\n")[0]
                                : (netPane.busyOp === "disconnect" ? I18n.tr("Could not disconnect VPN") : I18n.tr("Could not connect VPN"));
                            netPane.errors = nextErr;
                        }
                        vpnAct.errText = "";
                        netPane.busyId = "";
                        netPane.busyOp = "";
                        netPane.refresh();
                    }
                }

                // Primary network services (Wi-Fi, Ethernet)
                SCard {
                    t: pal
                    visible: netPane.services.length > 0
                    Repeater {
                        model: netPane.services
                        delegate: Item {
                            id: svcRow
                            required property var modelData
                            required property int index
                            readonly property bool clickable: modelData.type === "wifi"
                            readonly property bool active: modelData.statusKind === "connected"
                            width: parent ? parent.width : 0
                            height: Math.max(54, svcCol.implicitHeight + 20)

                            Rectangle {
                                visible: svcRow.index > 0
                                x: 54; width: parent.width - 68; height: 1
                                color: pal.sep
                            }
                            Rectangle {
                                visible: svcRow.clickable && svcMa.containsMouse
                                anchors.fill: parent; anchors.margins: 4
                                radius: 18
                                color: svcMa.pressed ? pal.selInactive : pal.hover
                            }
                            Rectangle {
                                x: 14; anchors.verticalCenter: parent.verticalCenter
                                width: 28; height: 28; radius: 7
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: svcRow.active ? "#3D9BFF" : (pal.dark ? "#545458" : "#AEAEB2") }
                                    GradientStop { position: 1.0; color: svcRow.active ? "#0A6CFF" : (pal.dark ? "#3A3A3C" : "#8E8E93") }
                                }
                                WGlyph {
                                    anchors.centerIn: parent; width: 16; height: 16
                                    kind: svcRow.modelData.type === "wifi" ? "wifi" : "ethernet"
                                    color: "white"
                                }
                            }
                            Column {
                                id: svcCol
                                x: 54
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.max(0, parent.width - x - (svcRow.clickable ? 38 : 20))
                                spacing: 3
                                Text {
                                    width: parent.width
                                    text: netPane.serviceTitle(svcRow.modelData)
                                    elide: Text.ElideRight
                                    color: pal.text
                                    font.family: root.fontForWeight(Font.Normal, pal.fam); font.pixelSize: 13
                                }
                                Row {
                                    width: parent.width
                                    spacing: 6
                                    Rectangle {
                                        width: 8; height: 8; radius: 4
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: netPane.statusColor(svcRow.modelData.statusKind)
                                    }
                                    Text {
                                        width: Math.max(0, parent.width - 14)
                                        text: netPane.serviceSubtitle(svcRow.modelData)
                                        elide: Text.ElideRight
                                        color: pal.text2
                                        font.family: root.fontForWeight(Font.Normal, pal.fam); font.pixelSize: 12
                                    }
                                }
                            }
                            WGlyph {
                                visible: svcRow.clickable
                                anchors.right: parent.right; anchors.rightMargin: 16
                                anchors.verticalCenter: parent.verticalCenter
                                width: 12; height: 12
                                kind: "chevR"
                                color: pal.text3
                            }
                            MouseArea {
                                id: svcMa
                                anchors.fill: parent
                                enabled: svcRow.clickable
                                hoverEnabled: svcRow.clickable
                                cursorShape: svcRow.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: {
                                    var idx = netPane.paneIndex("wifi");
                                    if (idx >= 0) prefsWindow.go(idx);
                                }
                            }
                        }
                    }
                }

                // VPN & virtual tunnel services
                SLabel {
                    t: pal
                    header: true
                    visible: netPane.vpns.length > 0
                    text: I18n.tr("VPN")
                }
                SCard {
                    t: pal
                    visible: netPane.vpns.length > 0
                    Repeater {
                        model: netPane.vpns
                        delegate: Item {
                            id: vpnRow
                            required property var modelData
                            required property int index
                            readonly property string stKind: netPane.vpnStatusKind(modelData)
                            readonly property bool up: modelData.statusKind === "connected"
                            readonly property bool busy: netPane.busyId === modelData.id
                            readonly property bool hasErr: (netPane.errors[modelData.id] || "") !== ""
                            width: parent ? parent.width : 0
                            height: Math.max(54, vpnCol.implicitHeight + 20)

                            Rectangle {
                                visible: vpnRow.index > 0
                                x: 54; width: parent.width - 68; height: 1
                                color: pal.sep
                            }
                            Rectangle {
                                x: 14; anchors.verticalCenter: parent.verticalCenter
                                width: 28; height: 28; radius: 7
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: vpnRow.up ? "#5E5CE6" : (pal.dark ? "#545458" : "#AEAEB2") }
                                    GradientStop { position: 1.0; color: vpnRow.up ? "#3634A3" : (pal.dark ? "#3A3A3C" : "#8E8E93") }
                                }
                                WGlyph {
                                    anchors.centerIn: parent; width: 15; height: 15
                                    kind: "lock"
                                    color: "white"
                                }
                            }
                            Column {
                                id: vpnCol
                                x: 54
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.max(0, parent.width - x - vpnCtrl.width - 28)
                                spacing: 3
                                Text {
                                    width: parent.width
                                    text: vpnRow.modelData.name
                                    elide: Text.ElideRight
                                    color: pal.text
                                    font.family: root.fontForWeight(Font.Normal, pal.fam); font.pixelSize: 13
                                }
                                Row {
                                    width: parent.width
                                    spacing: 6
                                    Rectangle {
                                        width: 8; height: 8; radius: 4
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: vpnRow.hasErr ? "#FF453A" : netPane.statusColor(vpnRow.stKind)
                                    }
                                    Text {
                                        width: Math.max(0, parent.width - 14)
                                        text: netPane.vpnSubtitle(vpnRow.modelData)
                                        elide: Text.ElideRight
                                        color: vpnRow.hasErr ? "#FF453A" : pal.text2
                                        font.family: root.fontForWeight(Font.Normal, pal.fam); font.pixelSize: 12
                                    }
                                }
                            }
                            Item {
                                id: vpnCtrl
                                anchors.right: parent.right; anchors.rightMargin: 14
                                anchors.verticalCenter: parent.verticalCenter
                                width: vpnRow.modelData.controllable ? vpnSw.width : extLbl.implicitWidth
                                height: vpnRow.modelData.controllable ? vpnSw.height : extLbl.implicitHeight

                                SSwitch {
                                    id: vpnSw
                                    visible: vpnRow.modelData.controllable
                                    enabled: !vpnRow.busy && !vpnAct.running
                                    opacity: enabled ? 1.0 : 0.6
                                    t: pal
                                    checked: vpnRow.busy ? (netPane.busyOp === "connect") : vpnRow.up
                                    onToggled: v => netPane.toggleVpn(vpnRow.modelData, v)
                                }
                                Text {
                                    id: extLbl
                                    visible: !vpnRow.modelData.controllable
                                    text: I18n.tr("Managed by app")
                                    color: pal.text3
                                    font.family: root.fontForWeight(Font.Normal, pal.fam); font.pixelSize: 12
                                }
                            }
                        }
                    }
                }
            }
        }
