#!/usr/bin/env bash
set -euo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
version=0.6.1
revision=bf947e6cf28ac0b666d0f14a22db5f5d3f4f6f06
patch_file="$repo/patches/folio-$version-silky.patch"
source_dir=${FOLIO_SOURCE_DIR:-"${XDG_CACHE_HOME:-$HOME/.cache}/silky-omarchy/folio-$version"}
data=${XDG_DATA_HOME:-"$HOME/.local/share"}
config=${XDG_CONFIG_HOME:-"$HOME/.config"}
target="$data/silky-omarchy/folio"
launcher="$HOME/.local/bin/folio"
desktop="$data/applications/folio.desktop"
portal_service="$data/dbus-1/services/org.freedesktop.impl.portal.desktop.folio.service"
fm1_service="$data/dbus-1/services/org.freedesktop.FileManager1.service"
macshell="$config/quickshell/MacShell"

if [[ ! -x /usr/bin/folio || ! -r /usr/share/applications/folio.desktop ]]; then
  printf 'Install the Folio package first.\n' >&2
  exit 1
fi
if [[ ! -f $data/icons/MacTahoe/apps/scalable/system-file-manager.svg ]]; then
  printf 'Install the MacTahoe icons with scripts/install-macos-theme.sh first.\n' >&2
  exit 1
fi
if [[ ! -d $source_dir/.git ]]; then
  mkdir -p -- "$(dirname -- "$source_dir")"
  git clone --depth 1 --branch "v$version" https://github.com/omacom/folio.git "$source_dir"
fi
if [[ $(git -C "$source_dir" rev-parse HEAD) != "$revision" ]]; then
  printf 'Unexpected Folio source revision at %s.\n' "$source_dir" >&2
  exit 1
fi
if ! git -C "$source_dir" apply --reverse --check "$patch_file" 2>/dev/null; then
  if ! git -C "$source_dir" apply --check "$patch_file" 2>/dev/null; then
    # An older Silky patch may already be applied. Build from the same pinned
    # commit in a separate cache so the previous build and source edits survive.
    patch_id=$(sha256sum -- "$patch_file")
    previous_source=$source_dir
    source_dir="$source_dir.silky-${patch_id:0:12}"
    if [[ ! -d $source_dir/.git ]]; then
      git -c advice.detachedHead=false clone --shared --quiet --no-checkout "$previous_source" "$source_dir"
      git -C "$source_dir" checkout --quiet --detach "$revision"
    fi
  fi
  if ! git -C "$source_dir" apply --reverse --check "$patch_file" 2>/dev/null; then
    git -C "$source_dir" apply "$patch_file"
  fi
fi

cmake -S "$source_dir" -B "$source_dir/build" -DCMAKE_BUILD_TYPE=Release
cmake --build "$source_dir/build" --target folio --parallel "${FOLIO_BUILD_JOBS:-4}"

staging=$(mktemp -d)
trap 'rm -rf -- "$staging"' EXIT
desktop_source=/usr/share/applications/folio.desktop
[[ ! -f $desktop ]] || desktop_source=$desktop
python3 - "$desktop_source" "$staging/folio.desktop" "$launcher" <<'PY'
import re
import sys
from pathlib import Path

source, output, launcher = sys.argv[1:]
entry, *actions = re.split(r"(?m)(?=^\[Desktop Action )", Path(source).read_text(), maxsplit=1)
if any(ch in launcher for ch in ' \t\n"\'\\`$|&;<>()'):
    exec_bin = '"' + re.sub(r'([\\`"$])', r'\\\1', launcher) + '"'
else:
    exec_bin = launcher
entry = re.sub(r"(?m)^Exec=.*$", lambda _: f"Exec={exec_bin} %U", entry, count=1)
entry = re.sub(r"(?m)^Icon=.*$", "Icon=system-file-manager", entry, count=1)
if not re.search(r"(?m)^Name\[zh_CN\]=", entry):
    entry = re.sub(r"(?m)^Name=.*$", r"\g<0>\nName[zh_CN]=文件", entry, count=1)
