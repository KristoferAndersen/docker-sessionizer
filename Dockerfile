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
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Copy modular install scripts
COPY scripts/ /usr/local/lib/dev-scripts/
RUN chmod +x /usr/local/lib/dev-scripts/*.sh


# Create dev user
RUN useradd -m -s /bin/zsh dev && mkdir -p /home/dev/.cache && chown dev:dev /home/dev/.cache

# Entrypoint handles dotfiles setup
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /home/dev
USER dev

# Oh My Zsh with sensible defaults
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended \
    && git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions \
        /home/dev/.oh-my-zsh/custom/plugins/zsh-autosuggestions \
    && git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting \
        /home/dev/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting \
    && sed -i 's/^plugins=(git)$/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' /home/dev/.zshrc

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/bin/zsh"]
