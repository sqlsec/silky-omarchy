#!/usr/bin/env bash
# Render the Silky notification-centre widgets offscreen into a PNG, with a snapshot of real data.
#   scripts/preview-macshell-widgets.sh [out.png] [kind:size ...]
#   SILKY_PREVIEW_LANG=en scripts/preview-macshell-widgets.sh /tmp/w.png ai:large stocks:medium
# Needs MacShell installed (for WeatherIcon.qml, I18n.js, the lunar calendar) and Quickshell (qs).
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
shell_dir="${MACSHELL_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/MacShell}"
out="$(realpath -m "${1:-/tmp/silky-widgets-preview.png}")"
shift || true
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

for file in WeatherIcon.qml I18n.js ChinaCalendar.js ChinaLunarDates.js; do
    [[ -e "$shell_dir/$file" ]] || { echo "MacShell file missing: $shell_dir/$file" >&2; exit 1; }
    cp "$shell_dir/$file" "$work/"
done
cp -r "$shell_dir/lang" "$work/"
mkdir -p "$work/assets"
[[ -d "$shell_dir/assets/ai-logos" ]] && cp -r "$shell_dir/assets/ai-logos" "$work/assets/"
cp "$repo"/config/macshell/widgets/*.qml "$repo"/config/macshell/widgets/*.js "$repo/config/macshell/widgets/preview/shell.qml" "$work/"

# a data snapshot from the real data process (weather from its cache, DeepSeek as a sample when no key is set)
python3 -I - "$repo/config/macshell/widgets/widgets.py" > "$work/info.js" <<'PY'
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location("widgets", sys.argv[1])
w = importlib.util.module_from_spec(spec)
spec.loader.exec_module(w)
try:
    weather = json.loads((w.CACHE / "widgets-weather.json").read_text())
except (OSError, ValueError):
    weather = None
ai = w.AiUsage().summary()
ai["deepseek"] = w.deepseek() if w.read_keys().get("deepseek") else {"configured": True, "balance": 18.3, "currency": "CNY", "spent": 0.42}
symbols = w.read_config().get("stocks") or w.DEFAULT_STOCKS
info = {"ai": ai, "weather": weather, "stocks": w.stocks(symbols[:6]), "errors": {}}
print(".pragma library\nvar info = " + json.dumps(info, ensure_ascii=False) + ";")
PY

export SILKY_PREVIEW_OUT="$out"
[[ $# -gt 0 ]] && export SILKY_PREVIEW_WIDGETS="$*"
(cd "$work" && QT_QPA_PLATFORM=offscreen timeout 30 qs -p "$work/shell.qml" 2>&1 \
    | grep -E "TypeError|ReferenceError|FINAL|is not a type|unavailable" || true)
[[ -s "$out" ]] || { echo "No image written" >&2; exit 1; }
echo "$out"
