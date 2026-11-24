import QtQuick
import Quickshell
import Quickshell.Wayland

// Folio supplies one still image. The GPU moves its mesh between the original
// window and the measured thumbnail slot while the real window sits off-screen.
Scope {
    id: fx

    property var job: null
    property var capJob: null
    property var destination: null
    property var bounds: null
    property bool mapOverlay: false
    property bool covered: false
    property bool parkRequested: false
    property bool started: false
    readonly property int duration: 300

    function capture(tl, screenName, winRect, callback) {
        if (capJob) {
            const stale = capJob
            capTimeout.stop()
            capJob = null
            if (stale.cb) stale.cb(null)
        }
        if (!tl || !screenName || !winRect || winRect.width < 1 || winRect.height < 1) {
            if (callback) callback(null)
            return
        }
        let w = Math.max(1, Math.round(winRect.width))
        let h = Math.max(1, Math.round(winRect.height))
        const maxW = 1152, maxH = 768
        if (w > maxW || h > maxH) {
            const s = Math.min(maxW / w, maxH / h)
            w = Math.max(1, Math.round(w * s))
            h = Math.max(1, Math.round(h * s))
        }
        capJob = { tl: tl, screen: screenName, width: w, height: h, cb: callback, grabbing: false }
        capTimeout.restart()
    }

    function finishCapture(current, result) {
        if (capJob !== current)
            return
        capTimeout.stop()
        capJob = null
        if (current.cb)
            current.cb(result)
    }

    function play(next) {
        if (job) finish()
        destination = null
        bounds = null
        mapOverlay = false
        job = next
        wait.start()
        deadline.start()
    }

    function prepare(screen) {
        const slot = job.targetFn()
        if (!slot)
            return

        const win = job.win
        const aspect = win.width / win.height
        const w = Math.min(slot.width, slot.height * aspect)
        const h = w / aspect
        destination = {
            x: slot.x + (slot.width - w) / 2,
            y: slot.y + (slot.height - h) / 2,
            width: w,
            height: h
        }

        // Restrict Wayland damage and the clear to the area the mesh can reach.
        const x = Math.max(screen.x, Math.floor(Math.min(win.x, destination.x)))
        const y = Math.max(screen.y, Math.floor(Math.min(win.y, destination.y)))
        const right = Math.min(screen.x + screen.width, Math.ceil(Math.max(win.x + win.width, destination.x + w)))
        const bottom = Math.min(screen.y + screen.height, Math.ceil(Math.max(win.y + win.height, destination.y + h)))
        bounds = { x: x, y: y, width: Math.max(1, right - x), height: Math.max(1, bottom - y) }
        wait.stop()
        const prepared = job
        Qt.callLater(function () {
            if (job === prepared)
                mapOverlay = true
        })
    }

    function startMotion() {
        deadline.stop()
        if (!parkRequested)
            job.before()
        started = true
    }

    function completeMotion() {
        if (!job || !job.after)
            return
        const completed = job
        completed.after()
        if (job !== completed)
            return
        completed.after = null
        // Hold the undimmed endpoint until the Dock thumbnail or restored
        // client has had a chance to render.
        handBack.restart()
    }

    function finish() {
        if (!job)
            return
        const previous = job
        wait.stop()
        deadline.stop()
        handBack.stop()
        if (!started && !parkRequested)
            previous.before()
        started = false
        covered = false
        parkRequested = false
        job = null
        if (previous.after) previous.after()
    }

    Timer {
        id: wait
        interval: 12
        repeat: true
    }
    Timer {
        id: deadline
        interval: 320
        onTriggered: fx.finish()
    }

    Timer {
        id: capTimeout
        interval: 450
        onTriggered: {
            if (fx.capJob)
                fx.finishCapture(fx.capJob, null)
        }
    }

    Timer {
        id: handBack
        interval: 32
        onTriggered: fx.finish()
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: capWin
            required property var modelData
            screen: modelData
            readonly property bool mine: fx.capJob !== null && fx.capJob.screen === modelData.name
            visible: mine
            anchors { top: true; left: true }
            implicitWidth: mine ? fx.capJob.width : 1
            implicitHeight: mine ? fx.capJob.height : 1
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            mask: Region {}
            WlrLayershell.namespace: "silky-folio-scale-out"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            // Keep the capture view inside a nearly invisible parent so Qt
            // renders it on screen while grabToImage captures it at full alpha.
            Item {
                anchors.fill: parent
                opacity: 0.002

                ScreencopyView {
                    id: sc
                    anchors.fill: parent
                    captureSource: capWin.mine ? fx.capJob.tl : null
                    live: false
                    onHasContentChanged: {
                        const current = fx.capJob
                        if (!hasContent || !capWin.mine || !current || current.grabbing)
                            return
                        current.grabbing = true
                        Qt.callLater(function () {
                            if (fx.capJob !== current)
                                return
                            const ok = sc.grabToImage(function (result) {
                                fx.finishCapture(current, result && result.url && String(result.url) !== "" ? result : null)
                            }, Qt.size(current.width, current.height))
                            if (!ok)
                                fx.finishCapture(current, null)
                        })
                    }
                }
            }
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: overlay
            required property var modelData
            screen: modelData
            readonly property bool mine: fx.job !== null && fx.job.screen === modelData.name
            readonly property bool ready: mine && fx.bounds !== null
            readonly property bool gpu: surface.GraphicsInfo.api !== GraphicsInfo.Software
            property int mapFrames: 0
            property int coverSwaps: 0
            visible: ready && fx.mapOverlay
            anchors { top: true; left: true }
            margins {
                left: overlay.ready ? fx.bounds.x - overlay.modelData.x : 0
                top: overlay.ready ? fx.bounds.y - overlay.modelData.y : 0
            }
            implicitWidth: ready ? fx.bounds.width : 1
            implicitHeight: ready ? fx.bounds.height : 1
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            mask: Region {}
            WlrLayershell.namespace: "silky-folio-scale"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Connections {
                target: wait
                enabled: overlay.mine
                function onTriggered() { fx.prepare(overlay.modelData) }
            }
            Connections {
                target: fx
                function onJobChanged() {
                    lamp.stop()
                    scaleMotion.stop()
                    overlay.mapFrames = 0
                    overlay.coverSwaps = 0
                    if (overlay.mine)
                        overlay.WlrLayershell.namespace = fx.job.reverse ? "silky-folio-scale" : "silky-folio-scale-out"
                    const initial = overlay.mine && fx.job?.reverse ? 1 : 0
                    shader.progress = initial
                    snapshot.progress = initial
                }
            }

            Connections {
                target: surface.Window.window
                enabled: fx.covered && overlay.visible && !fx.parkRequested
                function onFrameSwapped() { overlay.coverSwaps++ }
            }

            FrameAnimation {
                running: overlay.visible && snapshot.status === Image.Ready && !fx.started
                onTriggered: {
                    if (overlay.width !== fx.bounds.width || overlay.height !== fx.bounds.height) {
                        overlay.mapFrames = 0
                        return
                    }
                    if (++overlay.mapFrames < 2)
                        return

                    if (!fx.job.reverse) {
                        // Submit the still at full opacity before moving the
                        // client. Starting both together can expose a blank frame.
                        if (!fx.covered) {
                            fx.covered = true
                            return
                        }
                        if (!fx.parkRequested) {
                            // The first swap can belong to a frame queued before
                            // the opacity change. Request a repaint so the render
                            // thread actually swaps the covered frame.
                            if (overlay.coverSwaps < 2) {
                                if (surface.Window.window)
                                    surface.Window.window.update()
                                return
                            }
                            fx.parkRequested = true
                            fx.job.before()
                            return
                        }
                        // Begin deforming only after the live client is out of view.
                        if (fx.job.parked && !fx.job.parked())
                            return
                    }

                    const motion = overlay.gpu ? lamp : scaleMotion
                    motion.from = fx.job.reverse ? 1 : 0
                    motion.to = fx.job.reverse ? 0 : 1
                    fx.startMotion()
                    motion.start()
                }
            }

            Item {
                id: surface
                anchors.fill: parent
                readonly property var origin: overlay.ready ? fx.job.win : null
                readonly property var end: overlay.ready ? fx.destination : null

                function relative(rect) {
                    return rect ? Qt.vector4d(rect.x - fx.bounds.x, rect.y - fx.bounds.y, rect.width, rect.height)
                                : Qt.vector4d(0, 0, 1, 1)
                }

                Image {
                    id: snapshot
                    source: overlay.mine ? fx.job.image : ""
                    asynchronous: true
                    visible: overlay.ready && !overlay.gpu
                    opacity: fx.started || fx.covered ? 1 : 0
                    smooth: true
                    property real progress: 0

                    function interpolate(a, b) { return a + (b - a) * progress }

                    x: surface.origin && surface.end ? interpolate(surface.origin.x, surface.end.x) - fx.bounds.x : 0
                    y: surface.origin && surface.end ? interpolate(surface.origin.y, surface.end.y) - fx.bounds.y : 0
                    width: surface.origin && surface.end ? interpolate(surface.origin.width, surface.end.width) : 1
                    height: surface.origin && surface.end ? interpolate(surface.origin.height, surface.end.height) : 1
                }

                ShaderEffect {
                    id: shader
                    anchors.fill: parent
                    visible: overlay.ready && overlay.gpu
                    // Warm the mesh without drawing a second copy over the live window.
                    opacity: fx.started || fx.covered ? 1 : 0.002
                    mesh: GridMesh { resolution: Qt.size(1, 40) }
                    vertexShader: Qt.resolvedUrl("folio-genie.vert.qsb")
                    property variant source: snapshot
                    property real progress: 0
                    property vector4d win: surface.relative(surface.origin)
                    property vector4d target: surface.relative(surface.end)
                }

                UniformAnimator {
                    id: lamp
                    target: shader
                    uniform: "progress"
                    duration: fx.duration
                    easing.type: Easing.InOutSine
                    onFinished: fx.completeMotion()
                }
                NumberAnimation {
                    id: scaleMotion
                    target: snapshot
                    property: "progress"
                    duration: fx.duration
                    easing.type: Easing.InOutSine
                    onFinished: fx.completeMotion()
                }
            }
        }
    }
}
