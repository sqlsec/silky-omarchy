#!/usr/bin/env bash
set -euo pipefail

# Omalogi（罗技 G 系列鼠标配置）的汉化版，从源码构建，适配 ARM（aarch64）。
# 上游只发布 x86_64 预编译助手，插件自带的 install.sh 在 ARM 上直接退出，
# 所以这里固定到 0.3.8 的提交、打上汉化补丁、本机 cargo 构建，再走上游的 setup。

# 插件里的“允许访问 / 安装助手”按钮会经由 ~/.local/share/silky-omarchy 里的软链接调用本脚本
repo_root=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)
patch_file="$repo_root/patches/omalogi-0.3.8-zh.patch"
upstream=https://github.com/elberacasa/omalogi
commit=ff3d8c262a3726553c5a38b46f03a600ad6ee379   # v0.3.8
src_dir="${OMALOGI_SRC_DIR:-$HOME/.cache/silky-omarchy/omalogi}"
bin_dir="$HOME/.local/bin"
rule=/etc/udev/rules.d/70-omalogi.rules
build_only=false

usage() {
  cat <<'USAGE'
Usage: scripts/install-omalogi.sh [--build-only]

Builds the Chinese Omalogi 0.3.8 helper from source (works on aarch64 and
x86_64), installs it to ~/.local/bin, installs the udev rule (sudo once),
and runs `omalogi setup` (shell plugin, bar indicator, switching daemon).

  --build-only  Build and install the binary only; skip udev and setup.
USAGE
}

case "${1:-}" in
  "") ;;
  --build-only) build_only=true ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

for command_name in git cargo install; do
  command -v "$command_name" >/dev/null || {
    printf 'Missing required command: %s (sudo pacman -S git rust)\n' "$command_name" >&2
    exit 1
  }
done

if [[ ! -d "$src_dir/.git" ]]; then
  mkdir -p "$(dirname -- "$src_dir")"
  git clone --quiet "$upstream" "$src_dir"
fi
git -C "$src_dir" fetch --quiet origin "$commit" 2>/dev/null || git -C "$src_dir" fetch --quiet origin
git -C "$src_dir" checkout --quiet --force "$commit"
git -C "$src_dir" apply "$patch_file"
printf 'Patched %s at %s\n' "$src_dir" "${commit:0:7}"

cargo build --release --locked --manifest-path "$src_dir/Cargo.toml"
built="$src_dir/target/release/omalogi"
install -Dm755 "$built" "$bin_dir/omalogi.new"
mv -f "$bin_dir/omalogi.new" "$bin_dir/omalogi"
printf 'Installed %s (%s, %s)\n' "$bin_dir/omalogi" "$("$bin_dir/omalogi" --version)" "$(uname -m)"

# 登记本脚本，供 ARM 上插件自带的 install.sh 转交
link_dir="${XDG_DATA_HOME:-$HOME/.local/share}/silky-omarchy"
mkdir -p "$link_dir"
ln -sfn "$repo_root/scripts/install-omalogi.sh" "$link_dir/install-omalogi.sh"

$build_only && exit 0

if ! cmp -s "$src_dir/packaging/udev/70-omalogi.rules" "$rule"; then
  printf 'Installing the udev rule (asks for sudo once)\n'
  sudo install -Dm644 "$src_dir/packaging/udev/70-omalogi.rules" "$rule"
  sudo udevadm control --reload-rules
  sudo udevadm trigger --subsystem-match=hidraw --action=change
fi

"$bin_dir/omalogi" setup

# 独立窗口应用：Omalogi 插件跑在自己的 Quickshell 进程里（AppId io.github.elberacasa.omalogi），
# 这样启动台、Dock、Alt+Tab 显示「罗技鼠标」和它的图标，而不是 MacShell
app_dir="${XDG_DATA_HOME:-$HOME/.local/share}/silky-omarchy/omalogi-app"
mkdir -p "$app_dir"
install -m644 "$repo_root/omalogi-app/shell.qml" "$app_dir/shell.qml"
for module in Commons Ui services; do ln -sfn "/usr/share/omarchy/shell/$module" "$app_dir/$module"; done
ln -sfn "$HOME/.config/omarchy/plugins/io.github.elberacasa.omalogi" "$app_dir/omalogi"
install -Dm755 "$repo_root/bin/silky-omalogi" "$bin_dir/silky-omalogi"
# 窗口规则：居中浮动 1280×700。
install -Dm644 "$repo_root/config/hypr/silky-omalogi.lua" "$HOME/.config/hypr/silky-omalogi.lua"
if ! grep -q 'hypr.silky-omalogi' "$HOME/.config/hypr/hyprland.lua"; then
  printf '\n-- Omalogi window (silky-omarchy docs/14)\nrequire("hypr.silky-omalogi")\n' >> "$HOME/.config/hypr/hyprland.lua"
fi
hyprctl reload >/dev/null 2>&1 || true

# 应用程序面板入口 + MacTahoe 风格图标（tune-app-icons.py 统一加圆角瓦片和阴影）
install -Dm644 "$repo_root/config/icons/omalogi.svg" "$HOME/.local/share/icons/silky-apps/omalogi.svg"
if [[ -f "$repo_root/scripts/tune-app-icons.py" &&
      -f "$HOME/.local/share/icons/MacTahoe/apps/scalable/Zoom.svg" ]] &&
    command -v python3 >/dev/null && command -v magick >/dev/null &&
    python3 "$repo_root/scripts/tune-app-icons.py" &&
    [[ -f "$HOME/.local/share/icons/MacTahoe/apps/scalable/omalogi.svg" ]]; then
  icon="$HOME/.local/share/icons/MacTahoe/apps/scalable/omalogi.svg"
else
  icon="$HOME/.local/share/icons/hicolor/scalable/apps/omalogi.svg"
  install -Dm644 "$repo_root/config/icons/omalogi.svg" "$icon"
fi
# Dock 按窗口的 app id 找图标
ln -sfn "$(basename "$icon")" "$(dirname "$icon")/io.github.elberacasa.omalogi.svg"
# 绝对路径：MacShell 的 Qt 图标查找会把“找不到”缓存到进程重启，主题名要等重启 MacShell 才生效
# 先删再建：MacShell 只在目录变化时重读入口，原地改写不会刷新
apps="$HOME/.local/share/applications"
mkdir -p "$apps"
rm -f "$apps/omalogi.desktop" "$apps/io.github.elberacasa.omalogi.desktop"
sed "s|^Icon=.*|Icon=$icon|" "$repo_root/config/applications/io.github.elberacasa.omalogi.desktop" > "$apps/io.github.elberacasa.omalogi.desktop"
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
printf '\n完成：在应用程序面板里打开「罗技鼠标」，或运行 silky-omalogi\n'
