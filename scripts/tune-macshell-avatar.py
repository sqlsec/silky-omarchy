#!/usr/bin/env python3
"""Refresh the Settings avatar and load the MacLock avatar independently."""

import sys
from pathlib import Path

AVATAR_COMPONENT = Path(__file__).resolve().parents[1] / "config/macshell/SilkyAccountAvatar.qml"


def replace_once(text, old, new):
    if text.count(new) == 1:
        return text
    if text.count(old) != 1:
        raise ValueError(f"expected one occurrence of {old.strip().splitlines()[0]!r}")
    return text.replace(old, new, 1)


def tune_settings(text):
    text = replace_once(
        text,
        "    Window {\n        id: prefsWindow\n",
        '''    Window {
        id: prefsWindow
        property int avatarRevision: 0
        readonly property url avatarSource: "file://" + Quickshell.env("HOME") + "/.face?" + avatarRevision
        Connections {
            target: prefsWindow
            function onVisibleChanged() {
                if (prefsWindow.visible) prefsWindow.avatarRevision++;
            }
        }
''',
    )
    for name, position, size in (
        ("acctPic", "x: 6; anchors.verticalCenter: parent.verticalCenter; width: 38; height: 38", 96),
        ("upic", "anchors.horizontalCenter: parent.horizontalCenter\nwidth: 84; height: 84", 200),
    ):
        anchor = f"SilkyAccountAvatar {{\n                        id: {name}"
        if anchor in text:
            continue
        start = text.index(f"                    Item {{\n                        id: {name}\n")
        end = text.index("\n                    }", start) + len("\n                    }")
        indentation = " " * 24
        geometry = position.replace("\n", "\n" + indentation)
        text = text[:start] + f'''                    SilkyAccountAvatar {{
                        id: {name}
                        {geometry}
                        source: prefsWindow.avatarSource
                        sourcePixels: {size}
                        placeholder: pal.ctrl
                    }}''' + text[end:]
    text = replace_once(
        text,
        'onStreamFinished: if (text.indexOf("ok") >= 0) upic.ver++',
        'onStreamFinished: if (text.indexOf("ok") >= 0) prefsWindow.avatarRevision++',
    )
    return text


def tune_lock(text):
    avatar_lookup = next(
        (
            line.strip()[2:]
            for line in text.splitlines()
            if line.strip().startswith('+ "for a in ') and ".face.icon" in line
        ),
        None,
    )
    if avatar_lookup is None:
        if 'onStreamFinished: lockState.avatar = text.trim()' in text:
            return text
        raise ValueError("expected the MacLock account picture lookup")

    text = replace_once(
        text,
        "    // ── one-shot lookups: real name, avatar, wifi, and other settings",
        f'''    // Load the account picture before network probes finish.
    Process {{
        running: true
        command: ["sh", "-c", {avatar_lookup}]
        stdout: StdioCollector {{
            onStreamFinished: lockState.avatar = text.trim()
        }}
    }}

    // ── one-shot lookups: real name, wifi, and other settings''',
    )
    text = text.replace(f"            + {avatar_lookup}\n", "", 1)
    assignments = text.index("                lockState.avatar = (l[1]")
    start, end = text.index("\n", assignments) + 1, text.index("                if (!root.preview) lockState.sound", assignments)
    settings = text[start:end]
    for index in range(2, 9):
        settings = settings.replace(f"l[{index}]", f"l[{index - 1}]")
    return text[:assignments] + settings + text[end:]


if __name__ == "__main__":
    try:
        settings_path, lock_path = map(Path, sys.argv[1:])
        files = [(settings_path, tune_settings), (lock_path, tune_lock)]
        originals = [path.read_text() for path, _ in files]
        updated = [tune(text) for (_, tune), text in zip(files, originals)]
        component_path = settings_path.with_name(AVATAR_COMPONENT.name)
        component = AVATAR_COMPONENT.read_bytes()
        if not component_path.exists() or component_path.read_bytes() != component:
            component_path.write_bytes(component)
        for (path, _), original, update in zip(files, originals, updated):
            if original != update:
                path.write_text(update)
    except (OSError, ValueError) as error:
        sys.exit(f"MacShell avatar: {error}")
