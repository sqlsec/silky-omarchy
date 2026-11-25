        // ── Trackpad ──
        Component {
            id: paneTrackpad
            Column {
                id: tpPane
                spacing: 12
                property int tab: root.bar ? root.bar.tpSettingsTab : 0
                property string currentGesture: tab === 1 ? "tp_natural_scroll" : (tab === 2 ? "tp_mission_control" : "tp_tap")
                property string currentCaption: tab === 1 ? I18n.tr("Natural scrolling") : (tab === 2 ? I18n.tr("Mission Control") : I18n.tr("Tap to click"))

                Connections {
                    target: root.bar
                    function onTpSettingsTabChanged() {
                        if (root.bar && tpPane.tab !== root.bar.tpSettingsTab) {
                            tpPane.tab = root.bar.tpSettingsTab;
                            tpPane.selectForTab(tpPane.tab);
                        }
                    }
                }

                function selectForTab(idx) {
                    if (idx === 0) {
                        currentGesture = "tp_tap";
                        currentCaption = I18n.tr("Tap to click");
                    } else if (idx === 1) {
                        currentGesture = "tp_natural_scroll";
                        currentCaption = I18n.tr("Natural scrolling");
                    } else {
                        currentGesture = "tp_mission_control";
                        currentCaption = I18n.tr("Mission Control");
                    }
                }

                function pickGesture(gid, label, shouldReplay) {
                    var changed = (currentGesture !== gid);
                    currentGesture = gid;
                    currentCaption = label;
                    if (!changed && shouldReplay) tpStage.replay();
                }

                SilkyGestureStage {
                    id: tpStage
                    t: pal
                    device: "trackpad"
                    gesture: tpPane.currentGesture
                    caption: tpPane.currentCaption
                    naturalScroll: root.bar ? root.bar.tpNatural : true
                    scrollSpeed: root.bar ? root.bar.tpScroll : 0.7
                    secondaryCorner: root.bar ? !root.bar.tpClickfinger : false
                    workspaceFingers: root.bar && root.bar.tpWorkspaceSwipe === 3 ? 3 : 4
                    reduceMotion: root.bar ? root.bar.reduceMotion : false
                    running: prefsWindow.visible
                }

                SSegmented {
                    t: pal
                    anchors.horizontalCenter: parent.horizontalCenter
                    segWidth: Math.max(100, (tpPane.width - 4) / 3)
                    model: ["Point & Click", "Scroll & Zoom", "More Gestures"]
                    current: tpPane.tab
                    onPicked: i => {
                        tpPane.tab = i;
                        if (root.bar) root.bar.tpSettingsTab = i;
                        tpPane.selectForTab(i);
                    }
                }

                // Tab 0 · Point & Click
                SCard {
                    t: pal
                    visible: tpPane.tab === 0

                    SilkyGestureRow {
                        t: pal
                        title: I18n.tr("Tap to click")
                        subtitle: I18n.tr("Tap with one finger to click")
                        gestureId: "tp_tap"
                        activeGesture: tpPane.currentGesture
                        onActivated: (g, lbl, clicked) => tpPane.pickGesture(g, lbl, clicked)
                        SSwitch {
                            t: pal
                            checked: root.bar ? root.bar.tpTap : true
                            onToggled: v => {
                                tpPane.pickGesture("tp_tap", I18n.tr("Tap to click"), false);
                                if (root.bar) root.bar.tpTap = v;
                            }
                        }
                    }

                    SilkyGestureRow {
                        t: pal
                        title: I18n.tr("Secondary click")
                        subtitle: I18n.tr("Open context menus on files, icons and text")
                        gestureId: "tp_secondary"
                        activeGesture: tpPane.currentGesture
                        onActivated: (g, lbl, clicked) => tpPane.pickGesture(g, lbl, clicked)
                        SPopUp {
                            t: pal
                            width: Math.min(220, tpPane.width * 0.48)
                            model: [
                                I18n.tr("Click or Tap with Two Fingers"),
                                I18n.tr("Click in Bottom Right Corner")
                            ]
                            current: (root.bar ? root.bar.tpClickfinger : true) ? 0 : 1
                            onPicked: idx => {
                                tpPane.pickGesture("tp_secondary", I18n.tr("Secondary click"), true);
                                if (root.bar) root.bar.tpClickfinger = (idx === 0);
                            }
                        }
                    }

                    SilkyGestureRow {
                        t: pal
                        title: I18n.tr("Three Finger Drag")
                        subtitle: I18n.tr("Move windows, files, selected text and sliders with three fingers")
                        gestureId: "tp_drag3fg"
                        activeGesture: tpPane.currentGesture
                        onActivated: (g, lbl, clicked) => tpPane.pickGesture(g, lbl, clicked)
                        SSwitch {
                            t: pal
                            checked: root.bar ? root.bar.tpDrag3fg : true
                            onToggled: v => {
                                tpPane.pickGesture("tp_drag3fg", I18n.tr("Three Finger Drag"), false);
                                if (root.bar) {
                                    root.bar.tpDrag3fg = v;
                                    if (v && root.bar.tpWorkspaceSwipe === 3) root.bar.tpWorkspaceSwipe = 4;
                                }
                            }
                        }
                    }

                    SilkyGestureRow {
                        t: pal
                        title: I18n.tr("Tap and drag")
                        subtitle: I18n.tr("Double-tap and hold to drag without lifting your finger")
                        gestureId: "tp_tap_drag"
                        activeGesture: tpPane.currentGesture
                        onActivated: (g, lbl, clicked) => tpPane.pickGesture(g, lbl, clicked)
                        SSwitch {
                            t: pal
                            checked: root.bar ? root.bar.tpTapAndDrag : true
                            onToggled: v => {
                                tpPane.pickGesture("tp_tap_drag", I18n.tr("Tap and drag"), false);
                                if (root.bar) root.bar.tpTapAndDrag = v;
                            }
                        }
                    }

                    SilkyGestureRow {
                        t: pal
                        title: I18n.tr("Ignore trackpad while typing")
                        subtitle: I18n.tr("Prevent accidental palm touches while typing")
                        gestureId: "tp_dwt"
                        activeGesture: tpPane.currentGesture
                        onActivated: (g, lbl, clicked) => tpPane.pickGesture(g, lbl, clicked)
                        SSwitch {
                            t: pal
                            checked: root.bar ? root.bar.tpDwt : true
                            onToggled: v => {
                                tpPane.pickGesture("tp_dwt", I18n.tr("Ignore trackpad while typing"), false);
                                if (root.bar) root.bar.tpDwt = v;
                            }
                        }
                    }
                }

                // Tab 1 · Scroll & Zoom
                SCard {
                    t: pal
                    visible: tpPane.tab === 1

                    SilkyGestureRow {
                        t: pal
                        title: I18n.tr("Natural scrolling")
                        subtitle: I18n.tr("Content tracks finger movement")
                        gestureId: "tp_natural_scroll"
                        activeGesture: tpPane.currentGesture
                        onActivated: (g, lbl, clicked) => tpPane.pickGesture(g, lbl, clicked)
                        SSwitch {
                            t: pal
                            checked: root.bar ? root.bar.tpNatural : true
                            onToggled: v => {
                                tpPane.pickGesture("tp_natural_scroll", I18n.tr("Natural scrolling"), true);
                                if (root.bar) root.bar.tpNatural = v;
                            }
                        }
                    }

                    SilkyGestureRow {
                        t: pal
                        title: I18n.tr("Scrolling speed")
                        gestureId: "tp_scroll_speed"
                        activeGesture: tpPane.currentGesture
                        onActivated: (g, lbl, clicked) => tpPane.pickGesture(g, lbl, clicked)
                        SSlider {
                            t: pal
                            resetValue: 0.7
                            leftLabel: I18n.tr("Slow")
                            rightLabel: I18n.tr("Fast")
                            from: 0.2
                            to: 2.0
                            value: root.bar ? root.bar.tpScroll : 0.7
                            onMoved: v => {
                                tpPane.pickGesture("tp_scroll_speed", I18n.tr("Scrolling speed"), false);
                                if (root.bar) root.bar.tpScroll = v;
                            }
                        }
                    }

                    SilkyGestureRow {
                        t: pal
                        title: I18n.tr("Zoom in or out")
                        subtitle: I18n.tr("Pinch with two fingers in browsers, images and documents")
                        gestureId: "tp_zoom"
                        activeGesture: tpPane.currentGesture
                        onActivated: (g, lbl, clicked) => tpPane.pickGesture(g, lbl, clicked)
                        SilkyGestureBadge { t: pal; text: I18n.tr("Pinch with two fingers") }
                    }
                }

                // Tab 2 · More Gestures
                SCard {
                    t: pal
                    visible: tpPane.tab === 2

                    SilkyGestureRow {
                        t: pal
                        title: I18n.tr("Swipe between pages")
                        subtitle: I18n.tr("Scroll left or right with two fingers to navigate browser history")
                        gestureId: "tp_swipe_pages"
                        activeGesture: tpPane.currentGesture
                        onActivated: (g, lbl, clicked) => tpPane.pickGesture(g, lbl, clicked)
                        SilkyGestureBadge { t: pal; text: I18n.tr("Scroll left or right with two fingers") }
                    }

                    SilkyGestureRow {
                        t: pal
                        title: I18n.tr("Swipe between full-screen spaces")
                        subtitle: I18n.tr("1:1 workspace slide with rubber-band bounce at the first and last space")
                        gestureId: "tp_workspace_swipe"
                        activeGesture: tpPane.currentGesture
                        onActivated: (g, lbl, clicked) => tpPane.pickGesture(g, lbl, clicked)
                        SPopUp {
                            t: pal
                            width: Math.min(215, tpPane.width * 0.46)
                            readonly property var modes: [4, 3, 0]
                            model: [
                                I18n.tr("Swipe Left or Right with Four Fingers"),
                                I18n.tr("Swipe Left or Right with Three Fingers"),
                                I18n.tr("Off")
                            ]
                            current: {
                                var m = root.bar ? root.bar.tpWorkspaceSwipe : 4;
                                var idx = modes.indexOf(m);
                                return idx >= 0 ? idx : 0;
                            }
                            onPicked: idx => {
                                var next = modes[idx];
                                if (root.bar) {
                                    if (next === 3 && root.bar.tpDrag3fg) root.bar.tpDrag3fg = false;
                                    root.bar.tpWorkspaceSwipe = next;
                                }
                                tpPane.pickGesture("tp_workspace_swipe", I18n.tr("Swipe between full-screen spaces"), true);
                            }
                        }
                    }

                    SilkyGestureRow {
                        t: pal
                        title: I18n.tr("Mission Control")
                        subtitle: I18n.tr("Show workspace strip and all windows on the current workspace")
                        gestureId: "tp_mission_control"
                        activeGesture: tpPane.currentGesture
                        onActivated: (g, lbl, clicked) => tpPane.pickGesture(g, lbl, clicked)
                        SPopUp {
                            t: pal
                            width: Math.min(205, tpPane.width * 0.44)
                            model: [
                                I18n.tr("Swipe Up with Four Fingers"),
                                I18n.tr("Off")
                            ]
                            current: (root.bar ? root.bar.tpMissionControl : true) ? 0 : 1
                            onPicked: idx => {
                                if (root.bar) root.bar.tpMissionControl = (idx === 0);
                                tpPane.pickGesture("tp_mission_control", I18n.tr("Mission Control"), true);
                            }
                        }
                    }

                    SilkyGestureRow {
                        t: pal
                        title: I18n.tr("App Exposé")
                        subtitle: I18n.tr("Show all open windows of the active application across spaces")
                        gestureId: "tp_app_expose"
                        activeGesture: tpPane.currentGesture
                        onActivated: (g, lbl, clicked) => tpPane.pickGesture(g, lbl, clicked)
                        SPopUp {
                            t: pal
                            width: Math.min(205, tpPane.width * 0.44)
                            model: [
                                I18n.tr("Swipe Down with Four Fingers"),
                                I18n.tr("Off")
                            ]
                            current: (root.bar ? root.bar.tpAppExpose : true) ? 0 : 1
                            onPicked: idx => {
                                if (root.bar) root.bar.tpAppExpose = (idx === 0);
                                tpPane.pickGesture("tp_app_expose", I18n.tr("App Exposé"), true);
                            }
                        }
                    }

                    SilkyGestureRow {
                        t: pal
                        title: I18n.tr("Applications")
                        subtitle: I18n.tr("Pinch with thumb and three or four fingers to open, spread to close")
                        gestureId: "tp_launchpad"
                        activeGesture: tpPane.currentGesture
                        onActivated: (g, lbl, clicked) => tpPane.pickGesture(g, lbl, clicked)
                        SSwitch {
                            t: pal
                            checked: root.bar ? root.bar.tpLaunchpadPinch : true
                            onToggled: v => {
                                tpPane.pickGesture("tp_launchpad", I18n.tr("Applications"), true);
                                if (root.bar) root.bar.tpLaunchpadPinch = v;
                            }
                        }
                    }
                }

                SLabel {
                    t: pal
                    text: I18n.tr("Hover or click any gesture row to preview its finger motion and live desktop animation.")
                }
            }
        }

        // ── Touchscreen ──
        Component {
            id: paneTouchscreen
            Column {
                id: tsPane
                spacing: 12
                property int tab: root.bar ? root.bar.tsSettingsTab : 0
                property string currentGesture: tab === 1 ? "ts_kinetic_scroll" : (tab === 2 ? "ts_edge_swipe" : "ts_window_move")
                property string currentCaption: tab === 1 ? I18n.tr("Kinetic touch scrolling") : (tab === 2 ? I18n.tr("Screen-edge workspace swipe") : I18n.tr("Move floating windows"))

                Connections {
                    target: root.bar
                    function onTsSettingsTabChanged() {
                        if (root.bar && tsPane.tab !== root.bar.tsSettingsTab) {
                            tsPane.tab = root.bar.tsSettingsTab;
                            tsPane.selectForTab(tsPane.tab);
                        }
                    }
                }

                Component.onCompleted: touchscreenCtrl.refresh()

                function selectForTab(idx) {
                    if (idx === 0) {
                        currentGesture = "ts_window_move";
                        currentCaption = I18n.tr("Move floating windows");
                    } else if (idx === 1) {
                        currentGesture = "ts_kinetic_scroll";
                        currentCaption = I18n.tr("Kinetic touch scrolling");
                    } else {
                        currentGesture = "ts_edge_swipe";
                        currentCaption = I18n.tr("Screen-edge workspace swipe");
                    }
                }

                function pickGesture(gid, label, shouldReplay) {
                    var changed = (currentGesture !== gid);
                    currentGesture = gid;
                    currentCaption = label;
                    if (!changed && shouldReplay) tsStage.replay();
                }

                SilkyGestureStage {
                    id: tsStage
                    t: pal
                    device: "touchscreen"
                    gesture: tsPane.currentGesture
                    caption: tsPane.currentCaption
                    reduceMotion: root.bar ? root.bar.reduceMotion : false
                    running: prefsWindow.visible
                }

                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: I18n.tr("Touchscreen")
                        subtitle: touchscreenCtrl.hasDevice
                                  ? I18n.tr("Direct touch, floating window controls and multi-finger workspace gestures")
                                  : I18n.tr("No built-in touchscreen detected; gesture tutorials remain available for external touch displays")
                        SSwitch {
                            t: pal
                            enabled: touchscreenCtrl.hasDevice && !touchscreenCtrl.busy
                            checked: touchscreenCtrl.hasDevice ? touchscreenCtrl.touchEnabled : false
                            onToggled: v => touchscreenCtrl.setTouchEnabled(v)
                        }
                    }
                }

                SSegmented {
                    t: pal
                    anchors.horizontalCenter: parent.horizontalCenter
                    segWidth: Math.max(100, (tsPane.width - 4) / 3)
                    model: ["Window & Tap", "Scroll & Browse", "Workspaces & Multitasking"]
                    current: tsPane.tab
                    onPicked: i => {
                        tsPane.tab = i;
                        if (root.bar) root.bar.tsSettingsTab = i;
                        tsPane.selectForTab(i);
                    }
                }

                // Tab 0 · Window & Tap
                SCard {
                    t: pal
                    visible: tsPane.tab === 0

                    SilkyGestureRow {
                        t: pal
                        title: I18n.tr("Move floating windows")
                        subtitle: I18n.tr("Drag a window's top 44 px bar; stays below the menu bar and snaps at screen edges")
                        gestureId: "ts_window_move"
                        activeGesture: tsPane.currentGesture
                        onActivated: (g, lbl, clicked) => tsPane.pickGesture(g, lbl, clicked)
                        SilkyGestureBadge { t: pal; text: I18n.tr("Drag top bar") }
                    }

                    SilkyGestureRow {
                        t: pal
                        title: I18n.tr("Resize from edges or corners")
                        subtitle: I18n.tr("Drag any floating window edge (16 px band) or corner to resize")
                        gestureId: "ts_window_resize"
                        activeGesture: tsPane.currentGesture
                        onActivated: (g, lbl, clicked) => tsPane.pickGesture(g, lbl, clicked)
                        SilkyGestureBadge { t: pal; text: I18n.tr("Drag edge or corner") }
                    }

                    SilkyGestureRow {
                        t: pal
                        title: I18n.tr("Hold anywhere to move")
                        subtitle: I18n.tr("Hold one finger still for 0.4 s inside a floating window to pick it up and drag")
                        gestureId: "ts_hold_move"
                        activeGesture: tsPane.currentGesture
                        onActivated: (g, lbl, clicked) => tsPane.pickGesture(g, lbl, clicked)
                        SilkyGestureBadge { t: pal; text: I18n.tr("Hold 0.4 s & drag") }
                    }

                    SilkyGestureRow {
                        t: pal
                        title: I18n.tr("Context menu")
                        subtitle: I18n.tr("Long-press on files, list items or icons to open the context menu")
                        gestureId: "ts_context_menu"
                        activeGesture: tsPane.currentGesture
                        onActivated: (g, lbl, clicked) => tsPane.pickGesture(g, lbl, clicked)
                        SilkyGestureBadge { t: pal; text: I18n.tr("Long press") }
                    }
                }

                // Tab 1 · Scroll & Browse
                SCard {
                    t: pal
                    visible: tsPane.tab === 1

                    SilkyGestureRow {
                        t: pal
                        title: I18n.tr("Kinetic touch scrolling")
                        subtitle: I18n.tr("1:1 finger tracking in apps, Folio and WeChat; glides after lift and stops on touch")
                        gestureId: "ts_kinetic_scroll"
                        activeGesture: tsPane.currentGesture
                        onActivated: (g, lbl, clicked) => tsPane.pickGesture(g, lbl, clicked)
                        SilkyGestureBadge { t: pal; text: I18n.tr("One-finger swipe") }
                    }

                    SilkyGestureRow {
                        t: pal
                        title: I18n.tr("Pinch to zoom")
                        subtitle: I18n.tr("Spread or pinch two fingers on the screen to zoom pages and images")
                        gestureId: "ts_zoom"
                        activeGesture: tsPane.currentGesture
                        onActivated: (g, lbl, clicked) => tsPane.pickGesture(g, lbl, clicked)
                        SilkyGestureBadge { t: pal; text: I18n.tr("Pinch with two fingers") }
                    }
                }

                // Tab 2 · Workspaces & Multitasking
                SCard {
                    t: pal
                    visible: tsPane.tab === 2

                    SilkyGestureRow {
                        t: pal
                        title: I18n.tr("Screen-edge workspace swipe")
                        subtitle: I18n.tr("Swipe inward from the left or right 20 px screen edge; bounces at the ends")
                        gestureId: "ts_edge_swipe"
                        activeGesture: tsPane.currentGesture
                        onActivated: (g, lbl, clicked) => tsPane.pickGesture(g, lbl, clicked)
                        SilkyGestureBadge { t: pal; text: I18n.tr("Swipe from screen edge") }
                    }

                    SilkyGestureRow {
                        t: pal
                        title: I18n.tr("Three-finger workspace swipe")
                        subtitle: I18n.tr("Swipe left or right with three or more fingers anywhere on the screen")
                        gestureId: "ts_three_finger_swipe"
                        activeGesture: tsPane.currentGesture
                        onActivated: (g, lbl, clicked) => tsPane.pickGesture(g, lbl, clicked)
                        SilkyGestureBadge { t: pal; text: I18n.tr("Swipe with three fingers") }
                    }

                    SilkyGestureRow {
                        t: pal
                        title: I18n.tr("Mission Control")
                        subtitle: I18n.tr("Swipe up with four fingers on the screen to view all windows on this workspace")
                        gestureId: "ts_overview_up"
                        activeGesture: tsPane.currentGesture
                        onActivated: (g, lbl, clicked) => tsPane.pickGesture(g, lbl, clicked)
                        SSwitch {
                            t: pal
                            checked: root.bar ? root.bar.tpMissionControl : true
                            onToggled: v => {
                                tsPane.pickGesture("ts_overview_up", I18n.tr("Mission Control"), true);
                                if (root.bar) root.bar.tpMissionControl = v;
                            }
                        }
                    }

                    SilkyGestureRow {
                        t: pal
                        title: I18n.tr("App Exposé")
                        subtitle: I18n.tr("Swipe down with four fingers on the screen to view windows of the active app")
                        gestureId: "ts_overview_down"
                        activeGesture: tsPane.currentGesture
                        onActivated: (g, lbl, clicked) => tsPane.pickGesture(g, lbl, clicked)
                        SSwitch {
                            t: pal
                            checked: root.bar ? root.bar.tpAppExpose : true
                            onToggled: v => {
                                tsPane.pickGesture("ts_overview_down", I18n.tr("App Exposé"), true);
                                if (root.bar) root.bar.tpAppExpose = v;
                            }
                        }
                    }

                    SilkyGestureRow {
                        t: pal
                        title: I18n.tr("Applications")
                        subtitle: I18n.tr("Pinch in with four or five fingers on the screen to open Applications, spread to close")
                        gestureId: "ts_pinch_launchpad"
                        activeGesture: tsPane.currentGesture
                        onActivated: (g, lbl, clicked) => tsPane.pickGesture(g, lbl, clicked)
                        SSwitch {
                            t: pal
                            checked: root.bar ? root.bar.tpLaunchpadPinch : true
                            onToggled: v => {
                                tsPane.pickGesture("ts_pinch_launchpad", I18n.tr("Applications"), true);
                                if (root.bar) root.bar.tpLaunchpadPinch = v;
                            }
                        }
                    }
                }

                SLabel {
                    t: pal
                    text: I18n.tr("Tap or hover any row to replay the touch target and desktop gesture guide.")
                }
            }
        }
