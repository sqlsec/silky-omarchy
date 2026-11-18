        // ── Displays ──
        Component {
            id: paneDisplays
            Column {
                id: dispPane
                spacing: 12
                property string selectedOutput: ""
                readonly property var monitors: displaySettings.monitors
                readonly property string mainOutput: displaySettings.primary || root.monitor
                readonly property var activeDisplay: monitors.find(m => m.name === selectedOutput)
                    || monitors.find(m => m.name === mainOutput) || monitors[0]
                readonly property bool mirrored: !!activeDisplay && !!activeDisplay.mirrorOf && activeDisplay.mirrorOf !== "none"
                readonly property var modes: DisplayModes.modesOf(activeDisplay)
                readonly property var resolutions: modes.filter((mode, index) =>
                    modes.findIndex(candidate => DisplayModes.resolution(candidate) === DisplayModes.resolution(mode)) === index)
                readonly property var rates: activeDisplay ? modes.filter(mode =>
                    mode.width === activeDisplay.width && mode.height === activeDisplay.height) : []
                readonly property var scales: DisplayModes.presets(activeDisplay)
                Component.onCompleted: displaySettings.refresh()

                SilkyDisplayArrangement {
                    id: arrangement
                    t: pal
                    monitors: dispPane.monitors
                    primary: dispPane.mainOutput || dispPane.monitors[0]?.name || ""
                    wallpaperFor: function(name, desktopBackground) {
                        const sources = root.wallpaperMap;
                        return sources["wallpaper.monitors." + name]
                            || (root.bar && (root.bar.wallpaperPath || root.bar.wallpaperVideo))
                            || desktopBackground || sources["wallpaper.last"] || sources["wallpaper.default"] || "";
                    }
                    onApplied: boxes => displaySettings.tryLayout(boxes)
                }

                SCard {
                    t: pal
                    visible: dispPane.monitors.length > 0
                    Item { width: 1; height: 10 }
                    Grid {
                        id: deviceGrid
                        x: 12
                        width: parent.width - 24
                        columns: Math.max(1, Math.min(dispPane.monitors.length, Math.floor(width / 116)))
                        spacing: 6
                        Repeater {
                            model: dispPane.monitors
                            Button {
                                id: displayButton
                                required property var modelData
                                readonly property bool selected: modelData.name === dispPane.activeDisplay?.name
                                readonly property bool builtIn: DisplayModes.isBuiltIn(modelData)
                                readonly property string deviceType: I18n.tr(builtIn ? "Built-in display" : "External display")
                                readonly property string modelName: DisplayModes.displayName(modelData, deviceType)
                                width: (deviceGrid.width - (deviceGrid.columns - 1) * deviceGrid.spacing) / deviceGrid.columns
                                height: 116
                                padding: 0
                                hoverEnabled: true
                                Accessible.name: modelName === deviceType ? modelName : modelName + " · " + deviceType
                                Accessible.checkable: true
                                Accessible.checked: selected
                                ToolTip.visible: hovered && modelLabel.truncated
                                ToolTip.delay: 450
                                ToolTip.text: modelName
                                onClicked: dispPane.selectedOutput = modelData.name
                                background: Rectangle {
                                    radius: 14
                                    color: displayButton.selected ? Qt.rgba(pal.accent.r, pal.accent.g, pal.accent.b, 0.11)
                                                                  : displayButton.hovered ? pal.hover : "transparent"
                                    border.width: displayButton.selected || displayButton.visualFocus ? 1 : 0
                                    border.color: displayButton.visualFocus ? pal.accent : Qt.rgba(pal.accent.r, pal.accent.g, pal.accent.b, 0.48)
                                }
                                contentItem: Column {
                                    topPadding: 9
                                    spacing: 3
                                    SilkyDisplayDevice {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: Math.min(125, displayButton.width - 14)
                                        height: 65
                                        builtIn: displayButton.builtIn
                                        aspect: {
                                            const m = displayButton.modelData;
                                            return m.transform % 2 ? m.height / m.width : m.width / m.height;
                                        }
                                    }
                                    Text {
                                        id: modelLabel
                                        x: 5
                                        width: parent.width - 10
                                        text: displayButton.modelName
                                        elide: Text.ElideRight
                                        horizontalAlignment: Text.AlignHCenter
                                        color: pal.text
                                        font.family: root.fontForWeight(Font.DemiBold, pal.fam)
                                        font.weight: Font.DemiBold
                                        font.pixelSize: 12
                                    }
                                    Text {
                                        x: 5
                                        width: parent.width - 10
                                        visible: displayButton.deviceType !== displayButton.modelName
                                        text: displayButton.deviceType
                                        elide: Text.ElideRight
                                        horizontalAlignment: Text.AlignHCenter
                                        color: pal.text2
                                        font.family: pal.fam
                                        font.pixelSize: 11
                                    }
                                }
                            }
                        }
                    }
                    Item {
                        width: parent.width
                        height: visible ? 42 : 0
                        visible: dispPane.monitors.filter(m => !m.mirrorOf || m.mirrorOf === "none").length > 1
                        SButton {
                            anchors.right: parent.right
                            anchors.rightMargin: 13
                            anchors.verticalCenter: parent.verticalCenter
                            t: pal
                            enabled: !displaySettings.busy
                            text: I18n.tr("Arrange…")
                            activeFocusOnTab: enabled
                            Accessible.role: Accessible.Button
                            Accessible.name: text
                            Accessible.onPressAction: if (enabled) arrangement.begin()
                            Keys.onReturnPressed: arrangement.begin()
                            Keys.onSpacePressed: arrangement.begin()
                            onClicked: arrangement.begin()
                        }
                    }
                    Item { width: 1; height: 10; visible: dispPane.monitors.length < 2 }
                }

                SLabel {
                    t: pal
                    visible: !dispPane.activeDisplay
                    text: I18n.tr("No displays detected.")
                }

                SCard {
                    t: pal
                    visible: displaySettings.preview !== null
                    SRow {
                        t: pal
                        title: I18n.tr("Keep these display settings?")
                        subtitle: I18n.tr("Reverting in %1 s").replace("%1", displaySettings.seconds)
                        Row {
                            spacing: 6
                            SButton { t: pal; text: I18n.tr("Revert"); onClicked: displaySettings.revert() }
                            SButton { t: pal; text: I18n.tr("Keep Changes"); onClicked: displaySettings.keep() }
                        }
                    }
                }

                SLabel {
                    t: pal
                    visible: displaySettings.error !== ""
                    color: pal.danger
                    text: I18n.tr(displaySettings.error)
                }

                SCard {
                    t: pal
                    visible: !!dispPane.activeDisplay && !dispPane.mirrored
                    Column {
                        width: parent.width
                        topPadding: 12
                        bottomPadding: 12
                        spacing: 9
                        SLabel { t: pal; x: 10; width: parent.width - 20; header: true; topPadding: 0; text: I18n.tr("Scale") }
                        Row {
                            id: scaleRow
                            x: 12
                            width: parent.width - 24
                            spacing: 4
                            Repeater {
                                model: dispPane.scales
                                SilkyScaleTile {
                                    required property real modelData
                                    t: pal
                                    width: (scaleRow.width - (dispPane.scales.length - 1) * scaleRow.spacing) / dispPane.scales.length
                                    height: 75
                                    enabled: !displaySettings.busy
                                    selected: !!dispPane.activeDisplay && Math.abs(dispPane.activeDisplay.scale - modelData) < 0.0001
                                    factor: (modelData - dispPane.scales[dispPane.scales.length - 1])
                                        / Math.max(0.01, dispPane.scales[0] - dispPane.scales[dispPane.scales.length - 1])
                                    text: Number((modelData * 100).toFixed(1)) + "%"
                                    ToolTip.visible: hovered
                                    ToolTip.delay: 450
                                    ToolTip.text: dispPane.activeDisplay
                                        ? I18n.tr("Looks like %1").replace("%1", DisplayModes.resolution(
                                            DisplayModes.logicalSize(dispPane.activeDisplay, modelData, dispPane.activeDisplay.transform))) : ""
                                    onClicked: displaySettings.tryChange(dispPane.activeDisplay.name, dispPane.activeDisplay, modelData)
                                }
                            }
                        }
                        Item {
                            x: 14
                            width: parent.width - 28
                            height: Math.max(larger.height, space.height)
                            Text {
                                id: larger
                                text: I18n.tr("Larger text")
                                color: pal.text2
                                font.family: pal.fam
                                font.pixelSize: 11
                            }
                            Text {
                                id: space
                                anchors.right: parent.right
                                text: I18n.tr("More space")
                                color: pal.text2
                                font.family: pal.fam
                                font.pixelSize: 11
                            }
                        }
                        SLabel {
                            t: pal
                            horizontalAlignment: Text.AlignHCenter
                            leftPadding: 0
                            color: pal.text
                            text: dispPane.activeDisplay ? I18n.tr("Looks like %1").replace("%1", DisplayModes.resolution(
                                DisplayModes.logicalSize(dispPane.activeDisplay, dispPane.activeDisplay.scale, dispPane.activeDisplay.transform))) : ""
                        }
                    }
                }

                SCard {
                    t: pal
                    visible: !!dispPane.activeDisplay
                    SRow {
                        t: pal
                        visible: dispPane.monitors.length > 1
                        title: I18n.tr("Main display")
                        subtitle: dispPane.activeDisplay && dispPane.activeDisplay.name === dispPane.mainOutput
                            ? I18n.tr("The Dock is shown on this display.") : ""
                        Loader {
                            active: !!dispPane.activeDisplay && dispPane.activeDisplay.name !== dispPane.mainOutput && !dispPane.mirrored
                            sourceComponent: SButton {
                                t: pal
                                enabled: !displaySettings.busy
                                text: I18n.tr("Set as main display")
                                onClicked: {
                                    displaySettings.setPrimary(dispPane.activeDisplay.name);
                                    root.monitor = dispPane.activeDisplay.name;
                                }
                            }
                        }
                    }
                    SRow {
                        t: pal
                        visible: dispPane.mirrored
                        title: I18n.tr("Mirrored display")
                        subtitle: {
                            const source = dispPane.monitors.find(m => m.name === dispPane.activeDisplay?.mirrorOf);
                            if (!source) return "";
                            const type = I18n.tr(DisplayModes.isBuiltIn(source) ? "Built-in display" : "External display");
                            return DisplayModes.displayName(source, type);
                        }
                    }
                    SRow {
                        t: pal
                        title: I18n.tr("Resolution")
                        visible: !dispPane.mirrored
                        SPopUp {
                            t: pal
                            width: Math.min(180, dispPane.width * 0.52)
                            enabled: !displaySettings.busy && model.length > 1
                            model: dispPane.resolutions.map(mode => DisplayModes.resolution(mode))
                            current: dispPane.resolutions.findIndex(mode => dispPane.activeDisplay
                                && mode.width === dispPane.activeDisplay.width && mode.height === dispPane.activeDisplay.height)
                            onPicked: index => {
                                const display = dispPane.activeDisplay;
                                const resolution = dispPane.resolutions[index];
                                const mode = dispPane.modes.filter(m => m.width === resolution.width && m.height === resolution.height)
                                    .reduce((best, m) => Math.abs(m.hz - display.refreshRate) < Math.abs(best.hz - display.refreshRate) ? m : best);
                                const scale = DisplayModes.validScale(mode, display.scale) ? display.scale
                                    : DisplayModes.closest(DisplayModes.availableScales(mode), display.scale);
                                displaySettings.tryChange(display.name, mode, scale);
                            }
                        }
                    }
                    SRow {
                        t: pal
                        title: I18n.tr("Refresh rate")
                        visible: !dispPane.mirrored
                        SPopUp {
                            t: pal
                            width: Math.min(180, dispPane.width * 0.52)
                            enabled: !displaySettings.busy && model.length > 1
                            model: dispPane.rates.map(mode => Number(mode.hz.toFixed(2)) + " Hz")
                            current: dispPane.rates.findIndex(mode => DisplayModes.matchesMode(dispPane.activeDisplay, mode))
                            onPicked: index => displaySettings.tryChange(dispPane.activeDisplay.name,
                                dispPane.rates[index], dispPane.activeDisplay.scale)
                        }
                    }
                }

                SCard {
                    t: pal
                    SRow {
                        t: pal; title: I18n.tr("Brightness")
                        SSlider { t: pal; resetValue: 0.5; value: root.bar ? root.bar.brightness : 0.5; onMoved: v => { if (root.bar) root.bar.setBrightness(v); } }
                    }
                    SRow {
                        t: pal; title: I18n.tr("Night Shift")
                        subtitle: I18n.tr("Warmer colours to reduce blue light")
                        SSwitch { t: pal; checked: root.bar ? root.bar.nightOn : false; onToggled: v => { if (root.bar) root.bar.nightOn = v; } }
                    }
                    SRow {
                        t: pal; title: I18n.tr("Colour Temperature"); visible: root.bar && root.bar.nightOn
                        SSlider {
                            t: pal; resetValue: 0.571; leftLabel: I18n.tr("Less Warm"); rightLabel: I18n.tr("More Warm")
                            value: root.bar ? 1 - (root.bar.nightTemp - 2500) / 3500 : 0.5
                            onMoved: v => { if (root.bar) root.bar.nightTemp = Math.round(2500 + (1 - v) * 3500); }
                        }
                    }
                }
            }
        }
