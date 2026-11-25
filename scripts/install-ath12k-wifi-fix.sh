#!/usr/bin/env bash
# Install (or inspect / recover / uninstall) the Silky Qualcomm WCN7850
# (ath12k_wifi7_pci) 5 GHz Wi-Fi prevention config, auto-recovery service,
# regulatory domain setting, and saved 5 GHz connection priority tuning.
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

src_nm_conf="$repo_root/config/networkmanager/30-silky-ath12k-wifi.conf"
src_bin="$repo_root/bin/silky-ath12k-recovery"
src_unit="$repo_root/config/systemd/system/silky-ath12k-recovery.service"

dest_nm_conf="${SILKY_ATH12K_NM_CONF:-/etc/NetworkManager/conf.d/30-silky-ath12k-wifi.conf}"
dest_bin="${SILKY_ATH12K_BIN:-/usr/local/bin/silky-ath12k-recovery}"
dest_unit="${SILKY_ATH12K_UNIT:-/etc/systemd/system/silky-ath12k-recovery.service}"
regdom_conf="${SILKY_REGDOM_CONF:-/etc/conf.d/wireless-regdom}"
regdom_bin="${SILKY_SET_REGDOM_BIN:-/usr/bin/set-wireless-regdom}"
regdom_country="${SILKY_REGDOM_COUNTRY:-CN}"
driver_dir="${SILKY_ATH12K_DRIVER_DIR:-/sys/bus/pci/drivers/ath12k_wifi7_pci}"
backup_dir="${SILKY_ATH12K_BACKUP_DIR:-/var/backups/silky-omarchy}"
stamp_file="${SILKY_ATH12K_STAMP:-/run/silky-ath12k-recovery.stamp}"
sudo_cmd="${SILKY_SUDO_CMD-sudo}"

resolve_state_dir() {
  if [[ -n ${SILKY_WIFI_STATE_DIR:-} ]]; then
    printf '%s\n' "$SILKY_WIFI_STATE_DIR"
    return
  fi
  if [[ -n ${SUDO_USER:-} && ${SUDO_USER} != root ]]; then
    local user_home
    user_home=$(getent passwd "$SUDO_USER" | cut -d: -f6 || true)
    if [[ -n $user_home ]]; then
      printf '%s/.local/state/silky-omarchy\n' "$user_home"
      return
    fi
  fi
  printf '%s/silky-omarchy\n' "${XDG_STATE_HOME:-$HOME/.local/state}"
}

state_dir=$(resolve_state_dir)
prio_state_file="$state_dir/wifi-5ghz-priority.state"

usage() {
  cat <<'EOF'
Usage: ./scripts/install-ath12k-wifi-fix.sh [--status | --priorities-only | --recover | --uninstall | -h | --help]

  (no args)          Install NetworkManager conf, regdom, auto-recovery service,
                     tune saved 5 GHz priorities, and recover if currently wedged (uses sudo)
  --status           Show current installation and 5 GHz radio status (read-only, no sudo)
  --priorities-only  Prefer saved 5 GHz Wi-Fi profiles over 2.4 GHz (no sudo needed)
  --recover          Reload ath12k_wifi7 now to recover a wedged 5 GHz radio (uses sudo)
  --uninstall        Remove installed files/service and restore previous settings (uses sudo)
EOF
}

run_priv() {
  if [[ -n $sudo_cmd ]]; then
    "$sudo_cmd" "$@"
  else
    "$@"
  fi
}

require_cmd() {
  local cmd
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null || {
      printf 'Missing required command: %s\n' "$cmd" >&2
      exit 1
    }
  done
}

backup_if_changed() {
  local src="$1" dest="$2"
  if run_priv test -f "$dest" && ! run_priv cmp -s "$src" "$dest"; then
    run_priv install -d -m 755 "$backup_dir"
    local bkp="$backup_dir/$(basename -- "$dest").bak.$(date +%Y%m%d-%H%M%S)"
    run_priv cp -p -- "$dest" "$bkp"
    run_priv chmod 644 "$bkp"
    printf 'Backed up %s -> %s\n' "$dest" "$bkp"
  fi
}

