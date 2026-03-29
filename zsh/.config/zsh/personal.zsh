# Personal shell aliases and customizations
# This file is auto-sourced in dev-in-docker (via ZSH_CUSTOM)
# and sourced from .zshrc on personal machines.

# TODO: Add your personal aliases, functions, and env vars here.
alias ezsh="vim ~/.config/zsh/personal.zsh"
alias gco="git checkout"
alias gcob="gco -b"
alias gfd="git fetch origin dev"
alias gfco="gfd && gco origin/dev"
alias gfcob="gfd && gco origin/dev && gcob"
alias gfm="gfd && git merge origin/dev"
alias gfr="gfd && git rebase -i origin/dev"
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
