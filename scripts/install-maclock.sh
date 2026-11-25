#!/usr/bin/env bash
set -euo pipefail

# Silky Omarchy: use MacLock for every lock (keys, menu, idle, lid close, suspend) instead of Omarchy's lock screen.
# See docs/07-lock-and-boot.md. MacShell (0.5.1+) with MacLock must already be installed.
repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
stamp=$(date +%Y%m%d-%H%M%S)
lock_via_ipc="$HOME/.config/quickshell/MacLock/lock-via-ipc.sh"

[[ -f $lock_via_ipc ]] || { printf 'MacLock is not installed.\n' >&2; exit 1; }

mkdir -p "$HOME/.local/bin" "$HOME/.config/systemd/user" "$HOME/.config/omarchy/plugins"
install -m 755 \
  "$repo_root/bin/silky-lock" \
  "$repo_root/bin/silky-sleep-lock" \
  "$repo_root/bin/silky-lid-close" \
  "$HOME/.local/bin/"

# Serialize all MacLock launches with flock so simultaneous triggers (Super+L, lid switch, PrepareForSleep)
# can never spawn two competing `qs -c MacLock` instances.
if ! grep -q 'SILKY_MACLOCK_FLOCK' "$lock_via_ipc"; then
  cp -a "$lock_via_ipc" "$lock_via_ipc.bak.$stamp"
  python3 - "$lock_via_ipc" <<'PY'
import sys

path = sys.argv[1]
text = open(path, encoding="utf-8").read()
guard = """if [ "${SILKY_MACLOCK_FLOCK:-0}" != "1" ] && command -v flock >/dev/null 2>&1; then
    export SILKY_MACLOCK_FLOCK=1
    exec flock -w 8 "${XDG_RUNTIME_DIR:-/tmp}/silky-maclock.lock" "$0" "$@"
fi
"""
target = "set -u\n"
if target in text:
    text = text.replace(target, target + "\n" + guard, 1)
else:
    lines = text.splitlines(keepends=True)
    lines.insert(1 if lines and lines[0].startswith("#!") else 0, guard)
    text = "".join(lines)
open(path, "w", encoding="utf-8").write(text)
PY
  chmod +x "$lock_via_ipc"
fi

# Retire MacShell's redundant hypridle sleep-lock hook: silky-sleep-lock.service owns the pre-suspend lock
# and silky.idle owns idle timeouts, so running hypridle in parallel only causes duplicate PrepareForSleep races.
macshell_lua="$HOME/.config/hypr/macshell.lua"
if [[ -f $macshell_lua ]] && grep -Eq '^[[:space:]]*hl\.exec_cmd\("sh ~/.config/quickshell/MacLock/enable-sleep-lock\.sh"\)' "$macshell_lua"; then
  cp -a "$macshell_lua" "$macshell_lua.bak.$stamp"
  sed -i -E 's|^([[:space:]]*)hl\.exec_cmd\("sh ~/.config/quickshell/MacLock/enable-sleep-lock\.sh"\)|\1-- Silky Omarchy: disabled redundant hypridle hook (handled by silky-sleep-lock.service)\n\1-- hl.exec_cmd("sh ~/.config/quickshell/MacLock/enable-sleep-lock.sh")|' "$macshell_lua"
fi
hypridle_conf="$HOME/.config/hypr/hypridle.conf"
if [[ ! -f $hypridle_conf ]] || ! grep -Eq '^[[:space:]]*listener[[:space:]]*\{' "$hypridle_conf"; then
  pkill -x hypridle 2>/dev/null || true
fi

# Idle: a copy of Omarchy's idle service whose lock is MacLock.
rm -rf "$HOME/.config/omarchy/plugins/silky.idle"
cp -r "$repo_root/config/omarchy/plugins/silky.idle" "$HOME/.config/omarchy/plugins/"
omarchy plugin enable silky.idle >/dev/null
omarchy plugin disable omarchy.idle >/dev/null

# Suspend: our inhibitor-backed service instead of omarchy-sleep-lock.service.
install -m 644 "$repo_root/config/systemd/silky-sleep-lock.service" "$HOME/.config/systemd/user/"
systemctl --user daemon-reload
systemctl --user mask omarchy-sleep-lock.service >/dev/null 2>&1 || true
systemctl --user stop omarchy-sleep-lock.service 2>/dev/null || true
systemctl --user enable --now silky-sleep-lock.service
systemctl --user restart silky-sleep-lock.service

# Super+Ctrl+L, laptop lid close switches, and the menu's Lock item.
bindings="$HOME/.config/hypr/bindings.lua"
if [[ -f $bindings ]]; then
  need_rebind=0
  grep -q '"SUPER + CTRL + L", "Lock system", "silky-lock"' "$bindings" || need_rebind=1
  grep -q '"switch:on:Lid Switch", nil, "silky-lid-close"' "$bindings" || need_rebind=1
  if (( need_rebind )); then
    cp -a "$bindings" "$bindings.bak.$stamp"
    if ! grep -q '"SUPER + CTRL + L", "Lock system", "silky-lock"' "$bindings"; then
      cat "$repo_root/config/hypr/bindings-lock.lua" >> "$bindings"
    else
      cat >> "$bindings" <<'LUA'

-- Silky Omarchy: lid close locks with MacLock instead of omarchy-system-lid-close (omarchy.lock).
o.rebind("switch:on:Lid Switch", nil, "silky-lid-close", { locked = true })
o.rebind("switch:on:Apple SMC power/lid events", nil, "silky-lid-close", { locked = true })
o.rebind("switch:on:cros_ec_buttons", nil, "silky-lid-close", { locked = true })
LUA
    fi
  fi
fi

menu="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
if [[ -f $menu ]] && ! grep -q '"system.lock"' "$menu"; then
  cp -a "$menu" "$menu.bak.$stamp"
  python3 - "$menu" "$repo_root/config/omarchy/omarchy-menu-lock.jsonc" <<'PY'
import sys
path, snippet = sys.argv[1], open(sys.argv[2]).read()
text = open(path).read()
end = text.rstrip().rindex('}')
open(path, 'w').write(text[:end] + '\n' + snippet + text[end:])
PY
fi

# MacShell has its own Dock. Omarchy's dock otherwise comes back whenever the Omarchy shell restarts.
omarchy plugin disable omarchy.dock >/dev/null 2>&1 || true
omarchy restart shell >/dev/null 2>&1 || true
hyprctl reload >/dev/null 2>&1 || true
hyprctl configerrors
printf 'All locks now use MacLock.\n'
