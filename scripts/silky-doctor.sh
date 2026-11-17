#!/usr/bin/env bash
# Silky Omarchy self-check: the visible desktop state everything else here assumes. Run it after a login, an update
# or any change; each line is OK or a problem with the fix. Exit status is the number of problems.
set -u

problems=0
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
bad()  { printf '  \033[31m✗\033[0m %s\n    → %s\n' "$1" "$2"; problems=$((problems + 1)); }
count_layer() { hyprctl layers -j 2>/dev/null | jq -r '.[].levels[][]? | .namespace' | grep -c "^$1\$"; }

printf 'Silky Omarchy self-check\n'

errors=$(hyprctl configerrors 2>/dev/null | grep -v '^\s*$' || true)
[[ -z $errors ]] && ok "Hyprland config has no errors" || bad "Hyprland config errors: $errors" "fix the file named above, then: hyprctl reload"

n=$(pgrep -c -f '(^|/)qs( -n)? -c MacShell$'); n=${n:-0}
others=$(pgrep -a quickshell | grep -v -- '-p /usr/share/omarchy/shell' | grep -c . || true)
if [[ $n -eq 1 && $others -eq 0 ]]; then ok "exactly one MacShell"
else bad "$n MacShell instance(s), $others other quickshell process(es)" "pkill -f 'qs .*-c MacShell'; pkill -x quickshell -f -- '^/usr/bin/quickshell$'; sh ~/.local/bin/macshell-start &"; fi

for layer in macbar macdock; do
  c=$(count_layer "$layer")
  [[ $c -eq 1 ]] && ok "one $layer" || bad "$c $layer surfaces" "a duplicate MacShell is running: see the line above"
done

[[ $(count_layer omarchy-dock) -eq 0 ]] && ok "Omarchy's own dock is off" || bad "Omarchy's dock is showing" "omarchy plugin disable omarchy.dock"
bar_y=$(hyprctl layers -j | jq -r '[.[].levels[][]? | select(.namespace == "omarchy-bar")][0].y // "none"')
[[ $bar_y == none || $bar_y -lt 0 ]] && ok "Omarchy's own top bar is hidden" || bad "Omarchy's top bar is visible" "omarchy toggle bar on"

top=$(hyprctl monitors -j | jq '[.[] | .reserved[1]] | max')
under=$(hyprctl clients -j | jq -r --argjson top "$top" '[.[] | select(.floating and .mapped and (.at[1] < $top)) | .class] | join(", ")')
[[ -z $under ]] && ok "no window under the menu bar" || bad "under the menu bar: $under" "drag it down once (the plugin keeps it below from then on)"

[[ $(hyprctl -j plugin list | jq '[.[] | select(.name == "hyprbars")] | length') -le 1 ]] && ok "at most one titlebar plugin" \
  || bad "titlebar plugin loaded twice" "log out and back in; do not load a second hyprbars"
hyprctl -j plugin list | jq -e '.[] | select(.name == "silky-gestures")' >/dev/null && ok "silky-gestures loaded" \
  || bad "silky-gestures not loaded" "./scripts/install-silky-gestures.sh"

systemctl --user is-active -q silky-sleep-lock && ok "MacLock locks before suspend" || bad "silky-sleep-lock is not running" "systemctl --user enable --now silky-sleep-lock"
omarchy plugin list 2>/dev/null | grep -q '^silky.idle .*enabled' && ok "idle lock uses MacLock" || bad "silky.idle is not enabled" "./scripts/install-maclock.sh"
busctl --user list 2>/dev/null | grep -q 'WowType.VoiceOverlay' && ok "voice overlay is attached to WowType" || bad "voice overlay not running" "qs -c SilkyVoice &"

[[ $(hyprctl getoption input:natural_scroll | head -1) == *true* ]] && ok "mouse natural scrolling on" || bad "mouse natural scrolling off" "check input.natural_scroll in ~/.config/hypr/input.lua"

# 快捷键冲突: a key MacShell uses must do only the MacShell thing (config/hypr/silky-shortcuts.lua).
dump="${XDG_RUNTIME_DIR:-/tmp}/silky-keys-doctor.json"
if hyprctl dispatch "function() silky_keys.dump(\"$dump\") end" >/dev/null 2>&1 && [[ -s $dump ]]; then
  clash=$(jq -r 'group_by((.mods|join(" ")) + "+" + (.key|ascii_upcase))
                 | map(select(length > 1 and any(.[]; .desc | test("MacShell|MacLock"))))
                 | map((.[0].mods + [.[0].key] | join("+")) + " (" + (map(.desc) | join(" / ")) + ")") | join(", ")' "$dump")
  [[ -z $clash ]] && ok "no shortcut shared between MacShell and Omarchy" \
    || bad "shortcut conflicts: $clash" "move the Omarchy action in ~/.config/hypr/silky-shortcuts.lua (docs/10-shortcuts.md)"
  rm -f "$dump"
else
  bad "keybinding registry not loaded" "./scripts/install-shortcuts.sh"
fi
qs -c SilkyKeys ipc show >/dev/null 2>&1 && ok "Super+K shortcut panel is running" || bad "Silky Keys panel not running" "qs -c SilkyKeys -d"

crashes=$(find ~/.cache/quickshell/crashes -mindepth 1 -maxdepth 1 -newermt "$(uptime -s)" 2>/dev/null | wc -l)
[[ $crashes -eq 0 ]] && ok "no Quickshell crashes since boot" || bad "$crashes Quickshell crash report(s) since boot" "see ~/.cache/quickshell/crashes/*/report.txt"

printf '\n%s\n' "$([[ $problems -eq 0 ]] && echo 'All good.' || echo "$problems problem(s).")"
exit "$problems"
