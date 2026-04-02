# Personal shell aliases and customizations
# This file is auto-sourced in dev-in-docker (via ZSH_CUSTOM)
# and sourced from .zshrc on personal machines.

# TODO: Add your personal aliases, functions, and env vars here.
alias ezsh="vim ~/.config/zsh/personal.zsh"
alias gco="git checkout"
alias gcob="gco -b"
alias gfco="git fetch origin dev && gco origin/dev"
alias gfcob="git fetch origin dev && gco origin/dev && gcob"
alias gfm="git fetch origin dev && git merge origin/dev"
alias gfr="git fetch origin dev && git rebase -i origin/dev"
alias smypy="dev start dmypy"
alias up="dev compose up"
alias down="dev compose down"
alias downup="down && up"
alias web="dev start webpack"
alias pyu="dev test pyunit"
alias pyur="pyu run"
alias pyud="pyu debug"
alias js="dev test jsunit run"
alias cyp="dev test cypress open"
alias req="dev setup requirements"
alias lint="dev check lint"
alias linta="lint --autofix"
alias lintmypy="lint --only MONOLITH_MYPY"
alias bazelfix="dev bazel fix"
alias dbu="dev db upgrade"
alias smu="dev search migrate-up"
# alias ll="ls -la"
# alias gs="git status"
# alias gco="git checkout"

# Set default editor to nvim if available
if command -v nvim >/dev/null 2>&1; then
    export EDITOR="nvim"
    export VISUAL="nvim"
    alias vim="nvim"
fi
