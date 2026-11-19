#!/usr/bin/env bash
# Install (or with --uninstall, remove) the Silky desktop priority service.
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
bin=/usr/local/bin/silky-desktop-priority
conf=/etc/silky/desktop-priority.conf
unit=/etc/systemd/system/silky-desktop-priority.service

for command_name in python3 systemctl sudo; do
  command -v "$command_name" >/dev/null || {
    printf 'Missing required command: %s\n' "$command_name" >&2
    exit 1
  }
done

if [[ ${1:-} == --uninstall ]]; then
  # Stopping the service resets nice / uclamp and the GPU floor first.
  sudo systemctl disable --now silky-desktop-priority.service 2>/dev/null || true
  sudo rm -f -- "$bin" "$unit"
  sudo systemctl daemon-reload
  printf 'Removed the service. %s is kept; delete it by hand if unwanted.\n' "$conf"
  exit 0
fi

python3 -I -m py_compile "$repo_root/bin/silky-desktop-priority" 2>/dev/null ||
  { printf 'bin/silky-desktop-priority has a syntax error\n' >&2; exit 1; }
find "$repo_root/bin" -name __pycache__ -type d -exec rm -rf {} +
python3 -I "$repo_root/bin/silky-desktop-priority" \
  --config "$repo_root/config/silky/desktop-priority.conf" --status >/dev/null

if sudo test -f "$conf" && ! sudo cmp -s "$repo_root/config/silky/desktop-priority.conf" "$conf"; then
  backup="$conf.bak.$(date +%Y%m%d-%H%M%S)"
  sudo cp -p -- "$conf" "$backup"
  printf 'Backed up the existing configuration to %s\n' "$backup"
fi
sudo install -Dm 755 "$repo_root/bin/silky-desktop-priority" "$bin"
sudo install -Dm 644 "$repo_root/config/silky/desktop-priority.conf" "$conf"
sudo install -Dm 644 "$repo_root/config/systemd/system/silky-desktop-priority.service" "$unit"
sudo systemctl daemon-reload
sudo systemctl enable silky-desktop-priority.service
sudo systemctl restart silky-desktop-priority.service
sleep 3
if ! systemctl is-active --quiet silky-desktop-priority.service; then
  sudo journalctl -u silky-desktop-priority.service -n 20 --no-pager >&2
  printf 'silky-desktop-priority failed to start\n' >&2
  exit 1
fi
"$bin" --config "$conf" --status
