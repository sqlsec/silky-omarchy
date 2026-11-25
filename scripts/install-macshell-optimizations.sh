#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
shell_dir=${MACSHELL_DIR:-"$HOME/.config/quickshell/MacShell"}
quickshell_dir=$(dirname -- "$shell_dir")
installer_qml="${XDG_DATA_HOME:-$HOME/.local/share}/macshell/MacInstaller/shell.qml"
patch_file="$repo_root/patches/macshell-0.5.1-silky.patch"
minimize_upgrade="$repo_root/patches/macshell-0.5.1-minimize-upgrade.patch"
bar_settings="$HOME/.config/macbar/settings.json"
dock_settings="$HOME/.config/macdock/settings.json"
env_file="$HOME/.config/macshell/env"
check_only=false

usage() {
  cat <<'EOF'
Usage: scripts/install-macshell-optimizations.sh [--check]

Applies the Silky Omarchy localization, touch and real-time glass patch to an
installed MacShell. Any version is accepted: 0.5.1 uses its own patch, every other
version uses the newest patch (0.5.2), and the patch/marker check below decides
whether it fits. Existing files are backed up before any change.

  --check  Verify compatibility without changing files.
EOF
}

case "${1:-}" in
  "") ;;
  --check) check_only=true ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

for command_name in patch jq python3; do
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
case "$version" in
  0.5.1) ;;
  0.5.2) patch_file="$repo_root/patches/macshell-0.5.2-silky.patch" ;;
  # No version gate: newer releases try the newest patch. An already patched shell is recognized by its markers,
  # and a fresh one that the patch does not fit stops below with nothing changed.
  *)
    patch_file="$repo_root/patches/macshell-0.5.2-silky.patch"
    printf 'MacShell %s has no dedicated patch; trying the 0.5.2 patch and the tuners.\n' "$version"
    ;;
esac

patch_state=unknown
if patch --dry-run --silent --forward -p1 -d "$quickshell_dir" < "$patch_file" >/dev/null 2>&1; then
  patch_state=clean
elif grep -q 'function minimizeAddress' "$shell_dir/MacDock.qml" \
    && grep -q 'function restoreAddress' "$shell_dir/MacDock.qml" \
    && grep -q 'MinimizeFx { id: minimizeFx' "$shell_dir/shell.qml" \
    && grep -q 'WindowBar { id: windowBar' "$shell_dir/shell.qml"; then
  # Other Silky modules may add independent hunks to the same large QML files (for example Launchpad gestures).
  # Recognize this feature by its complete runtime markers instead of demanding byte-for-byte patch reversal.
  patch_state=applied
elif patch --dry-run --silent --reverse -p1 -d "$quickshell_dir" < "$patch_file" >/dev/null 2>&1; then
  patch_state=applied
elif [[ "$version" == "0.5.1" ]] && grep -q 'function isMinimized' "$shell_dir/MacDock.qml" \
    && ! grep -q 'function minimizeAddress' "$shell_dir/MacDock.qml" \
    && patch --dry-run --silent --forward -p1 -d "$quickshell_dir" < "$minimize_upgrade" >/dev/null 2>&1; then
  patch_state=upgrade
else
  printf 'MacShell %s does not match the Silky patch or a supported installed baseline. No files were changed.\n' "$version" >&2
  exit 1
fi

printf 'MacShell %s; patch state: %s\n' "$version" "$patch_state"
staging=$(mktemp -d)
trap 'rm -rf -- "$staging"' EXIT
staged_shell="$staging/MacShell"

# Stage exactly the files that the patches and tuners can change. Dereference
# source symlinks so even a linked installation stays untouched during preflight.
mapfile -t managed_files < <(
  awk '/^\+\+\+ [^ ]+\// { sub(/^\+\+\+ [^/]+\//, ""); print $1 }' "$patch_file" "$minimize_upgrade" | sort -u
)
calendar_files=(ChinaLunarDates.js ChinaCalendar.js ChinaCalendarDay.qml)
calendar_paths=()
for file in "${calendar_files[@]}"; do
  calendar_paths+=("MacShell/$file")
done
managed_files=("${calendar_paths[@]}" MacShell/FolioMinimizeFx.qml MacShell/FolioSnapPreview.qml MacShell/FootWindowLayout.qml MacShell/folio-genie.vert.qsb MacShell/DockGlassPanel.qml MacShell/SilkyAccountAvatar.qml MacShell/SilkyBarContrast.qml MacShell/assets/silky-bar-tone.py MacShell/assets/macshell-logo.png "${managed_files[@]}")
for display_asset in "$repo_root/config/macshell/displays/"{*.js,*.qml}; do
  managed_files+=("MacShell/${display_asset##*/}")
