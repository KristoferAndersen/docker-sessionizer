FROM debian:bookworm

# System packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    stow \
    zsh \
    python3 \
    python3-pip \
    python3-venv \
    nodejs \
    npm \
    gcc \
    g++ \
    make \
    cmake \
    unzip \
    curl \
    ripgrep \
    fd-find \
    fzf \
    jq \
    htop \
    locales \
    xxd \
    && rm -rf /var/lib/apt/lists/*

# Copy modular install scripts
COPY scripts/ /usr/local/lib/dev-scripts/
RUN chmod +x /usr/local/lib/dev-scripts/*.sh


# Create dev user
RUN useradd -m -s /bin/bash dev && mkdir -p /home/dev/.cache && chown dev:dev /home/dev/.cache

# Entrypoint handles dotfiles setup
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /home/dev
USER dev
ENTRYPOINT ["/entrypoint.sh"]
CMD ["/bin/bash"]
