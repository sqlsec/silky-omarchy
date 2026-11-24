#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
plugin_dir="$repo_root/plugins/silky-gestures"
lib_dir="$HOME/.local/lib/silky-omarchy"
hypr_dir="$HOME/.config/hypr"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/silky-omarchy"
build_only=false

usage() {
  cat <<'USAGE'
Usage: scripts/install-silky-gestures.sh [--build-only]

Builds the Silky Gestures Hyprland plugin against the installed Hyprland
headers and enables it. Installs automatic maintenance for Omarchy updates.

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

for command_name in g++ make pkg-config Hyprland hyprctl jq; do
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
installed_abi=$(Hyprland --version | sed -n 's/^Version ABI string: //p')
if [[ -z $installed_abi ]]; then
  printf 'Could not determine the installed Hyprland ABI.\n' >&2
  exit 1
fi
running=$(hyprctl version -j 2>/dev/null || true)
running_version=$(jq -r '.version // empty' <<< "$running")
running_abi=$(jq -r '.abiHash // empty' <<< "$running")
if ! $build_only && [[ -n "$running_version" && "$running_abi" != "$installed_abi" ]]; then
  printf 'The running Hyprland ABI differs from the installed build. Use --build-only or log out and back in.\n' >&2
  exit 1
fi

make -C "$plugin_dir" clean >/dev/null
make -C "$plugin_dir"

mkdir -p "$lib_dir"
target="$lib_dir/silky-gestures-$headers_version.so"
backup_if_changed() {
  local source=$1 destination=$2
  if [[ -f $destination ]] && ! cmp -s "$source" "$destination"; then
    local backup="$destination.bak.$(date +%Y%m%d-%H%M%S-%N)"
    cp -a -- "$destination" "$backup"
    printf 'Backed up %s to %s\n' "$destination" "$backup"
  fi
}

# A loaded plugin stays mapped: replace the file instead of writing into it.
backup_if_changed "$plugin_dir/silky-gestures.so" "$target"
install -m 755 "$plugin_dir/silky-gestures.so" "$target.new"
mv -f "$target.new" "$target"
printf '%s\n' "$installed_abi" > "$target.abi.new"
mv -f "$target.abi.new" "$target.abi"
if [[ -n "$running_version" && "$running_version" != "$headers_version" ]]; then
  find "$lib_dir" -maxdepth 1 \( -name 'silky-gestures-*.so' -o -name 'silky-gestures-*.so.abi' \) \
    ! -name "silky-gestures-$headers_version.so" ! -name "silky-gestures-$headers_version.so.abi" \
    ! -name "silky-gestures-$running_version.so" ! -name "silky-gestures-$running_version.so.abi" -delete
else
  find "$lib_dir" -maxdepth 1 \( -name 'silky-gestures-*.so' -o -name 'silky-gestures-*.so.abi' \) \
    ! -name "silky-gestures-$headers_version.so" ! -name "silky-gestures-$headers_version.so.abi" -delete
fi
printf 'Installed %s\n' "$target"

$build_only && exit 0

hook_staging=$(mktemp -d)
trap 'rm -rf -- "$hook_staging"' EXIT
printf '#!/usr/bin/env bash\nexec %q "$@"\n' "$repo_root/hooks/post-update-silky-gestures" \
  > "$hook_staging/silky-gestures.hook"
mkdir -p "$state_dir"
installed_hook="$HOME/.config/omarchy/hooks/post-update.d/silky-gestures.hook"
if [[ -f $installed_hook ]] && ! cmp -s "$hook_staging/silky-gestures.hook" "$installed_hook"; then
  cp -p -- "$installed_hook" "$state_dir/post-update-silky-gestures.bak.$(date +%Y%m%d-%H%M%S-%N)"
fi
omarchy hook install post-update "$hook_staging/silky-gestures.hook"

libinput_package="$HOME/.local/share/silky-omarchy/libinput/libinput-1.32.0-1.4-aarch64.pkg.tar.xz"
if [[ -f $libinput_package ]] && { [[ -f $state_dir/libinput-maintained ]] || [[ $(pacman -Q libinput 2>/dev/null || true) == 'libinput 1.32.0-1.4' ]]; }; then
  sha256sum -- "$libinput_package" > "$state_dir/libinput-maintained"
fi

backup_if_changed "$repo_root/config/hypr/silky-gestures.lua" "$hypr_dir/silky-gestures.lua"
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
