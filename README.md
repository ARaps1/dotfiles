# Dotfiles

Personal configuration files managed with [GNU Stow](https://www.gnu.org/software/stow/).

## What's included

- **nvim** — Neovim configuration (`~/.config/nvim/`)
- **tmux** — tmux configuration (`~/.tmux.conf`) + Tmux Plugin Manager
- **zsh** — Shell customizations (`~/.config/zsh/`) — aliases, env vars, functions
- **git** — Git configuration (`~/.config/git/config`)
- **herdr** — Herdr settings and keybindings (`~/.config/herdr-app/settings.json`, `keys.json`). macOS only; part of `all`.
- **herdr-mobile** — opt-in, for mobile development only; never part of `all`. Adds Herdr's simulator pane, the agents and simulators sidebar and its layout (`~/.config/herdr-app/mods/herdr-sim`, `herdr-sim-screen`, `agents-sims`, `layouts/main-sims.json`), and the scripts agents use in `~/.local/bin`: `sim-dibs` (which session drives which iOS simulator or Android emulator; boots Android through avdslim), `herdr-sim-pane`, `herdr-expo`, `herdr-supabase` and the log panes. Builds [avdslim](https://github.com/kdbhalala/avdslim) from source at a pinned tag and installs simslim. The default slim profiles for both platforms are in `~/.config/sim-dibs` (`simslim.json`, `avdslim.json`; the reasons are in its README). A repo's own profile at its git root wins.

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
./setup.sh herdr          # Herdr settings + keybindings (web or mobile)
./setup.sh herdr-mobile   # personal mobile machine only: simulator mods and scripts
```

Open Herdr once before `./setup.sh herdr`, so it creates `~/.config/herdr-app` and installs its stock mods.
Only our own files are linked: Herdr's runtime state and stock mods stay out of this repo.
Settings files are swapped for symlinks with a single rename, because Herdr recreates them the moment they disappear.
Mods are linked as whole folders, because Herdr refuses a mod whose imported files are symlinks pointing outside it.

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
