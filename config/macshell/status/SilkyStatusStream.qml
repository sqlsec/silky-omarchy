import QtQuick
import Quickshell.Io

Item {
    id: root
    required property string mode
    property bool active: false
    property var sample: null

    onActiveChanged: if (!active) sample = null

    Process {
        running: root.active
        command: ["/usr/bin/python3", "-I", decodeURIComponent(Qt.resolvedUrl("assets/silky-status.py").toString().substring(7)), root.mode]
        stdout: SplitParser {
            onRead: line => {
                if (!root.active)
                    return;
                try {
                    root.sample = JSON.parse(line);
                } catch (error) {
                    console.warn("Silky status:", error);
                }
            }
        }
    }
}
