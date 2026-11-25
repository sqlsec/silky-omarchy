#!/usr/bin/env bash
set -euo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
config_home=${XDG_CONFIG_HOME:-"$HOME/.config"}
shell_dir=${MACSHELL_DIR:-"$config_home/quickshell/MacShell"}
patch_file="$repo/patches/macshell-wifi-scan.patch"
helper=assets/silky-wifi-scan.py
files=(MacBar.qml MacDock.qml lang/zh-CN.js)
mode=${1:-}

case "$mode" in
  ""|--check|--post-update) ;;
  *) printf 'Usage: %s [--check]\n' "$0" >&2; exit 2 ;;
esac
if [[ $mode == --post-update && ! -d $shell_dir ]]; then
  exit 0
fi
for tool in python3 nmcli busctl patch; do
  command -v "$tool" >/dev/null || { printf 'Missing required command: %s\n' "$tool" >&2; exit 1; }
done

stage=$(mktemp -d)
trap 'rm -rf -- "$stage"' EXIT
mkdir -p "$stage/lang" "$stage/assets"
for file in "${files[@]}"; do
  cp -pL -- "$shell_dir/$file" "$stage/$file"
done

if patch --dry-run --batch --silent --fuzz=0 --forward -p1 -d "$stage" < "$patch_file" >/dev/null 2>&1; then
  patch --batch --silent --fuzz=0 --forward -p1 -d "$stage" < "$patch_file"
elif grep -q 'Silky WiFi model begin' "$stage/MacBar.qml" && grep -q 'assets/silky-wifi-scan.py' "$stage/MacBar.qml"; then
  : # scripts/tune-wifi.py rebuilt the list and Settings page on top of this patch, so it is applied
elif ! patch --dry-run --batch --silent --fuzz=0 --reverse -p1 -d "$stage" < "$patch_file" >/dev/null 2>&1; then
  printf 'MacShell Wi-Fi code differs from the supported baseline in %s. Review %s; no files changed.\n' "$shell_dir" "$patch_file" >&2
  exit 1
fi
install -m 644 -- "$repo/config/macshell/silky-wifi-scan.py" "$stage/$helper"
if [[ $mode == --check ]]; then
  printf 'MacShell Wi-Fi patch passed preflight.\n'
  exit 0
fi

backup=
for file in "$helper" "${files[@]}"; do
  cmp -s "$stage/$file" "$shell_dir/$file" && continue
  if [[ -z $backup ]]; then
    state_dir=${XDG_STATE_HOME:-"$HOME/.local/state"}/macshell
    mkdir -p "$state_dir"
    backup=$(mktemp -d "$state_dir/silky-backup-wifi.XXXXXX")
    printf 'MacShell Wi-Fi backup: %s\n' "$backup"
  fi
  if [[ -n $backup && -f $shell_dir/$file ]]; then
    mkdir -p "$backup/$(dirname -- "$file")"
    cp -a -- "$shell_dir/$file" "$backup/$file"
  fi
  mkdir -p "$shell_dir/$(dirname -- "$file")"
  temporary=$(mktemp "${shell_dir}/${file}.silky.XXXXXX")
  cp -p -- "$stage/$file" "$temporary"
  mv -fT -- "$temporary" "$shell_dir/$file"
done

if [[ -z $mode ]]; then
  hook=$stage/silky-macshell-wifi.hook
  printf '#!/usr/bin/env bash\nexec %q --post-update\n' "$repo/scripts/install-macshell-wifi.sh" > "$hook"
  if ! cmp -s "$hook" "$config_home/omarchy/hooks/post-update.d/${hook##*/}"; then
    omarchy hook install post-update "$hook"
  fi
fi
if [[ -n $backup ]] && command -v qs >/dev/null && qs -c MacShell ipc show >/dev/null 2>&1; then
  qs -c MacShell ipc call macshell reload || printf 'Reload MacShell to load the Wi-Fi changes.\n' >&2
fi
