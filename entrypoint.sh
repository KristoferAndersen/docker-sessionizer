#!/bin/zsh
set -e

dotfiles="$HOME/dotfiles"

if [[ -d "$dotfiles" ]]; then
    cd "$dotfiles"
    stow --no-folding --restow -t "$HOME" nvim
    cd "$HOME"
fi

# Seed a config stub only when the shared store is brand-new, so the very first
# launch skips onboarding. CLAUDE_CONFIG_DIR (set by docker-sessionizer) places
# .claude.json inside the bind-mounted ~/.claude dir, so it — and thus the OAuth
# session/login state — persists across container rebuilds instead of being
# reseeded every boot. Once you log in, real state fills this file and survives.
claude_config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
mkdir -p "$claude_config_dir"
[[ -f "$claude_config_dir/.claude.json" ]] \
    || echo '{"hasCompletedOnboarding":true,"installMethod":"native"}' > "$claude_config_dir/.claude.json"

exec sleep infinity
