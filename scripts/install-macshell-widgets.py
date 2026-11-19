#!/usr/bin/env python3
"""Install the Silky widgets (weather, stocks, screen time, batteries, calendar, system) under MacShell's notifications."""
import argparse
import os
import shutil
import re
import stat
import urllib.request
from pathlib import Path
from tempfile import NamedTemporaryFile

SOURCE = Path(__file__).resolve().parents[1] / "config/macshell/widgets"
VERSIONS = {"0.5.1", "0.5.2", "0.5.3"}
NEEDS = ["WeatherIcon.qml", "ChinaCalendar.js", "I18n.js"]
# Brand logos for the AI usage widget, from LobeHub's MIT-licensed icon set (the logos are their owners' trademarks,
# so they are fetched at install time instead of being kept in this repository). Pinned for reproducibility.
LOGO_PACKAGE = "https://cdn.jsdelivr.net/npm/@lobehub/icons-static-svg@1.104.0/icons/"
LOGOS = {"claude": "claude-color.svg", "codex": "codex-color.svg", "deepseek": "deepseek-color.svg"}

FULL_H_OLD = ("                    property real fullH: 92 + (notifHist.count === 0 ? 70 : "
              "(root.notifClearing ? Math.max(70, nfl.height) : nfl.height)) + 14\n")
FULL_H_NEW = ("                    readonly property real silkyListH: notifHist.count === 0 ? 70 : "
              "(root.notifClearing ? Math.max(70, nfl.height) : nfl.height)\n"
              "                    // Silky widgets sit under the list (scripts/install-macshell-widgets.py)\n"
              "                    property real fullH: 92 + silkyListH + 14 + (silkyWidgetDeck.height > 0 ? silkyWidgetDeck.height + 6 : 0)\n")
LIST_OLD = "                    Flickable {\n                        id: nfl\n"
DECK = """                    SilkyWidgetDeck {
                        id: silkyWidgetDeck
                        x: 12; y: 92 + notifPop.silkyListH + 10
                        opacity: notifPop.merging ? notifPop.chrome : notifPop.contentT
                        theme: pal
                        fam: pal.fam
                        bold: root.fontForWeight(Font.DemiBold, pal.fam)
                        accent: (pal && silkyStatusSummary.sample?.wallpaperAccent?.[pal.dark ? "dark" : "light"]) || (pal ? pal.accent : "#6cb8ff")
                        open: ui.pop === "notif"
                        maxHeight: Math.max(172, (ui.height - notifPop.dstY - 12) / notifPop.ps - (92 + notifPop.silkyListH + 30))
                        // the Control Center tile material: the panel's liquid glass again, with the same thin border
                        glass: Component {
                            Item {
                                property real r: 22
                                GGlass { anchors.fill: parent; gx: notifPopGlass.ctx; cornerR: parent.r; thickness: 22; shadowAmt: 0; flatInner: 1 }
                                CornerBorder {
                                    z: 2; anchors.fill: parent; cornerR: parent.r; lineW: 0.8
                                    dark: notifPopGlass.ctx.dark; tint: notifPopGlass.ctx.borderTint; amount: notifPopGlass.ctx.borderAmount
                                }
                            }
                        }
                    }
"""
FOCUS_OLD = ('            WlrLayershell.keyboardFocus: ((ui.pop === "wifi" || (ui.pop === "cc" && ui.ccPage === "wifi")) '
             '&& ui.wifiPrompt !== "") ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None\n')
FOCUS_NEW = ('            WlrLayershell.keyboardFocus: (ui.pop === "notif" && silkyWidgetDeck.wantsKeyboard) ? WlrKeyboardFocus.OnDemand\n'
             '                : ((ui.pop === "wifi" || (ui.pop === "cc" && ui.ccPage === "wifi")) '
             '&& ui.wifiPrompt !== "") ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None\n')


