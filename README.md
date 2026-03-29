# Dotfiles

Personal configuration files managed with [GNU Stow](https://www.gnu.org/software/stow/).

## What's included

- **nvim** — Neovim configuration (`~/.config/nvim/`)
- **tmux** — tmux configuration (`~/.tmux.conf`) + Tmux Plugin Manager
- **zsh** — Shell customizations (`~/.config/zsh/`) — aliases, env vars, functions
- **git** — Git configuration (`~/.config/git/config`)

## Installation

### On a personal machine

```bash
git clone https://github.com/YOUR_USERNAME/dotfiles.git ~/.config/dotfiles
cd ~/.config/dotfiles

# Install everything
./setup.sh all

# Or install individual components
./setup.sh nvim
./setup.sh tmux
./setup.sh zsh
./setup.sh git
```

### In dev-in-docker (Benchling)

Copy `run_on_start/personal-dotfiles.zsh` to `~/bootstrap-aurelia/run_on_start/`:

```bash
cp ~/.config/dotfiles/run_on_start/personal-dotfiles.zsh ~/bootstrap-aurelia/run_on_start/
```

This script automatically clones (or updates) this repo and runs setup on each rebuild.

## How it works

Each top-level directory (e.g., `nvim/`, `tmux/`) is a GNU Stow "package."
The directory structure inside each package mirrors the path relative to `$HOME`.
Running `stow -t $HOME <package>` creates symlinks from `$HOME` into this repo.

For example:
```
nvim/.config/nvim/init.lua  →  ~/.config/nvim/init.lua (symlink)
tmux/.tmux.conf             →  ~/.tmux.conf (symlink)
```

## Adding new configs

To add a new tool (e.g., `starship`):

1. Create the directory mirroring the target path:
   ```bash
   mkdir -p starship/.config
   cp ~/.config/starship.toml starship/.config/starship.toml
   ```
2. Add a setup function in `setup.sh` if the tool needs binary installation.
3. Run `stow -R -v -d . -t $HOME starship` (or add it to `setup.sh`).

## Work-specific config

Do **not** put work credentials, API keys, or internal URLs in this repo.

For git, use `includeIf` in `git/.config/git/config` to conditionally load
a local-only work config file. See the comments in that file for details.
