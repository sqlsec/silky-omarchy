#!/usr/bin/env bash
set -euo pipefail

# Silky Omarchy terminal: zsh + Oh My Zsh (ys theme) + autosuggestions + syntax highlighting + extra completions.
# Run it in a terminal: it asks for your password twice (installing zsh, changing your login shell).
repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
omz_dir="$HOME/.oh-my-zsh"
custom="$omz_dir/custom/plugins"

clone() { # clone <repo> <dir>: shallow, and only once
  [[ -d $2/.git ]] && { git -C "$2" pull -q --ff-only || true; return; }
  git clone -q --depth 1 "https://github.com/$1.git" "$2"
}

command -v zsh >/dev/null || sudo pacman -S --needed --noconfirm zsh

clone ohmyzsh/ohmyzsh "$omz_dir"
mkdir -p "$custom"
clone zsh-users/zsh-autosuggestions "$custom/zsh-autosuggestions"
clone zsh-users/zsh-syntax-highlighting "$custom/zsh-syntax-highlighting"
clone zsh-users/zsh-completions "$custom/zsh-completions"

if [[ -f $HOME/.zshrc ]] && ! grep -q 'Silky Omarchy zsh' "$HOME/.zshrc"; then
  cp -a "$HOME/.zshrc" "$HOME/.zshrc.bak.$(date +%Y%m%d-%H%M%S)"
fi
install -m 644 "$repo_root/config/zsh/zshrc" "$HOME/.zshrc"

# Build the completion cache once now, so the first real terminal opens fast.
zsh -i -c exit >/dev/null 2>&1 || true

if [[ $(getent passwd "$USER" | cut -d: -f7) != "$(command -v zsh)" ]]; then
  chsh -s "$(command -v zsh)"
fi

printf '\nDone. Open a new terminal (or log out and in) to start zsh.\n'
printf 'Startup time: '
{ time zsh -i -c exit; } 2>&1 | awk '/real/ {print $2}'
