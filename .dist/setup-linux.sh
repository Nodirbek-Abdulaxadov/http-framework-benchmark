#!/usr/bin/env bash
# Provision a fresh Ubuntu 24.04 server (Hetzner CCX33 / AWS c7i.4xlarge /
# DigitalOcean CPU-Optimized / etc.) with every toolchain the suite needs,
# then build all stacks under release flags.
#
# Idempotent: re-running on an already-set-up box only rebuilds whatever
# changed. Designed for a fresh root shell — `cloud-init` can call it
# directly with `bash setup-linux.sh`.
#
# Total wall-clock on CCX33: ~6 min (apt + rust + dotnet + node + go).
# Then `bench-all.sh` takes ~6 min × N stacks.

set -euo pipefail

if [[ "$EUID" -ne 0 ]]; then
    echo "Run as root (sudo bash $0)" >&2
    exit 1
fi

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
cd "$REPO_ROOT"

echo "==> apt update + base tools"
export DEBIAN_FRONTEND=noninteractive
apt-get -qq update
apt-get -qq install -y \
    curl wget git build-essential pkg-config libssl-dev \
    jq python3 python3-pip python3-venv \
    htop lsof psmisc \
    ca-certificates gnupg lsb-release

echo "==> bombardier (Go binary, no Go toolchain needed)"
if ! command -v bombardier &>/dev/null; then
    BOMB_VER="1.2.6"
    wget -q -O /usr/local/bin/bombardier \
        "https://github.com/codesenberg/bombardier/releases/download/v${BOMB_VER}/bombardier-linux-amd64"
    chmod +x /usr/local/bin/bombardier
fi
bombardier --version || true

echo "==> Go (for go-fiber)"
if ! command -v go &>/dev/null; then
    GO_VER="1.24.0"
    wget -q -O /tmp/go.tgz "https://go.dev/dl/go${GO_VER}.linux-amd64.tar.gz"
    rm -rf /usr/local/go
    tar -C /usr/local -xzf /tmp/go.tgz
    ln -sf /usr/local/go/bin/go /usr/local/bin/go
fi
go version

echo "==> Rust (for rust-axum + jwc native build)"
if ! command -v cargo &>/dev/null; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
    export PATH="$HOME/.cargo/bin:$PATH"
    echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> /root/.bashrc
fi
. "$HOME/.cargo/env" 2>/dev/null || true
rustc --version

echo "==> .NET 10 SDK (for dotnet-minimal + liteapi)"
if ! command -v dotnet &>/dev/null; then
    wget -q https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb -O /tmp/ms.deb
    dpkg -i /tmp/ms.deb
    apt-get -qq update
    # Use SDK preview if 10 isn't GA in your distro yet; on Hetzner 24.04 the
    # `dotnet-sdk-10.0` package is available via the Microsoft preview feed.
    apt-get -qq install -y dotnet-sdk-10.0 || apt-get -qq install -y dotnet-sdk-9.0
fi
dotnet --version

echo "==> Node 22 (for node-fastify)"
if ! command -v node &>/dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
    apt-get -qq install -y nodejs
fi
node --version

echo "==> Python deps (fastapi + uvicorn for python-fastapi)"
python3 -m pip install --quiet --break-system-packages \
    fastapi==0.115.14 uvicorn==0.35.0 || true

# ---------------------------------------------------------------------------
# Build every stack under release flags. Each block guards on existence so
# re-running on a partial checkout still does the right thing.
# ---------------------------------------------------------------------------

if [[ -d dotnet-minimal ]]; then
    echo "==> build dotnet-minimal"
    (cd dotnet-minimal && dotnet publish -c Release -o ./publish)
fi

if [[ -d go-fiber ]]; then
    echo "==> build go-fiber"
    (cd go-fiber && go build -ldflags="-s -w" -o go-fiber .)
fi

if [[ -d rust-axum ]]; then
    echo "==> build rust-axum"
    (cd rust-axum && . "$HOME/.cargo/env" && cargo build --release)
fi

if [[ -d node-fastify ]]; then
    echo "==> install node-fastify deps"
    (cd node-fastify && npm install --silent --no-fund --no-audit)
fi

# JWC native build — assumes the jwc-lang repo is cloned to a sibling dir or
# JWC_BIN points at a prebuilt jwc binary. The bench suite only needs
# jwc-app's native binary; we install jwc itself only if absent.
if [[ -d _my/jwc-app ]]; then
    echo "==> build jwc + jwc-app native"
    JWC_BIN="${JWC_BIN:-$(command -v jwc || echo /usr/local/bin/jwc)}"
    if [[ ! -x "$JWC_BIN" ]] && [[ -d /opt/jwc-lang ]]; then
        (cd /opt/jwc-lang && . "$HOME/.cargo/env" && cargo build --release)
        cp /opt/jwc-lang/target/release/jwc /usr/local/bin/jwc
        JWC_BIN=/usr/local/bin/jwc
    fi
    if [[ -x "$JWC_BIN" ]]; then
        (cd _my/jwc-app && "$JWC_BIN" build --native --release)
    else
        echo "WARN: jwc not found — skipping jwc-app build. Clone jwc-lang to /opt/jwc-lang or set JWC_BIN." >&2
    fi
fi

echo
echo "Setup complete. Run: bash .dist/bench-all.sh"
