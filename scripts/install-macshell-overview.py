#!/usr/bin/env python3
"""Install the Silky window overview (four-finger up / down) into a MacShell configuration.

Copies config/macshell/overview/SilkyOverview.qml next to MacShell's shell.qml and adds one instance of it there.
The four-finger gesture itself comes from the silky-gestures Hyprland plugin (scripts/install-silky-gestures.sh).
"""
import argparse
import os
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path

SOURCE_DIR = Path(__file__).resolve().parents[1] / "config/macshell/overview"
SOURCE = SOURCE_DIR / "SilkyOverview.qml"
SHADER = SOURCE_DIR / "silkyround.frag"
QSB_CANDIDATES = ["/usr/lib/qt6/bin/qsb", "qsb6", "qsb"]
ANCHOR = "    AboutApp { id: aboutApp; hub: sharedHub }\n"
LINE = ("    // four fingers up / down on the touchpad: every window of the workspace / of the focused app (silky-gestures plugin)\n"
        "    SilkyOverview { id: silkyOverview; hub: sharedHub }\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--config", default=os.path.join(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config")),
                                                         "quickshell/MacShell"), help="MacShell config directory")
    parser.add_argument("--check", action="store_true", help="only report whether it can be installed")
    args = parser.parse_args()

    target = Path(args.config)
    shell = target / "shell.qml"
    if not shell.is_file() or not (target / "SafeCapture.qml").is_file():
        sys.exit(f"MacShell not found (or too old: no SafeCapture.qml) in {target}")
    text = shell.read_text()
    installed = "SilkyOverview {" in text
    if not installed and ANCHOR not in text:
        sys.exit("shell.qml: AboutApp line not found; add the SilkyOverview line by hand:\n" + LINE)
    if args.check:
        print("already installed (will refresh SilkyOverview.qml)" if installed else "can be installed")
        return

    qml = target / SOURCE.name
    out = target / "silkyround.frag.qsb"
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    for path in (qml, out):
        if path.is_file():
            backup = path.with_name(f"{path.name}.bak-overview-{stamp}")
            shutil.copy2(path, backup)
            print(f"Backed up {backup}")

    shutil.copyfile(SOURCE, qml)
    # the rounded-corner shader: compiled here when Qt's shader baker is available, otherwise the prebuilt copy
    qsb = next((c for c in QSB_CANDIDATES if shutil.which(c)), None)
    if qsb:
        subprocess.run([qsb, "--qt6", "-o", str(out), str(SHADER)], check=True)
    else:
        shutil.copyfile(SHADER.with_name("silkyround.frag.qsb"), out)
    if not installed:
        shutil.copyfile(shell, shell.with_name("shell.qml.bak-overview"))
        tmp = shell.with_name("shell.qml.new")
        tmp.write_text(text.replace(ANCHOR, ANCHOR + LINE, 1))
        os.replace(tmp, shell)
    print(f"Installed {target / 'SilkyOverview.qml'}" + ("" if installed else " and added it to shell.qml"))
    print("Apply with: qs -c MacShell ipc call macshell reload")


if __name__ == "__main__":
    main()
