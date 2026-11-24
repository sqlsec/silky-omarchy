#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
version=1.32.0
architecture=$(uname -m)
stock_package=${1:-/var/cache/pacman/pkg/libinput-$version-1-$architecture.pkg.tar.xz}
dest=${PKGDEST:-"$HOME/.local/share/silky-omarchy/libinput"}

if (( $# > 1 )) || [[ ${1:-} == --help ]]; then
  printf 'Usage: %s [stock libinput 1.32.0-1 package]\n' "${0##*/}"
  exit "$(( $# > 1 ? 2 : 0 ))"
fi

for tool in makepkg bsdtar; do
  if ! command -v "$tool" >/dev/null; then
    printf 'Missing build tool: %s\n' "$tool" >&2
    exit 1
  fi
done

if [[ $architecture != aarch64 ]]; then
  printf 'This recipe is for the Arch Linux ARM aarch64 libinput package.\n' >&2
  exit 1
fi
if [[ ! -f $stock_package ]]; then
  printf 'Stock libinput package not found: %s\n' "$stock_package" >&2
  exit 1
fi
metadata=$(bsdtar -xOf "$stock_package" .PKGINFO)
for field in "pkgname = libinput" "pkgver = $version-1" "arch = $architecture"; do
  if ! grep -Fxq "$field" <<< "$metadata"; then
    printf 'Stock package metadata must contain: %s\n' "$field" >&2
    exit 1
  fi
done

staging=$(mktemp -d)
trap 'rm -rf -- "$staging"' EXIT
for tool in meson ninja; do
  if ! command -v "$tool" >/dev/null; then
    cached_pkg=$(ls -1 /var/cache/pacman/pkg/"$tool"-[0-9]*.pkg.tar.* 2>/dev/null | grep -v '\.sig$' | sort -V | tail -n 1 || true)
    if [[ -z $cached_pkg ]]; then
      printf 'Missing build tool (and not in pacman cache): %s\n' "$tool" >&2
      exit 1
    fi
    mkdir -p -- "$staging/tools"
    bsdtar -xf "$cached_pkg" -C "$staging/tools"
  fi
done
if [[ -d $staging/tools/usr/bin ]]; then
  export PATH="$staging/tools/usr/bin:$PATH"
  shopt -s nullglob
  pysites=("$staging"/tools/usr/lib/python*/site-packages)
  shopt -u nullglob
  if (( ${#pysites[@]} > 0 )); then
    export PYTHONPATH="${pysites[0]}${PYTHONPATH:+:$PYTHONPATH}"
  fi
fi
cp -- "$repo_root/packaging/libinput/PKGBUILD" "$staging/PKGBUILD"
cp -- "$repo_root/patches/libinput-$version-"{immediate-3fg-release,multifinger-pinch}.patch "$staging/"
ln -s -- "$(realpath -- "$stock_package")" "$staging/stock-libinput.pkg"
mkdir -p -- "$dest"
export PKGDEST
PKGDEST=$(realpath -- "$dest")
cd -- "$staging"
makepkg --force --nodeps
makepkg --packagelist