Path(output).write_text(entry + "".join(actions))
PY
if command -v desktop-file-validate >/dev/null; then
  desktop-file-validate "$staging/folio.desktop"
fi
if [[ -f $macshell/MacDock.qml && -f $macshell/shell.qml ]]; then
  python3 "$repo/scripts/tune-folio-macshell.py" "$macshell" --backup
fi

stamp=$(date +%Y%m%d-%H%M%S-%N)
install_file() {
  local source=$1 destination=$2 mode=$3 next
  if cmp -s -- "$source" "$destination"; then return; fi
  if [[ -e $destination || -L $destination ]]; then
    cp -a -- "$destination" "$destination.bak.folio.$stamp"
    printf 'Backed up %s\n' "$destination.bak.folio.$stamp"
  fi
  mkdir -p -- "$(dirname -- "$destination")"
  next=$(mktemp "$destination.tmp.XXXXXX")
  install -m "$mode" -- "$source" "$next"
  mv -fT -- "$next" "$destination"
}

install_file "$source_dir/build/folio" "$target/folio" 755
install_file "$repo/bin/silky-folio" "$launcher" 755
install_file "$staging/folio.desktop" "$desktop" 644
cat > "$staging/org.freedesktop.impl.portal.desktop.folio.service" <<EOF
[D-BUS Service]
Name=org.freedesktop.impl.portal.desktop.folio
Exec=$launcher chooser
EOF
install_file "$staging/org.freedesktop.impl.portal.desktop.folio.service" "$portal_service" 644
cat > "$staging/org.freedesktop.FileManager1.service" <<EOF
[D-BUS Service]
Name=org.freedesktop.FileManager1
Exec=$launcher --file-manager-service
EOF
install_file "$staging/org.freedesktop.FileManager1.service" "$fm1_service" 644
if command -v dbus-send >/dev/null; then
  dbus-send --session --dest=org.freedesktop.DBus --type=method_call \
    /org/freedesktop/DBus org.freedesktop.DBus.ReloadConfig 2>/dev/null || true
fi
pkill -f '^/usr/bin/folio chooser$' 2>/dev/null || true
network_plugin="$data/folio/plugins/network"
mkdir -p -- "$network_plugin/i18n"
chmod 755 "$data/folio" "$data/folio/plugins" "$network_plugin" "$network_plugin/i18n"
install_file "$repo/config/folio/plugins/network/manifest.json" "$network_plugin/manifest.json" 644
install_file "$repo/config/folio/plugins/network/discover" "$network_plugin/discover" 755
install_file "$repo/config/folio/plugins/network/i18n/zh-CN.json" "$network_plugin/i18n/zh-CN.json" 644
install_file "$repo/config/folio/plugins/network/i18n/zh-TW.json" "$network_plugin/i18n/zh-TW.json" 644
if [[ -f $config/hypr/hyprland.lua ]]; then
  hypr_main=$(realpath -- "$config/hypr/hyprland.lua")
  install_file "$repo/config/hypr/silky-folio.lua" "$config/hypr/silky-folio.lua" 644
  if ! grep -Fxq 'require("hypr.silky-folio")' "$hypr_main"; then
    cp -- "$hypr_main" "$staging/hyprland.lua"
    printf '\n-- Silky Omarchy: let Folio set the sidebar translucency.\nrequire("hypr.silky-folio")\n' >> "$staging/hyprland.lua"
    install_file "$staging/hyprland.lua" "$hypr_main" "$(stat -c '%a' -- "$hypr_main")"
  fi
fi
if command -v update-desktop-database >/dev/null; then
  update-desktop-database "$data/applications"
fi
printf 'Installed the Silky Folio launcher. Reopen Folio and reload MacShell for the Dock changes.\n'
