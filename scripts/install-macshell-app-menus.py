#!/usr/bin/env python3
"""Install per-application menu profiles into a MacShell 0.5.3 configuration."""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

SOURCE = Path(__file__).resolve().parents[1] / "config/macshell/app-menus"
CONFIG_HOME = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
STATE_HOME = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state")


def apply_patch(bar, reverse=False):
    command = ["git", "apply", "-p0", "--unidiff-zero"]
    if reverse:
        command.append("--reverse")
    return subprocess.run(
        [*command, str(SOURCE / "MacBar.patch")],
        cwd=bar.parent, capture_output=True, text=True, check=False,
        env={**os.environ, "GIT_CEILING_DIRECTORIES": str(bar.parent.parent)},
    )


def install(target, check):
    if (target / "VERSION").read_text().strip() != "0.5.3":
        raise ValueError(f"{target}: this patch requires MacShell 0.5.3")

    bar = target / "MacBar.qml"
    profiles = target / "SilkyAppMenus.js"
    with tempfile.TemporaryDirectory(prefix="app-menus-", dir=target) as directory:
        staged = Path(directory)
        staged_bar = staged / bar.name
        shutil.copy2(bar, staged_bar)
        result = apply_patch(staged_bar)
        if result.returncode:
            shutil.copy2(bar, staged_bar)
            if apply_patch(staged_bar, reverse=True).returncode:
                raise ValueError(f"{bar}: patch could not be applied cleanly\n{result.stdout}{result.stderr}")
            shutil.copy2(bar, staged_bar)

        staged_profiles = staged / profiles.name
        shutil.copy2(SOURCE / profiles.name, staged_profiles)
        changes = [
            path for path in (profiles, bar)
            if not path.exists() or path.read_bytes() != (staged / path.name).read_bytes()
        ]
        if not changes:
            print("MacShell application menus are up to date.")
            return
        if check:
            print("MacShell application menus can be installed.")
            return

        state = STATE_HOME / "macshell"
        state.mkdir(parents=True, exist_ok=True)
        backup = Path(tempfile.mkdtemp(prefix="silky-app-menus-", dir=state))
        for path in changes:
            if path.exists():
                shutil.copy2(path, backup / path.name)
        for path in changes:
            os.replace(staged / path.name, path)
        print(f"Installed application menus in {target}. Original files: {backup}")
        print("Reload with: qs -c MacShell ipc call macshell reload")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=CONFIG_HOME / "quickshell/MacShell")
    parser.add_argument("--check", action="store_true", help="check compatibility without installing")
    args = parser.parse_args()
    try:
        install(args.config.resolve(), args.check)
    except (OSError, ValueError) as error:
        sys.exit(str(error))


if __name__ == "__main__":
    main()
