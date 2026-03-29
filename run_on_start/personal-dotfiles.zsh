#!/bin/zsh
# Dev-in-docker run_on_start script
# Place this at: ~/bootstrap-aurelia/run_on_start/personal-dotfiles.zsh
#
# This script runs on each dev-in-docker rebuild.
# It clones the dotfiles repo into ~/dotfiles if missing (e.g., after hard reset)
# and runs the setup script to install configs.

DOTFILES_DIR="$HOME/dotfiles"
DOTFILES_REPO="https://github.com/ARaps1/dotfiles.git"

# Clone if missing (hard reset), otherwise pull latest
if [ ! -d "$DOTFILES_DIR" ]; then
  echo "Cloning dotfiles..."
  git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
else
  echo "Updating dotfiles..."
  cd "$DOTFILES_DIR" && git pull --ff-only
fi

"$DOTFILES_DIR/setup.sh" nvim
"$DOTFILES_DIR/setup.sh" tmux
"$DOTFILES_DIR/setup.sh" zsh
