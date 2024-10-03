#!/bin/bash
# shellcheck disable=SC1091

CLICOLOR=1
# shellcheck disable=SC2016
LESS='-R --use-color -Dd+r$Du+b$'
LSCOLORS="Ea"
PS1='[\[\e[31m\]\u\[\e[0m\]@\[\e[32m\]\H\[\e[0m\]:\[\e[33m\]\w\[\e[0m\]]{\[\e[34m\]$?\[\e[0m\]}\$ '
SYMENV_DIR="$HOME/.symbiont"

# shellcheck disable=SC1091
if [ -f /usr/share/bash-completion/bash_completion ]; then
  source /usr/share/bash-completion/bash_completion
fi

PATH="$SYMENV_DIR/versions/current/bin:$PATH"

. "$HOME/.symbiont/symenv.sh"
. "$HOME/.symbiont/bash_completion"

export CLICOLOR
export LESS
export LSCOLORS
export PS1
export PATH
