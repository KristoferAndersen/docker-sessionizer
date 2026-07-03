# --- builder: compile/fetch tools too old (or absent) in bookworm apt ---
# Currently: git (bookworm ships 2.39.5). Add more source builds here as needed.
FROM debian:bookworm AS builder
ARG GIT_VERSION=2.50.1
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    dpkg-dev \
    gcc \
    make \
    gettext \
    libssl-dev \
    libcurl4-gnutls-dev \
    libexpat1-dev \
    libpcre2-dev \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL "https://mirrors.edge.kernel.org/pub/software/scm/git/git-${GIT_VERSION}.tar.gz" -o /tmp/git.tar.gz \
    && mkdir -p /tmp/git && tar -xzf /tmp/git.tar.gz -C /tmp/git --strip-components=1 \
    && cd /tmp/git \
    && make prefix=/usr/local NO_TCLTK=1 -j"$(nproc)" \
    && make prefix=/usr/local NO_TCLTK=1 install

FROM debian:bookworm

# System packages
RUN apt-get update && apt-get install -y --no-install-recommends \
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
    libcurl3-gnutls \
    libpcre2-8-0 \
    libexpat1 \
    zlib1g \
    && rm -rf /var/lib/apt/lists/*

# Tools built from source (see builder stage above)
COPY --from=builder /usr/local /usr/local

# Copy modular install scripts
COPY scripts/ /usr/local/lib/dev-scripts/
RUN chmod +x /usr/local/lib/dev-scripts/*.sh \
    && ln -sf /usr/local/lib/dev-scripts/ralph.sh /usr/local/bin/ralph


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
