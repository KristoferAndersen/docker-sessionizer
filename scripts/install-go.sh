#!/usr/bin/env bash
set -euo pipefail

GO_VERSION="${GO_VERSION:-1.25.7}"

ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  GO_ARCH="amd64" ;;
    aarch64) GO_ARCH="arm64" ;;
    *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz" | tar -C /usr/local -xz

echo 'export PATH="/usr/local/go/bin:$PATH"' >> /etc/profile.d/go.sh
echo 'export GOPATH="$HOME/go"' >> /etc/profile.d/go.sh
echo 'export PATH="$GOPATH/bin:$PATH"' >> /etc/profile.d/go.sh
