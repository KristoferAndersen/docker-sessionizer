#!/bin/zsh
set -e

dotfiles="$HOME/dotfiles"

if [[ -d "$dotfiles" ]]; then
    cd "$dotfiles"
    stow --no-folding --restow -t "$HOME" nvim
    cd "$HOME"
fi

exec sleep infinity
