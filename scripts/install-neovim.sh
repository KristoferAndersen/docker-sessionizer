#!/usr/bin/env bash
set -euo pipefail

NVIM_VERSION="${NVIM_VERSION:-0.11.6}"

ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  NVIM_ARCH="x86_64" ;;
    aarch64) NVIM_ARCH="arm64" ;;
    *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

curl -fsSL "https://github.com/neovim/neovim/releases/download/v${NVIM_VERSION}/nvim-linux-${NVIM_ARCH}.tar.gz" \
    | tar -xz -C /usr/local

echo "export PATH=\"/usr/local/nvim-linux-${NVIM_ARCH}/bin:\$PATH\"" >> /etc/profile.d/neovim.sh
