# Personal shell aliases and customizations
# This file is auto-sourced in dev-in-docker (via ZSH_CUSTOM)
# and sourced from .zshrc on personal machines.

# TODO: Add your personal aliases, functions, and env vars here.

# Example aliases:
# alias ll="ls -la"
# alias gs="git status"
# alias gco="git checkout"

# Set default editor to nvim if available
if command -v nvim >/dev/null 2>&1; then
    export EDITOR="nvim"
    export VISUAL="nvim"
    alias vim="nvim"
fi
