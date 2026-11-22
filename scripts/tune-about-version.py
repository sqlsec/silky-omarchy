#!/usr/bin/env python3
"""Show Omarchy's Edge / Dev builds in MacShell's About window as "Edge · e4635a4" with a faint "11-20 build".

The Edge and Dev channels install `omarchy-dev`, whose version comes from `git describe` on master, for example
`4.0.0.r8103.ge4635a4`. `4.0.0` is only the last tag reachable from master, so the About window made a build newer
than the stable 4.5.0 look like a downgrade. This makes `about-info.sh` report the channel, the short commit and the
package build date instead. The About window shows the date as small, faint auxiliary text (`11-20 构建` in Chinese). Stable and RC
installations, and systems without `omarchy-dev`, keep the os-release version.

Usage: tune-about-version.py <MacShell dir>
"""
from pathlib import Path
import sys

shell = Path(sys.argv[1])
MARK = "# Silky: Edge / Dev builds"

INFO_OLD = "printf 'osbuild=%s\\n' \"$osbuild\"\n"
INFO_NEW = MARK + """ (omarchy-dev) are versioned by git describe on master, so "4.0.0.r8103.ge4635a4" would
# read older than the stable release. Show the channel, short commit and package build date instead.
osbuilddate=""
if [ "${ID:-}" = "omarchy" ] && command -v pacman >/dev/null 2>&1; then
    devver=$(pacman -Q omarchy-dev 2>/dev/null | awk 'NR==1 {print $2}')
    if [ -n "$devver" ]; then
        channel=$(omarchy-channel-current 2>/dev/null)
        case "$channel" in dev) channel="Dev" ;; *) channel="Edge" ;; esac
        commit=$(printf %s "$devver" | sed -n 's/.*\\.g\\([0-9a-f]\\{7,\\}\\).*/\\1/p')
        if [ -n "$commit" ]; then
            osver="$channel · $commit"; osbuild=""
            for desc in /var/lib/pacman/local/omarchy-dev-"$devver"/desc; do
                [ -r "$desc" ] || continue
                epoch=$(awk 'f {print; exit} /^%BUILDDATE%$/ {f=1}' "$desc")
                [ -n "$epoch" ] && osbuilddate=$(date -d "@$epoch" +%m-%d 2>/dev/null)
            done
            printf 'osver=%s\\nosbuild=\\n' "$osver"
        fi
    fi
fi
printf 'osbuilddate=%s\\n' "$osbuilddate"
"""

QML_OLD = 'r.push({ k: o.osname || "Linux", v: (o.osver || "") + (o.osbuild || ""), s: "" });'
# The build date is auxiliary text, small and faint like "12 cores" and "8448 MT/s".
QML_NEW = ('r.push({ k: o.osname || "Linux", v: (o.osver || "") + (o.osbuild || ""),'
           ' s: o.osbuilddate ? I18n.tr("%1 build").replace("%1", o.osbuilddate) : "" });')
# Earlier form of this tuning (date in parentheses inside the value), migrated in place.
QML_PREVIOUS = ('r.push({ k: o.osname || "Linux", v: (o.osver || "") + (o.osbuild || "")'
                ' + (o.osbuilddate ? I18n.tr(" (%1 build)").replace("%1", o.osbuilddate) : ""), s: "" });')

LANG_ANCHOR = '    "Available": "可用",\n'
LANG_NEW = '    "%1 build": "%1 构建",\n'
LANG_PREVIOUS = '    " (%1 build)": "（%1 构建）",\n'


def tune(path, old, new, insert_after=False):
    text = path.read_text()
    if new in text:
        return
    if text.count(old) != 1:
        raise SystemExit(f"About version tuning ({path.name}): expected text missing or repeated: {old[:70]!r}")
    text = text.replace(old, old + new if insert_after else new)
    path.write_text(text)


info = shell / "assets/about-info.sh"
if MARK not in info.read_text():
    tune(info, INFO_OLD, INFO_NEW, insert_after=True)
about = shell / "AboutApp.qml"
if QML_PREVIOUS in about.read_text():
    tune(about, QML_PREVIOUS, QML_NEW)
tune(about, QML_OLD, QML_NEW)
lang = shell / "lang/zh-CN.js"
if LANG_PREVIOUS in lang.read_text():
    lang.write_text(lang.read_text().replace(LANG_PREVIOUS, ""))
tune(lang, LANG_ANCHOR, LANG_NEW, insert_after=True)
