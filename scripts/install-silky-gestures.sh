#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
plugin_dir="$repo_root/plugins/silky-gestures"
lib_dir="$HOME/.local/lib/silky-omarchy"
hypr_dir="$HOME/.config/hypr"
build_only=false

usage() {
  cat <<'USAGE'
Usage: scripts/install-silky-gestures.sh [--build-only]

Builds the Silky Gestures Hyprland plugin against the installed Hyprland
headers and enables it. Re-run after every Hyprland update.

  --build-only  Build and install the plugin file, but do not touch the
                Hyprland configuration or the running compositor.
USAGE
}

case "${1:-}" in
  "") ;;
  --build-only) build_only=true ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

for command_name in g++ make pkg-config hyprctl; do
  command -v "$command_name" >/dev/null || {
    printf 'Missing required command: %s\n' "$command_name" >&2
    exit 1
  }
done

pkg-config --exists hyprland || {
  printf 'Hyprland headers not found (pkg-config hyprland).\n' >&2
  exit 1
}

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
target="$lib_dir/silky-gestures-$headers_version.so"
# A loaded plugin stays mapped: replace the file instead of writing into it.
install -m 755 "$plugin_dir/silky-gestures.so" "$target.new"
mv -f "$target.new" "$target"
find "$lib_dir" -maxdepth 1 -name 'silky-gestures-*.so' ! -name "silky-gestures-$headers_version.so" -delete
printf 'Installed %s\n' "$target"

$build_only && exit 0

install -m 644 "$repo_root/config/hypr/silky-gestures.lua" "$hypr_dir/silky-gestures.lua"
if ! grep -q 'require("hypr.silky-gestures")' "$hypr_dir/hyprland.lua"; then
  cp -a "$hypr_dir/hyprland.lua" "$hypr_dir/hyprland.lua.bak.$(date +%Y%m%d-%H%M%S)"
  printf '\n-- Silky Omarchy: touch-screen workspace swipes and rubber band.\nrequire("hypr.silky-gestures")\n' >> "$hypr_dir/hyprland.lua"
fi

# Hyprland only (re)loads config plugins when the list in the config changes, so a reload alone neither picks up a
# rebuilt file nor brings back a plugin that was unloaded by hand. Let any automatic config reload settle, then swap
# the running copy explicitly; the config line takes care of the next login.
hyprctl reload >/dev/null
sleep 1
hyprctl plugin unload "$target" >/dev/null 2>&1 || true
hyprctl plugin load "$target" >/dev/null
hyprctl plugin list
