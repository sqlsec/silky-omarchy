#!/bin/bash
# Install the Silky macOS Obsidian theme and the Silky Typing plugin into Obsidian vaults.
#
#   ./scripts/install-obsidian-theme.sh                 # every vault listed in ~/.config/obsidian/obsidian.json
#   ./scripts/install-obsidian-theme.sh ~/Notes ...     # only these vaults
#   ./scripts/install-obsidian-theme.sh --no-plugin     # theme only, no typing animation
#   ./scripts/install-obsidian-theme.sh --remove [...]  # put the vaults back the way they were
#
# Per vault it copies the theme to .obsidian/themes/Silky macOS/, the plugin to .obsidian/plugins/silky-typing/,
# sets "cssTheme" and "theme": "system" (follow light / dark) in appearance.json and lists the plugin in
# community-plugins.json. The original appearance.json and community-plugins.json are saved once to
# ~/.local/state/silky-omarchy/obsidian/<vault-hash>/ and restored by --remove. Safe to run again.
#
# It also writes ~/.local/share/applications/obsidian.desktop, a copy of the packaged entry with
# StartupWMClass=md.obsidian.Obsidian, so the Dock recognises the open window instead of bouncing.
set -euo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
theme_name="Silky macOS"
plugin_id="silky-typing"
theme_src="$repo/config/obsidian/themes/$theme_name"
plugin_src="$repo/config/obsidian/plugins/$plugin_id"
obsidian_json="${XDG_CONFIG_HOME:-$HOME/.config}/obsidian/obsidian.json"
state_root="${XDG_STATE_HOME:-$HOME/.local/state}/silky-omarchy/obsidian"

mode=install
with_plugin=1
vaults=()
for arg in "$@"; do
  case "$arg" in
    --remove) mode=remove ;;
    --no-plugin) with_plugin=0 ;;
    -h | --help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "Unknown option: $arg" >&2; exit 2 ;;
    *) vaults+=("$(realpath -- "$arg")") ;;
  esac
done

command -v python3 >/dev/null || { echo "python3 is required to edit the vault's JSON settings." >&2; exit 1; }

