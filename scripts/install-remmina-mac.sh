#!/usr/bin/env bash
# Install the Simplified Chinese launcher and the macOS glass look for Remmina:
# a GTK3 module loaded only into Remmina, its stylesheet and line icons, and
# Remmina preferences for a top toolbar that hides tabs for a single session.
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
launcher="$HOME/.local/bin/silky-remmina"
share_dir="$data_home/silky-remmina"
module_dir="$share_dir/gtk-3.0/modules"
pref="$config_home/remmina/remmina.pref"
stamp=$(date +%Y%m%d-%H%M%S-%N)

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

[[ -x /usr/bin/remmina && -x /usr/bin/remmina-file-wrapper ]] || fail "Remmina is not installed (pacman -S remmina)."
[[ -f /usr/share/locale/zh_CN/LC_MESSAGES/remmina.mo ]] || fail "Remmina's zh_CN translation is missing."
locale -a | grep -qix 'zh_CN.utf8' || fail "Generate the zh_CN.UTF-8 locale first (locale-gen)."
for cmd in cc pkg-config; do
  command -v "$cmd" >/dev/null || fail "Missing required command: $cmd (pacman -S --needed base-devel)"
done
pkg-config --exists gtk+-3.0 librsvg-2.0 || fail "Missing GTK3 or librsvg development files (pacman -S --needed gtk3 librsvg)."

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

# GTK3 module: built in a temporary directory so the repository stays clean.
build_dir=$(mktemp -d)
trap 'rm -rf -- "$build_dir"' EXIT
cc -O2 -Wall -shared -fPIC -o "$build_dir/libsilky-remmina.so" \
  "$repo_root/plugins/silky-remmina/silky-remmina.c" \
  $(pkg-config --cflags --libs gtk+-3.0 librsvg-2.0) || fail "Building the silky-remmina GTK module failed."
install -Dm 644 "$build_dir/libsilky-remmina.so" "$module_dir/libsilky-remmina.so"
install -Dm 644 "$repo_root/config/remmina/silky-remmina.css" "$share_dir/silky-remmina.css"
install -d "$share_dir/icons"
install -m 644 "$repo_root"/config/remmina/icons/*.svg "$share_dir/icons/"
printf 'Installed the Remmina module, stylesheet and icons to %s\n' "$share_dir"

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

# Remmina preferences: toolbar across the top (0), tabs only with two or more
# sessions. Remmina rewrites remmina.pref when it quits, so only edit it while
# Remmina is not running.
set_pref() {
  local file=$1 key=$2 value=$3
  if grep -q "^$key=" "$file"; then
    sed -i "s|^$key=.*|$key=$value|" "$file"
  else
    sed -i "/^\[remmina_pref\]/a $key=$value" "$file"
  fi
}

running=false
pgrep -u "$(id -u)" -x remmina >/dev/null && running=true

if $running; then
  printf 'Remmina is running, so its preferences were left alone.\n'
  printf 'Close remote sessions, run "remmina --quit", then run this script again.\n'
elif [[ -f $pref ]] && grep -q '^\[remmina_pref\]' "$pref"; then
  staged=$(mktemp)
  cp -- "$pref" "$staged"
  set_pref "$staged" toolbar_placement 0
  set_pref "$staged" always_show_tab false
  update "$pref" "$staged"
  printf 'Done. Open Remmina from the launcher.\n'
else
  printf 'No Remmina preferences yet: open Remmina once, quit it, and run this script again\n'
  printf 'to move the connection toolbar to the top.\n'
fi
