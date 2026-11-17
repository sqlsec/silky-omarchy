#!/usr/bin/env bash
set -euo pipefail

# Omarchy's own menus (Super+Esc, Super+Ctrl+M, clipboard, emojis) as MacShell-style macOS 27 glass that follows
# light / dark mode (see docs/11-menu-glass.md).
repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
hypr_dir="$HOME/.config/hypr"

for command_name in gsettings jq hyprctl systemctl; do
  command -v "$command_name" >/dev/null || { printf 'Missing required command: %s\n' "$command_name" >&2; exit 1; }
done
fc-list : family | grep -qx 'Inter' || printf 'Note: the Inter font is missing (pacman -S inter-font); menus fall back to the default sans.\n' >&2

install -Dm 755 "$repo_root/bin/silky-menu-glass" "$HOME/.local/bin/silky-menu-glass"
install -Dm 644 "$repo_root/config/systemd/silky-menu-glass.service" "$HOME/.config/systemd/user/silky-menu-glass.service"
install -m 644 "$repo_root/config/hypr/silky-menu-glass.lua" "$hypr_dir/silky-menu-glass.lua"
if ! grep -q 'require("hypr.silky-menu-glass")' "$hypr_dir/hyprland.lua"; then
  cp -a "$hypr_dir/hyprland.lua" "$hypr_dir/hyprland.lua.bak.$(date +%Y%m%d-%H%M%S)"
  printf '\n-- Silky Omarchy: Omarchy menus as macOS glass (blur + font; colours from silky-menu-glass).\nrequire("hypr.silky-menu-glass")\n' >> "$hypr_dir/hyprland.lua"
fi
hyprctl reload >/dev/null

systemctl --user daemon-reload
systemctl --user enable --now silky-menu-glass.service
systemctl --user restart silky-menu-glass.service

# The menu font is read when the Omarchy shell starts.
omarchy-restart-shell >/dev/null 2>&1 || true
printf 'Installed. Super+Esc or Super+Ctrl+M to see it; switch light / dark in MacShell and the menus follow.\n'
