# 06 · Terminal: zsh + Oh My Zsh (ys theme)

[简体中文](../06-terminal.md) | English

## Goals

- zsh instead of bash, with Oh My Zsh's `ys` theme (two-line prompt: user@host, path, git branch and status, time)
- Grey suggestions from history while you type; accept with → or Ctrl+Space
- Live colouring as you type: existing commands green, unknown ones red, quotes, paths and arguments each in their own colour
- Tab completion for more commands; arrow keys move through the completion menu; case-insensitive
- Keep Omarchy's handy bash setup: `eza` listings, `zoxide`, `mise`, fzf's Ctrl+R / Ctrl+T / Alt+C
- Fast start-up

## Options considered

| Option | Looks | Speed | Notes |
| --- | --- | --- | --- |
| **Oh My Zsh + ys + a lean plugin set** (chosen) | Good | about 0.1 s | The ys theme you asked for; only 4 plugins and no update check at start-up, fast enough |
| zsh + Starship + zinit/antidote | Very good | about 0.03 s | Fastest; Omarchy already ships Starship, but its prompt looks different from ys |
| fish | Good | Fast | Suggestions and highlighting built in, zero config; but not bash/zsh syntax, scripts need rewriting |

For more speed or a different look, turn off `ZSH_THEME` in `~/.zshrc.local` and add `eval "$(starship init zsh)"`.

## Parts

| Plugin | Role |
| --- | --- |
| `zsh-autosuggestions` | Grey history suggestions (strategy: history first, then completion; computed asynchronously) |
| `zsh-syntax-highlighting` | Live right/wrong colouring; must be the last plugin loaded |
| `zsh-completions` | Extra completion definitions, added to `fpath` only rather than loaded as a plugin, which is faster |
| `git`, `sudo` | Bundled with Oh My Zsh: git aliases; press Esc twice to prefix the command with sudo |

Speed settings: `zstyle ':omz:update' mode disabled` (no update check at every start; run `omz update` when you want), `DISABLE_MAGIC_FUNCTIONS`, `ZSH_DISABLE_COMPFIX` (skips the permission scan), completion cache in `~/.cache/zsh/`.

## Install

```bash
./scripts/install-zsh.sh
```

The script installs zsh with pacman (asks for your password), clones Oh My Zsh and the three plugins, backs up your existing `~/.zshrc` and installs [`config/zsh/zshrc`](../../config/zsh/zshrc), switches your login shell to zsh with `chsh` (asks for the password again), and finally prints the start-up time.

Open a new terminal window to use it; already running programs only treat zsh as the default shell after you log in again.

Put personal aliases and environment variables in `~/.zshrc.local`; upgrades do not overwrite it.

## Verify

```bash
echo $SHELL
time zsh -i -c exit
```

## Rollback

```bash
chsh -s /usr/bin/bash
```

The bash configuration (`~/.bashrc`) is untouched, so switching back restores everything as it was.