if ((${#vaults[@]} == 0)); then
  if [[ ! -f $obsidian_json ]]; then
    echo "No vaults given and $obsidian_json does not exist. Open a vault in Obsidian once, or pass its path." >&2
    exit 1
  fi
  mapfile -t vaults < <(python3 -I -c '
import json, sys
for v in json.load(open(sys.argv[1])).get("vaults", {}).values():
    print(v["path"])' "$obsidian_json")
fi
((${#vaults[@]})) || { echo "No Obsidian vaults found." >&2; exit 1; }

# Edits one JSON file in place: python3 json_edit FILE ACTION
json_edit() {
  python3 -I - "$@" <<'PY'
import json, os, sys
path, action = sys.argv[1], sys.argv[2]
theme, plugin = "Silky macOS", "silky-typing"
try:
    with open(path) as f:
        data = json.load(f)
except FileNotFoundError:
    data = [] if path.endswith("community-plugins.json") else {}
if action == "appearance":
    data["cssTheme"] = theme
    data["theme"] = "system"
elif action == "plugin-add":
    if plugin not in data:
        data.append(plugin)
elif action == "plugin-del":
    data = [p for p in data if p != plugin]
elif action == "appearance-del":
    if data.get("cssTheme") == theme:
        data.pop("cssTheme")
tmp = path + ".silky-tmp"
with open(tmp, "w") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")
os.replace(tmp, path)
PY
}

failures=0
for vault in "${vaults[@]}"; do
  config="$vault/.obsidian"
  if [[ ! -d $config ]]; then
    echo "skip  $vault (no .obsidian folder — open it in Obsidian first)" >&2
    failures=$((failures + 1))
    continue
  fi
  state="$state_root/$(printf '%s' "$vault" | sha1sum | cut -c1-12)"

  if [[ $mode == install ]]; then
    if [[ ! -f $state/vault ]]; then
      mkdir -p "$state"
      printf '%s\n' "$vault" > "$state/vault"
      for f in appearance.json community-plugins.json; do
        if [[ -f $config/$f ]]; then cp -p -- "$config/$f" "$state/$f"; else : > "$state/$f.absent"; fi
      done
    fi

    mkdir -p "$config/themes"
    rm -rf -- "$config/themes/$theme_name"
    cp -r -- "$theme_src" "$config/themes/$theme_name"
    json_edit "$config/appearance.json" appearance

    if ((with_plugin)); then
      mkdir -p "$config/plugins"
      rm -rf -- "${config:?}/plugins/$plugin_id"
      cp -r -- "$plugin_src" "$config/plugins/$plugin_id"
      json_edit "$config/community-plugins.json" plugin-add
    fi
    echo "ok    $vault"
  else
    rm -rf -- "$config/themes/$theme_name" "${config:?}/plugins/$plugin_id"
    for f in appearance.json community-plugins.json; do
      if [[ -f $state/$f ]]; then
        cp -p -- "$state/$f" "$config/$f"
      elif [[ -f $state/$f.absent ]]; then
        rm -f -- "$config/$f"
      elif [[ $f == appearance.json && -f $config/$f ]]; then
        json_edit "$config/$f" appearance-del
      elif [[ -f $config/$f ]]; then
        json_edit "$config/$f" plugin-del
      fi
    done
    rmdir -- "$config/themes" "$config/plugins" 2>/dev/null || true
    rm -rf -- "$state"
    echo "removed $vault"
  fi
done

# Obsidian's native Wayland window has the app id md.obsidian.Obsidian, but the packaged entry says
# StartupWMClass=obsidian. The Dock then never links the open window to its icon: every click starts a
# second process that hands over to the running one and exits, and the icon bounces waiting for a window.
# A user-level copy of the entry with the right class fixes it; nothing under /usr/share is touched.
apps_dir="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
desktop_user="$apps_dir/obsidian.desktop"
desktop_backup="$state_root/obsidian.desktop.backup"
desktop_marker="X-Silky-Omarchy=obsidian-wmclass"
desktop_system=""
for dir in /usr/share/applications /usr/local/share/applications; do
  [[ -f $dir/obsidian.desktop ]] && { desktop_system="$dir/obsidian.desktop"; break; }
done
if [[ $mode == install ]]; then
  if [[ -z $desktop_system ]]; then
    echo "skip  desktop entry (no obsidian.desktop under /usr/share/applications)" >&2
  else
    mkdir -p "$apps_dir" "$state_root"
    if [[ -f $desktop_user ]] && ! grep -qx "$desktop_marker" "$desktop_user" && [[ ! -f $desktop_backup ]]; then
      cp -p -- "$desktop_user" "$desktop_backup"
    fi
    awk -v marker="$desktop_marker" '
      /^\[/ { in_entry = ($0 == "[Desktop Entry]") }
      in_entry && /^StartupWMClass=/ { next }
      { print }
      $0 == "[Desktop Entry]" { print "StartupWMClass=md.obsidian.Obsidian"; print marker }
    ' "$desktop_system" > "$desktop_user.silky-tmp"
    mv -f -- "$desktop_user.silky-tmp" "$desktop_user"
    command -v update-desktop-database >/dev/null && update-desktop-database -q "$apps_dir" || true
    echo "ok    $desktop_user (StartupWMClass=md.obsidian.Obsidian)"
  fi
else
  if [[ -f $desktop_user ]] && grep -qx "$desktop_marker" "$desktop_user"; then
    rm -f -- "$desktop_user"
    [[ -f $desktop_backup ]] && mv -f -- "$desktop_backup" "$desktop_user"
    command -v update-desktop-database >/dev/null && update-desktop-database -q "$apps_dir" || true
    echo "removed $desktop_user"
  fi
fi

if [[ $mode == install ]]; then
  cat <<'EOF'

Obsidian picks up the theme without a restart. For the typing animation, once per vault:
  Settings → Community plugins → turn off Restricted mode, then make sure "Silky Typing" is on.
设置 → 第三方插件 → 关闭「安全模式」，并确认「Silky Typing」已开启（每个库一次）。
EOF
fi
exit $((failures > 0))
