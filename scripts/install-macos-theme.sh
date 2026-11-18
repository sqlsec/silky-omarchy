#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

# Third-party pieces, pinned so every install gets exactly what was tested.
icons_repo=https://github.com/vinceliuice/MacTahoe-icon-theme.git
icons_commit=839848b9a8a38a92a6936e30c4abe35cc6f2546d
gtk_repo=https://github.com/vinceliuice/MacTahoe-gtk-theme.git
gtk_commit=1e45e19f510edb8cde18fa84d6cd5319f60b086b

icons_dir="$HOME/.local/share/icons"
gtk_themes_dir="$HOME/.local/share/themes"
omarchy_themes_dir="$HOME/.config/omarchy/themes"
omarchy_backgrounds_dir="$HOME/.config/omarchy/backgrounds"
hook_dir="$HOME/.config/omarchy/hooks/theme-set.d"
lib_dir="$HOME/.local/lib/silky-omarchy"
hypr_dir="$HOME/.config/hypr"
macshell_env="$HOME/.config/macshell/env"

with_icons=true
with_gtk=true
with_bars=true

usage() {
  cat <<'USAGE'
Usage: scripts/install-macos-theme.sh [--no-icons] [--no-gtk] [--no-bars]

Installs the Silky "macOS Tahoe" look for Omarchy:

  icons    MacTahoe icon theme (blue folders, macOS app icons) plus aliases for Omarchy's own apps
  gtk      MacTahoe GTK 3 / libadwaita theme: Finder-style Nautilus, traffic lights in header bars
  themes   Omarchy themes "macos-tahoe-dark" and "macos-tahoe-light"
  hook     theme-set hook that switches GTK, cursor and MacShell together with the Omarchy theme
  bars     restyle Omarchy's floating-window titlebars as macOS traffic lights

Nothing is applied until you pick the theme:  omarchy theme set macos-tahoe-dark
USAGE
}

for argument in "$@"; do
  case "$argument" in
    --no-icons) with_icons=false ;;
    --no-gtk) with_gtk=false ;;
    --no-bars) with_bars=false ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

for command_name in git tar; do
  command -v "$command_name" >/dev/null || {
    printf 'Missing required command: %s\n' "$command_name" >&2
    exit 1
  }
done

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/silky-macos.XXXXXX")
trap 'rm -rf -- "$work_dir"' EXIT

# Fetch one exact commit into its own empty directory.
fetch() {
  local url=$1 commit=$2 target=$3
  git init -q "$target"
  git -C "$target" remote add origin "$url"
  git -C "$target" fetch -q --depth 1 origin "$commit"
  git -C "$target" checkout -q FETCH_HEAD
}

install_icons() {
  if [[ ! -f $icons_dir/MacTahoe/index.theme ]]; then
    printf 'Installing MacTahoe icons…\n'
    fetch "$icons_repo" "$icons_commit" "$work_dir/icons"
    mkdir -p "$icons_dir"
    bash "$work_dir/icons/install.sh" -d "$icons_dir" >/dev/null
  fi

  # Omarchy's own apps have no icon in the set: point them at the matching macOS one.
  local apps="$icons_dir/MacTahoe/apps/scalable" name target
  while read -r name target; do
    [[ -e $apps/$target && ! -e $apps/$name ]] && ln -s "$target" "$apps/$name"
  done <<'ALIASES'
omacalc.svg calc.svg
omawrite.svg text-editor.svg
omarchy-discord.svg discord.svg
ALIASES

  # The set redraws these two brands; step aside so the vendors' own artwork is used.
  for name in chatgpt.svg claude-desktop.svg; do
    [[ -L $apps/$name ]] && mv -- "$apps/$name" "$apps/$name.mactahoe-backup"
  done

  # Every other launcher app gets a MacTahoe-style icon too (aliases + logos redrawn on the MacTahoe tile).
  if command -v magick >/dev/null; then
    python3 -I "$repo_root/scripts/tune-app-icons.py" >/dev/null || printf 'App icon tuning failed; continuing.\n' >&2
  fi

  if command -v gtk-update-icon-cache >/dev/null; then
    for name in MacTahoe MacTahoe-dark MacTahoe-light; do
      gtk-update-icon-cache -q -f "$icons_dir/$name" 2>/dev/null || true
    done
  fi

  # A small inheriting theme keeps Finder-style sidebar symbols together without
  # modifying the upstream MacTahoe installation or its full-colour folder icons.
  local variant overlay
  for variant in dark light; do
    overlay="$icons_dir/Silky-MacTahoe-$variant"
    mkdir -p "$overlay/sidebar" "$overlay/places"
    # Remove symbols installed by older versions of this overlay.
    find "$overlay/sidebar" -maxdepth 1 -type f -name "*-symbolic.svg" -delete
    # Projects has no symbolic icon upstream; reuse MacTahoe’s code-folder icon.
    install -m 644 "$icons_dir/MacTahoe-$variant/places/symbolic/folder-code-symbolic.svg" \
      "$overlay/sidebar/folder-projects-symbolic.svg"
    # GTK searches the overlay before its parent even for full-size icons.
    install -m 644 "$icons_dir/MacTahoe-$variant/places/scalable/folder-projects.svg" \
      "$overlay/places/folder-projects.svg"
    cat > "$overlay/index.theme" <<EOF
[Icon Theme]
Name=Silky-MacTahoe-$variant
Inherits=MacTahoe-$variant
Directories=sidebar,places

[places]
Size=48
Type=Scalable
MinSize=16
MaxSize=512
Context=Places

[sidebar]
Size=16
Type=Scalable
MinSize=16
MaxSize=16
Context=Places
EOF
    command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -q -f "$overlay" || true
  done

  # MacShell's Dock and Spotlight take their icon theme from this file.
  if [[ -f $macshell_env ]] && ! grep -q '^export QS_ICON_THEME=' "$macshell_env"; then
    cp -a "$macshell_env" "$macshell_env.bak.$(date +%Y%m%d-%H%M%S)"
    if grep -q '^#export QS_ICON_THEME=' "$macshell_env"; then
      sed -i '0,/^#export QS_ICON_THEME=.*/s//export QS_ICON_THEME=MacTahoe-dark/' "$macshell_env"
    else
      printf '\nexport QS_ICON_THEME=MacTahoe-dark\n' >> "$macshell_env"
    fi
  fi
}

