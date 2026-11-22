#!/usr/bin/env bash
set -euo pipefail

# Installs Silky Voice: the waveform pill for WowType and vinput (see docs/05-voice-overlay.md).
repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
target="$HOME/.config/quickshell/SilkyVoice"
hypr_dir="$HOME/.config/hypr"

for command_name in qs python3 hyprctl; do
  command -v "$command_name" >/dev/null || { printf 'Missing required command: %s\n' "$command_name" >&2; exit 1; }
done
python3 -c 'from gi.repository import Gio' 2>/dev/null || { printf 'Missing python-gobject.\n' >&2; exit 1; }

install_config() {
  local mode=$1 source=$2 destination=$3 backup
  if [[ -f "$destination" ]]; then
    if cmp -s "$source" "$destination"; then
      chmod "$mode" "$destination"
      return
    fi
    backup=$(mktemp "${destination}.bak.XXXXXX")
    cp -p -- "$destination" "$backup"
    printf 'Backed up %s to %s\n' "$destination" "$backup"
  fi
  install -m "$mode" "$source" "$destination"
}

mkdir -p "$target"
install_config 644 "$repo_root/voice-overlay/shell.qml" "$target/shell.qml"
install_config 755 "$repo_root/voice-overlay/bridge.py" "$target/bridge.py"
install_config 644 "$repo_root/config/hypr/silky-voice.lua" "$hypr_dir/silky-voice.lua"
if ! grep -q 'require("hypr.silky-voice")' "$hypr_dir/hyprland.lua"; then
  cp -a "$hypr_dir/hyprland.lua" "$hypr_dir/hyprland.lua.bak.$(date +%Y%m%d-%H%M%S)"
  printf '\n-- Silky Omarchy: waveform pill for WowType voice input.\nrequire("hypr.silky-voice")\n' >> "$hypr_dir/hyprland.lua"
fi

# Restart a running copy so the new files are used.
qs kill -c SilkyVoice >/dev/null 2>&1 || true
sleep 0.5
hyprctl dispatch 'hl.dsp.exec_cmd("qs -n -c SilkyVoice")' >/dev/null
printf 'Installed. Hold Right Alt in WowType or vinput and speak. Preview: SILKY_VOICE_DEMO=1 qs -c SilkyVoice\n'
