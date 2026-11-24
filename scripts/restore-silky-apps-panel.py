#!/usr/bin/env python3
"""Restore the Applications panel on a compatible MacShell after an update."""

import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


REPO = Path(__file__).resolve().parents[1]
# MacBar hunks from the existing 0.5.2 patch. Stock MacShell 0.5.3 shares
# these contexts. The rest of the patch manages unrelated MacShell features.
LAUNCHPAD_HUNKS = {
    3184, 3485,                                        # IPC and settings
    5120, 5138, 5160, 5175, 5194, 5236, 5254, 5265,      # state and events
    5369, 5538, 5554, 5585,                            # backdrop warm-up
    9565, 9589, 9603, 9688, 9747, 9782, 9803,            # surface and Spotlight
    10535, 10608, 10616,                               # Applications content
}


def launchpad_patch():
    text = (REPO / "patches/macshell-0.5.2-silky.patch").read_text()
    macbar = next(section for section in re.split(r"(?=^diff --git )", text, flags=re.M)
                  if section.startswith("diff --git i/MacShell/MacBar.qml "))
    header, *hunks = re.split(r"(?=^@@ )", macbar, flags=re.M)
    selected = {int(re.match(r"@@ -(\d+)", hunk)[1]): hunk for hunk in hunks}
    return header + "".join(selected[number] for number in sorted(LAUNCHPAD_HUNKS))


def dock_glass_enabled(config: Path) -> bool:
    env_file = config / "macshell/env"
    if not env_file.is_file():
        return False
    return any(line.strip() == "export SILKY_DOCK_GLASS_PLUGIN=1"
               for line in env_file.read_text(errors="ignore").splitlines())


def restore(shell, state, config):
    bar = shell / "MacBar.qml"
    if not bar.is_file():
        return
    dock = shell / "MacDock.qml"
    original_bar = bar.read_bytes()
    original_dock = dock.read_bytes() if dock.is_file() else None

    with tempfile.TemporaryDirectory(prefix=".silky-apps-", dir=shell) as directory:
        stage_dir = Path(directory)
        staged_bar = stage_dir / bar.name
        staged_bar.write_bytes(original_bar)
        shutil.copymode(bar, staged_bar)

        staged_dock = None
        if original_dock is not None:
            staged_dock = stage_dir / dock.name
            staged_dock.write_bytes(original_dock)
            shutil.copymode(dock, staged_dock)

        for helper in ("DockGlassPanel.qml", "SilkyGlassMarker.qml"):
            src = shell / helper
            if src.is_file():
                shutil.copy2(src, stage_dir / helper)

        if b"function lpEvent(data)" not in original_bar:
            result = subprocess.run(
                ["patch", "--batch", "--forward", "--fuzz=0", "--no-backup-if-mismatch",
                 "--reject-file=-", str(staged_bar)],
                input=launchpad_patch(), text=True, capture_output=True,
            )
            if result.returncode:
                raise ValueError(f"the Applications patch no longer matches {bar}")

        subprocess.run([sys.executable, REPO / "scripts/tune-apps-panel.py", staged_bar], check=True)
        if staged_dock is not None:
            subprocess.run([sys.executable, REPO / "scripts/tune-apps-dock-passthrough.py", staged_dock], check=True)
        if dock_glass_enabled(config):
            subprocess.run([sys.executable, REPO / "scripts/tune-dock-glass-plugin.py", stage_dir], check=True)

        bar_changed = staged_bar.read_bytes() != original_bar
        dock_changed = staged_dock is not None and staged_dock.read_bytes() != original_dock
        if not bar_changed and not dock_changed:
            return

        state.mkdir(parents=True, exist_ok=True)
        backups = []
        if bar_changed:
            with tempfile.NamedTemporaryFile(prefix="MacBar.qml.before-apps-update.", dir=state,
                                             delete=False) as backup:
                backup.write(original_bar)
                backups.append(backup.name)
        if dock_changed:
            with tempfile.NamedTemporaryFile(prefix="MacDock.qml.before-apps-update.", dir=state,
                                             delete=False) as backup:
                backup.write(original_dock)
                backups.append(backup.name)
        if bar.read_bytes() != original_bar or (dock_changed and dock.read_bytes() != original_dock):
            raise ValueError("MacShell files changed while preparing the Applications update")
        if bar_changed:
            staged_bar.replace(bar)
        if dock_changed:
            staged_dock.replace(dock)
        print(f"Restored the Applications panel. Backup: {', '.join(backups)}")


if __name__ == "__main__":
    config = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    state = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "silky-omarchy"
    shell = Path(os.environ.get("MACSHELL_DIR", config / "quickshell/MacShell"))
    try:
        restore(shell, state, config)
    except (OSError, ValueError, KeyError, StopIteration, subprocess.CalledProcessError) as error:
        sys.exit(f"Silky Applications panel: {error}")
