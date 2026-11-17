#!/usr/bin/env bash
set -euo pipefail

# Silky MacLock boot screen: a macOS FileVault-style Plymouth theme for the disk unlock prompt.
# Builds the images from your current wallpaper and avatar, installs the theme, and rebuilds the initramfs.
#
#   scripts/install-boot-screen.sh            build, install and activate (asks for your password)
#   scripts/install-boot-screen.sh --preview  only build the images and a preview.png, change nothing
#   scripts/install-boot-screen.sh --restore  go back to Omarchy's own boot screen

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
theme=silky-maclock
dest=/usr/share/plymouth/themes/$theme
fonts="$HOME/.config/quickshell/MacLock/fonts"
font_bold="$fonts/OpenRunde-Semibold.otf"
font_regular="$fonts/OpenRunde-Regular.otf"
# Open Runde has no Chinese glyphs: the "输入密码" hint uses Noto Sans CJK when it is there.
font_cjk=/usr/share/fonts/noto-cjk/NotoSansCJK-Regular.ttc
[[ -f $font_cjk ]] || font_cjk=$font_regular

rebuild_initramfs() {
  if command -v limine-mkinitcpio >/dev/null; then sudo limine-mkinitcpio; else sudo mkinitcpio -P; fi
}

if [[ ${1:-} == --restore ]]; then
  sudo plymouth-set-default-theme omarchy
  sudo sed -i '/^DeviceScale=1$/d' /etc/plymouth/plymouthd.conf
  rebuild_initramfs
  printf 'Omarchy boot screen restored.\n'
  exit 0
fi

command -v magick >/dev/null || { printf 'Missing ImageMagick (magick).\n' >&2; exit 1; }
[[ -f $font_bold ]] || { printf 'MacLock fonts not found in %s\n' "$fonts" >&2; exit 1; }

wallpaper=$(readlink -f "$HOME/.local/state/omarchy/current/background" 2>/dev/null || true)
case "${wallpaper,,}" in *.mp4|*.webm|*.mkv|*.mov|*.m4v) wallpaper= ;; esac
avatar=""
for candidate in "$HOME/.face" "$HOME/.face.icon"; do [[ -f $candidate ]] && { avatar=$candidate; break; }; done
display_name=$(getent passwd "$USER" | cut -d: -f5 | cut -d, -f1)
display_name=${display_name:-$USER}

