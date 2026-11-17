# 06 · 终端：zsh + Oh My Zsh（ys 主题）

简体中文 | [English](en/06-terminal.md)

## 目标

- 用 zsh 替代 bash，Oh My Zsh 的 `ys` 主题（两行提示符：用户@主机、路径、git 分支与状态、时间）
- 输入时用灰字给出历史里的命令建议，按 → 或 Ctrl+Space 接受
- 命令在敲的过程中实时着色：存在的命令是绿色，不存在的是红色，引号、路径、参数分别着色
- 更多命令的 Tab 补全，补全菜单可以用方向键选择，大小写不敏感
- 保留 Omarchy 在 bash 里的好用配置：`eza` 列表、`zoxide`、`mise`、fzf 的 Ctrl+R / Ctrl+T / Alt+C
- 启动快

## 方案选择

| 方案 | 颜值 | 速度 | 说明 |
| --- | --- | --- | --- |
| **Oh My Zsh + ys + 精简插件**（采用） | 好 | 约 0.1 秒 | 你指定的 ys 主题；只装 4 个插件、关掉自动更新检查，速度够用 |
| zsh + Starship + zinit/antidote | 很好 | 约 0.03 秒 | 最快；Omarchy 默认已装 Starship，提示符风格不同于 ys |
| fish | 好 | 快 | 自带建议和高亮，零配置；但不兼容 bash/zsh 语法，脚本要另写 |

想要更快或换风格，可以在 `~/.zshrc.local` 里关掉 `ZSH_THEME` 并加一行 `eval "$(starship init zsh)"`。

## 组成

| 插件 | 作用 |
| --- | --- |
| `zsh-autosuggestions` | 灰字历史建议（策略：先历史，后补全；异步计算） |
| `zsh-syntax-highlighting` | 命令对错实时着色，必须是最后加载的插件 |
| `zsh-completions` | 额外的补全定义，只加到 `fpath`，不作为插件加载，更快 |
| `git`、`sudo` | Oh My Zsh 自带：git 别名；按两下 Esc 在命令前加 sudo |

提速设置：`zstyle ':omz:update' mode disabled`（不在每次启动检查更新，需要时手动 `omz update`）、`DISABLE_MAGIC_FUNCTIONS`、`ZSH_DISABLE_COMPFIX`（跳过权限扫描）、补全缓存放在 `~/.cache/zsh/`。

## 安装

```bash
./scripts/install-zsh.sh
```

脚本会：用 pacman 安装 zsh（要输入密码）；克隆 Oh My Zsh 和三个插件；备份原有 `~/.zshrc` 后安装 [`config/zsh/zshrc`](../config/zsh/zshrc)；用 `chsh` 把登录 shell 改为 zsh（再输一次密码）；最后打印启动耗时。

新开一个终端窗口即可使用；所有已打开的程序要重新登录后才会把 zsh 当作默认 shell。

个人的别名、环境变量写在 `~/.zshrc.local`，升级配置时不会被覆盖。

## 验证

```bash
echo $SHELL
time zsh -i -c exit
```

## 回滚

```bash
chsh -s /usr/bin/bash
```

bash 的配置（`~/.bashrc`）没有改动，切回去即恢复原样。
