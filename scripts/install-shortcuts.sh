#!/usr/bin/env bash
set -euo pipefail

# Installs the shortcut fixes (see docs/10-shortcuts.md):
#   - silky-keys-registry.lua  records every bind (required first in hyprland.lua)
#   - silky-shortcuts.lua      MacShell wins shared keys; Omarchy's actions move to free keys (required last)
#   - silky-keys.lua + keys-panel/shell.qml   Super+K: searchable macOS 27-style shortcut panel (Silky Keys)
repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
hypr_dir="$HOME/.config/hypr"
panel_dir="$HOME/.config/quickshell/SilkyKeys"
config="$hypr_dir/hyprland.lua"

for command_name in qs hyprctl jq python3; do
  command -v "$command_name" >/dev/null || { printf 'Missing required command: %s\n' "$command_name" >&2; exit 1; }
done
[[ -f $config ]] || { printf 'Missing %s\n' "$config" >&2; exit 1; }
grep -q 'require("hypr.macshell")' "$config" || printf 'Note: MacShell is not loaded in hyprland.lua; the panel works, the MacShell keys will do nothing.\n' >&2

mkdir -p "$panel_dir"
install -m 644 "$repo_root/keys-panel/shell.qml" "$panel_dir/shell.qml"
for name in silky-keys-registry silky-shortcuts silky-keys; do
  install -m 644 "$repo_root/config/hypr/$name.lua" "$hypr_dir/$name.lua"
done

cp -a "$config" "$config.bak.$(date +%Y%m%d-%H%M%S)"
python3 -I - "$config" <<'PY'
import sys, pathlib
path = pathlib.Path(sys.argv[1])
text = path.read_text()
boot = 'dofile((os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/default/hypr/bootstrap.lua")\n'
if 'require("hypr.silky-keys-registry")' not in text:
    if boot not in text:
        sys.exit("Could not find Omarchy's bootstrap line in hyprland.lua; add require(\"hypr.silky-keys-registry\") right after it by hand.")
    text = text.replace(boot, boot + '\n-- Silky Omarchy: remember every keybinding for the Super+K panel. Keep this before Omarchy\'s defaults.\nrequire("hypr.silky-keys-registry")\n', 1)
# These two must come after everything else (silky-shortcuts overrides hypr.macshell): drop and re-append them.
lines = [l for l in text.splitlines() if l.strip() not in (
    'require("hypr.silky-shortcuts")', 'require("hypr.silky-keys")',
    '-- Silky Omarchy: MacShell wins shared shortcuts; Omarchy actions move to free keys. Keep this last.',
    '-- Silky Omarchy: Super+K opens the searchable macOS-style shortcut panel.')]
text = "\n".join(lines).rstrip() + "\n"
text += '\n-- Silky Omarchy: MacShell wins shared shortcuts; Omarchy actions move to free keys. Keep this last.\nrequire("hypr.silky-shortcuts")\n'
text += '\n-- Silky Omarchy: Super+K opens the searchable macOS-style shortcut panel.\nrequire("hypr.silky-keys")\n'
path.write_text(text)
PY

hyprctl reload >/dev/null
errors=$(hyprctl configerrors | grep -v '^\s*$' || true)
[[ -z $errors ]] || { printf 'Hyprland config errors:\n%s\n' "$errors" >&2; exit 1; }

# Restart a running panel so the new files are used.
pkill -x -f 'qs -c SilkyKeys( -d)?' 2>/dev/null || true
sleep 0.5
qs -c SilkyKeys -d >/dev/null 2>&1
printf 'Installed. Press Super+K. Moved Omarchy keys: Omarchy menu Super+Ctrl+M, universal paste Super+Alt+V,\n'
printf 'cycle layout Super+Shift+L, next/previous window Alt+` / Alt+Shift+`.\n'
