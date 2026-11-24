#!/usr/bin/env python3
"""Install per-output wallpaper contrast in MacShell's menu bar."""

import argparse
import os
import shutil
import tempfile
from datetime import datetime
from pathlib import Path

ASSETS = Path(__file__).resolve().parents[1] / "config/macshell/menubar"

CONTRAST = """                SilkyBarContrast {
                    id: barContrast
                    width: ui.width
                    active: root.barEnabled
                    outputHeight: win.modelData ? win.modelData.height : 0
                    barHeight: root.barH
                    barFill: Math.max(0, Math.min(1, root.barBgOpacity))
                    fontFamily: root.fontFamily
                    wallpaper: win.modelData ? root.menuBarWallpaperFor(win.modelData.name) : ""
                }
                // Menu titles, workspaces and tray items declare a palette with the same id inside their
                // delegates, so each of them picks its own ink. These cover the remaining fixed controls.
                SilkyBarContrast.Palette { id: barMenuPalette; contrast: barContrast; items: leftRow.children.filter(child => child.activeApp === undefined) }
                SilkyBarContrast.Palette { id: barWorkspacePalette; contrast: barContrast; items: wsRow.children.filter(child => child.cur === undefined) }
                SilkyBarContrast.Palette { id: bpal; contrast: barContrast; items: rightRow.children.filter(child => child.silkyIconKind === undefined) }

"""

# Each delegate gets a palette for its own span: (anchor line, palette line).
DELEGATE_PALETTES = [
    ('                                readonly property bool activeApp: modelData.id === "app"\n',
     "                                SilkyBarContrast.Palette { id: barMenuPalette; contrast: barContrast; item: mt }\n"),
    ("                                readonly property bool busy: root.wsOccupied(modelData)\n",
     "                                SilkyBarContrast.Palette { id: barWorkspacePalette; contrast: barContrast; item: wsi }\n"),
    ("                                id: tray\n                                required property var modelData\n",
     "                                SilkyBarContrast.Palette { id: bpal; contrast: barContrast; item: tray }\n"),
]

WALLPAPER = """    Binding { target: root.hub; property: "barWantsWallpaper"; value: root.barEnabled || root.liquidActive }
    function menuBarWallpaperFor(screenName) {
        var path = wallpaperMap["wallpaper.display." + screenName]
                || wallpaperMap["wallpaper.monitors." + screenName]
                || wallpaperMap["wallpaper.last"] || wallpaperMap["wallpaper.default"];
        if (!path) return wallpaperFor(screenName);
        if (path.indexOf("~/") === 0) path = Quickshell.env("HOME") + path.substring(1);
        return path;
    }
"""

PROBE = r'''                + "printf '%s\n' \"$out\"\n"
                + "if [ -f \"$omarchy_bg\" ]; then\n"
                + "  hyprctl -j layers 2>/dev/null | jq -r --arg path \"$omarchy_bg\" "
                + "'to_entries[] | select(any(.value.levels[\"0\"][]?; .namespace == \"omarchy-background\")) "
                + "| \"wallpaper.display.\\(.key)\\t\\($path)\"'\n"
                + "fi\n"
                + "live=$(awww query 2>/dev/null || swww query 2>/dev/null)\n"
                + "if [ -n \"$live\" ]; then\n"
                + "  printf '%s\\n' \"$live\" | sed -nE 's/^(: )?([^:]+): .*image: (.*)$/wallpaper.display.\\2\\t\\3/p'\n"
                + "else\n"
                + "  hyprctl hyprpaper listactive 2>/dev/null | sed -nE 's/^([^ ]+) = (.+)$/wallpaper.display.\\1\\t\\2/p'\n"
                + "fi\n"'''


def replace(text, old, new):
    if text.count(old) != 1:
        raise ValueError(f"expected one match for {old.strip()[:90]!r}")
    return text.replace(old, new, 1)


def remove_between(text, start, end, replacement=""):
    first = text.index(start)
    last = text.index(end, first)
    return text[:first] + replacement + text[last:]


# Ask the shell for the live wallpaper as soon as awww has taken the new image, so the bar ink follows
# the wallpaper transition instead of the next 4 s poll.
WALLPAPER_APPLIED = "        onExited: { root.wallpaperSampleForce = true; wallpaperColorTimer.restart(); }\n"
WALLPAPER_REFRESH = ("        onExited: { root.wallpaperSampleForce = true; wallpaperColorTimer.restart();"
                     " if (root.hub && root.hub.refreshWallpaper) root.hub.refreshWallpaper(); }\n")


def per_control(text):
    """Upgrade the group-wide ink of earlier installs and give each delegate its own palette."""
    if WALLPAPER_APPLIED in text:
        text = text.replace(WALLPAPER_APPLIED, WALLPAPER_REFRESH, 1)
    if "                    groups: [" in text:
        text = remove_between(text, "                SilkyBarContrast {", "                // click-away layer", CONTRAST)
    for anchor, palette in DELEGATE_PALETTES:
        if anchor + palette not in text:
            text = replace(text, anchor, anchor + palette)
    return text