def strip_deck(text):
    """Remove a deck block left by an earlier version, so the current DECK is inserted fresh."""
    start = text.find("                    SilkyWidgetDeck {\n")
    if start < 0 or DECK in text:
        return text
    end = text.index("\n                    }\n", start) + len("\n                    }\n")
    return text[:start] + text[end:]


def integrate(text):
    if "id: silkyStatusSummary" not in text:
        raise ValueError("Install the MacShell status integration first: python3 scripts/install-macshell-status.py")
    text = strip_deck(text)
    for before, after in ((FULL_H_OLD, FULL_H_NEW), (LIST_OLD, DECK + LIST_OLD), (FOCUS_OLD, FOCUS_NEW)):
        if after in text:
            continue
        if text.count(before) != 1:
            raise ValueError(f"MacBar integration point changed: {before.strip().splitlines()[0][:90]}")
        text = text.replace(before, after, 1)
    return text


def fetch_logos(root):
    """Download the AI logos once; on failure the widget shows coloured letter tiles instead."""
    folder = root / "assets/ai-logos"
    folder.mkdir(parents=True, exist_ok=True)
    for name, remote in LOGOS.items():
        target = folder / f"{name}.svg"
        if target.exists():
            continue
        try:
            with urllib.request.urlopen(LOGO_PACKAGE + remote, timeout=15) as response:
                svg = response.read(65536).decode("utf-8")
        except (OSError, UnicodeDecodeError) as error:
            print(f"Logo {name} not downloaded ({error}); the widget uses a letter tile")
            continue
        if not svg.lstrip().startswith("<svg") or re.search(r"<script|<foreignObject|\bon\w+=|href=\"(?!#)", svg, re.I):
            print(f"Logo {name} rejected: not a plain SVG")
            continue
        target.write_text(svg)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("shell_dir", type=Path, nargs="?", default=Path(
        os.environ.get("MACSHELL_DIR", Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
                       / "quickshell/MacShell")))
    args = parser.parse_args()
    root = args.shell_dir
    bar = root / "MacBar.qml"
    try:
        if (root / "VERSION").read_text().strip() not in VERSIONS:
            raise ValueError("This integration targets MacShell 0.5.1 to 0.5.3.")
        missing = [name for name in NEEDS if not (root / name).exists()]
        if missing:
            raise ValueError("MacShell is missing " + ", ".join(missing))
        if not shutil.which("python3"):
            raise ValueError("python3 is required for the widget data process")
        original = bar.read_text()
        updated = integrate(original)
    except (OSError, ValueError) as error:
        parser.exit(1, f"{error}\n")
    if args.check:
        print(f"MacShell widgets integration compatible at {root}")
        return

    (root / "assets").mkdir(exist_ok=True)
    (Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "silky").mkdir(parents=True, exist_ok=True)
    changed = False
    for source in sorted(SOURCE.iterdir()):
        if not source.is_file():
            continue
        destination = root / "assets/silky-widgets.py" if source.name == "widgets.py" else root / source.name
        if not destination.exists() or destination.read_bytes() != source.read_bytes():
            with NamedTemporaryFile(dir=destination.parent, delete=False) as tmp:
                tmp.write(source.read_bytes())
            Path(tmp.name).replace(destination)
            changed = True
    fetch_logos(root)
    if updated != original:
        backup = bar.with_name(f"MacBar.qml.bak.silky-widgets-{os.urandom(4).hex()}")
        shutil.copy2(bar, backup)
        with NamedTemporaryFile(mode="w", dir=root, delete=False) as tmp:
            tmp.write(updated)
            os.fchmod(tmp.fileno(), stat.S_IMODE(bar.stat().st_mode))
        Path(tmp.name).replace(bar)
        print(f"Backup: {backup}")
    elif changed:
        bar.touch()      # atomic replacement of a child QML file can leave its old watcher behind
    print(f"MacShell widgets installed at {root}")


if __name__ == "__main__":
    main()
