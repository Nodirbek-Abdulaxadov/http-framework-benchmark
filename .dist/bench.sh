#!/usr/bin/env bash
# Linux port of bench.ps1. Identical schedule: 5 endpoints × 15s each
# (c=500 / 500 / 200 / 32 / 1000) with a 3 s c=50 warm-up against /ping.
#
# Usage:
#   ./bench.sh <name> <start-cmd> <work-dir> [port]
#
# Example:
#   ./bench.sh jwc ./bin/release/jwc-app.exe ./_my/jwc-app 8080
#
# Writes one JSON result per endpoint to .dist/results/<name>/<endpoint>.json
# (same layout the PowerShell version produces).

set -euo pipefail

NAME="${1:?usage: bench.sh <name> <start-cmd> <work-dir> [port]}"
START_CMD="${2:?usage: bench.sh <name> <start-cmd> <work-dir> [port]}"
WORK_DIR="${3:?usage: bench.sh <name> <start-cmd> <work-dir> [port]}"
PORT="${4:-8080}"

# Resolve script-relative paths so this can run from anywhere.
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
BOMB="${BOMBARDIER_BIN:-$(command -v bombardier || echo "$SCRIPT_DIR/bombardier")}"
RESULTS="$SCRIPT_DIR/results"
OUT_DIR="$RESULTS/$NAME"
mkdir -p "$OUT_DIR"

if [[ ! -x "$BOMB" ]]; then
    echo "bombardier not found at $BOMB" >&2
    echo "Install via: go install github.com/codesenberg/bombardier@latest" >&2
    exit 2
fi

stop_on_port() {
    # Free $PORT regardless of which process holds it. ss + fuser is the
    # most portable combo on a fresh Ubuntu/Debian box.
    if command -v fuser &>/dev/null; then
        fuser -k "${PORT}/tcp" 2>/dev/null || true
    elif command -v lsof &>/dev/null; then
        local pids
        pids=$(lsof -ti:"$PORT" 2>/dev/null || true)
        [[ -n "$pids" ]] && kill -9 $pids 2>/dev/null || true
    fi
    sleep 0.8
}

echo "=== $NAME ==="
stop_on_port

# Start the server detached. PowerShell uses Hidden + PassThru; on Linux we
# nohup + background it, then track the PID for cleanup at the end.
pushd "$WORK_DIR" > /dev/null
nohup bash -c "$START_CMD" > "/tmp/bench-${NAME}.log" 2>&1 &
SERVER_PID=$!
popd > /dev/null

# Wait up to 60 s for /ping to answer 200.
ready=0
for i in $(seq 1 120); do
    if curl -fsS --max-time 1 "http://127.0.0.1:${PORT}/ping" > /dev/null 2>&1; then
        ready=1
        break
    fi
    sleep 0.5
done

if [[ $ready -ne 1 ]]; then
    echo "FAILED to start $NAME (see /tmp/bench-${NAME}.log)" >&2
    kill -9 "$SERVER_PID" 2>/dev/null || true
    stop_on_port
    exit 1
fi

echo "$NAME started (took $((i / 2))s)"

# Warm-up — same shape as the PowerShell version (c=50, d=3s on /ping).
"$BOMB" -c 50 -d 3s -q "http://127.0.0.1:${PORT}/ping" > /dev/null

# Endpoints — schedule identical to bench.ps1.
# DB tier (/db, /queries, /updates) only meaningful when DATABASE_URL is wired
# and the world table is seeded — see .dist/setup-linux.sh.
endpoints=(
    "ping        500 15s"
    "json-small  500 15s"
    "json-large  200 15s"
    "cpu         32  15s"
    "async-delay 1000 15s"
    "db          64  15s"
    "queries     64  15s"
    "updates     64  15s"
)

for line in "${endpoints[@]}"; do
    # Trim leading whitespace, split on space.
    read -r ep c d <<< "$(echo "$line" | tr -s ' ')"
    out_file="$OUT_DIR/$ep.json"
    # /queries and /updates take a ?queries=20 query string (TechEmpower-shape).
    case "$ep" in
        queries|updates) url="http://127.0.0.1:${PORT}/${ep}?queries=20" ;;
        *)               url="http://127.0.0.1:${PORT}/${ep}" ;;
    esac
    echo "  bench /$ep c=$c d=$d"
    raw=$("$BOMB" -c "$c" -d "$d" -t 5s -l -o json "$url")
    # bombardier's --print-json prints the result envelope on the last line.
    # Extract the last `{ ... }` line just like the PowerShell version did.
    echo "$raw" | awk '/^\{.*\}$/{ last=$0 } END{ if (last) print last; else exit 1 }' \
        > "$out_file" || echo "$raw" > "$out_file"
done

# Cleanup
kill -9 "$SERVER_PID" 2>/dev/null || true
stop_on_port
echo "$NAME done"