install_gtk() {
  printf 'Installing MacTahoe GTK theme…\n'
  fetch "$gtk_repo" "$gtk_commit" "$work_dir/gtk"
  mkdir -p "$gtk_themes_dir" "$work_dir/gtk-release"
  local variant part
  for variant in Dark Light; do
    # The upstream release archives are prebuilt, so no Sass compiler is needed.
    tar -xJf "$work_dir/gtk/release/MacTahoe-$variant.tar.xz" -C "$work_dir/gtk-release"
    rm -rf -- "$gtk_themes_dir/MacTahoe-$variant.new"
    mkdir -p "$gtk_themes_dir/MacTahoe-$variant.new"
    for part in index.theme gtk-2.0 gtk-3.0 gtk-4.0; do
      cp -a "$work_dir/gtk-release/MacTahoe-$variant/$part" "$gtk_themes_dir/MacTahoe-$variant.new/"
    done
    rm -rf -- "$gtk_themes_dir/MacTahoe-$variant"
    mv -- "$gtk_themes_dir/MacTahoe-$variant.new" "$gtk_themes_dir/MacTahoe-$variant"
  done
}

install_sidebar_style() {
  local variant target css
  for variant in Dark Light; do
    target="$gtk_themes_dir/Silky-MacTahoe-$variant/gtk-4.0"
    mkdir -p "$target"
    ln -sfn "../../MacTahoe-$variant/gtk-4.0/assets" "$target/assets"
    ln -sfn "../../MacTahoe-$variant/gtk-4.0/windows-assets" "$target/windows-assets"
    for css in gtk.css gtk-dark.css; do
      cat > "$target/$css" <<EOF
@import url("file://$gtk_themes_dir/MacTahoe-$variant/gtk-4.0/$css");
.nautilus-window placessidebar image.sidebar-icon { color: #0a84ff; opacity: 1; }
EOF
    done
  done
}

install_themes() {
  local current_background theme
  current_background=$(readlink -f "$HOME/.local/state/omarchy/current/background" 2>/dev/null || true)
  mkdir -p "$omarchy_themes_dir"
  for theme in macos-tahoe-dark macos-tahoe-light; do
    mkdir -p "$omarchy_themes_dir/$theme"
    cp -a "$repo_root/themes/$theme/." "$omarchy_themes_dir/$theme/"
    # The themes ship no wallpaper. Carry the current one over so switching does not leave the desktop empty;
    # add more to the same folder at any time.
    if [[ -f $current_background ]] && ! compgen -G "$omarchy_backgrounds_dir/$theme/*" >/dev/null; then
      mkdir -p "$omarchy_backgrounds_dir/$theme"
      cp -- "$current_background" "$omarchy_backgrounds_dir/$theme/"
    fi
  done
  printf 'Installed Omarchy themes: macos-tahoe-dark, macos-tahoe-light\n'
}

install_hook() {
  mkdir -p "$hook_dir"
  install -m 755 "$repo_root/hooks/theme-set-silky-macos" "$hook_dir/silky-macos"
  printf 'Installed theme-set hook: %s\n' "$hook_dir/silky-macos"
}

install_bars() {
  # Omarchy already draws titlebars on floating workspaces (omarchy-hyprland-titlebars). These two files restyle
  # them as macOS traffic lights; the guard must load before Omarchy's defaults to keep its square buttons out.
  install -m 644 "$repo_root/config/hypr/silky-titlebar-guard.lua" "$hypr_dir/silky-titlebar-guard.lua"
  install -m 644 "$repo_root/config/hypr/silky-macos.lua" "$hypr_dir/silky-macos.lua"
  cp -a "$hypr_dir/hyprland.lua" "$hypr_dir/hyprland.lua.bak.$(date +%Y%m%d-%H%M%S)"
  python3 - "$hypr_dir/hyprland.lua" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
if 'hypr.silky-titlebar-guard' not in text:
    text = text.replace('require("default.hypr.omarchy")',
        'require("hypr.silky-titlebar-guard")\nrequire("default.hypr.omarchy")', 1)
if 'require("hypr.silky-macos")' not in text:
    text += '\n-- Silky Omarchy: macOS traffic lights on Omarchy\'s floating-window titlebars.\nrequire("hypr.silky-macos")\n'
open(path, 'w').write(text)
PY
  # An older version built its own hyprbars, which doubled Omarchy's: remove it.
  rm -f "$lib_dir"/hyprbars-*.so
  hyprctl reload >/dev/null
  hyprctl configerrors
}

$with_icons && install_icons
$with_gtk && install_gtk
install_sidebar_style
install_themes
install_hook
$with_bars && install_bars

cat <<'DONE'

Done. Apply with one of:

  omarchy theme set macos-tahoe-dark
  omarchy theme set macos-tahoe-light

Open GTK apps (Files, Settings) pick up the new look after they are restarted.
DONE
