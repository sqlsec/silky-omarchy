#!/usr/bin/env bash
set -euo pipefail

# Completely covered windows stop redrawing: the silky-occlusion Hyprland plugin holds their frame callbacks
# until any part of them shows again (see docs/02-macshell.md).
repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
plugin_dir="$repo_root/plugins/silky-occlusion"
lib_dir="$HOME/.local/lib/silky-omarchy"
hypr_dir="$HOME/.config/hypr"
stamp=$(date +%Y%m%d-%H%M%S)

usage() {
  cat <<'USAGE'
Usage: scripts/install-occlusion-plugin.sh [--build-only | --remove]

Builds the silky-occlusion Hyprland plugin against the installed Hyprland headers, installs it and loads it into
the running Hyprland. Re-run after every Hyprland update.

  --build-only  Build and install the plugin file only.
  --remove      Unload the plugin and stop loading it at login (the built files stay in place).
USAGE
}

mode=install
case "${1:-}" in
  "") ;;
  --build-only) mode=build ;;
  --remove) mode=remove ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

require_line='require("hypr.silky-occlusion")'
main_config="$hypr_dir/hyprland.lua"

if [[ $mode == remove ]]; then
  if [[ -f $main_config ]] && grep -Fxq "$require_line" "$main_config"; then
    cp -a -- "$main_config" "$main_config.bak.$stamp"
    grep -Fxv "$require_line" "$main_config.bak.$stamp" \
      | grep -Fxv -- '-- Silky Omarchy: completely covered windows stop redrawing.' > "$main_config"
    printf 'Removed the plugin from %s (backup: %s)\n' "$main_config" "$main_config.bak.$stamp"
  fi
  while read -r path; do
    [[ -n $path ]] && hyprctl plugin unload "$path" >/dev/null 2>&1 || true
  done < <(find "$lib_dir" -maxdepth 1 -name 'silky-occlusion-*.so' 2>/dev/null)
  hyprctl reload >/dev/null
  if hyprctl plugin list 2>/dev/null | grep -q 'silky-occlusion'; then
    printf 'The plugin is still loaded; sign out and back in to drop it.\n' >&2
    exit 1
  fi
  printf 'silky-occlusion unloaded. Covered windows redraw at full rate again.\n'
  exit 0
fi

for command_name in g++ make pkg-config hyprctl; do
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
target="$lib_dir/silky-occlusion-$headers_version.so"
# A loaded plugin stays mapped: replace the file instead of writing into it.
if [[ -f $target ]] && ! cmp -s "$plugin_dir/silky-occlusion.so" "$target"; then
  cp -a -- "$target" "$target.bak.$stamp"
  printf 'Backed up %s\n' "$target.bak.$stamp"
fi
install -m 755 "$plugin_dir/silky-occlusion.so" "$target.new"
mv -f "$target.new" "$target"
printf 'Installed %s\n' "$target"
[[ $mode == build ]] && exit 0

[[ -f $main_config ]] || { printf 'Hyprland config not found: %s\n' "$main_config" >&2; exit 1; }
if [[ -f $hypr_dir/silky-occlusion.lua ]] && ! cmp -s "$repo_root/config/hypr/silky-occlusion.lua" "$hypr_dir/silky-occlusion.lua"; then
  cp -a -- "$hypr_dir/silky-occlusion.lua" "$hypr_dir/silky-occlusion.lua.bak.$stamp"
fi
install -m 644 "$repo_root/config/hypr/silky-occlusion.lua" "$hypr_dir/silky-occlusion.lua"
if ! grep -Fxq "$require_line" "$main_config"; then
  cp -a -- "$main_config" "$main_config.bak.$stamp"
  printf '\n-- Silky Omarchy: completely covered windows stop redrawing.\n%s\n' "$require_line" >> "$main_config"
  printf 'Added the plugin to %s (backup: %s)\n' "$main_config" "$main_config.bak.$stamp"
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
hyprctl plugin list | grep -A2 'silky-occlusion' || { printf 'The plugin did not load; see the Hyprland log.\n' >&2; exit 1; }
hyprctl silkyocclusion
