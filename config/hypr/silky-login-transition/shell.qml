import QtQuick
import Quickshell
import Quickshell.Wayland

ShellRoot {
    id: root

    readonly property string wallpaper: Quickshell.env("SILKY_LOGIN_WALLPAPER")
    readonly property url wallpaperUrl: wallpaper.startsWith("/")
        ? "file://" + wallpaper.split("/").map(encodeURIComponent).join("/")
        : ""

    // The normal wallpaper surfaces are mapped after this one, above it.
    // Keep a short overlap for image decoding, then release the startup image.
    Timer {
        interval: 7000
        running: true
        onTriggered: Qt.quit()
    }

    Variants {
        model: root.wallpaperUrl.toString() ? Quickshell.screens : []

        PanelWindow {
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            mask: Region {}
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.namespace: "silky-login-wallpaper"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Image {
                anchors.fill: parent
                source: root.wallpaperUrl
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: Math.max(1, Math.min(2560,
                    Math.ceil(modelData.width * modelData.devicePixelRatio * 1.15)))
                asynchronous: true
                onStatusChanged: {
                    if (status === Image.Ready)
                        console.info("Login wallpaper decoded for", modelData.name)
                }
            }
        }
    }
}
