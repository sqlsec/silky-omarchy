#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
launcher="$HOME/.local/bin/wechat-wayland-touch"
wechat_dir="${XDG_DATA_HOME:-$HOME/.local/share}/wechat-wayland"
hypr_dir="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
hypr_config="$hypr_dir/hyprland.lua"

if [[ ! -x $launcher ]] || ! grep -Fq 'touch-scroll.so' "$launcher"; then
  printf 'The existing WeChat Wayland launcher with touch-scroll support is required: %s\n' "$launcher" >&2
  exit 1
fi
[[ -f $hypr_config ]] || { printf 'Missing Hyprland config: %s\n' "$hypr_config" >&2; exit 1; }
pkg-config --exists wayland-client || { printf 'Missing Wayland client development files.\n' >&2; exit 1; }

build_dir=$(mktemp -d)
trap 'rm -rf -- "$build_dir"' EXIT
scroll_source="$repo_root/plugins/wechat-wayland/touch-scroll.c"
cc -std=gnu11 -Wall -Wextra -O2 -shared -fPIC -Wl,-z,defs \
  $(pkg-config --cflags wayland-client) "$scroll_source" -o "$build_dir/touch-scroll.so" \
  $(pkg-config --libs wayland-client)

install_with_backup() {
  local source=$1 target=$2 mode=$3 backup staged
  if cmp -s "$source" "$target"; then return; fi
  if [[ -f $target ]]; then
    backup=$(mktemp "$target.bak.XXXXXXXX")
    cp -p -- "$target" "$backup"
    printf 'Backed up %s to %s\n' "$target" "$backup"
  fi
  staged=$(mktemp "$target.tmp.XXXXXXXX")
  if ! install -m "$mode" "$source" "$staged" || ! mv -fT -- "$staged" "$target"; then
    rm -f -- "$staged"
    return 1
  fi
}

mkdir -p -- "$wechat_dir"
install_with_backup "$scroll_source" "$wechat_dir/touch-scroll.c" 644
install_with_backup "$build_dir/touch-scroll.so" "$wechat_dir/touch-scroll.so" 755
install_with_backup "$repo_root/config/hypr/silky-wechat-glass.lua" "$hypr_dir/silky-wechat-glass.lua" 644
if ! grep -Fq 'require("hypr.silky-wechat-glass")' "$hypr_config"; then
  cp -- "$hypr_config" "$build_dir/hyprland.lua"
  printf '\nrequire("hypr.silky-wechat-glass")\n' >> "$build_dir/hyprland.lua"
  install_with_backup "$build_dir/hyprland.lua" "$hypr_config" 644
fi

hyprctl reload >/dev/null
errors=$(hyprctl configerrors)
if [[ -n ${errors//[[:space:]]/} ]]; then
  printf '%s\n' "$errors" >&2
  exit 1
fi
printf 'WeChat main-window appearance applied. Quit and reopen WeChat to load the new touch scrolling adapter.\n'
