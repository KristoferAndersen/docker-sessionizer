#!/bin/zsh
set -e

dotfiles="$HOME/dotfiles"

if [[ -d "$dotfiles" ]]; then
    cd "$dotfiles"
    stow --no-folding --restow -t "$HOME" nvim
    cd "$HOME"
fi

# Seed a config stub so Claude doesn't treat each container as a fresh install.
# ~/.claude.json isn't mounted (atomic rename is incompatible with a single-file
# bind mount); credentials persist in the bind-mounted ~/.claude directory. This
# only skips onboarding — login is still required when no credentials are present.
[[ -f "$HOME/.claude.json" ]] || echo '{"hasCompletedOnboarding":true,"installMethod":"native"}' > "$HOME/.claude.json"

exec sleep infinity