apply_saved_5ghz_priorities() {
  require_cmd nmcli python3
  mkdir -p "$state_dir"
  python3 -I - "$prio_state_file" <<'PY'
import os
import pathlib
import re
import subprocess
import sys

state_path = pathlib.Path(sys.argv[1])
env = {**os.environ, "LC_ALL": "C"}
five_re = re.compile(r"(?:^|[-_ ])5[gG](?:[hH][zZ])?$")

recorded = {}
if state_path.is_file():
    for raw in state_path.read_text(encoding="utf-8", errors="replace").splitlines():
        parts = raw.split("\t")
        if len(parts) >= 2:
            recorded[parts[0]] = parts[1]

res = subprocess.run(
    ["nmcli", "-t", "-f", "NAME,UUID,TYPE", "connection", "show"],
    capture_output=True, text=True, check=True, env=env,
)

changed = False
for line in res.stdout.splitlines():
    parts = line.rsplit(":", 2)
    if len(parts) != 3 or parts[2] != "802-11-wireless":
        continue
    name, uuid, _ = parts
    det = subprocess.run(
        ["nmcli", "-g", "connection.autoconnect-priority,802-11-wireless.band", "connection", "show", "uuid", uuid],
        capture_output=True, text=True, check=False, env=env,
    )
    if det.returncode != 0:
        continue
    lines = det.stdout.splitlines()
    prio_str = lines[0].strip() if len(lines) >= 1 else "0"
    band = lines[1].strip() if len(lines) >= 2 else ""
    try:
        prio = int(prio_str)
    except ValueError:
        continue

    if (band == "a" or five_re.search(name)) and prio == 0:
        if uuid not in recorded:
            recorded[uuid] = str(prio)
        mod = subprocess.run(
            ["nmcli", "connection", "modify", "uuid", uuid, "connection.autoconnect-priority", "10"],
            capture_output=True, text=True, check=False, env=env,
        )
        if mod.returncode == 0:
            print(f"Set saved 5 GHz profile '{name}' ({uuid}) autoconnect-priority: {prio} -> 10")
            changed = True

if recorded:
    state_path.write_text(
        "".join(f"{u}\t{p}\n" for u, p in sorted(recorded.items())),
        encoding="utf-8",
    )
elif not changed:
    print("Saved 5 GHz connection priorities already configured (or no matching profiles at priority 0).")
PY
}

restore_saved_5ghz_priorities() {
  [[ -f $prio_state_file ]] || return 0
  if command -v nmcli >/dev/null; then
    while IFS=$'\t' read -r uuid old_prio; do
      [[ -n ${uuid:-} && -n ${old_prio:-} ]] || continue
      if nmcli connection show uuid "$uuid" >/dev/null 2>&1; then
        nmcli connection modify uuid "$uuid" connection.autoconnect-priority "$old_prio" >/dev/null 2>&1 || true
        printf 'Restored connection %s autoconnect-priority -> %s\n' "$uuid" "$old_prio"
      fi
    done <"$prio_state_file"
  fi
  rm -f -- "$prio_state_file"
}

configure_regdom() {
  run_priv test -f "$regdom_conf" || return 0
  if run_priv grep -Eq '^[[:space:]]*WIRELESS_REGDOM="[A-Z0-9]{2}"[[:space:]]*$' "$regdom_conf"; then
    return 0
  fi
  run_priv install -d -m 755 "$backup_dir"
  local bkp="$backup_dir/wireless-regdom.bak.$(date +%Y%m%d-%H%M%S)"
  run_priv cp -p -- "$regdom_conf" "$bkp"
  run_priv chmod 644 "$bkp"
  printf '%s\n' "$bkp" | run_priv tee "$backup_dir/wireless-regdom.managed" >/dev/null
  printf 'Backed up %s -> %s\n' "$regdom_conf" "$bkp"

  local tmp
  tmp=$(mktemp)
  python3 -I - "$regdom_conf" "$regdom_country" "$tmp" <<'PY'
import pathlib
import re
import sys

src = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace").splitlines(keepends=True)
country = sys.argv[2]
out_path = pathlib.Path(sys.argv[3])
target_re = re.compile(rf'^\s*#\s*WIRELESS_REGDOM="{re.escape(country)}"\s*$')

replaced = False
out = []
for line in src:
    if not replaced and target_re.match(line):
        out.append(f'WIRELESS_REGDOM="{country}"\n')
        replaced = True
    else:
        out.append(line)
if not replaced:
    if out and not out[-1].endswith("\n"):
        out[-1] += "\n"
    out.append(f'WIRELESS_REGDOM="{country}"\n')
out_path.write_text("".join(out), encoding="utf-8")
PY
  run_priv install -m 644 "$tmp" "$regdom_conf"
  rm -f -- "$tmp"
  if [[ -x $regdom_bin ]]; then
    run_priv "$regdom_bin" || true
  fi
  printf 'Enabled WIRELESS_REGDOM="%s" in %s\n' "$regdom_country" "$regdom_conf"
}

