#!/usr/bin/env bash
# Install (or with --uninstall, remove; with --status, inspect) the Silky
# systemd system-sleep hooks for Qualcomm Snapdragon X laptops:
#   1. silky-dwc3-lid-wake  — disable dwc3-qcom USB wakeup IRQs while lid is closed
#   2. silky-ath12k-sleep   — unload/reload ath12k_wifi7 across suspend to prevent
#                             PCIe L2 timeouts and resume hard resets
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

src_dwc3_hook="$repo_root/config/systemd/system-sleep/silky-dwc3-lid-wake"
dest_dwc3_hook="${SILKY_SLEEP_HOOK_DEST:-/usr/lib/systemd/system-sleep/silky-dwc3-lid-wake}"
dwc3_driver_dir="${SILKY_DWC3_DRIVER_DIR:-/sys/bus/platform/drivers/dwc3-qcom}"
dwc3_state_file="${SILKY_DWC3_STATE_FILE:-/run/silky-dwc3-lid-wake.state}"

src_ath12k_hook="$repo_root/config/systemd/system-sleep/silky-ath12k-sleep"
dest_ath12k_hook="${SILKY_ATH12K_HOOK_DEST:-/usr/lib/systemd/system-sleep/silky-ath12k-sleep}"
ath12k_module_root="${SILKY_ATH12K_MODULE_ROOT:-/sys/module}"
ath12k_pci_root="${SILKY_ATH12K_PCI_DRIVERS_ROOT:-/sys/bus/pci/drivers}"
ath12k_state_file="${SILKY_ATH12K_STATE_FILE:-/run/silky-ath12k-sleep.state}"

backup_dir="${SILKY_SLEEP_BACKUP_DIR:-/var/backups/silky-omarchy}"
sudo_cmd="${SILKY_SUDO_CMD-sudo}"

usage() {
  cat <<'EOF'
Usage: ./scripts/install-sleep-usb-wakeup.sh [--status | --uninstall | -h | --help]

  (no args)    Install silky-dwc3-lid-wake and silky-ath12k-sleep into /usr/lib/systemd/system-sleep/ (uses sudo)
  --status     Show hook installation status, dwc3-qcom wakeup flags, and ath12k module state (read-only)
  --uninstall  Remove both hooks and restore any pending wakeup/module state (uses sudo)
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

report_hook() {
  local label="$1" src="$2" dest="$3" state="$4"
  printf '=== %s ===\n' "$label"
  printf 'Hook destination: %s\n' "$dest"
  if [[ -f $dest ]]; then
    if [[ -x $dest ]]; then
      printf 'Hook state: installed (executable)\n'
    else
      printf 'Hook state: installed (NOT executable)\n'
    fi
    if cmp -s "$src" "$dest" 2>/dev/null; then
      printf 'Hook content: matches repository\n'
    else
      printf 'Hook content: differs from repository\n'
    fi
  else
    printf 'Hook state: not installed\n'
  fi

  if [[ -f $state ]]; then
    printf 'Pending state file: %s (present)\n' "$state"
  else
    printf 'Pending state file: none\n'
  fi
}

show_status() {
  shopt -s nullglob

  report_hook "silky-dwc3-lid-wake" "$src_dwc3_hook" "$dest_dwc3_hook" "$dwc3_state_file"
  local lid_closed
  lid_closed=$(busctl --timeout=5 get-property org.freedesktop.login1 /org/freedesktop/login1 \
    org.freedesktop.login1.Manager LidClosed 2>/dev/null || printf 'unavailable')
  printf 'LidClosed: %s\n' "$lid_closed"

  local found=0 wakeup
  for wakeup in "$dwc3_driver_dir"/*/power/wakeup; do
    found=1
    printf 'Controller: %s = %s\n' "$wakeup" "$(cat "$wakeup" 2>/dev/null || printf 'unreadable')"
  done
  if (( found == 0 )); then
    printf 'Controller: none found under %s\n' "$dwc3_driver_dir"
  fi

  report_hook "silky-ath12k-sleep" "$src_ath12k_hook" "$dest_ath12k_hook" "$ath12k_state_file"
  local mod_found=0 mod
  for mod in ath12k_wifi7 ath12k_pci ath12k; do
    if [[ -d "$ath12k_module_root/$mod" ]]; then
      mod_found=1
      printf 'Module: %s = loaded\n' "$mod"
    fi
  done
  if (( mod_found == 0 )); then
    printf 'Module: none of ath12k_wifi7 / ath12k_pci loaded\n'
  fi

  local drv dev
  for drv in ath12k_wifi7_pci ath12k_pci; do
    for dev in "$ath12k_pci_root/$drv"/[0-9a-fA-F]*:*; do
      [[ -L $dev ]] || continue
      printf 'PCI device: %s (%s)\n' "${dev##*/}" "$drv"
    done
  done
}

install_one_hook() {
  local src="$1" dest="$2" stamp="$3"
  if run_priv test -f "$dest" && ! run_priv cmp -s "$src" "$dest"; then
    # Keep backups outside /usr/lib/systemd/system-sleep/ so systemd-sleep never
    # executes a backup file as an extra hook.
    run_priv install -d -m 755 "$backup_dir"
    local backup="$backup_dir/$(basename -- "$dest").bak.$stamp"
    run_priv cp -p -- "$dest" "$backup"
    run_priv chmod 644 "$backup"
    printf 'Backed up existing hook to %s\n' "$backup"
  fi
  run_priv install -Dm 755 "$src" "$dest"
  printf 'Installed %s\n' "$dest"
}

remove_one_hook() {
  local dest="$1"
  if run_priv test -e "$dest"; then
    run_priv rm -f -- "$dest"
    printf 'Removed %s\n' "$dest"
  else
    printf '%s is already absent.\n' "$dest"
  fi
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
  --status)
    show_status
    exit 0
    ;;
  --uninstall)
    [[ -n $sudo_cmd ]] && require_cmd "$sudo_cmd"
    if run_priv test -f "$dwc3_state_file"; then
      run_priv bash -c '
        while IFS= read -r wakeup; do
          [[ -n $wakeup && -w $wakeup ]] || continue
          printf "enabled\n" >"$wakeup" 2>/dev/null || true
        done <"$1"
        rm -f -- "$1"
      ' _ "$dwc3_state_file"
    fi
    if run_priv test -f "$ath12k_state_file"; then
      run_priv "$src_ath12k_hook" post suspend || run_priv rm -f -- "$ath12k_state_file"
    fi
    remove_one_hook "$dest_dwc3_hook"
    remove_one_hook "$dest_ath12k_hook"
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

require_cmd bash busctl install cmp modprobe
[[ -n $sudo_cmd ]] && require_cmd "$sudo_cmd"

for src in "$src_dwc3_hook" "$src_ath12k_hook"; do
  [[ -f $src ]] || {
    printf 'Source hook not found: %s\n' "$src" >&2
    exit 1
  }
  bash -n "$src"
done

shopt -s nullglob
wakeups=("$dwc3_driver_dir"/*/power/wakeup)
if (( ${#wakeups[@]} == 0 )); then
  printf 'Warning: no dwc3-qcom controllers found under %s; installing hook anyway.\n' "$dwc3_driver_dir" >&2
fi

stamp=$(date +%Y%m%d-%H%M%S)
install_one_hook "$src_dwc3_hook" "$dest_dwc3_hook" "$stamp"
install_one_hook "$src_ath12k_hook" "$dest_ath12k_hook" "$stamp"
show_status
