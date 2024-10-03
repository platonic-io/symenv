#!/bin/sh

SYM_DIR="$(pwd)"

export SYM_DIR

if [ -s "$SYM_DIR/symenv.sh" ]; then
    /bin/sh "$SYM_DIR/symenv.sh"
fi
