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
    # One run can update a file twice; never overwrite the first backup.
    local backup="$target.bak.$stamp" n=1
    while [[ -e $backup ]]; do backup="$target.bak.$stamp.$((n++))"; done
    cp -p -- "$target" "$backup"
    printf 'Backed up %s\n' "$backup"
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

# HiDPI RDP plugin: Remmina 1.4.44 sends the logical window size as the
# remote resolution and doubles every remote pixel on a scale-2 output.
# patches/remmina-1.4.44-rdp-hidpi.patch fixes that; the patched plugin goes
# into ~/.config/remmina/plugins/, which Remmina searches before
# /usr/lib/remmina/plugins/. Built from the pinned upstream tarball, only
# when the version, tarball or patch changed. SILKY_REMMINA_HIDPI=0 skips it.
remmina_version=1.4.44
remmina_sha256=67199bb48657e8b42892924f005781542f50f8b029597f8b6c1ee9ed8a80b68e
hidpi_patch="$repo_root/patches/remmina-$remmina_version-rdp-hidpi.patch"
user_plugins="$config_home/remmina/plugins"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/silky-omarchy/remmina-$remmina_version"
installed_version=$(pacman -Q remmina 2>/dev/null | awk '{print $2}' | sed -E 's/^[0-9]+://; s/-[0-9.]+$//')

build_hidpi_plugin() {
  local tarball="$cache_dir/Remmina-v$remmina_version.tar.gz" src out stamp
  stamp="$remmina_version $(sha256sum "$hidpi_patch" | cut -d' ' -f1)"
  if [[ -f $user_plugins/remmina-plugin-rdp.so && $(cat "$user_plugins/.silky-hidpi" 2>/dev/null) == "$stamp" ]]; then
    printf 'HiDPI RDP plugin is up to date.\n'
    return
  fi
  for cmd in cmake make curl patch; do
    command -v "$cmd" >/dev/null || fail "Missing required command for the HiDPI RDP plugin: $cmd (or set SILKY_REMMINA_HIDPI=0)"
  done
  mkdir -p -- "$cache_dir"
  if [[ ! -f $tarball ]] || ! printf '%s  %s\n' "$remmina_sha256" "$tarball" | sha256sum -c --quiet - 2>/dev/null; then
    curl -fL --retry 2 -o "$tarball.part" \
      "https://gitlab.com/Remmina/Remmina/-/archive/v$remmina_version/Remmina-v$remmina_version.tar.gz" \
      || fail "Downloading the Remmina $remmina_version source failed."
    printf '%s  %s\n' "$remmina_sha256" "$tarball.part" | sha256sum -c --quiet - \
      || fail "The Remmina $remmina_version source tarball does not match the pinned checksum."
    mv -f -- "$tarball.part" "$tarball"
  fi
  src="$build_dir/src"
  out="$build_dir/out"
  mkdir -p -- "$src"
  tar -xzf "$tarball" -C "$src" --strip-components=1
  patch -d "$src" -p1 --quiet < "$hidpi_patch" || fail "Applying $hidpi_patch failed."
  # Same feature switches as Arch's package for the RDP plugin; unrelated plugins off.
  cmake -S "$src" -B "$out" -DCMAKE_BUILD_TYPE=None -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_INSTALL_LIBDIR=/usr/lib \
    -DWITH_FREERDP3=ON -DWITH_NEWS=OFF -DWITH_APPINDICATOR=OFF -DWITH_KF5WALLET=OFF -DWITH_X2GO=OFF \
    -DWITH_GVNC=OFF -DWITH_PYTHONLIBS=OFF -DWITH_WWW=OFF -DWITH_SPICE=OFF -DWITH_VTE=OFF -DWITH_LIBSSH=OFF \
    -Wno-dev > "$build_dir/cmake.log" 2>&1 \
    || { tail -20 "$build_dir/cmake.log" >&2; fail "Configuring Remmina for the HiDPI RDP plugin failed."; }
  make -C "$out" -j"$(nproc)" remmina-plugin-rdp > "$build_dir/make.log" 2>&1 \
    || { tail -20 "$build_dir/make.log" >&2; fail "Building the HiDPI RDP plugin failed."; }
  if [[ -f $user_plugins/remmina-plugin-rdp.so ]]; then
    cp -p -- "$user_plugins/remmina-plugin-rdp.so" "$user_plugins/remmina-plugin-rdp.so.bak.$stamp_time"
    printf 'Backed up %s\n' "$user_plugins/remmina-plugin-rdp.so.bak.$stamp_time"
  fi
  install -Dm 755 "$out/plugins/rdp/remmina-plugin-rdp.so" "$user_plugins/remmina-plugin-rdp.so"
  printf '%s\n' "$stamp" > "$user_plugins/.silky-hidpi"
  printf 'Installed the HiDPI RDP plugin to %s\n' "$user_plugins"
}

stamp_time=$stamp
if [[ ${SILKY_REMMINA_HIDPI:-1} == 0 ]]; then
  printf 'Skipping the HiDPI RDP plugin (SILKY_REMMINA_HIDPI=0).\n'
elif [[ $installed_version != "$remmina_version" ]]; then
  printf 'Skipping the HiDPI RDP plugin: it targets Remmina %s, installed is %s.\n' "$remmina_version" "${installed_version:-none}"
else
  build_hidpi_plugin
fi

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

# Windows UI size for the sharp HiDPI picture (Remmina: Preferences → RDP →
# Desktop scale factor %). The RDP plugin reads these from remmina.pref at
# every connection and Remmina keeps unknown keys when it saves, so they can
# be set while Remmina runs. Only filled in when unset, to keep user choices.
if [[ -f $pref ]] && grep -q '^\[remmina_pref\]' "$pref" && [[ -f $user_plugins/.silky-hidpi ]]; then
  desktop_scale=$(sed -n 's/^rdp_desktopScaleFactor=//p' "$pref")
  device_scale=$(sed -n 's/^rdp_deviceScaleFactor=//p' "$pref")
  if [[ -z $desktop_scale || $desktop_scale == 0 || -z $device_scale || $device_scale == 0 ]]; then
    staged=$(mktemp)
    cp -- "$pref" "$staged"
    set_pref "$staged" rdp_desktopScaleFactor "${SILKY_REMMINA_SCALE:-150}"
    set_pref "$staged" rdp_deviceScaleFactor 100
    update "$pref" "$staged"
  fi
fi

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
