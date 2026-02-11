#!/bin/zsh
set -e

cd "$HOME/dotfiles"
stow -t ~ nvim zsh
cd "$HOME"

# Set up Go path
export GOPATH="$HOME/go"
export PATH="$GOPATH/bin:$PATH"

exec "$@"
