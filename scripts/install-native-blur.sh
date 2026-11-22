#!/usr/bin/env bash
set -euo pipefail

# Switch MacShell's menu bar, popovers, Applications panel and Dock from Liquid Glass to Hyprland blur
# (see docs/02-macshell.md). Safe to run repeatedly. Restart MacShell afterwards.
repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
hypr_dir="$HOME/.config/hypr"
stamp=$(date +%Y%m%d-%H%M%S)

for command_name in jq hyprctl python3; do
  command -v "$command_name" >/dev/null || { printf 'Missing required command: %s\n' "$command_name" >&2; exit 1; }
done
[[ -f "$hypr_dir/hyprland.lua" ]] || { printf 'Missing %s\n' "$hypr_dir/hyprland.lua" >&2; exit 1; }

if [[ -f "$hypr_dir/silky-native-blur.lua" ]]; then
  cp -a "$hypr_dir/silky-native-blur.lua" "$hypr_dir/silky-native-blur.lua.bak.$stamp"
fi
install -m 644 "$repo_root/config/hypr/silky-native-blur.lua" "$hypr_dir/silky-native-blur.lua"
if ! grep -q 'require("hypr.silky-native-blur")' "$hypr_dir/hyprland.lua"; then
  cp -a "$hypr_dir/hyprland.lua" "$hypr_dir/hyprland.lua.bak.$stamp"
  printf '\n-- Silky Omarchy: Hyprland blur behind MacShell popovers, switcher, wallpaper picker and OSD.\nrequire("hypr.silky-native-blur")\n' >> "$hypr_dir/hyprland.lua"
fi
hyprctl reload >/dev/null
errors=$(hyprctl configerrors)
if [[ -n "${errors//[[:space:]]/}" ]]; then
  printf 'Hyprland reported config errors:\n%s\n' "$errors" >&2
  exit 1
fi

set_style() {
  local path=$1 key=$2 temporary
  [[ -f "$path" ]] || { printf 'Skipped %s (not found; open MacShell Settings once first)\n' "$path"; return 0; }
  [[ "$(jq -r --arg k "$key" '.[$k] // ""' "$path")" == blur ]] && return 0
  cp -a "$path" "$path.bak.$stamp"
  temporary=$(mktemp "${path}.silky.XXXXXX")
  jq --arg k "$key" '.[$k] = "blur"' "$path" > "$temporary"
  chmod --reference="$path" "$temporary"
  mv -f "$temporary" "$path"
  printf 'Set %s = "blur" in %s (backup: %s.bak.%s)\n' "$key" "$path" "$path" "$stamp"
}
# Tint close to Liquid Glass + quieter About button (backs up the QML files it changes).
shell_dir=${MACSHELL_DIR:-"$HOME/.config/quickshell/MacShell"}
if [[ -d "$shell_dir" ]]; then
  backup_dir="$HOME/.local/state/macshell/silky-backup-native-blur-$stamp/MacShell"
  mkdir -p "$backup_dir"
  cp -a "$shell_dir/MacBar.qml" "$shell_dir/MacDock.qml" "$shell_dir/AboutApp.qml" "$backup_dir/"
  python3 "$repo_root/scripts/tune-native-blur.py" "$shell_dir"
  printf 'Tuned Normal Blur tints in %s (backup: %s)\n' "$shell_dir" "$backup_dir"
fi

set_style "$HOME/.config/macbar/settings.json" barStyle
set_style "$HOME/.config/macdock/settings.json" dockStyle

printf 'Done. Restart MacShell from Settings > Tools > Restart to apply.\n'
