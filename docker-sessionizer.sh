#!/bin/bash
set -e

dotfiles_path="$HOME/personal/dots"

base_image_name="dev-base"
container_prefix="dev"
search_dirs=("$HOME/dev" "$HOME/git" "$HOME/personal")

if [[ $# -eq 1 ]]; then
    selected=$1
else
    selected=$(find "${search_dirs[@]}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | fzf)
fi

if [[ -z $selected ]]; then
    exit 0
fi

project_path=$(realpath "$selected")
project_name=$(basename "$project_path" | tr . _)
container_name="${container_prefix}-${project_name}"
session_name="${container_name}"

sessionizer_dir="$(dirname "$(realpath "$0")")"

# Determine image: project-specific if Dockerfile exists, otherwise default
if [[ -f "$project_path/Dockerfile" ]]; then
    image_name="dev-session-${project_name}"
    echo "Building project image from $project_path/Dockerfile..."
    docker build -t "$image_name" "$project_path"
else
    image_name="dev-default"
    echo "Building base dev image..."
    docker build -t "$base_image_name" "$sessionizer_dir"
    echo "Building default dev image..."
    docker build -t "$image_name" -f "$sessionizer_dir/Dockerfile.default" "$sessionizer_dir"
fi

mkdir -p "$HOME/.claude-container"
[[ -f "$HOME/.claude-container.json" ]] || echo '{}' > "$HOME/.claude-container.json"

# Start container if not running
if ! docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
    docker rm "$container_name" &>/dev/null || true

    docker run -d \
        --name "$container_name" \
        -v "$project_path:/workspace" \
        -v "$dotfiles_path:/home/dev/dotfiles" \
        -v "${container_name}-cache:/home/dev/.cache" \
        -v "$HOME/.claude-container:/home/dev/.claude" \
        -v "$HOME/.claude-container.json:/home/dev/.claude.json" \
        "$image_name"
fi

# Create or switch to tmux session with docker exec as default command
if ! tmux has-session -t "$session_name"; then
    tmux new-session -d -s "$session_name" \
        "docker exec -it -w /workspace $container_name /bin/bash -l"
    tmux set-option -t "$session_name" default-command \
        "docker exec -it -w /workspace $container_name /bin/bash -l"
fi

# Attach or switch
if [[ -z "$TMUX" ]]; then
    tmux attach-session -t "$session_name"
else
    tmux switch-client -t "$session_name"
fi
