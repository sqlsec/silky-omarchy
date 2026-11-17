#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
target="${XDG_DATA_HOME:-$HOME/.local/share}/nautilus-python/extensions/silky_actions.py"
if ! command -v xdg-terminal-exec >/dev/null || ! pacman -Q nautilus-python >/dev/null 2>&1; then
  echo '请先安装 nautilus-python 和 xdg-terminal-exec。' >&2
  exit 1
fi
mkdir -p "$(dirname -- "$target")"
if [[ -e "$target" ]] && ! cmp -s "$root/nautilus/silky_actions.py" "$target"; then
  cp -p -- "$target" "$target.bak.$(date +%Y%m%d%H%M%S)"
fi
install -m 644 "$root/nautilus/silky_actions.py" "$target"
echo '安装完成。请关闭所有文件窗口后执行 nautilus -q，再重新打开文件管理器。'