restore_regdom() {
  local marker="$backup_dir/wireless-regdom.managed"
  if run_priv test -f "$marker"; then
    local bkp
    bkp=$(run_priv cat "$marker")
    if [[ -n $bkp ]] && run_priv test -f "$bkp"; then
      run_priv cp -p -- "$bkp" "$regdom_conf"
      printf 'Restored %s from %s\n' "$regdom_conf" "$bkp"
    fi
    run_priv rm -f -- "$marker"
  fi
}

run_status() {
  require_cmd python3
  SILKY_ATH12K_DRIVER_DIR="$driver_dir" \
  SILKY_ATH12K_NM_CONF="$dest_nm_conf" \
  SILKY_REGDOM_CONF="$regdom_conf" \
  SILKY_ATH12K_STAMP="$stamp_file" \
    python3 -I "$src_bin" --status
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
  --status)
    run_status
    exit 0
    ;;
  --priorities-only)
    apply_saved_5ghz_priorities
    exit 0
    ;;
  --recover)
    require_cmd python3
    [[ -n $sudo_cmd ]] && require_cmd "$sudo_cmd"
    target_bin="$src_bin"
    [[ -x $dest_bin ]] && target_bin="$dest_bin"
    run_priv env \
      SILKY_ATH12K_DRIVER_DIR="$driver_dir" \
      SILKY_ATH12K_NM_CONF="$dest_nm_conf" \
      SILKY_REGDOM_CONF="$regdom_conf" \
      SILKY_ATH12K_STAMP="$stamp_file" \
      python3 -I "$target_bin" --recover
    exit 0
    ;;
  --uninstall)
    [[ -n $sudo_cmd ]] && require_cmd "$sudo_cmd"
    restore_saved_5ghz_priorities
    run_priv systemctl disable --now silky-ath12k-recovery.service 2>/dev/null || true
    run_priv rm -f -- "$dest_unit" "$dest_bin" "$dest_nm_conf" "$stamp_file"
    restore_regdom
    run_priv systemctl daemon-reload 2>/dev/null || true
    run_priv nmcli general reload conf 2>/dev/null || true
    printf 'Removed ath12k 5 GHz Wi-Fi fix and restored previous settings.\n'
    if [[ -d $backup_dir ]]; then
      printf 'Backups (if any) remain in %s.\n' "$backup_dir"
    fi
    exit 0
    ;;
  "")
    ;;
  *)
    printf 'Unknown argument: %s\n' "$1" >&2
    usage >&2
    exit 1
    ;;
esac

require_cmd bash python3 nmcli systemctl install cmp
[[ -n $sudo_cmd ]] && require_cmd "$sudo_cmd"

for f in "$src_nm_conf" "$src_bin" "$src_unit"; do
  [[ -f $f ]] || {
    printf 'Source file missing: %s\n' "$f" >&2
    exit 1
  }
done

bash -n "$0"
python3 -I -m py_compile "$src_bin"
find "$repo_root/bin" -name __pycache__ -type d -exec rm -rf {} + 2>/dev/null || true

apply_saved_5ghz_priorities

backup_if_changed "$src_nm_conf" "$dest_nm_conf"
backup_if_changed "$src_bin" "$dest_bin"
backup_if_changed "$src_unit" "$dest_unit"

run_priv install -Dm 644 "$src_nm_conf" "$dest_nm_conf"
run_priv install -Dm 755 "$src_bin" "$dest_bin"
run_priv install -Dm 644 "$src_unit" "$dest_unit"

configure_regdom

run_priv nmcli general reload conf 2>/dev/null || run_priv systemctl reload NetworkManager
run_priv systemctl daemon-reload
if [[ -d $driver_dir ]]; then
  run_priv systemctl enable --now silky-ath12k-recovery.service
else
  run_priv systemctl enable silky-ath12k-recovery.service
fi

if SILKY_ATH12K_DRIVER_DIR="$driver_dir" \
   SILKY_ATH12K_NM_CONF="$dest_nm_conf" \
   SILKY_REGDOM_CONF="$regdom_conf" \
   SILKY_ATH12K_STAMP="$stamp_file" \
   python3 -I "$dest_bin" --check-wedge; then
  printf 'Detected active 5 GHz scan wedge; reloading ath12k_wifi7 now...\n'
  run_priv env \
    SILKY_ATH12K_DRIVER_DIR="$driver_dir" \
    SILKY_ATH12K_NM_CONF="$dest_nm_conf" \
    SILKY_REGDOM_CONF="$regdom_conf" \
    SILKY_ATH12K_STAMP="$stamp_file" \
    "$dest_bin" --recover
fi

run_status
