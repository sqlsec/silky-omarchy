#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
foot_dir="$config_home/foot"
foot_config="$foot_dir/foot.ini"
helper="$HOME/.local/bin/silky-foot-glass"

for command_name in foot gsettings pkill systemctl; do
  command -v "$command_name" >/dev/null || {
    printf 'Missing required command: %s\n' "$command_name" >&2
    exit 1
  }
done

palette="$repo_root/config/foot/silky-glass.ini"
installed_palette="$foot_dir/silky-glass.ini"
palette_include="include=$installed_palette"
appearance_include="include=$foot_dir/silky-appearance.ini"
needs_font=false
if [[ ! -f $foot_config || ! -f $installed_palette ]] ||
  ! grep -Fxq -- "$palette_include" "$foot_config" || ! grep -Fxq '[main]' "$installed_palette"; then
  needs_font=true
fi
foot --check-config --config="$palette"
if ! cmp -s "$palette" "$installed_palette"; then
  if [[ -f $installed_palette ]]; then
    backup="$installed_palette.bak.$(date +%Y%m%d-%H%M%S-%N)"
    cp -pL -- "$installed_palette" "$backup"
    printf 'Backed up Foot appearance to %s\n' "$backup"
  fi
  install -Dm 644 "$palette" "$installed_palette"
fi
install -Dm 755 "$repo_root/bin/silky-foot-glass" "$helper"
if [[ ! -f $foot_dir/silky-appearance.ini ]]; then
  "$helper" --initialize
fi

if $needs_font || ! grep -Fxq -- "$palette_include" "$foot_config" ||
  ! grep -Fxq -- "$appearance_include" "$foot_config"; then
  staged=$(mktemp "$foot_dir/foot.ini.XXXXXX")
  trap 'rm -f -- "$staged"' EXIT
  if [[ -f $foot_config ]]; then
    cp -p -- "$foot_config" "$staged"
  fi
  if $needs_font; then
    # Keep fonts in foot.ini, where Omarchy's font and text-size commands edit them.
    if [[ -f $foot_config ]]; then
      awk '
        BEGIN { main = 1 }
        /^[[:space:]]*\[/ { main = ($0 ~ /^[[:space:]]*\[main\]/) }
        !(main && /^[[:space:]]*font[[:space:]]*=/)
      ' "$foot_config" > "$staged"
    fi
  fi
  printf '\n[main]\n' >> "$staged"
  if $needs_font; then
    printf 'font=Monaco:size=11,JetBrainsMono Nerd Font:size=11,Sarasa Mono SC:size=11,Noto Color Emoji:size=11\n' >> "$staged"
  fi
  for include in "$palette_include" "$appearance_include"; do
    if ! grep -Fxq -- "$include" "$staged"; then
      printf '%s\n' "$include" >> "$staged"
    fi
  done
  foot --check-config --config="$staged"
  if [[ -f $foot_config ]]; then
    backup="$foot_config.bak.$(date +%Y%m%d-%H%M%S-%N)"
    cp -pL -- "$foot_config" "$backup"
    printf 'Backed up Foot configuration to %s\n' "$backup"
    # Write through an existing symlink so a managed config keeps its link.
    if [[ -L $foot_config ]]; then
      cat "$staged" > "$foot_config"
    else
      mv -f -- "$staged" "$foot_config"
    fi
  else
    mv -f -- "$staged" "$foot_config"
  fi
fi

install -Dm 644 "$repo_root/config/systemd/silky-foot-glass.service" \
  "$config_home/systemd/user/silky-foot-glass.service"
systemctl --user daemon-reload
systemctl --user enable silky-foot-glass.service
systemctl --user restart silky-foot-glass.service
printf 'Open a new Foot window to load the Tahoe profile. Use MacShell Appearance to switch modes.\n'
