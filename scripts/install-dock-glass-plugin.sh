#!/usr/bin/env bash
set -euo pipefail

# Prototype: zero-latency Liquid Glass for the MacShell Dock, drawn by the silky-dock-glass Hyprland plugin
# (see docs/02-macshell.md). Requires the Dock in the Normal Blur style (scripts/install-native-blur.sh).
repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
plugin_dir="$repo_root/plugins/silky-dock-glass"
lib_dir="$HOME/.local/lib/silky-omarchy"
hypr_dir="$HOME/.config/hypr"
shell_dir=${MACSHELL_DIR:-"$HOME/.config/quickshell/MacShell"}
env_file="$HOME/.config/macshell/env"
stamp=$(date +%Y%m%d-%H%M%S)

usage() {
  cat <<'USAGE'
Usage: scripts/install-dock-glass-plugin.sh [--build-only]

Builds the silky-dock-glass Hyprland plugin against the installed Hyprland headers, loads it, and switches MacDock
to hand its glass to the plugin. Re-run after every Hyprland update. Restart MacShell afterwards.

  --build-only  Build and install the plugin file only.
USAGE
}

build_only=false
case "${1:-}" in
  "") ;;
  --build-only) build_only=true ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

for command_name in g++ make pkg-config hyprctl python3; do
  command -v "$command_name" >/dev/null || { printf 'Missing required command: %s\n' "$command_name" >&2; exit 1; }
done
pkg-config --exists hyprland || { printf 'Hyprland headers not found (pkg-config hyprland).\n' >&2; exit 1; }

headers_version=$(pkg-config --modversion hyprland)
running_version=$(hyprctl version -j | sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' | head -n1)
if [[ -n "$running_version" && "$running_version" != "$headers_version" ]]; then
  printf 'Running Hyprland is %s but the headers are %s. Log out and back in after the update, then re-run.\n' \
    "$running_version" "$headers_version" >&2
  exit 1
fi

make -C "$plugin_dir" clean >/dev/null
make -C "$plugin_dir"
mkdir -p "$lib_dir"
target="$lib_dir/silky-dock-glass-$headers_version.so"
# A loaded plugin stays mapped: replace the file instead of writing into it.
if [[ -f $target ]] && ! cmp -s "$plugin_dir/silky-dock-glass.so" "$target"; then
  cp -a -- "$target" "$target.bak.$stamp"
  printf 'Backed up %s\n' "$target.bak.$stamp"
fi
install -m 755 "$plugin_dir/silky-dock-glass.so" "$target.new"
mv -f "$target.new" "$target"
printf 'Installed %s\n' "$target"
$build_only && exit 0

[[ -f "$shell_dir/MacDock.qml" ]] || { printf 'MacShell not found in %s\n' "$shell_dir" >&2; exit 1; }
backup_dir="$HOME/.local/state/macshell/silky-backup-dock-glass-$stamp"
mkdir -p "$backup_dir"
cp -a "$shell_dir/MacDock.qml" "$backup_dir/"
[[ ! -f "$shell_dir/MacBar.qml" ]] || cp -a "$shell_dir/MacBar.qml" "$backup_dir/"
[[ ! -f "$shell_dir/SilkyGlassMarker.qml" ]] || cp -a "$shell_dir/SilkyGlassMarker.qml" "$backup_dir/"
[[ ! -f "$env_file" ]] || cp -a "$env_file" "$backup_dir/env"
python3 "$repo_root/scripts/tune-dock-glass-plugin.py" "$shell_dir"
mkdir -p "$(dirname -- "$env_file")"
touch "$env_file"
grep -q '^export SILKY_DOCK_GLASS_PLUGIN=1' "$env_file" \
  || printf '\n# Silky Omarchy: the silky-dock-glass Hyprland plugin paints MacShell glass\nexport SILKY_DOCK_GLASS_PLUGIN=1\n' >> "$env_file"
printf 'MacDock and MacBar tuned (backup: %s)\n' "$backup_dir"

# Live-tunable glass parameters: installed once, never overwritten (your own tuning stays).
conf="$HOME/.config/silky-omarchy/dock-glass.conf"
[[ -f "$conf" ]] || install -Dm 644 "$repo_root/config/silky-omarchy/dock-glass.conf" "$conf"

install -m 644 "$repo_root/config/hypr/silky-dock-glass.lua" "$hypr_dir/silky-dock-glass.lua"
if ! grep -q 'require("hypr.silky-dock-glass")' "$hypr_dir/hyprland.lua"; then
  cp -a "$hypr_dir/hyprland.lua" "$hypr_dir/hyprland.lua.bak.$stamp"
  printf '\n-- Silky Omarchy (prototype): Liquid Glass Dock drawn by Hyprland.\nrequire("hypr.silky-dock-glass")\n' >> "$hypr_dir/hyprland.lua"
fi

# Hyprland only (re)loads config plugins when the list changes: swap the running copy explicitly.
hyprctl reload >/dev/null
sleep 1
hyprctl plugin unload "$target" >/dev/null 2>&1 || true
hyprctl plugin load "$target" >/dev/null
errors=$(hyprctl configerrors)
if [[ -n "${errors//[[:space:]]/}" ]]; then
  printf 'Hyprland reported config errors:\n%s\n' "$errors" >&2
  exit 1
fi
hyprctl plugin list | grep -A2 'silky-dock-glass' || { printf 'The plugin did not load; see the Hyprland log.\n' >&2; exit 1; }
printf 'Done. Restart MacShell from Settings > Tools > Restart so the Dock hands its glass to the plugin.\n'
