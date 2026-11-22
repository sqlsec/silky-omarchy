// Silky Voice: a frosted-glass waveform pill for WowType and vinput.
//
// bridge.py sends WowType and vinput recording events here as JSON lines. While you speak,
// three overlapping curves (blue, violet, pink) swell with your real input level; while WowType recognizes, they
// settle into a soft shimmer. Live text and the waveform share the pill.
//
//   qs -c SilkyVoice                     run it (Hyprland starts it at login, see config/hypr/silky-voice.lua)
//   SILKY_VOICE_DEMO=1 qs -c SilkyVoice  show the pill with a fake voice, to tweak the look
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    readonly property int stHide: 0
    readonly property int stListening: 1
    readonly property int stRecognizing: 2
    readonly property int stDone: 3
    readonly property int stError: 4

    readonly property bool demo: Quickshell.env("SILKY_VOICE_DEMO") === "1"

    property int state: demo ? stListening : stHide
    property string label: ""
    property string draft: demo ? "我们来试试这段实时转写。" : ""
    property real voiceTarget: 0      // 0..1 from WowType's level
    property real voice: 0            // smoothed
    property real time: 0
    property bool shown: demo
    property bool ambientPulse: false

    // WowType's level is 0..100 (-60 dB .. -10 dB); a quiet room sits below ~20.
    function levelToVoice(level) {
        var k = Math.max(0, Math.min(1, (level - 20) / 60));
        return Math.max(0, Math.min(1, 1.6 * Math.pow(k, 0.9)));
    }

    function defaultLabel(s) {
        if (s === stListening) return "正在听…";
        if (s === stRecognizing) return "识别中…";
        if (s === stDone) return "已输入";
        if (s === stError) return "出错了";
        return "";
    }

    function onState(m) {
        staleTimer.restart();
        if (m.s === stHide) {
            if (root.state !== stDone && root.state !== stError) root.shown = false;
            return;
        }
        root.state = m.s;
        root.ambientPulse = m.pulse === true;
        root.label = m.t || "";
        root.draft = m.draft || "";
        root.voiceTarget = m.s === stListening ? levelToVoice(m.l || 0) : 0;
        root.shown = true;
        if (m.s === stDone || m.s === stError) doneTimer.restart();
        else doneTimer.stop();
    }

    Timer { id: doneTimer; interval: 900; onTriggered: root.shown = false }
    // WowType went away mid-utterance: fold the pill instead of leaving it on screen.
    Timer { id: staleTimer; interval: 1500; onTriggered: if (!root.demo && root.state !== root.stDone) root.shown = false }

    Process {
        id: bridge
        running: !root.demo
        command: ["python3", "-I", Quickshell.shellDir + "/bridge.py"]
        stdout: SplitParser {
            onRead: data => {
                try { var m = JSON.parse(data); if (m.s !== undefined) root.onState(m); } catch (e) {}
            }
        }
        stderr: SplitParser { onRead: data => console.warn("[silky-voice] " + data) }
        // Keep the overlay alive across a crashed bridge or a dbus hiccup.
        onExited: restartTimer.start()
    }
    Timer { id: restartTimer; interval: 3000; onTriggered: bridge.running = true }

    // Demo: a voice that rises and falls like speech.
    Timer {
        interval: 50; repeat: true; running: root.demo
        onTriggered: {
            var t = root.time;
            root.voiceTarget = Math.max(0, 0.55 + 0.35 * Math.sin(t * 2.3) * Math.sin(t * 0.9) + 0.15 * Math.sin(t * 7.1));
        }
    }

    FrameAnimation {
        running: root.shown || pill.opacity > 0
        onTriggered: {
            var dt = Math.min(0.05, frameTime);
            root.time += dt;
            // fast attack, slower release, like a VU meter
            var target = root.ambientPulse
                ? 0.38 + 0.20 * Math.sin(root.time * 4.6) + 0.10 * Math.sin(root.time * 7.7)
                : root.voiceTarget;
            var rate = target > root.voice ? 18 : 6;
            root.voice += (target - root.voice) * (1 - Math.exp(-rate * dt));
            wave.requestPaint();
        }
    }

    PanelWindow {
        id: win
        anchors.bottom: true
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "silky-voice"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        // sits above the Dock
        margins.bottom: 104
        implicitWidth: Math.min(392, screen ? screen.width : 392)
        implicitHeight: 84
        color: "transparent"
        mask: Region {}           // never takes a click
        visible: root.shown || pill.opacity > 0.01

        Item {
            id: pill
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            height: 52
            width: parent.width - 24

            opacity: root.shown ? 1 : 0
            scale: root.shown ? 1 : 0.96
            Behavior on opacity { NumberAnimation { duration: root.shown ? 180 : 120; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: root.shown ? 180 : 120; easing.type: Easing.OutCubic } }

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                gradient: Gradient {
                    GradientStop { position: 0; color: "#eb272830" }
                    GradientStop { position: 1; color: "#ed15161c" }
                }
                border.width: 1
                border.color: "#32ffffff"
            }

            Item {
                id: badge
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                width: 30
                height: 30
                Rectangle {
                    anchors.centerIn: parent
                    width: 30; height: 30; radius: 15
                    scale: 1 + 0.26 * root.voice
                    opacity: root.state === root.stListening ? 0.24 : 0
                    color: "#5e5ce6"
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                }
                Rectangle {
                    anchors.fill: parent
                    radius: 15
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: root.state === root.stError ? "#ff453a" : "#497bf4" }
                        GradientStop { position: 1; color: root.state === root.stError ? "#ff6961" : "#9a5de2" }
                    }
                }
                Canvas {
                    anchors.fill: parent
                    Component.onCompleted: requestPaint()
                    onPaint: {
                        var c = getContext("2d");
                        c.reset();
                        c.strokeStyle = "white"; c.fillStyle = "white";
                        c.lineWidth = 1.6; c.lineCap = "round";
                        var cx = width / 2;
                        // capsule
                        c.beginPath();
                        c.moveTo(cx - 3.2, 9.5); c.lineTo(cx - 3.2, 15);
                        c.arc(cx, 15, 3.2, Math.PI, 0, true);
                        c.lineTo(cx + 3.2, 9.5);
                        c.arc(cx, 9.5, 3.2, 0, Math.PI, true);
                        c.fill();
                        // cradle and stem
                        c.beginPath(); c.arc(cx, 14.6, 6, 0.15 * Math.PI, 0.85 * Math.PI, false); c.stroke();
                        c.beginPath(); c.moveTo(cx, 20.6); c.lineTo(cx, 23); c.stroke();
                    }
                }
            }

            Item {
                id: caption
                anchors.left: badge.right
                anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                height: 38

                readonly property bool active: root.state === root.stListening
                                               || root.state === root.stRecognizing
                readonly property bool hasDraft: active && root.draft.length > 0

                Text {
                    id: labelText
                    anchors.left: parent.left
                    anchors.right: stateMark.visible ? stateMark.left : parent.right
                    anchors.rightMargin: stateMark.visible ? 10 : 0
                    y: caption.active ? 2 : (parent.height - height) / 2
                    textFormat: Text.PlainText
                    text: caption.hasDraft ? root.draft : (root.label || root.defaultLabel(root.state))
                    elide: caption.hasDraft ? Text.ElideLeft : Text.ElideRight
                    color: root.state === root.stError ? "#ffaaa6"
                         : caption.hasDraft || root.state === root.stDone ? "#f6f4fc" : "#c5c2d1"
                    font.family: "Sarasa UI SC"
                    font.pixelSize: caption.hasDraft ? 15 : 13
                    font.weight: caption.hasDraft ? Font.Medium : Font.Normal
                }

                Rectangle {
                    id: stateMark
                    visible: caption.hasDraft
                    anchors.right: parent.right
                    anchors.verticalCenter: labelText.verticalCenter
                    width: 5
                    height: 5
                    radius: width / 2
                    color: root.state === root.stRecognizing ? "#d0b8ff" : "#8fa9ff"
                }

                Canvas {
                    id: wave
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 1
                    height: 14
                    opacity: caption.active ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 130 } }
                    readonly property var layers: [
                        // colour, cycles across the width, speed, amplitude share, phase
                        { c: [90, 200, 250],  f: 1.6, v: 2.9, a: 1.00, p: 0.0 },
                        { c: [175, 82, 222],  f: 2.3, v: -3.6, a: 0.82, p: 1.7 },
                        { c: [255, 55, 95],   f: 1.1, v: 2.2, a: 0.66, p: 3.4 }
                    ]
                    onPaint: {
                        var c = getContext("2d");
                        c.reset();
                        var w = width, h = height, mid = h / 2, t = root.time;
                        var thinking = root.state === root.stRecognizing;
                        var base = thinking ? 0.16 + 0.06 * Math.sin(t * 5) : 0.07 + 0.03 * Math.sin(t * 2.1);
                        var amp = (mid - 2) * Math.min(1, base + 1.15 * root.voice);
                        c.globalCompositeOperation = "lighter";
                        for (var i = 0; i < layers.length; i++) {
                            var L = layers[i];
                            var wobble = 0.78 + 0.22 * Math.sin(t * (1.3 + i * 0.7) + L.p);
                            var A = amp * L.a * wobble;
                            var ph = L.p + t * L.v * (thinking ? 1.8 : 1);
                            var pts = [];
                            for (var x = 0; x <= w; x += 2) {
                                var u = x / w;
                                var env = Math.pow(Math.sin(Math.PI * u), 2.2);   // taper both ends
                                pts.push(mid + A * env * Math.sin(u * L.f * 2 * Math.PI + ph));
                            }
                            var rgb = L.c[0] + "," + L.c[1] + "," + L.c[2];
                            // soft lobes between the curve and the centre line
                            c.beginPath();
                            c.moveTo(0, mid);
                            for (var j = 0; j < pts.length; j++) c.lineTo(j * 2, pts[j]);
                            c.lineTo(w, mid);
                            c.closePath();
                            c.fillStyle = "rgba(" + rgb + ",0.14)";
                            c.fill();
                            // the curve itself, open, so no straight closing edge is drawn
                            c.beginPath();
                            c.moveTo(0, pts[0]);
                            for (var k = 1; k < pts.length; k++) c.lineTo(k * 2, pts[k]);
                            c.lineWidth = 1.25;
                            c.lineJoin = "round";
                            // fade the tapered ends out, where the three colours would otherwise add up to white
                            var g = c.createLinearGradient(0, 0, w, 0);
                            g.addColorStop(0.0, "rgba(" + rgb + ",0)");
                            g.addColorStop(0.2, "rgba(" + rgb + ",0.72)");
                            g.addColorStop(0.8, "rgba(" + rgb + ",0.72)");
                            g.addColorStop(1.0, "rgba(" + rgb + ",0)");
                            c.strokeStyle = g;
                            c.stroke();
                        }
                    }
                }

            }
        }
    }
}
