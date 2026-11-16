#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
shell_dir=${MACSHELL_DIR:-"$HOME/.config/quickshell/MacShell"}
quickshell_dir=$(dirname -- "$shell_dir")
patch_file="$repo_root/patches/macshell-0.5.1-silky.patch"
bar_settings="$HOME/.config/macbar/settings.json"
dock_settings="$HOME/.config/macdock/settings.json"
env_file="$HOME/.config/macshell/env"
check_only=false

usage() {
  cat <<'EOF'
Usage: scripts/install-macshell-optimizations.sh [--check]

Applies the Silky Omarchy localization, touch and real-time glass patch to an
installed MacShell 0.5.1. Existing files are backed up before any change.

  --check  Verify compatibility without changing files.
EOF
}

case "${1:-}" in
  "") ;;
  --check) check_only=true ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

for command_name in patch jq; do
  command -v "$command_name" >/dev/null || {
    printf 'Missing required command: %s\n' "$command_name" >&2
    exit 1
  }
done

[[ -f "$shell_dir/VERSION" ]] || {
  printf 'MacShell is not installed at %s\n' "$shell_dir" >&2
  exit 1
}

version=$(tr -d '[:space:]' < "$shell_dir/VERSION")
[[ "$version" == "0.5.1" ]] || {
  printf 'This patch targets MacShell 0.5.1; installed version is %s.\n' "$version" >&2
  exit 1
}

patch_state=unknown
if patch --dry-run --silent --forward -p1 -d "$quickshell_dir" < "$patch_file" >/dev/null 2>&1; then
  patch_state=clean
elif patch --dry-run --silent --reverse -p1 -d "$quickshell_dir" < "$patch_file" >/dev/null 2>&1; then
  patch_state=applied
else
  printf 'The installed MacShell differs from both pristine 0.5.1 and the Silky patch.\n' >&2
  printf 'Reinstall MacShell 0.5.1 or merge the patch manually. No files were changed.\n' >&2
  exit 1
fi

printf 'MacShell %s; patch state: %s\n' "$version" "$patch_state"
$check_only && exit 0

stamp=$(date +%Y%m%d-%H%M%S)
backup_dir="$HOME/.local/state/macshell/silky-backup-$stamp"
mkdir -p "$backup_dir/MacShell/assets" "$backup_dir/MacShell/lang" "$backup_dir/settings"

for relative_path in I18n.js AboutApp.qml MacBar.qml MacDock.qml shell.qml; do
  cp -a "$shell_dir/$relative_path" "$backup_dir/MacShell/$relative_path"
done
cp -a "$shell_dir/assets/about-info.sh" "$backup_dir/MacShell/assets/about-info.sh"
[[ ! -f "$shell_dir/lang/zh-CN.js" ]] || cp -a "$shell_dir/lang/zh-CN.js" "$backup_dir/MacShell/lang/zh-CN.js"
[[ ! -f "$bar_settings" ]] || cp -a "$bar_settings" "$backup_dir/settings/macbar.json"
[[ ! -f "$dock_settings" ]] || cp -a "$dock_settings" "$backup_dir/settings/macdock.json"
[[ ! -f "$env_file" ]] || cp -a "$env_file" "$backup_dir/settings/macshell.env"

if [[ "$patch_state" == clean ]]; then
  patch --silent --forward -p1 -d "$quickshell_dir" < "$patch_file"
fi

update_json() {
  local path=$1 filter=$2 temporary
  [[ -f "$path" ]] || return 0
  temporary=$(mktemp "${path}.silky.XXXXXX")
  jq "$filter" "$path" > "$temporary"
  chmod --reference="$path" "$temporary"
  mv -f "$temporary" "$path"
}

update_json "$bar_settings" \
  '.barStyle = "liquid" | .glassOpacity = 0.38 | .glassBlur = 24 | .glassRealtime = true | .language = "zh-CN"'
update_json "$dock_settings" \
  '.dockStyle = "liquid" | .glassOpacity = 0.38 | .glassBlur = 24 | .glassLive = true | .windowCapture = false'

mkdir -p "$(dirname -- "$env_file")"
touch "$env_file"
sed -i \
  -e '/# Silky Omarchy GPU begin/,/# Silky Omarchy GPU end/d' \
  -e '/^export QSG_RHI_BACKEND=/d' \
  -e '/^export QSG_RENDER_LOOP=/d' \
  "$env_file"
cat >> "$env_file" <<'EOF'

# Silky Omarchy GPU begin
export QSG_RHI_BACKEND=vulkan
export QSG_RENDER_LOOP=threaded
# Silky Omarchy GPU end
EOF

printf 'Applied successfully. Backup: %s\n' "$backup_dir"
printf 'Restart MacShell from Settings > Tools > Restart to load the QML and renderer changes.\n'
