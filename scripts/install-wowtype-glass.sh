#!/usr/bin/env bash
set -euo pipefail

# Installs Silky Glass: rounded, frosted WowType candidate skins that follow light / dark mode,
# and the Hyprland rules for WeChat and WPS popups (see docs/09-wowtype-glass.md).
repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
hypr_dir="$HOME/.config/hypr"
themes_dir="${XDG_DATA_HOME:-$HOME/.local/share}/fcitx5/themes"
classicui="$HOME/.config/fcitx5/conf/classicui.conf"

for command_name in python3 rsvg-convert gsettings busctl hyprctl systemctl; do
  command -v "$command_name" >/dev/null || { printf 'Missing required command: %s\n' "$command_name" >&2; exit 1; }
done

python3 "$repo_root/wowtype-glass/build-themes.py" "$themes_dir"

if [[ -f $classicui ]] && [[ ! -f $classicui.silky-backup ]]; then
  cp -a "$classicui" "$classicui.silky-backup"
fi
install -Dm 755 "$repo_root/wowtype-glass/silky-ime-theme" "$HOME/.local/bin/silky-ime-theme"
install -Dm 755 "$repo_root/wowtype-glass/silky-xwayland-dpi" "$HOME/.local/bin/silky-xwayland-dpi"
install -Dm 644 "$repo_root/config/systemd/silky-ime-theme.service" "$HOME/.config/systemd/user/silky-ime-theme.service"
systemctl --user daemon-reload
systemctl --user enable --now silky-ime-theme.service
systemctl --user restart silky-ime-theme.service

install -m 644 "$repo_root/config/hypr/silky-ime.lua" "$hypr_dir/silky-ime.lua"
if ! grep -q 'require("hypr.silky-ime")' "$hypr_dir/hyprland.lua"; then
  cp -a "$hypr_dir/hyprland.lua" "$hypr_dir/hyprland.lua.bak.$(date +%Y%m%d-%H%M%S)"
  printf '\n-- Silky Omarchy: crisp, glassy WowType candidate window.\nrequire("hypr.silky-ime")\n' >> "$hypr_dir/hyprland.lua"
fi
hyprctl reload >/dev/null
if ! "$HOME/.local/bin/silky-xwayland-dpi"; then
  printf 'Could not set XWayland DPI in this session. Hyprland will retry at startup.\n' >&2
fi

# WeChat only: show pinyin in the candidate bar so the bar stops being remapped on every key.
if command -v pkg-config >/dev/null && command -v make >/dev/null && pkg-config --exists Fcitx5Core; then
  preedit_src="$repo_root/plugins/silky-wechat-preedit"
  preedit_lib="$HOME/.local/lib/silky-omarchy/libsilkywechatpreedit"
  make -s -C "$preedit_src" -B
  install -Dm 755 "$preedit_src/libsilkywechatpreedit.so" "$preedit_lib.so"
  mkdir -p "${XDG_DATA_HOME:-$HOME/.local/share}/fcitx5/addon"
  sed "s|@LIBRARY@|$preedit_lib|" "$preedit_src/silky-wechat-preedit.conf.in" \
    > "${XDG_DATA_HOME:-$HOME/.local/share}/fcitx5/addon/silky-wechat-preedit.conf"
  if pgrep -x fcitx5 >/dev/null; then
    busctl --user call org.fcitx.Fcitx5 /controller org.fcitx.Fcitx.Controller1 Restart >/dev/null ||
      printf 'Could not restart fcitx5. Log out and back in to load the WeChat preedit addon.\n' >&2
  fi
else
  printf 'Skipped the WeChat preedit addon: needs make, pkg-config and fcitx5 headers (Fcitx5Core).\n' >&2
fi

printf 'Installed. Restart WeChat once so its built-in candidate bar loads the new skin.\n'
printf 'Undo: systemctl --user disable --now silky-ime-theme; mv %s.silky-backup %s\n' "$classicui" "$classicui"
