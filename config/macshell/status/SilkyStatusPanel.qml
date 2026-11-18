import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import "SilkyStatusFormat.js" as Status

Item {
    id: root
    required property string mode
    required property var palette
    required property var summary
    required property var battery
    required property real charge
    property bool active: false
    // the menu-bar battery's number (MacShell's showBatteryPercent); toggled from the right-click power-mode panel
    property bool showPercent: true
    signal dismiss()
    signal togglePercent()
    readonly property real preferredHeight: Math.ceil(header.height + content.implicitHeight + 27)
    readonly property string title: mode === "network" ? Status.tr("Network")
                                    : mode === "thermal" ? Status.tr("CPU Temperature")
                                    : mode === "profiles" ? Status.tr("Power mode") : Status.tr("Power & Battery")

    onModeChanged: {
        if (flick)
            flick.contentY = 0;
        copiedAddress = "";
        profileFailed = false;
    }
    property string copiedAddress: ""

    function metric(label, value) {
        return {"label": label, "value": value};
    }

    readonly property color downloadColor: palette.dark ? "#58dcf0" : "#00778a"
    readonly property color uploadColor: palette.dark ? "#bba4ff" : "#6743a5"
    readonly property color thermalColor: palette.dark ? "#ffb36d" : "#a8551a"
    readonly property bool batteryPowered: power.sample?.onBattery ?? UPower.onBattery
    // Four power states, shared with the menu-bar battery. Color marks only what is worth noticing: charging green,
    // external power without charging (e.g. held at the charge limit) a calm blue, on battery neutral like macOS,
    // low battery red. Charging wins over low so a plugged-in low battery shows it is recovering.
    readonly property color batteryColor: palette.dark ? "#e6e8ef" : "#3b4252"
    readonly property color chargingColor: palette.dark ? "#72e5a7" : "#167748"
    readonly property color externalColor: palette.dark ? "#6cb8ff" : "#0b62c4"
    readonly property color lowColor: palette.dark ? "#ff8279" : "#a62b25"
    // the power chart is data, not state: its own hue so it never reads as a warning
    readonly property color powerPlotColor: palette.dark ? "#b9a6ff" : "#5f43b2"
    readonly property bool batteryCharging: primaryBattery ? primaryBattery.status === "Charging"
                                                           : battery?.state === UPowerDeviceState.Charging
    readonly property string powerState: batteryCharging ? "charging" : charge < 20 ? "low"
                                         : batteryPowered ? "battery" : "external"
    readonly property color powerColor: powerState === "charging" ? chargingColor : powerState === "low" ? lowColor
                                        : powerState === "battery" ? batteryColor : externalColor
    readonly property string powerStateText: powerState === "charging" ? "Charging"
                                             : batteryPowered ? "On battery" : "External power"
    readonly property color panelTint: palette.dark ? "#14151b" : "#f2f4f9"
    readonly property color surface: palette.dark ? Qt.rgba(0.09, 0.10, 0.13, 0.45)
                                                  : Qt.rgba(1, 1, 1, 0.46)
    readonly property color outline: palette.dark ? Qt.rgba(1, 1, 1, 0.14)
                                                  : Qt.rgba(1, 1, 1, 0.74)
    readonly property color divider: palette.dark ? Qt.rgba(1, 1, 1, 0.13)
                                                  : Qt.rgba(0.15, 0.18, 0.24, 0.13)
    readonly property color muted: palette.dark ? "#d6d9e2" : "#42495a"
    readonly property color accent: mode === "network" ? downloadColor : mode === "thermal" ? thermalColor : powerColor
    readonly property string iconKind: mode === "network" ? "network" : mode === "thermal" ? "thermal" : mode === "profiles" ? "power" : "battery"
    readonly property var primaryBattery: power.sample?.batteries[0]

    function batteryFlow(device) {
        if (device?.status === "Charging")
            return "Charging power";
        if (device?.status === "Discharging")
            return "Discharging power";
        return "";
    }
    readonly property var chargeLimit: primaryBattery?.limit
    // Whole-system power. Only measurable on battery: the discharge rate is everything the laptop draws. On external
    // power (Snapdragon X battmgr at least) neither the adapter input nor the system load is reported, so leave a gap.
    readonly property var powerHistory: (summary?.batteryPowerHistory || []).map(sample =>
        sample && sample[0] === "Discharging" && sample[2] !== false ? sample[1] : null)
    readonly property var powerSamples: powerHistory.filter(Number.isFinite)
    readonly property var systemPower: batteryPowered && primaryBattery?.status === "Discharging"
                                       ? primaryBattery.power_now : null
    property int draftLimit: 80
    property bool limitEdited: false
    property int pendingLimit: 0
    property bool chargeLimitFailed: false

    onChargeLimitChanged: {
        if (!chargeLimit)
            return;
        if (pendingLimit && chargeLimit.end === pendingLimit && !limitCall.running) {
            limitRefresh.stop();
            pendingLimit = 0;
            limitEdited = false;
        }
        if (!limitEdited && !pendingLimit)
            draftLimit = chargeLimit.end ?? 80;
    }

    function applyChargeLimit() {
        if (!chargeLimit || pendingLimit || draftLimit === chargeLimit.end)
            return;
        chargeLimitFailed = false;
        pendingLimit = draftLimit;
        const script = decodeURIComponent(Qt.resolvedUrl("assets/silky-status.py").toString().substring(7));
        limitCall.exec(["/usr/bin/python3", "-I", script, "set-charge-limit", String(pendingLimit)]);
    }

    Process {
        id: limitCall
        onExited: (code, status) => {
            if (status !== 0 || code !== 0) {
                root.chargeLimitFailed = true;
                root.pendingLimit = 0;
            } else if (root.chargeLimit?.end === root.pendingLimit) {
                root.pendingLimit = 0;
                root.limitEdited = false;
            } else if (!root.active || root.mode !== "power") {
                root.pendingLimit = 0;
                root.limitEdited = false;
            } else {
                limitRefresh.restart();
            }
        }
    }

    Timer {
        id: limitRefresh
        interval: 6500
        onTriggered: {
            root.chargeLimitFailed = root.active && root.mode === "power";
            root.pendingLimit = 0;
        }
    }

    readonly property var trends: summary && summary.trend ? summary.trend : ({})

    function tinted(base, color, strength, opacity) {
        return Qt.rgba(base.r + (color.r - base.r) * strength,
                       base.g + (color.g - base.g) * strength,
                       base.b + (color.b - base.b) * strength, opacity);
    }

    function networkGroups(data) {
        if (!data)
            return [];
        const addresses = data.addresses.map(item => ({
            "label": item[0],
            "badge": item[1] === "inet" ? "IPv4" : "IPv6",
            "value": item[2],
            "copy": true
        }));
        const peak = data.apps.length ? data.apps[0][1][0] + data.apps[0][1][1] : 0;
        const apps = data.apps.map(item => ({
            "label": item[0],
            "down": Status.rate(item[1][0], true),
            "up": Status.rate(item[1][1], true),
            "downWeight": item[1][0] / peak,
            "upWeight": item[1][1] / peak
        }));
        return [
            { "title": Status.tr("Local IP addresses"), "icon": "network", "rows": addresses,
              "hint": addresses.length ? "" : Status.tr("No active address") },
            { "title": Status.tr("Top apps by traffic"), "icon": "apps", "rows": apps,
              "hint": apps.length ? "" : Status.tr(data.sampling ? "Sampling traffic…" : "No TCP traffic in this sample"),
              "note": Status.tr("Current user’s TCP traffic · Proxied traffic may show under the proxy") }
        ];
    }

    function thermalGroups(data) {
        if (!data)
            return [];
        const sections = [];
        if (data.overview.length) {
            const hardware = data.overview.map(item => metric(Status.tr(item[0]),
                                    Status.quantity(item[1], item[2], item[2] === "RPM" ? 0 : 1)));
            sections.push({ "title": Status.tr("Hardware overview"), "icon": "thermal", "rows": hardware });
        }
        sections.push({ "rows": [], "gauges": [
            { "label": Status.tr("CPU usage"), "value": data.usage?.cpu, "color": thermalColor },
            { "label": Status.tr("Memory usage"), "value": data.usage?.memory, "color": uploadColor },
            { "label": Status.tr("System disk usage"), "value": data.usage?.disk, "color": downloadColor }
        ] });
        const processes = data.cpuTop.map(item => ({
            "label": item[1],
            "pid": item[0],
            "value": Status.quantity(item[2], "%", 1),
            "cpuLoad": Math.min(item[2] / 100, 1)
        }));
        sections.push({
            "title": Status.tr("Top 10 by CPU usage"), "icon": "chip", "rows": processes,
            "hint": processes.length ? "" : Status.tr(data.sampling ? "Sampling CPU usage…" : "No active processes in this sample"),
            "note": processes.length ? Status.tr("100% = one logical core") : ""
        });
        return sections;
    }

    function batteryRows(data) {
        var values = [
            metric(Status.tr("Status"), Status.tr(data.status)),
            metric(Status.tr("Model"), [data.manufacturer, data.model_name].filter(Boolean).join(" ")),
            metric(Status.tr("Technology"), data.technology)
        ];
        const flow = batteryFlow(data);
        const toFull = data.status === "Charging";
        const showTime = toFull || (batteryPowered && data.status === "Discharging");
        if (battery && power.sample.batteries.length === 1 && showTime) {
            let seconds = toFull ? battery.timeToFull : battery.timeToEmpty;
            if (seconds <= 0 && data.power_now > 0 && data.energy_now !== null) {
                const wattHours = toFull ? data.energy_full - data.energy_now : data.energy_now;
                seconds = wattHours > 0 ? wattHours / data.power_now * 3600 : 0;
            }
            if (seconds > 0)
                values.push(metric(Status.tr(toFull ? "Time to full" : "Time remaining"), Status.duration(seconds)));
        }
        var fields = [
            ["Health", data.health, "%", 1],
            ["Cycle count", data.cycle_count, "", 0],
            [flow || "Battery power", data.power_now, "W", 1],
            ["Voltage", data.voltage_now, "V", 2],
            ["Current", data.current_now, "A", 2],
            ["Temperature", data.temp, "°C", 1],
            ["Energy remaining", data.energy_now, "Wh", 2],
            ["Charge remaining", data.energy_now === null ? data.charge_now : null, "Ah", 2],
            ["Full charge capacity", data.energy_full ?? data.charge_full, data.energy_full === null ? "Ah" : "Wh", 2],
            ["Design capacity", data.energy_full_design ?? data.charge_full_design, data.energy_full_design === null ? "Ah" : "Wh", 2],
            ["Start charging below", data.charge_control_start_threshold || null, "%", 0],
            ["Stop charging at", data.limit ? null : data.charge_control_end_threshold || null, "%", 0]
        ];
        return values.concat(fields.map(field => metric(Status.tr(field[0]),
                             Status.quantity(field[1], field[2], field[3]).trim()))).filter(row => row.value !== "");
    }

    function powerGroups(data) {
        if (!data)
            return [];
        var connected = batteryPowered ? [] : data.sources.filter(source => source.online);
        var sources = connected.map(source => {
            var values = [source.usbType, Status.quantity(source.voltage || null, "V", 2),
                          Status.quantity(source.current || null, "A", 2)];
            return metric(Status.tr(source.label), values.filter(Boolean).join(" · ") || Status.tr("Online"));
        });
        var supply = metric(Status.tr("Power source"), Status.tr(batteryPowered ? "On battery" : "External power"));
        var draw = metric(Status.tr("System power"), batteryPowered ? Status.quantity(systemPower, "W", 1)
                                                                    : Status.tr("Unavailable on external power"));
        var rows = [supply].concat(draw.value ? [draw] : [], sources);
        var groups = [{ "title": Status.tr("Power source"), "icon": "power", "rows": rows }];
        if (data.profile)
            groups[0].rows.push(metric(Status.tr("Power mode"), Status.tr(data.profile)));
        return groups.concat(data.batteries.map(item => ({
            "title": data.batteries.length === 1 ? Status.tr("Battery") : Status.tr("Battery") + " · " + item.name,
            "icon": "battery",
            "rows": batteryRows(item)
        })));
    }

    readonly property var groups: mode === "network" ? networkGroups(network.sample)
                                  : mode === "thermal" ? thermalGroups(temperature.sample)
                                  : mode === "power" ? powerGroups(power.sample) : []
    readonly property var profileChoices: [
        { "key": "power-saver", "icon": "battery" },
        { "key": "balanced", "icon": "activity" },
        { "key": "performance", "icon": "power" }
    ].filter(choice => profiles.sample?.available.includes(choice.key))
    property bool profileFailed: false

    function selectProfile(key) {
        if (profileCall.running || profiles.sample?.current === key
            || !profileChoices.some(choice => choice.key === key))
            return;
        profileFailed = false;
        profileCall.exec(["/usr/bin/omarchy-powerprofiles-set", "autodetect", key]);
    }

    Process {
        id: profileCall
        onExited: (code, status) => { root.profileFailed = code !== 0 || status !== 0; }
    }

    SilkyStatusStream { id: network; mode: "network"; active: root.active && root.mode === mode }
    SilkyStatusStream { id: temperature; mode: "thermal"; active: root.active && root.mode === mode }
    SilkyStatusStream { id: power; mode: "power"; active: root.active && root.mode === mode }
    SilkyStatusStream { id: profiles; mode: "profiles"; active: root.active && root.mode === mode }

    component LabelText: Text {
        color: root.palette.fg
        font.family: root.palette.fam
        font.pixelSize: 13
        textFormat: Text.PlainText
    }

    Rectangle {
        anchors.fill: parent
        radius: 24
        gradient: Gradient {
            GradientStop {
                position: 0
                color: root.tinted(root.panelTint, root.accent, root.palette.dark ? 0.07 : 0.045,
                                   root.palette.dark ? 0.57 : 0.63)
            }
            GradientStop {
                position: 1
                color: root.tinted(root.panelTint, root.accent, 0.02, root.palette.dark ? 0.44 : 0.57)
            }
        }
    }

    RowLayout {
        id: header
        x: 16
        y: 12
        width: parent.width - 32
        height: 31
        spacing: 8

        SilkyStatusIcon {
            Layout.preferredWidth: 21
            Layout.preferredHeight: 21
            kind: root.iconKind
            ink: root.accent
        }
        LabelText {
            Layout.fillWidth: true
            text: root.title
            font.pixelSize: 17
            font.weight: Font.DemiBold
        }
        Rectangle {
            Layout.preferredWidth: 23
            Layout.preferredHeight: 23
            radius: width / 2
            color: closeMouse.containsMouse ? root.palette.hover : "transparent"
            Accessible.role: Accessible.Button
            Accessible.name: Status.tr("Close")
            Accessible.onPressAction: root.dismiss()
            SilkyStatusIcon { anchors.centerIn: parent; width: 13; height: 13; kind: "close"; ink: root.muted }
            MouseArea {
                id: closeMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.dismiss()
            }
        }
    }

    Flickable {
        id: flick
        x: 15
        y: header.y + header.height + 6
        width: parent.width - 24
        height: Math.max(0, parent.height - y - 12)
        clip: true
        contentWidth: width
        contentHeight: content.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar {
            policy: flick.interactive ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        }

        Column {
            id: content
            width: flick.width - 6
            spacing: 10

            Rectangle {
                visible: root.mode !== "profiles"
                radius: 12
                border.color: root.outline
                border.width: 1
                width: parent.width
                height: summaryContent.implicitHeight + 24
                gradient: Gradient {
                    GradientStop {
                        position: 0
                        color: root.tinted(root.panelTint, root.accent, root.palette.dark ? 0.16 : 0.09, 0.53)
                    }
                    GradientStop {
                        position: 1
                        color: root.tinted(root.panelTint, root.mode === "network" ? root.uploadColor : root.accent,
                                           0.07, 0.48)
                    }
                }

                Column {
                    id: summaryContent
                    x: 13
                    y: 12
                    width: parent.width - 26
                    spacing: 8

                    RowLayout {
                        width: parent.width
                        spacing: 14
                        SilkyStatusReading {
                            foreground: root.tinted(root.palette.fg, root.accent, 0.56, 1)
                            muted: root.muted
                            fontFamily: root.palette.fam
                            Layout.fillWidth: true
                            label: root.mode === "network" ? Status.tr("Download") : root.mode === "thermal"
                                   ? Status.tr("Hottest CPU sensor") : Status.tr("Battery charge")
                            symbol: root.mode === "network" ? "down" : root.iconKind
                            ink: root.accent
                            value: root.mode === "network" ? Status.rate(root.summary?.down, false)
                                 : root.mode === "thermal" ? Status.quantity(root.summary?.temp, "°C", 1) || "—"
                                 : Status.quantity(root.charge, "%", 0)
                        }
                        Rectangle {
                            visible: root.mode === "network"
                            Layout.preferredWidth: 1
                            Layout.preferredHeight: 31
                            color: root.divider
                        }
                        SilkyStatusReading {
                            foreground: root.tinted(root.palette.fg, root.uploadColor, 0.56, 1)
                            muted: root.muted
                            fontFamily: root.palette.fam
                            visible: root.mode === "network"
                            Layout.fillWidth: true
                            label: Status.tr("Upload")
                            symbol: "up"
                            ink: root.uploadColor
                            value: Status.rate(root.summary?.up, false)
                        }
                        SilkyStatusReading {
                            visible: root.mode === "power"
                            Layout.fillWidth: true
                            foreground: root.tinted(root.palette.fg, root.powerColor, 0.56, 1)
                            muted: root.muted
                            fontFamily: root.palette.fam
                            label: Status.tr("Power source")
                            symbol: "power"
                            ink: root.powerColor
                            value: Status.tr(root.batteryPowered ? "On battery" : "External power")
                        }
                        LabelText {
                            visible: root.mode === "power" && !!text
                            text: root.primaryBattery ? Status.tr(root.primaryBattery.status) : ""
                            color: root.powerColor
                            font.pixelSize: 11
                        }

                    }

                    SilkyStatusChart {
                        visible: root.active && root.mode !== "power"
                        width: parent.width
                        height: 43
                        thermal: root.mode === "thermal"
                        gridColor: root.divider
                        series: thermal ? [{ "values": root.trends.temp || [], "color": root.thermalColor }]
                            : [{ "values": root.trends.down || [], "color": root.downloadColor },
                               { "values": root.trends.up || [], "color": root.uploadColor }]
                    }
                    LabelText {
                        visible: root.mode !== "power"
                        width: parent.width
                        text: Status.tr("Last minute")
                        horizontalAlignment: Text.AlignRight
                        color: root.muted
                        font.pixelSize: 10
                    }
                    Rectangle {
                        visible: root.mode === "power"
                        width: parent.width
                        height: 6
                        radius: 3
                        color: root.divider
                        Rectangle {
                            width: parent.width * Math.max(0, Math.min(100, root.charge)) / 100
                            height: parent.height
                            radius: 3
                            color: root.powerColor
                        }
                    }
                }
            }

            Rectangle {
                visible: root.mode === "power"
                width: parent.width
                height: powerPlot.implicitHeight + 20
                radius: 12
                color: root.surface
                border.color: root.outline
                border.width: 1

                Column {
                    id: powerPlot
                    x: 11
                    y: 10
                    width: parent.width - 22
                    spacing: 6

                    RowLayout {
                        width: parent.width
                        spacing: 6
                        SilkyStatusIcon {
                            Layout.preferredWidth: 15
                            Layout.preferredHeight: 15
                            kind: "activity"
                            ink: root.powerPlotColor
                        }
                        LabelText {
                            Layout.fillWidth: true
                            text: Status.tr("System power")
                            font.weight: Font.DemiBold
                        }
                        LabelText {
                            visible: root.powerSamples.length > 0
                            text: Status.tr("Peak %1").replace("%1",
                                  Status.quantity(Math.max.apply(null, root.powerSamples), "W", 1))
                            color: root.powerPlotColor
                            font.pixelSize: 11
                        }
                    }
                    SilkyStatusChart {
                        visible: root.active && root.mode === "power" && root.powerSamples.length > 0
                        width: parent.width
                        height: 44
                        sampleCount: 100
                        minimumUpper: 5
                        gridColor: root.divider
                        series: [{ "values": root.powerHistory, "color": root.powerPlotColor }]
                    }
                    LabelText {
                        width: parent.width
                        text: Status.tr(root.powerSamples.length > 0 ? "Last 5 minutes · on battery"
                                        : root.batteryPowered ? "Waiting for power data…"
                                        : "Not reported on external power")
                        wrapMode: Text.Wrap
                        horizontalAlignment: root.powerSamples.length > 0 ? Text.AlignRight : Text.AlignLeft
                        color: root.muted
                        font.pixelSize: 10
                    }
                }
            }

            Rectangle {
                visible: root.mode === "power" && !!root.chargeLimit
                width: parent.width
                height: limitContent.implicitHeight + 20
                radius: 12
                color: root.surface
                border.color: root.outline
                border.width: 1

                ColumnLayout {
                    id: limitContent
                    x: 11
                    y: 10
                    width: parent.width - 22
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        SilkyStatusIcon {
                            Layout.preferredWidth: 15
                            Layout.preferredHeight: 15
                            kind: "battery"
                            ink: root.powerColor
                        }
                        LabelText {
                            Layout.fillWidth: true
                            text: Status.tr("Charge limit")
                            font.weight: Font.DemiBold
                        }
                        LabelText {
                            text: root.draftLimit + "%"
                            color: root.powerColor
                            font.weight: Font.DemiBold
                        }
                    }
                    Slider {
                        id: limitSlider
                        Layout.fillWidth: true
                        Layout.preferredHeight: 22
                        from: root.chargeLimit?.minimum ?? 55
                        to: root.chargeLimit?.maximum ?? 100
                        stepSize: 1
                        snapMode: Slider.SnapAlways
                        value: root.draftLimit
                        enabled: !root.pendingLimit
                        Accessible.name: Status.tr("Charge limit")
                        onMoved: {
                            root.limitEdited = true;
                            root.draftLimit = Math.round(value);
                            root.chargeLimitFailed = false;
                        }
                        background: Rectangle {
                            x: limitSlider.leftPadding
                            y: (limitSlider.height - height) / 2
                            width: limitSlider.availableWidth
                            height: 4
                            radius: 2
                            color: root.divider
                            Rectangle {
                                width: limitSlider.visualPosition * parent.width
                                height: parent.height
                                radius: 2
                                color: root.powerColor
                            }
                        }
                        handle: Rectangle {
                            x: limitSlider.leftPadding + limitSlider.visualPosition * (limitSlider.availableWidth - width)
                            y: (limitSlider.height - height) / 2
                            width: 13
                            height: 13
                            radius: width / 2
                            color: root.powerColor
                            border.color: root.outline
                            border.width: 1
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        LabelText {
                            Layout.fillWidth: true
                            text: root.chargeLimit?.end != null
                                ? Status.tr("Current limit %1").replace("%1", root.chargeLimit.end + "%")
                                : Status.tr("Current limit unavailable")
                            color: root.muted
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                        Button {
                            id: applyLimit
                            Layout.preferredHeight: 24
                            enabled: !root.pendingLimit && root.draftLimit !== root.chargeLimit?.end
                            text: Status.tr(root.pendingLimit ? "Applying…" : "Apply")
                            onClicked: root.applyChargeLimit()
                            contentItem: LabelText {
                                text: applyLimit.text
                                color: applyLimit.enabled ? root.powerColor : root.muted
                                font.pixelSize: 11
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle {
                                radius: 6
                                color: applyLimit.hovered ? root.palette.hover : root.divider
                            }
                        }
                    }
                    LabelText {
                        visible: root.chargeLimitFailed
                        Layout.fillWidth: true
                        text: Status.tr("Could not change the charge limit")
                        color: root.palette.dark ? "#ff9c94" : "#a62b25"
                        font.pixelSize: 11
                        wrapMode: Text.Wrap
                    }
                }
            }

            Rectangle {
                visible: root.mode === "profiles" && root.profileChoices.length > 0
                width: parent.width
                height: profileRows.implicitHeight + 10
                radius: 12
                color: root.surface
                border.color: root.outline
                border.width: 1

                Column {
                    id: profileRows
                    x: 5
                    y: 5
                    width: parent.width - 10
                    Repeater {
                        model: root.profileChoices
                        delegate: Rectangle {
                            id: profileRow
                            required property var modelData
                            readonly property bool selected: profiles.sample?.current === modelData.key
                            width: profileRows.width
                            height: 31
                            radius: 7
                            color: profileMouse.containsMouse ? root.palette.hover : "transparent"
                            Accessible.role: Accessible.RadioButton
                            Accessible.checked: selected
                            Accessible.name: Status.tr(modelData.key)
                            Accessible.onPressAction: root.selectProfile(modelData.key)

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 9
                                anchors.rightMargin: 9
                                spacing: 7
                                SilkyStatusIcon {
                                    Layout.preferredWidth: 15
                                    Layout.preferredHeight: 15
                                    kind: profileRow.modelData.icon
                                    ink: profileRow.selected ? root.accent : root.muted
                                }
                                LabelText {
                                    Layout.fillWidth: true
                                    text: Status.tr(profileRow.modelData.key)
                                }
                                SilkyStatusIcon {
                                    visible: profileRow.selected
                                    Layout.preferredWidth: 15
                                    Layout.preferredHeight: 15
                                    kind: "check"
                                    ink: root.accent
                                }
                            }

                            MouseArea {
                                id: profileMouse
                                anchors.fill: parent
                                enabled: !profileCall.running
                                hoverEnabled: enabled
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.selectProfile(profileRow.modelData.key)
                            }
                        }
                    }
                }
            }

            // right-click on the battery: show / hide the number inside the menu-bar battery
            Rectangle {
                visible: root.mode === "profiles"
                width: parent.width
                height: 41
                radius: 12
                color: root.surface
                border.color: root.outline
                border.width: 1
                Accessible.role: Accessible.CheckBox
                Accessible.checked: root.showPercent
                Accessible.name: Status.tr("Show battery percentage")
                Accessible.onPressAction: root.togglePercent()

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 5
                    radius: 7
                    color: percentMouse.containsMouse ? root.palette.hover : "transparent"
                }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 12
                    spacing: 7
                    SilkyStatusIcon {
                        Layout.preferredWidth: 15
                        Layout.preferredHeight: 15
                        kind: "battery"
                        ink: root.muted
                    }
                    LabelText {
                        Layout.fillWidth: true
                        text: Status.tr("Show battery percentage")
                    }
                    // macOS-style switch
                    Rectangle {
                        Layout.preferredWidth: 30
                        Layout.preferredHeight: 18
                        radius: 9
                        color: root.showPercent ? root.palette.accent
                                                : (root.palette.dark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.14))
                        Behavior on color { ColorAnimation { duration: 160 } }
                        Rectangle {
                            width: 14; height: 14; radius: 7
                            y: 2
                            x: root.showPercent ? parent.width - width - 2 : 2
                            color: "white"
                            Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        }
                    }
                }
                MouseArea {
                    id: percentMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.togglePercent()
                }
            }

            LabelText {
                width: parent.width
                visible: root.mode === "profiles" && (root.profileChoices.length === 0
                                                      || root.profileFailed || profileCall.running)
                text: Status.tr(profileCall.running ? "Applying…" : root.profileFailed ? "Could not change the power mode"
                    : profiles.sample ? "No power modes available" : "Reading…")
                color: root.muted
                wrapMode: Text.Wrap
            }

            LabelText {
                width: parent.width
                visible: root.mode !== "profiles" && root.groups.length === 0
                text: Status.tr("Reading…")
                color: root.muted
            }

            Repeater {
                model: root.groups.length
                Rectangle {
                    id: card
                    radius: 12
                    color: root.surface
                    border.color: root.outline
                    border.width: 1
                    required property int index
                    readonly property var section: root.groups[index]
                    width: content.width
                    height: sectionContent.implicitHeight + 16

                    Column {
                        id: sectionContent
                        x: 11
                        y: 8
                        width: parent.width - 22

                        RowLayout {
                            visible: !!card.section.title
                            width: parent.width
                            height: 26
                            spacing: 6
                            SilkyStatusIcon {
                                Layout.preferredWidth: 15
                                Layout.preferredHeight: 15
                                kind: card.section.icon || ""
                                ink: root.accent
                            }
                            LabelText {
                                Layout.fillWidth: true
                                text: card.section.title || ""
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                        }

                        RowLayout {
                            width: parent.width
                            visible: !!card.section.gauges
                            spacing: 6

                            Repeater {
                                model: card.section.gauges ? card.section.gauges.length : 0
                                delegate: ColumnLayout {
                                    id: gauge
                                    required property int index
                                    readonly property var reading: card.section.gauges[index]
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 1
                                    spacing: 5

                                    Item {
                                        Layout.alignment: Qt.AlignHCenter
                                        Layout.preferredWidth: Math.max(1, Math.min(67, (sectionContent.width - 12) / 3))
                                        Layout.preferredHeight: Layout.preferredWidth

                                        Canvas {
                                            id: ring
                                            anchors.fill: parent
                                            antialiasing: true
                                            readonly property real percent: gauge.reading.value ?? 0
                                            readonly property color ink: gauge.reading.color
                                            readonly property color trackColor: root.divider
                                            onPercentChanged: requestPaint()
                                            onInkChanged: requestPaint()
                                            onTrackColorChanged: requestPaint()
                                            onWidthChanged: requestPaint()
                                            onHeightChanged: requestPaint()

                                            onPaint: {
                                                const ctx = getContext("2d");
                                                ctx.reset();
                                                const half = width / 2;
                                                if (half <= 3)
                                                    return;
                                                const radius = half - 3;
                                                const start = -Math.PI / 2;
                                                ctx.lineWidth = 4;
                                                ctx.lineCap = "round";
                                                ctx.beginPath();
                                                ctx.arc(half, half, radius, start, start + Math.PI * 2);
                                                ctx.strokeStyle = trackColor;
                                                ctx.stroke();
                                                if (percent > 0) {
                                                    ctx.beginPath();
                                                    ctx.arc(half, half, radius, start, start + Math.PI * 2 * percent / 100);
                                                    ctx.strokeStyle = ink;
                                                    ctx.stroke();
                                                }
                                            }
                                        }

                                        LabelText {
                                            anchors.centerIn: parent
                                            text: Status.quantity(gauge.reading.value, "%", 0) || "—"
                                            font.pixelSize: 17
                                            font.weight: Font.DemiBold
                                        }
                                    }

                                    LabelText {
                                        Layout.fillWidth: true
                                        text: gauge.reading.label
                                        horizontalAlignment: Text.AlignHCenter
                                        color: root.muted
                                        elide: Text.ElideRight
                                        font.pixelSize: 11
                                    }
                                }
                            }
                        }

                        Repeater {
                            model: card.section.rows.length
                            Item {
                                id: row
                                required property int index
                                readonly property var entry: card.section.rows[index]
                                readonly property bool canCopy: entry.copy === true
                                readonly property bool app: entry.down !== undefined
                                readonly property bool cpu: entry.cpuLoad !== undefined
                                readonly property bool copied: canCopy && root.copiedAddress === entry.value
                                width: sectionContent.width
                                height: Math.max(app ? 33 : 25, line.implicitHeight + (app ? 10 : 7))

                                Rectangle {
                                    anchors.top: parent.top
                                    width: parent.width
                                    height: 1
                                    color: root.divider
                                }
                                Rectangle {
                                    anchors.fill: parent
                                    anchors.topMargin: 1
                                    radius: 4
                                    color: row.canCopy && rowMouse.containsMouse ? root.palette.hover : "transparent"
                                }
                                RowLayout {
                                    id: line
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.verticalCenterOffset: row.app ? -2 : 0
                                    spacing: 6
                                    LabelText {
                                        visible: row.cpu
                                        Layout.preferredWidth: 18
                                        text: row.index + 1
                                        color: root.thermalColor
                                        font.pixelSize: 10
                                    }
                                    LabelText {
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: row.canCopy ? 76 : implicitWidth
                                        text: row.entry.label
                                        color: root.muted
                                        font.pixelSize: 12
                                        elide: Text.ElideRight
                                    }
                                    LabelText {
                                        visible: row.canCopy
                                        text: row.entry.badge || ""
                                        color: root.downloadColor
                                        font.pixelSize: 9
                                    }
                                    LabelText {
                                        visible: row.cpu
                                        text: row.cpu ? "PID " + row.entry.pid : ""
                                        color: root.muted
                                        font.pixelSize: 10
                                    }
                                    Rectangle {
                                        visible: row.cpu
                                        Layout.preferredWidth: 50
                                        Layout.preferredHeight: 3
                                        radius: height / 2
                                        color: root.divider
                                        Rectangle {
                                            width: parent.width * (row.entry.cpuLoad || 0)
                                            height: parent.height
                                            radius: parent.radius
                                            color: root.thermalColor
                                        }
                                    }
                                    LabelText {
                                        visible: !row.app
                                        Layout.preferredWidth: row.cpu ? 48 : implicitWidth
                                        Layout.maximumWidth: line.width * (row.canCopy ? 0.67 : 0.55)
                                        text: row.entry.value || ""
                                        font.family: row.canCopy ? "monospace" : root.palette.fam
                                        font.pixelSize: row.canCopy ? 10 : 12
                                        horizontalAlignment: Text.AlignRight
                                        wrapMode: row.canCopy ? Text.WrapAnywhere : Text.NoWrap
                                        elide: row.canCopy ? Text.ElideNone : Text.ElideRight
                                    }
                                    SilkyStatusIcon {
                                        visible: row.canCopy
                                        Layout.preferredWidth: 12
                                        Layout.preferredHeight: 12
                                        kind: row.copied ? "check" : "copy"
                                        ink: row.copied ? root.powerColor : root.muted
                                        opacity: row.copied || rowMouse.containsMouse ? 1 : 0.55
                                    }
                                    LabelText {
                                        visible: row.app
                                        Layout.preferredWidth: 69
                                        horizontalAlignment: Text.AlignRight
                                        text: "↓ " + (row.entry.down || "")
                                        color: root.downloadColor
                                        font.pixelSize: 11
                                    }
                                    LabelText {
                                        visible: row.app
                                        Layout.preferredWidth: 69
                                        horizontalAlignment: Text.AlignRight
                                        text: "↑ " + (row.entry.up || "")
                                        color: root.uploadColor
                                        font.pixelSize: 11
                                    }
                                }
                                Row {
                                    visible: row.app
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: 5
                                    width: parent.width
                                    height: 2
                                    Rectangle { width: parent.width * (row.entry.downWeight || 0); height: 2; color: root.downloadColor; opacity: 0.64 }
                                    Rectangle { width: parent.width * (row.entry.upWeight || 0); height: 2; color: root.uploadColor; opacity: 0.64 }
                                }
                                MouseArea {
                                    id: rowMouse
                                    anchors.fill: parent
                                    enabled: row.canCopy
                                    hoverEnabled: enabled
                                    cursorShape: Qt.PointingHandCursor
                                    Accessible.role: Accessible.Button
                                    Accessible.name: Status.tr("Copy address") + " " + (row.entry.value || "")
                                    Accessible.ignored: !row.canCopy
                                    Accessible.onPressAction: copyAddress()
                                    function copyAddress() {
                                        Quickshell.execDetached(["wl-copy", "--", row.entry.value]);
                                        root.copiedAddress = row.entry.value;
                                    }
                                    onClicked: copyAddress()
                                }
                            }
                        }

                        LabelText {
                            width: parent.width
                            visible: !!card.section.hint
                            text: card.section.hint || ""
                            color: root.muted
                            font.pixelSize: 11
                            topPadding: 4
                            wrapMode: Text.Wrap
                        }
                        LabelText {
                            width: parent.width
                            visible: !!card.section.note
                            text: card.section.note || ""
                            color: root.muted
                            font.pixelSize: 10
                            topPadding: 5
                            wrapMode: Text.Wrap
                        }
                    }
                }
            }
        }
    }
}