work=$(mktemp -d "${TMPDIR:-/tmp}/silky-boot.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
out="$work/$theme"
mkdir -p "$out"

# Draw everything at the built-in panel's real resolution. Plymouth runs with DeviceScale=1 (set below), so a
# pixel here is a pixel on screen: nothing is upscaled, which is what made the old version look soft.
read -r W H < <(hyprctl monitors -j 2>/dev/null | jq -r '([.[] | select(.name | test("^eDP"))] + .)[0] | "\(.width) \(.height)"' 2>/dev/null || true)
[[ ${W:-} =~ ^[0-9]+$ && ${H:-} =~ ^[0-9]+$ ]] || { W=1920; H=1080; }
# MacLock's layout unit: 1.0 on a 1200 px tall screen (LockScreen.qml: u = height / 1200).
px() { awk -v v="$1" -v h="$H" 'BEGIN { printf "%d", v * h / 1200 + 0.5 }'; }
printf 'Drawing for %sx%s\n' "$W" "$H"

# Wallpaper: sharp, exactly the panel size, the way MacLock shows it before you start typing. No blur, so no halos.
if [[ -n $wallpaper ]]; then
  magick "$wallpaper" -colorspace sRGB -resize "${W}x${H}^" -gravity center -extent "${W}x${H}" \
    -strip -define png:compression-level=9 "$out/background.png"
else
  magick -size "${W}x${H}" gradient:'#2b2d42-#0d0e14' "$out/background.png"
fi

# Avatar: 70u circle with MacLock's 1 px (2 device px on a 2x panel) ring at 22 % white. Drawn 4x larger and scaled
# down, so the circle edge is smooth.
A=$(px 70); A4=$((A * 4)); ring=$(( (H + 599) / 600 ))
if [[ -n $avatar ]]; then
  magick "$avatar" -resize "${A4}x${A4}^" -gravity center -extent "${A4}x${A4}" "$work/face4.png"
else
  magick -size "${A4}x${A4}" xc:'rgba(255,255,255,0.16)' -fill white -font "$font_bold" -pointsize $((A4 * 3 / 7)) \
    -gravity center -annotate +0+0 "${display_name:0:1}" "$work/face4.png"
fi
magick "$work/face4.png" \( -size "${A4}x${A4}" xc:none -fill white -draw "circle $((A4/2)),$((A4/2)) $((A4/2)),0" \) \
  -compose DstIn -composite \
  \( -size "${A4}x${A4}" xc:none -fill none -stroke 'rgba(255,255,255,0.22)' -strokewidth $((ring * 4)) \
     -draw "circle $((A4/2)),$((A4/2)) $((A4/2)),$((ring * 2))" \) -compose Over -composite \
  -resize "${A}x${A}" "$out/avatar.png"

# User name: 15u, semibold, white, with MacLock's faint drop shadow (blur 0.5, 30 %, 1 px down).
magick -background none -fill white -font "$font_bold" -pointsize "$(px 15)" label:"$display_name" "$work/name.png"
magick "$work/name.png" \( +clone -background black -shadow "30x$(( (H + 1199) / 1200 ))+0+$(( (H + 599) / 600 ))" \) \
  +swap -background none -layers merge +repage "$out/name.png"

# Password pill: 210u x 36u, fully rounded, frosted glass with a hairline edge and a soft top highlight.
PW=$(px 210); PH=$(px 36); R=$((PH / 2)); edge=$(( (H + 599) / 600 ))
magick -size "$((PW * 4))x$((PH * 4))" xc:none \
  -fill 'rgba(255,255,255,0.17)' -draw "roundrectangle 0,0 $((PW * 4 - 1)),$((PH * 4 - 1)) $((R * 4)),$((R * 4))" \
  \( -size "$((PW * 4))x$((PH * 4))" gradient:'rgba(255,255,255,0.10)-rgba(255,255,255,0)' \
     \( -size "$((PW * 4))x$((PH * 4))" xc:none -fill white -draw "roundrectangle 0,0 $((PW * 4 - 1)),$((PH * 4 - 1)) $((R * 4)),$((R * 4))" \) \
     -compose DstIn -composite \) -compose Over -composite \
  -fill none -stroke 'rgba(255,255,255,0.30)' -strokewidth $((edge * 4)) \
  -draw "roundrectangle $((edge * 2)),$((edge * 2)) $((PW * 4 - 1 - edge * 2)),$((PH * 4 - 1 - edge * 2)) $((R * 4 - edge * 2)),$((R * 4 - edge * 2))" \
  -resize "${PW}x${PH}" "$out/entry.png"
# "输入密码", 14u at 62 % white, left-aligned 16u in (MacLock's "Enter Password").
magick -background none -fill 'rgba(255,255,255,0.62)' -font "$font_cjk" -pointsize "$(px 14)" label:'输入密码' "$out/hint.png"
B=$(px 7); magick -size "$((B * 4))x$((B * 4))" xc:none -fill white -draw "circle $((B*2)),$((B*2)) $((B*2)),0" -resize "${B}x${B}" "$out/bullet.png"

# After the password: the logo and a thin rounded progress bar.
if [[ -f /usr/share/plymouth/themes/omarchy/logo.png ]]; then
  magick /usr/share/plymouth/themes/omarchy/logo.png -fill white -colorize 100 -resize "$(px 150)x" "$out/logo.png"
else
  magick -size 2x2 xc:none "$out/logo.png"
fi
TW=$(px 160); TH=$(px 4); [[ $TH -ge 2 ]] || TH=2
magick -size "${TW}x${TH}" xc:none -fill 'rgba(255,255,255,0.22)' -draw "roundrectangle 0,0 $((TW-1)),$((TH-1)) $((TH/2)),$((TH/2))" "$out/track.png"
magick -size "${TW}x${TH}" xc:none -fill white -draw "roundrectangle 0,0 $((TW-1)),$((TH-1)) $((TH/2)),$((TH/2))" "$out/fill.png"

sed "s/@BUILD_HEIGHT@/$H/" "$repo_root/plymouth/$theme.script" > "$out/$theme.script"
printf '%s\n' \
  '[Plymouth Theme]' \
  'Name=Silky MacLock' \
  'Description=Disk unlock screen laid out like MacLock (Silky Omarchy)' \
  'ModuleName=script' \
  '' \
  '[script]' \
  "ImageDir=$dest" \
  "ScriptFile=$dest/$theme.script" \
  'ConsoleLogBackgroundColor=0x0a0a0d' > "$out/$theme.plymouth"

# Preview: the unlock screen composed at full size, same geometry as the script.
NH=$(magick identify -format %h "$out/name.png"); HH=$(magick identify -format %h "$out/hint.png")
entry_y=$((H - $(px 78) - PH)); name_y=$((entry_y - $(px 10) - NH)); avatar_y=$((name_y - $(px 10) - A))
magick "$out/background.png" \
  "$out/avatar.png" -gravity north -geometry "+0+$avatar_y" -composite \
  "$out/name.png" -gravity north -geometry "+0+$name_y" -composite \
  "$out/entry.png" -gravity north -geometry "+0+$entry_y" -composite \
  "$out/hint.png" -gravity northwest -geometry "+$(( W / 2 - PW / 2 + $(px 16) ))+$(( entry_y + PH / 2 - HH / 2 ))" -composite \
  "$repo_root/plymouth/preview.png"
printf 'Preview: %s\n' "$repo_root/plymouth/preview.png"

[[ ${1:-} == --preview ]] && exit 0

sudo rm -rf -- "$dest"
sudo install -d -m 755 "$dest"
sudo install -m 644 "$out"/* "$dest/"
sudo plymouth-set-default-theme "$theme"
# Draw in real device pixels. Left to guess, Plymouth treats a HiDPI panel as scale 2 and upscales every frame 2x.
if grep -q "^DeviceScale=" /etc/plymouth/plymouthd.conf; then
  sudo sed -i "s/^DeviceScale=.*/DeviceScale=1/" /etc/plymouth/plymouthd.conf
else
  sudo sed -i "/^\[Daemon\]/a DeviceScale=1" /etc/plymouth/plymouthd.conf
fi
rebuild_initramfs
printf '\nInstalled. You will see it at the next boot. Undo: %s --restore\n' "$0"
