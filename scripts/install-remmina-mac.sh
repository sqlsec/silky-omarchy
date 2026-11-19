#!/usr/bin/env bash
# Install the Simplified Chinese launcher and macOS-style stylesheet for Remmina.
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
launcher="$HOME/.local/bin/silky-remmina"
stamp=$(date +%Y%m%d-%H%M%S-%N)

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

[[ -x /usr/bin/remmina && -x /usr/bin/remmina-file-wrapper ]] || fail "Remmina is not installed (pacman -S remmina)."
[[ -f /usr/share/locale/zh_CN/LC_MESSAGES/remmina.mo ]] || fail "Remmina's zh_CN translation is missing."
locale -a | grep -qix 'zh_CN.utf8' || fail "Generate the zh_CN.UTF-8 locale first (locale-gen)."
command -v gsettings >/dev/null || fail "Missing required command: gsettings"

# Write a file only when its content changes, keeping a timestamped backup.
update() {
  local target=$1 staged=$2
  if [[ -f $target ]] && cmp -s -- "$staged" "$target"; then
    rm -f -- "$staged"
    return
  fi
  if [[ -f $target ]]; then
    cp -p -- "$target" "$target.bak.$stamp"
    printf 'Backed up %s\n' "$target.bak.$stamp"
  fi
  mkdir -p -- "$(dirname -- "$target")"
  mv -f -- "$staged" "$target"
  printf 'Updated %s\n' "$target"
}

install -Dm 755 "$repo_root/bin/silky-remmina" "$launcher"

for variant in Dark Light; do
  base="$data_home/themes/MacTahoe-$variant/gtk-3.0/gtk.css"
  if [[ ! -f $base ]]; then
    printf 'Skipping Silky-Remmina-%s: %s not found (install the macOS theme first).\n' "$variant" "$base"
    continue
  fi
  theme_dir="$data_home/themes/Silky-Remmina-$variant/gtk-3.0"
  mkdir -p -- "$theme_dir"
  install -m 644 "$repo_root/config/remmina/silky-remmina.css" "$theme_dir/silky-remmina.css"
  # The base theme resolves its assets relative to its own file, so an import is enough.
  printf '@import url("%s");\n@import url("silky-remmina.css");\n' "$base" > "$theme_dir/gtk.css"
done

# Point every launcher entry at the wrapper.
rewrite_exec() {
  sed -E \
    -e "s#^Exec=remmina-file-wrapper#Exec=$launcher#" \
    -e "s#^Exec=(/usr/bin/)?remmina( |\$)#Exec=$launcher\\2#" "$1"
}

for name in org.remmina.Remmina.desktop org.remmina.Remmina-file.desktop; do
  stock="/usr/share/applications/$name"
  [[ -f $stock ]] || continue
  local_entry="$data_home/applications/$name"
  source_entry=$stock
  [[ -f $local_entry ]] && source_entry=$local_entry
  staged=$(mktemp)
  rewrite_exec "$source_entry" > "$staged"
  update "$local_entry" "$staged"
done

applet="$config_home/autostart/remmina-applet.desktop"
if [[ -f $applet ]]; then
  staged=$(mktemp)
  rewrite_exec "$applet" > "$staged"
  update "$applet" "$staged"
fi

command -v update-desktop-database >/dev/null && update-desktop-database "$data_home/applications" 2>/dev/null || true

if pgrep -u "$(id -u)" -x remmina >/dev/null; then
  printf 'Remmina is running. Close remote sessions, run "remmina --quit", then open Remmina again from the launcher.\n'
else
  printf 'Done. Open Remmina from the launcher.\n'
fi
