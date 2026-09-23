#!/usr/bin/env zsh
set -e

dotfiles_path="$HOME/dev/personal/dots"

base_image_name="dev-base"
container_prefix="dev"
# Named group roots (name=path): each holds the repos of one kind that may be
# containerized, as real directories or as symlinks to repos living elsewhere.
# Every entry of the selected repo's group is mounted at /workspace/<name>/<entry>,
# so sibling repos are visible and other groups are not. Override with
# SESSIONIZER_GROUP_DIRS, colon-separated name=path entries.
group_specs=(
    "work=$HOME/dev/work/containerized"
    "personal=$HOME/dev/personal/containerized"
)
[[ -n "${SESSIONIZER_GROUP_DIRS:-}" ]] && group_specs=("${(s.:.)SESSIONIZER_GROUP_DIRS}")

usage() {
    echo "Usage: $(basename "$0") [--rebuild] [group/project|project_path]"
    echo "       $(basename "$0") clean [--all]"
    echo ""
    echo "  Projects are directories or symlinks one level below a named group root"
    echo "  (default work=~/dev/work/containerized, personal=~/dev/personal/containerized;"
    echo "  override with \$SESSIONIZER_GROUP_DIRS as name=path:name=path). Every entry"
    echo "  of the selected group is mounted at /workspace/<name>/<entry>."
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

# Resolve name=path specs into groups whose root exists.
typeset -A groups   # name -> resolved path
for spec in "${group_specs[@]}"; do
    name="${spec%%=*}"; root="${spec#*=}"
    if [[ -z "$name" || "$name" == "$spec" || "$name" == */* ]]; then
        echo "Bad group spec (want name=path): $spec" >&2
        exit 1
    fi
    [[ -d "$root" ]] && groups[$name]=$(realpath "$root")
done
if (( ${#groups} == 0 )); then
    echo "No group directories found: ${group_specs[*]}" >&2
    exit 1
fi

# Entries of a group: directories and symlinks-to-directories, by entry name.
group_entries() {
    find -L "${groups[$1]}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null \
        | sed "s|^${groups[$1]}/||" | sort
}

if [[ -z "$selected" ]]; then
    # Picker shows "<name>/<entry>".
    selected=$(for name in "${(k)groups[@]}"; do
        group_entries "$name" | sed "s|^|$name/|"
    done | sort | fzf)
fi

if [[ -z $selected ]]; then
    exit 0
fi

# Accept "<name>/<entry>" (from the picker) or a path to a repo that some
# group entry points at (directly or via symlink).
group_name=""; project_dir=""
if [[ "$selected" != /* && "$selected" != .* && "$selected" == */* ]]; then
    name="${selected%%/*}"; entry="${selected#*/}"
    if [[ -n "${groups[$name]:-}" && "$entry" != */* && -d "${groups[$name]}/$entry" ]]; then
        group_name="$name"; project_dir="$entry"
    fi
fi
if [[ -z "$group_name" && -d "$selected" ]]; then
    want=$(realpath "$selected")
    for name in "${(k)groups[@]}"; do
        for entry in ${(f)"$(group_entries "$name")"}; do
            if [[ "$(realpath "${groups[$name]}/$entry")" == "$want" ]]; then
                group_name="$name"; project_dir="$entry"; break 2
            fi
        done
    done
fi
if [[ -z "$group_name" ]]; then
    echo "Not an entry of a group root (${(v)groups[*]}): $selected" >&2
    exit 1
fi

group_path="${groups[$group_name]}"
project_path=$(realpath "$group_path/$project_dir")
# Docker/tmux-safe names; mount paths keep the real directory names.
project_name="${group_name//./_}-${project_dir//./_}"
workdir="/workspace/$group_name/$project_dir"
container_name="${container_prefix}-${project_name}"
session_name="${container_name}"

sessionizer_dir="$(dirname "$(realpath "$0")")"

# Build the default dev image.
image_name="dev-default"
if $rebuild || ! image_exists "$base_image_name"; then
    echo "Building base dev image..."
    docker build -t "$base_image_name" "$sessionizer_dir"
fi
if $rebuild || ! image_exists "$image_name"; then
    echo "Building default dev image..."
    docker build -t "$image_name" -f "$sessionizer_dir/Dockerfile.default" "$sessionizer_dir"
fi

# Shared Claude state: one credential + config + history store for all repos,
# under ~/.claude-sessions/_shared, bind-mounted to /home/dev/.claude. Authenticate
# once, everywhere. CLAUDE_CONFIG_DIR (set on `docker run` below) relocates BOTH
# .credentials.json AND .claude.json — the latter holds the OAuth session/account
# state (oauthAccount, userID, machineID) that gates "logged in" — into this one
# mounted directory. Mounting the directory (not the single .claude.json file)
# sidesteps the atomic-rename problem that breaks a single-file bind mount, so
# login now survives container rebuilds instead of resetting every reboot.
claude_state="$HOME/.claude-sessions/_shared"
mkdir -p "$claude_state/.claude"

# Mount every entry of the selected group at /workspace/<group>/<entry>,
# resolving symlinks on the host side (Docker cannot follow them inside the
# container). Entries added later need a container restart to appear.
mount_args=()
for entry in ${(f)"$(group_entries "$group_name")"}; do
    mount_args+=(-v "$(realpath "$group_path/$entry"):/workspace/$group_name/$entry")
done

# /home/dev/.local holds nvim's shada/undo history (.local/state) and
# lazy.nvim/mason plugin installs (.local/share) — not under ~/.cache, so it
# needs its own persistent volume too.

# Start container if not running
if ! docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
    docker rm "$container_name" &>/dev/null || true

    docker run -d \
        --name "$container_name" \
        "${mount_args[@]}" \
        -v "$dotfiles_path:/home/dev/dotfiles" \
        -v "${container_name}-cache:/home/dev/.cache" \
        -v "${container_name}-local-cache:/home/dev/.local" \
        -v "${container_name}-go-cache:/home/dev/go" \
        -v "$claude_state/.claude:/home/dev/.claude" \
        -e CLAUDE_CONFIG_DIR=/home/dev/.claude \
        "$image_name"
fi

# Create or switch to tmux session with docker exec as default command
# "=" forces an exact match — without it, dev-foo would match dev-foo-bar.
if ! tmux has-session -t "=$session_name" 2>/dev/null; then
    tmux new-session -d -s "$session_name" \
        "docker exec -it -w $workdir $container_name /bin/zsh -l"
    tmux set-option -t "$session_name" default-command \
        "docker exec -it -w $workdir $container_name /bin/zsh -l"
fi

# Attach or switch
if [[ -z "$TMUX" ]]; then
    tmux attach-session -t "$session_name"
else
    tmux switch-client -t "$session_name"
fi
