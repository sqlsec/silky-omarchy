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

printf 'Installed. Restart WeChat once so its built-in candidate bar loads the new skin.\n'
printf 'Undo: systemctl --user disable --now silky-ime-theme; mv %s.silky-backup %s\n' "$classicui" "$classicui"