def tune_bar(text):
    if "id: barContrast" in text:
        return per_control(text)
    text = remove_between(text, "    // ── bar text colour:", "    property bool lockArtBackground")
    text = remove_between(text, "    // ── Dynamic text colour", "    readonly property bool panelTextDark")
    start = text.index("    QtObject {\n        id: bpal")
    end = text.index("\n    }\n", start) + len("\n    }\n")
    text = text[:start] + text[end:]
    for line in (
        '    property string barToneGeo: ""\n',
        '    readonly property string toneWallScript:',
        '    //  • bar: the strip behind the bar',
    ):
        start = text.index(line)
        text = text[:start] + text[text.index("\n", start) + 1:]
    # The panel sampling state was reset on appearance changes in the old bar watcher.
    text = replace(text, "    property var tonePending: null",
                   """    Connections {
        target: root
        function onDarkModeChanged() { root.panelTone = 0; }
        function onAutoContrastChanged() { if (!root.autoContrast) root.panelTone = 0; }
    }
    property var tonePending: null""")
    text = replace(text, '    Binding { target: root.hub; property: "barWantsWallpaper"; value: root.liquidActive }\n', WALLPAPER)
    text = remove_between(text, "                // Feather:", "                // click-away layer", CONTRAST)
    text = replace(text, "                    dark: !root.barTextDark", "                    dark: barWorkspacePalette.dark")
    text = replace(text, 'source: !root.barTextDark ? Qt.resolvedUrl("apple-logo-white.svg")',
                   'source: bpal.dark ? Qt.resolvedUrl("apple-logo-white.svg")')
    left = text.index("id: leftRow")
    center = text.index("id: wsRow", left)
    right = text.index("id: rightRow", center)
    text = (text[:left] + text[left:center].replace("bpal.", "barMenuPalette.")
            + text[center:right].replace("bpal.", "barWorkspacePalette.") + text[right:])
    old_tray = '''                                    // every tray glyph follows the resolved Light / Dark appearance; MacShell's
                                    // measured top-bar palette keeps bpal.fg white in both modes
                                    ink: root.darkMode ? "#FFFFFF" : "#1D1D1F"'''
    if old_tray in text:
        text = replace(text, old_tray, "                                    ink: bpal.fg")
    old_kimi = 'root.darkMode ? Qt.resolvedUrl("assets/tray/kimi-tray-white.png")'
    if old_kimi in text:
        text = replace(text, old_kimi, 'bpal.dark ? Qt.resolvedUrl("assets/tray/kimi-tray-white.png")')
    # The clock settings preview lives outside the bar.
    after_bar = text.index("\n                    }\n                }", text.index("id: rightRow"))
    text = text[:after_bar] + text[after_bar:].replace("bpal.fam", "root.fontFamily")
    return per_control(text)


def install(directory, stage):
    shell = directory / "shell.qml"
    bar = directory / "MacBar.qml"
    shell_text = shell.read_text()
    if "wallpaper.display." not in shell_text:
        source_lookup = r'''                + "p=$(readlink -f \"$HOME/.local/state/omarchy/current/background\" 2>/dev/null)\n"'''
        shell_text = replace(shell_text, source_lookup, source_lookup + "\n"
                             + r'''                + "omarchy_bg=$p\n"''')
        original_probe = r'''                + "printf '%s' \"$out\"'''
        ending = r'\n"' if original_probe + r'\n"' in shell_text else '"'
        shell_text = replace(shell_text, original_probe + ending, PROBE)
    changes = {
        shell: shell_text.encode(),
        bar: tune_bar(bar.read_text()).encode(),
        directory / "SilkyBarContrast.qml": (ASSETS / "SilkyBarContrast.qml").read_bytes(),
        directory / "assets/silky-bar-tone.py": (ASSETS / "silky-bar-tone.py").read_bytes(),
    }
    changes = {path: content for path, content in changes.items() if not path.exists() or path.read_bytes() != content}
    if not changes:
        return
    if not stage:
        state = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "macshell"
        state.mkdir(parents=True, exist_ok=True)
        backup = Path(tempfile.mkdtemp(prefix=f"silky-backup-bar-contrast-{datetime.now():%Y%m%d-%H%M%S}.", dir=state))
        for path in changes:
            if path.exists():
                saved = backup / path.relative_to(directory)
                saved.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(path, saved)
        print(f"MacShell menu bar backup: {backup}")
    # Write the component and sampler before QML starts referring to them.
    for path, content in reversed(changes.items()):
        path.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as temporary:
            pending = Path(temporary.name)
            temporary.write(content)
        try:
            pending.chmod(path.stat().st_mode & 0o777 if path.exists() else 0o644)
            pending.replace(path)
        finally:
            pending.unlink(missing_ok=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path, help="MacShell QML directory")
    parser.add_argument("--stage", action="store_true", help="edit a staged copy without another backup")
    args = parser.parse_args()
    try:
        install(args.directory, args.stage)
    except (OSError, ValueError) as error:
        parser.exit(1, f"MacShell menu bar contrast: {error}\n")
