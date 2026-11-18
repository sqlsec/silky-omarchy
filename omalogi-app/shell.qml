//@ pragma AppId io.github.elberacasa.omalogi
// Silky Omarchy: Omalogi as its own app window (launcher, Dock, Alt+Tab show 罗技鼠标 with its icon).
// Installed by scripts/install-omalogi.sh to ~/.local/share/silky-omarchy/omalogi-app, next to links to
// Omarchy's shell modules (Commons, Ui, services) and the installed Omalogi plugin (omalogi/).
// Started by bin/silky-omalogi; quits once the window is closed and every save has finished.
import QtQuick
import Quickshell
import "omalogi/plugin"

ShellRoot {
  Omalogi {
    id: app
    property bool shown: false

    onMountedChanged: if (mounted) shown = true
    Component.onCompleted: Qt.callLater(function() { app.open("{}") })
  }

  // Closing saves what is pending first (see Omalogi.close / the window's onVisibleChanged);
  // wait for that write, then quit so no helper is left running.
  Timer {
    interval: 200
    repeat: true
    running: app.shown && !app.mounted
    onTriggered: if (!app.saving && !app.undoing) Qt.quit()
  }
}
