#!/usr/bin/zsh

export SYMENV_DIR="$HOME/.symbiont"

# This loads symenv
if [ -f "$SYMENV_DIR/symenv.sh" ]; then
    source "$SYMENV_DIR/symenv.sh"
fi

# This loads symenv managed SDK
if [ -f "$SYMENV_DIR/versions/current" ]; then
    export PATH="$SYMENV_DIR/versions/current/bin":$PATH
fi

# This loads symenv bash_completion
if [ -f "$SYMENV_DIR/bash_completion" ]; then
    source "$SYMENV_DIR/bash_completion"
fi