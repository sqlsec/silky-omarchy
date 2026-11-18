#!/usr/bin/env bash
set -euo pipefail

# Silky Omarchy: use MacLock for every lock (keys, menu, idle, suspend) instead of Omarchy's lock screen.
# See docs/07-lock-and-boot.md. MacShell (0.5.1 or 0.5.2) with MacLock must already be installed.
repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
stamp=$(date +%Y%m%d-%H%M%S)

[[ -f $HOME/.config/quickshell/MacLock/lock-via-ipc.sh ]] || { printf 'MacLock is not installed.\n' >&2; exit 1; }

mkdir -p "$HOME/.local/bin" "$HOME/.config/systemd/user" "$HOME/.config/omarchy/plugins"
install -m 755 "$repo_root/bin/silky-lock" "$repo_root/bin/silky-sleep-lock" "$HOME/.local/bin/"

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

# Super+Ctrl+L and the menu's Lock item.
bindings="$HOME/.config/hypr/bindings.lua"
if ! grep -q '"SUPER + CTRL + L", "Lock system", "silky-lock"' "$bindings"; then
  cp -a "$bindings" "$bindings.bak.$stamp"
  cat "$repo_root/config/hypr/bindings-lock.lua" >> "$bindings"
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
hyprctl configerrors
printf 'All locks now use MacLock.\n'