done
for trackpad_asset in "$repo_root/config/macshell/trackpad/"*.qml; do
  managed_files+=("MacShell/${trackpad_asset##*/}")
done
# Bluetooth backend, device icon and pairing helper (scripts/tune-bluetooth.py installs them).
managed_files+=(MacShell/SilkyBluetooth.qml MacShell/SilkyBtIcon.qml MacShell/assets/silky-bt-helper.py)
# Wi-Fi model and details helper; the scan helper is refreshed too (scripts/tune-wifi.py installs them).
managed_files+=(MacShell/SilkyWifi.qml MacShell/assets/silky-wifi-info.py MacShell/assets/silky-wifi-conn.py MacShell/assets/silky-wifi-scan.py)
for relative_path in "${managed_files[@]}"; do
  case "$relative_path" in
    MacShell/*) source_path="$shell_dir/${relative_path#MacShell/}" ;;
    MacLock/*) source_path="$quickshell_dir/$relative_path" ;;
  esac
  if [[ -f "$source_path" ]]; then
    mkdir -p "$staging/$(dirname -- "$relative_path")"
    cp -pL -- "$source_path" "$staging/$relative_path"
  fi
done
mkdir -p "$staged_shell/assets" "$staged_shell/lang" "$staging/MacLock"
install -m 644 -- "$repo_root/config/icons/macshell-logo.png" "$staged_shell/assets/macshell-logo.png"

if [[ "$patch_state" == clean ]]; then
  patch --silent --forward -p1 -d "$staging" < "$patch_file"
elif [[ "$patch_state" == upgrade ]]; then
  patch --silent --forward -p1 -d "$staging" < "$minimize_upgrade"
fi

# Upgrade the old bottom-anchored icon scaling on already-patched installations.
python3 "$repo_root/scripts/tune-dock-icons.py" "$staged_shell/MacDock.qml"
# Use the wallpaper when a Dock window capture has no frame.
sed -i '/^\([[:space:]]*\)placeholder: (root\.bar ? root\.bar\.darkMode : true) ? "#1e1e20" : "#f2f2f7"$/c\                                    // Use the wallpaper when a window has no captured frame.\n                                    placeholder: "transparent"' "$staged_shell/MacDock.qml"
# After a click the icon's hover label stays away until the pointer moves (no glass bubble built mid-animation).
python3 "$repo_root/scripts/tune-dock-hover-label.py" "$staged_shell/MacDock.qml"
python3 "$repo_root/scripts/tune-dock-smart-hide.py" "$staged_shell/MacDock.qml"
# The right-click menu uses the same see-through glass as the Dock (tint / blur follow the Dock's glass settings).
python3 "$repo_root/scripts/tune-dock-menu-glass.py" "$staged_shell"
# The Dock glass follows the system Light / Dark appearance instead of staying dark.
python3 "$repo_root/scripts/tune-dock-follow-appearance.py" "$staged_shell"
# Normal Blur (Hyprland blur) tints close to Liquid Glass; quieter About button.
python3 "$repo_root/scripts/tune-native-blur.py" "$staged_shell"
if [[ -f "$installer_qml" ]]; then
  managed_files+=(MacInstaller/shell.qml)
  mkdir -p "$staging/MacInstaller"
  cp -pL -- "$installer_qml" "$staging/MacInstaller/shell.qml"
fi
python3 "$repo_root/scripts/tune-macshell-window-edges.py" "$staged_shell"
# About: Edge / Dev builds read "Edge · <commit> (<MM-DD> build)" instead of git describe's old 4.0.0 tag.
python3 "$repo_root/scripts/tune-about-version.py" "$staged_shell"

# Keep the Applications panel interaction tuning current on existing installations too.
python3 "$repo_root/scripts/tune-apps-panel.py" "$staged_shell/MacBar.qml"
python3 "$repo_root/scripts/tune-apps-dock-passthrough.py" "$staged_shell/MacDock.qml"
python3 "$repo_root/scripts/tune-control-center-glass.py" "$staged_shell/MacBar.qml"
# WiFi / Bluetooth tiles: the round icon toggles, the rest of the tile (and its "›") opens the list.
python3 "$repo_root/scripts/tune-control-center-network-tiles.py" "$staged_shell/MacBar.qml"
for file in "${calendar_files[@]}"; do
  install -m 644 "$repo_root/config/macshell/calendar/$file" "$staged_shell/$file"
done
python3 "$repo_root/scripts/tune-calendar.py" "$staged_shell/MacBar.qml"
python3 "$repo_root/scripts/tune-display-controls.py" "$staged_shell/MacBar.qml"
python3 "$repo_root/scripts/tune-display-settings.py" "$staged_shell"
python3 "$repo_root/scripts/tune-trackpad-settings.py" "$staged_shell"
# Bluetooth: D-Bus backend, paired-only Control Center list, macOS-style Settings page with pairing requests.
python3 "$repo_root/scripts/tune-bluetooth.py" "$staged_shell"
# Wi-Fi: known / other networks, Option-click details, macOS-style Settings page (needs install-macshell-wifi.sh first).
if grep -q 'assets/silky-wifi-scan.py' "$staged_shell/MacBar.qml"; then
  python3 "$repo_root/scripts/tune-wifi.py" "$staged_shell"
else
  printf 'Skipping the Wi-Fi page: run scripts/install-macshell-wifi.sh first.\n' >&2
fi
python3 "$repo_root/scripts/tune-window-tiling.py" "$staged_shell/MacBar.qml"
# Volume sliders play a tap at the level they set.
python3 "$repo_root/scripts/tune-volume-feedback.py" "$staged_shell/MacBar.qml"
# Screen Recording first lets you click a monitor or drag a region (slurp), Esc cancels.
python3 "$repo_root/scripts/tune-screen-recording-picker.py" "$staged_shell/MacBar.qml"
# Live microphone level under the input slider on the Sound page.
python3 "$repo_root/scripts/tune-mic-meter.py" "$staged_shell/MacBar.qml"
# Keep glass window stacking in sync when focus changes without a geometry change.
python3 "$repo_root/scripts/tune-glass-stacking.py" "$staged_shell/shell.qml"
python3 "$repo_root/scripts/configure-macshell-reload.py" "$staged_shell/shell.qml"
python3 "$repo_root/scripts/tune-settings-scroll.py" "$staged_shell/MacDock.qml"

python3 "$repo_root/scripts/tune-macshell-performance.py" "$staged_shell"
python3 "$repo_root/scripts/tune-macshell-system-menu.py" "$staged_shell/MacBar.qml"
python3 "$repo_root/scripts/tune-workspace-indicators.py" "$staged_shell/MacBar.qml"
python3 "$repo_root/scripts/tune-macshell-bar-contrast.py" "$staged_shell" --stage
python3 "$repo_root/scripts/tune-dock-trash.py" "$staged_shell/MacDock.qml"
python3 "$repo_root/scripts/tune-dock-menu-room.py" "$staged_shell/MacDock.qml"
python3 "$repo_root/scripts/tune-macshell-avatar.py" "$staged_shell/MacDock.qml" "$staging/MacLock/shell.qml"

# Remove legacy minimize entry points, then attach Silky's unified snapshot Genie minimize effect.
python3 "$repo_root/scripts/disable-minimize.py" "$staged_shell"
python3 "$repo_root/scripts/tune-folio-macshell.py" "$staged_shell"
python3 "$repo_root/scripts/tune-wps-dock.py" "$staged_shell/MacDock.qml"
python3 "$repo_root/scripts/tune-macshell-settings.py" "$staged_shell/MacDock.qml"
python3 "$repo_root/scripts/tune-wallpaper-picker.py" "$staged_shell/MacDock.qml"
python3 "$repo_root/scripts/tune-dock-focus-cursor.py" "$staged_shell/MacDock.qml"
python3 "$repo_root/scripts/tune-dock-window-pick.py" "$staged_shell/MacDock.qml"
python3 "$repo_root/scripts/tune-dock-window-check.py" "$staged_shell/MacDock.qml"

# Also update existing Silky installations: keep application-provided window controls visible.
sed -i 's/readonly property bool enabled: true/readonly property bool enabled: false/' "$staged_shell/WindowBar.qml"

# Parse settings during preflight too, since the installer rewrites them below.
for settings in "$bar_settings" "$dock_settings"; do
  [[ ! -f "$settings" ]] || jq empty "$settings"
done
python3 "$repo_root/scripts/migrate-macshell-files.py" --check
if $check_only; then
  printf 'MacShell patch and tuners passed preflight.\n'
  exit 0
fi

stamp=$(date +%Y%m%d-%H%M%S)
mkdir -p "$HOME/.local/state/macshell"
backup_dir=$(mktemp -d "$HOME/.local/state/macshell/silky-backup-$stamp.XXXXXX")
mkdir -p "$backup_dir/settings"
for relative_path in "${managed_files[@]}"; do
  case "$relative_path" in
    MacShell/*) destination="$shell_dir/${relative_path#MacShell/}" ;;
    MacLock/*) destination="$quickshell_dir/$relative_path" ;;
    MacInstaller/shell.qml) destination="$installer_qml" ;;
  esac
  source_path="$staging/$relative_path"
  [[ -f "$source_path" ]] || continue
  cmp -s "$source_path" "$destination" && continue
  if [[ -f "$destination" ]]; then
    mkdir -p "$backup_dir/$(dirname -- "$relative_path")"
    cp -a -- "$destination" "$backup_dir/$relative_path"
  fi
  mkdir -p "$(dirname -- "$destination")"
  temporary=$(mktemp "${destination}.silky.XXXXXX")
  cp -p -- "$source_path" "$temporary"
  mv -fT -- "$temporary" "$destination"
done
[[ ! -f "$bar_settings" ]] || cp -a "$bar_settings" "$backup_dir/settings/macbar.json"
[[ ! -f "$dock_settings" ]] || cp -a "$dock_settings" "$backup_dir/settings/macdock.json"
[[ ! -f "$env_file" ]] || cp -a "$env_file" "$backup_dir/settings/macshell.env"

update_json() {
  local path=$1 filter=$2 temporary
  [[ -f "$path" ]] || return 0
  temporary=$(mktemp "${path}.silky.XXXXXX")
  jq "$filter" "$path" > "$temporary"
  chmod --reference="$path" "$temporary"
  mv -f "$temporary" "$path"
}

update_json "$bar_settings" \
  '.barStyle = "blur" | .ccStyle = "macos" | .glassOpacity = 0.38 | .glassBlur = 24 | .glassRealtime = true | .language = "zh-CN" | .screenshotNotify = false'
update_json "$dock_settings" \
  '.dockStyle = "blur" | .glassOpacity = 0.38 | .glassBlur = 24 | .glassLive = true | .windowCapture = false | .desktopIcons = false'

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
# One restart path only: no crash dialog or self-relaunch from Quickshell; macshell-start restarts the shell quietly.
export QS_DISABLE_CRASH_HANDLER=1
# Silky Omarchy GPU end
EOF

# MacShell starts from ~/.config/hypr/macshell.lua. If that module or its require line went missing, the menu bar,
# Dock and the mouse settings MacShell applies (natural scrolling) are all gone after the next login.
hypr_dir="$HOME/.config/hypr"
if [[ -f "$hypr_dir/hyprland.lua" ]]; then
  # Keep the live module in step with the patched one (it no longer binds PRINT, see docs/02-macshell.md).
  [[ ! -f "$hypr_dir/macshell.lua" ]] || cp -a "$hypr_dir/macshell.lua" "$backup_dir/settings/macshell.lua"
  cp "$shell_dir/macshell.lua" "$hypr_dir/macshell.lua"
  # Keep MacShell window sizing and avoid exposing the desktop during window open.
  [[ ! -f "$hypr_dir/silky-macshell-windows.lua" ]] ||
    cp -a "$hypr_dir/silky-macshell-windows.lua" "$backup_dir/settings/"
  install -m 644 "$repo_root/config/hypr/silky-macshell-windows.lua" "$hypr_dir/silky-macshell-windows.lua"
  # Drop GTK3 CSD's transparent shadow margin so Firefox aligns cleanly on its first frame.
  gtk3_dir="$HOME/.config/gtk-3.0"
  mkdir -p "$gtk3_dir"
  [[ ! -f "$gtk3_dir/gtk.css" ]] || cp -a "$gtk3_dir/gtk.css" "$backup_dir/settings/gtk3.css"
  install -m 644 "$repo_root/config/gtk-3.0/silky-csd.css" "$gtk3_dir/silky-csd.css"
  if [[ ! -f "$gtk3_dir/gtk.css" ]] || ! grep -Fq '@import url("silky-csd.css");' "$gtk3_dir/gtk.css"; then
    printf '@import url("silky-csd.css");\n' >> "$gtk3_dir/gtk.css"
  fi
  # Install the two-button hyprbars configuration.
  [[ ! -f "$hypr_dir/silky-macos.lua" ]] || cp -a "$hypr_dir/silky-macos.lua" "$backup_dir/settings/silky-macos.lua"
  install -m 644 "$repo_root/config/hypr/silky-macos.lua" "$hypr_dir/silky-macos.lua"
  if ! grep -q 'require("hypr.silky-macshell-windows")' "$hypr_dir/hyprland.lua"; then
    printf '\n-- Silky Omarchy: keep MacShell windows at their own size on floating workspaces.\nrequire("hypr.silky-macshell-windows")\n' >> "$hypr_dir/hyprland.lua"
  fi
  # Screenshots: PRINT goes to omasnap with its floating preview instead of a notification.
  if ! grep -q 'Silky Omarchy: screenshots' "$hypr_dir/bindings.lua" 2>/dev/null; then
    cp -a "$hypr_dir/bindings.lua" "$hypr_dir/bindings.lua.bak.$stamp" 2>/dev/null || true
    { printf '\n'; cat "$repo_root/config/hypr/bindings-screenshot.lua"; } >> "$hypr_dir/bindings.lua"
  fi
  if ! grep -q 'require("hypr.macshell")\|require("macshell")' "$hypr_dir/hyprland.lua"; then
    cp -a "$hypr_dir/hyprland.lua" "$hypr_dir/hyprland.lua.bak.$stamp"
    cat >> "$hypr_dir/hyprland.lua" <<'LUA'

-- >>> MacShell (added by install.sh) >>>
-- Load the generated MacShell autostart and keybind module.
require("hypr.macshell")
-- Liquid Glass: blur behind the shell surfaces
hl.layer_rule({ name = "macdock",  match = { namespace = "macdock"  }, blur = true, ignore_alpha = 0.2,  no_anim = true })
hl.layer_rule({ name = "macspot",  match = { namespace = "macspot"  }, blur = true, ignore_alpha = 0.05, no_anim = true })
hl.layer_rule({ name = "macbarbg", match = { namespace = "macbarbg" }, blur = true, ignore_alpha = 0.05, no_anim = true })
hl.layer_rule({ name = "macshot",  match = { namespace = "macshot"  }, no_anim = true })
-- <<< MacShell <<<
LUA
    printf 'Restored MacShell autostart in %s\n' "$hypr_dir/hyprland.lua"
  fi
fi

# Hyprland blur behind the menu bar's popovers, switcher, wallpaper picker and OSD (barStyle / dockStyle "blur").
if [[ -f "$HOME/.config/hypr/hyprland.lua" ]]; then
  [[ ! -f "$HOME/.config/hypr/silky-native-blur.lua" ]] ||
    cp -a "$HOME/.config/hypr/silky-native-blur.lua" "$backup_dir/settings/"
  install -m 644 "$repo_root/config/hypr/silky-native-blur.lua" "$HOME/.config/hypr/silky-native-blur.lua"
  grep -q 'require("hypr.silky-native-blur")' "$HOME/.config/hypr/hyprland.lua" \
    || printf '\n-- Silky Omarchy: Hyprland blur behind MacShell popovers, switcher, wallpaper picker and OSD.\nrequire("hypr.silky-native-blur")\n' >> "$HOME/.config/hypr/hyprland.lua"
fi

# macshell-start: never start a second MacShell next to a running one (-n), so a crash can not leave two menu bars.
start_script="$HOME/.local/bin/macshell-start"
if [[ -f $start_script ]] && ! grep -q 'qs -n -c "$NAME"' "$start_script"; then
  cp -a "$start_script" "$backup_dir/settings/macshell-start"
  sed -i 's/    qs -c "$NAME" >>"$LOG" 2>&1 &/    qs -n -c "$NAME" >>"$LOG" 2>\&1 \&   # -n: never a second copy next to a running one/' "$start_script"
fi
if [[ -f $start_script ]]; then
  python3 "$repo_root/scripts/install-macshell-watchdog.py" "$backup_dir/settings"
fi

python3 "$repo_root/scripts/migrate-macshell-files.py"

printf 'Applied successfully. Backup: %s\n' "$backup_dir"
printf 'Restart MacShell from Settings > Tools > Restart to load the QML and renderer changes.\n'
