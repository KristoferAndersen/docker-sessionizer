FROM debian:bookworm-slim

ARG GO_VERSION=1.23.5

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
    wget \
    ripgrep \
    fd-find \
    fzf \
    bash-completion \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install Go from official tarball
RUN curl -fsSL https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz | tar -C /usr/local -xz
ENV PATH="/usr/local/go/bin:${PATH}"

# Install Neovim
RUN wget https://github.com/neovim/neovim/releases/download/v0.11.6/nvim-linux-x86_64.tar.gz
RUN tar xfz nvim-linux-x86_64.tar.gz -C /usr/local
ENV PATH="/usr/local/nvim-linux-x86_64/bin:${PATH}"

# Create dev user with zsh as default shell
RUN useradd -m -s /bin/zsh dev

# Install oh-my-zsh and powerlevel10k as dev user
USER dev
WORKDIR /home/dev
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended && \
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k

# Switch back to root for remaining setup
USER root

# Pre-create cache directories with correct ownership
# When empty volumes are mounted here, Docker will copy these permissions
RUN mkdir -p /home/dev/.cache /home/dev/.claude && \
    chown -R dev:dev /home/dev/.cache /home/dev/.claude

# Entrypoint handles dotfiles setup
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /home/dev
USER dev
ENTRYPOINT ["/entrypoint.sh"]
CMD ["/bin/zsh"]
