#!/usr/bin/env bash
# Install (or with --uninstall, remove) the Silky battery charge limit helper,
# persistence service, resume hook, and polkit action.
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
bin=/usr/local/bin/silky-charge-limit
conf=/etc/silky/charge-limit.conf
unit=/etc/systemd/system/silky-charge-limit.service
sleep_hook=/etc/systemd/system-sleep/silky-charge-limit
policy=/usr/share/polkit-1/actions/com.silky.charge-limit.policy
limit_arg=""

usage() {
  printf 'Usage: %s [--limit <55..100> | --uninstall]\n' "$(basename -- "$0")" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --uninstall)
      sudo systemctl disable --now silky-charge-limit.service 2>/dev/null || true
      sudo rm -f -- "$bin" "$unit" "$sleep_hook" "$policy"
      sudo systemctl daemon-reload
      printf 'Removed silky-charge-limit. %s is kept; delete it by hand if unwanted.\n' "$conf"
      exit 0
      ;;
    --limit)
      [[ $# -ge 2 ]] || usage
      limit_arg=$2
      if [[ ! $limit_arg =~ ^[0-9]{2,3}$ ]] || (( limit_arg < 55 || limit_arg > 100 )); then
        printf 'Invalid --limit %q (expected 55..100)\n' "$limit_arg" >&2
        exit 2
      fi
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

for command_name in systemctl sudo; do
  command -v "$command_name" >/dev/null || {
    printf 'Missing required command: %s\n' "$command_name" >&2
    exit 1
  }
done

bash -n "$repo_root/bin/silky-charge-limit"
bash -n "$repo_root/config/systemd/system-sleep/silky-charge-limit"

backup_if_diff() {
  local src=$1 dst=$2
  if sudo test -f "$dst" && ! sudo cmp -s "$src" "$dst"; then
    local bak="$dst.bak.$(date +%Y%m%d-%H%M%S)"
    sudo cp -p -- "$dst" "$bak"
    printf 'Backed up %s to %s\n' "$dst" "$bak"
  fi
}

backup_if_diff "$repo_root/bin/silky-charge-limit" "$bin"
backup_if_diff "$repo_root/config/systemd/system/silky-charge-limit.service" "$unit"
backup_if_diff "$repo_root/config/systemd/system-sleep/silky-charge-limit" "$sleep_hook"
backup_if_diff "$repo_root/config/polkit/com.silky.charge-limit.policy" "$policy"

sudo install -Dm 755 "$repo_root/bin/silky-charge-limit" "$bin"
sudo install -Dm 644 "$repo_root/config/systemd/system/silky-charge-limit.service" "$unit"
sudo install -Dm 755 "$repo_root/config/systemd/system-sleep/silky-charge-limit" "$sleep_hook"
sudo install -Dm 644 "$repo_root/config/polkit/com.silky.charge-limit.policy" "$policy"

if [[ -n $limit_arg ]]; then
  sudo "$bin" apply "$limit_arg"
elif ! sudo test -f "$conf"; then
  sudo install -Dm 644 "$repo_root/config/silky/charge-limit.conf" "$conf"
  sudo "$bin" restore
else
  sudo "$bin" restore
fi

sudo systemctl daemon-reload
sudo systemctl enable --now silky-charge-limit.service
"$bin" status
