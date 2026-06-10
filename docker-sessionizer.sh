#!/usr/bin/env zsh
set -e

dotfiles_path="$HOME/personal/dots"

base_image_name="dev-base"
container_prefix="dev"
search_dirs=("$HOME/dev" "$HOME/git" "$HOME/personal")

usage() {
    echo "Usage: $(basename "$0") [--rebuild] [project_path]"
    echo "       $(basename "$0") clean [--all]"
    echo ""
    echo "  --rebuild   Force rebuild of images even if they already exist"
    echo "  clean       Remove stopped ${container_prefix}-* containers and their cache volumes"
    echo "  clean --all Also stop running containers and remove dev images"
}

image_exists() {
    docker image inspect "$1" &>/dev/null
}

clean() {
    local all=false
    [[ "$1" == "--all" ]] && all=true

    if $all; then
        local running
        running=$(docker ps --format '{{.Names}}' | grep "^${container_prefix}-" || true)
        if [[ -n "$running" ]]; then
            echo "Stopping running containers..."
            echo "$running" | xargs docker stop
        fi
    fi

    local stopped
    stopped=$(docker ps -a --filter status=exited --filter status=created \
        --format '{{.Names}}' | grep "^${container_prefix}-" || true)
    if [[ -n "$stopped" ]]; then
        echo "Removing stopped containers..."
        echo "$stopped" | xargs docker rm
    fi

    # Cache volumes no longer attached to any container
    local volumes
    volumes=$(docker volume ls --format '{{.Name}}' | grep "^${container_prefix}-.*-cache$" || true)
    for vol in ${(f)volumes}; do
        if ! docker ps -a --filter "volume=$vol" --format '{{.Names}}' | grep -q .; then
            echo "Removing orphaned volume $vol"
            docker volume rm "$vol"
        fi
    done

    if $all; then
        echo "Removing dev images..."
        docker images --format '{{.Repository}}' \
            | grep -E "^(${base_image_name}|dev-default|dev-session-)" \
            | sort -u | xargs -r docker rmi || true
    fi

    echo "Done."
}

# Parse arguments
rebuild=false
selected=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        clean)
            shift
            clean "$@"
            exit 0
            ;;
        --rebuild)
            rebuild=true
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            selected="$1"
            ;;
    esac
    shift
done

if [[ -z "$selected" ]]; then
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
    if $rebuild || ! image_exists "$image_name"; then
        echo "Building project image from $project_path/Dockerfile..."
        docker build -t "$image_name" "$project_path"
    fi
else
    image_name="dev-default"
    if $rebuild || ! image_exists "$base_image_name"; then
        echo "Building base dev image..."
        docker build -t "$base_image_name" "$sessionizer_dir"
    fi
    if $rebuild || ! image_exists "$image_name"; then
        echo "Building default dev image..."
        docker build -t "$image_name" -f "$sessionizer_dir/Dockerfile.default" "$sessionizer_dir"
    fi
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
        "docker exec -it -w /workspace $container_name /bin/zsh -l"
    tmux set-option -t "$session_name" default-command \
        "docker exec -it -w /workspace $container_name /bin/zsh -l"
fi

# Attach or switch
if [[ -z "$TMUX" ]]; then
    tmux attach-session -t "$session_name"
else
    tmux switch-client -t "$session_name"
fi
