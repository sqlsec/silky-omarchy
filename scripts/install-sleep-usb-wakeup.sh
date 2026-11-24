#!/usr/bin/env bash
# Install (or with --uninstall, remove; with --status, inspect) the Silky
# systemd system-sleep hook that disables Qualcomm dwc3-qcom USB controller
# wakeups while suspending with the lid closed.
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
src_hook="$repo_root/config/systemd/system-sleep/silky-dwc3-lid-wake"
dest_hook="${SILKY_SLEEP_HOOK_DEST:-/usr/lib/systemd/system-sleep/silky-dwc3-lid-wake}"
backup_dir="${SILKY_SLEEP_BACKUP_DIR:-/var/backups/silky-omarchy}"
driver_dir="${SILKY_DWC3_DRIVER_DIR:-/sys/bus/platform/drivers/dwc3-qcom}"
state_file="${SILKY_DWC3_STATE_FILE:-/run/silky-dwc3-lid-wake.state}"
sudo_cmd="${SILKY_SUDO_CMD-sudo}"

usage() {
  cat <<'EOF'
Usage: ./scripts/install-sleep-usb-wakeup.sh [--status | --uninstall | -h | --help]

  (no args)    Install /usr/lib/systemd/system-sleep/silky-dwc3-lid-wake (uses sudo)
  --status     Show hook installation status and current dwc3-qcom wakeup flags (read-only)
  --uninstall  Remove the hook and restore any pending wakeup state (uses sudo)
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

show_status() {
  shopt -s nullglob
  printf 'Hook destination: %s\n' "$dest_hook"
  if [[ -f $dest_hook ]]; then
    if [[ -x $dest_hook ]]; then
      printf 'Hook state: installed (executable)\n'
    else
      printf 'Hook state: installed (NOT executable)\n'
    fi
    if cmp -s "$src_hook" "$dest_hook" 2>/dev/null; then
      printf 'Hook content: matches repository\n'
    else
      printf 'Hook content: differs from repository\n'
    fi
  else
    printf 'Hook state: not installed\n'
  fi

  if [[ -f $state_file ]]; then
    printf 'Pending state file: %s (present)\n' "$state_file"
  else
    printf 'Pending state file: none\n'
  fi

  local lid_closed
  lid_closed=$(busctl --timeout=5 get-property org.freedesktop.login1 /org/freedesktop/login1 \
    org.freedesktop.login1.Manager LidClosed 2>/dev/null || printf 'unavailable')
  printf 'LidClosed: %s\n' "$lid_closed"

  local found=0 wakeup
  for wakeup in "$driver_dir"/*/power/wakeup; do
    found=1
    printf 'Controller: %s = %s\n' "$wakeup" "$(cat "$wakeup" 2>/dev/null || printf 'unreadable')"
  done
  if (( found == 0 )); then
    printf 'Controller: none found under %s\n' "$driver_dir"
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
    if run_priv test -f "$state_file"; then
      run_priv bash -c '
        while IFS= read -r wakeup; do
          [[ -n $wakeup && -w $wakeup ]] || continue
          printf "enabled\n" >"$wakeup" 2>/dev/null || true
        done <"$1"
        rm -f -- "$1"
      ' _ "$state_file"
    fi
    if run_priv test -e "$dest_hook"; then
      run_priv rm -f -- "$dest_hook"
      printf 'Removed %s\n' "$dest_hook"
    else
      printf '%s is already absent.\n' "$dest_hook"
    fi
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

require_cmd bash busctl install cmp
[[ -n $sudo_cmd ]] && require_cmd "$sudo_cmd"

[[ -f $src_hook ]] || {
  printf 'Source hook not found: %s\n' "$src_hook" >&2
  exit 1
}

bash -n "$src_hook"

shopt -s nullglob
wakeups=("$driver_dir"/*/power/wakeup)
if (( ${#wakeups[@]} == 0 )); then
  printf 'Warning: no dwc3-qcom controllers found under %s; installing hook anyway.\n' "$driver_dir" >&2
fi

if run_priv test -f "$dest_hook" && ! run_priv cmp -s "$src_hook" "$dest_hook"; then
  # Keep backups outside /usr/lib/systemd/system-sleep/ so systemd-sleep never
  # executes a backup file as an extra hook.
  run_priv install -d -m 755 "$backup_dir"
  backup="$backup_dir/$(basename -- "$dest_hook").bak.$(date +%Y%m%d-%H%M%S)"
  run_priv cp -p -- "$dest_hook" "$backup"
  run_priv chmod 644 "$backup"
  printf 'Backed up existing hook to %s\n' "$backup"
fi

run_priv install -Dm 755 "$src_hook" "$dest_hook"
printf 'Installed %s\n' "$dest_hook"
show_status
