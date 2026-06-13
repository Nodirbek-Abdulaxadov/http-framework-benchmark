#!/usr/bin/env bash
# Orchestrate the benchmark suite across every framework on a freshly
# provisioned Linux box. Assumes the toolchains are already installed
# (run cloud-init/setup.sh first on a new machine).
#
# All five baseline stacks + the two `_my/` projects run in sequence —
# never in parallel, so the only thing competing for CPU is the
# framework under test + bombardier. Results land under
# .dist/results/<name>/<endpoint>.json — same shape the PowerShell
# version produces.

set -euo pipefail

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
REPO_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"

run() {
    local name="$1"
    local cmd="$2"
    local dir="$3"
    echo
    "$SCRIPT_DIR/bench.sh" "$name" "$cmd" "$dir" || {
        echo "WARN: $name failed, continuing" >&2
    }
}

# --- dotnet-minimal ---
if [[ -d "$REPO_ROOT/dotnet-minimal/publish" ]]; then
    run "dotnet-minimal" \
        "dotnet ./publish/dotnet-minimal.dll --urls http://0.0.0.0:8080" \
        "$REPO_ROOT/dotnet-minimal"
fi

# --- go-fiber ---
if [[ -x "$REPO_ROOT/go-fiber/go-fiber" ]] || [[ -x "$REPO_ROOT/go-fiber/go-fiber.exe" ]]; then
    GO_BIN="$REPO_ROOT/go-fiber/go-fiber"
    [[ -x "$GO_BIN" ]] || GO_BIN="$REPO_ROOT/go-fiber/go-fiber.exe"
    run "go-fiber" "$GO_BIN" "$REPO_ROOT/go-fiber"
fi

# --- node-fastify ---
if [[ -f "$REPO_ROOT/node-fastify/index.js" ]]; then
    run "node-fastify" "node index.js" "$REPO_ROOT/node-fastify"
fi

# --- python-fastapi ---
if [[ -f "$REPO_ROOT/python-fastapi/main.py" ]]; then
    run "python-fastapi" \
        "python3 -m uvicorn main:app --host 0.0.0.0 --port 8080 --workers 1 --log-level warning" \
        "$REPO_ROOT/python-fastapi"
fi

# --- rust-axum ---
if [[ -x "$REPO_ROOT/rust-axum/target/release/benchmark" ]]; then
    run "rust-axum" "./target/release/benchmark" "$REPO_ROOT/rust-axum"
fi

# --- jwc-app (native AOT) ---
if [[ -x "$REPO_ROOT/_my/jwc-app/bin/release/jwc-app" ]]; then
    run "jwc" "./bin/release/jwc-app" "$REPO_ROOT/_my/jwc-app"
elif [[ -x "$REPO_ROOT/_my/jwc-app/bin/release/jwc-app.exe" ]]; then
    run "jwc" "./bin/release/jwc-app.exe" "$REPO_ROOT/_my/jwc-app"
fi

# --- liteapi (managed + rust) ---
if [[ -d "$REPO_ROOT/_my/liteapi-managed/publish" ]]; then
    run "liteapi-managed" \
        "dotnet ./publish/liteapi-managed.dll --urls http://0.0.0.0:8080" \
        "$REPO_ROOT/_my/liteapi-managed"
fi
if [[ -d "$REPO_ROOT/_my/liteapi-rust/publish" ]]; then
    run "liteapi-rust" \
        "dotnet ./publish/liteapi-rust.dll --urls http://0.0.0.0:6080" \
        "$REPO_ROOT/_my/liteapi-rust" 6080
fi

echo
echo "ALL DONE — results in $SCRIPT_DIR/results/"
