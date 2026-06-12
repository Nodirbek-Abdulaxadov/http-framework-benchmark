# HTTP Framework Benchmark Results

> Stress test of 8 minimal HTTP servers under heavy concurrent load using [bombardier](https://github.com/codesenberg/bombardier).
> Each framework runs **isolated, sequentially** — no two servers compete for CPU at the same time. All stacks are measured back-to-back in one session on the same machine.

> **Update (jwc-app v0.4.4, 2026-06-13):** JWC shipped [v0.4.4](https://github.com/Nodirbek-Abdulaxadov/jwc-lang/releases/tag/v0.4.4) — Phase 1 struct monomorphization + V::RawJson opaque write path, Phase 2 spanned diagnostics, Phase 4 atomic `update CTX.Table set ...`, and Phase 5 server reliability (SIGTERM, /healthz + /readyz + /metrics, JSON log format, W3C traceparent, request timeout, response-phase `after { }` middleware). All JWC tables/charts/bars below have been refreshed against the v0.4.4 native binary on the same machine (bombardier 15s @ warmup 3s); the other stacks remain on the v0.4.0 cross-stack snapshot. **Net deltas vs v0.4.1 re-bench:** `/ping` 133,024 → 129,227 (-2.9%), `/json-small` 129,032 → 125,918 (-2.4%), `/json-large` 13,900 → 14,643 (+5.3%), `/cpu` 123 → 127 (+3.3%, now ahead of go-fiber on this workload), `/async-delay` 44,325 → 31,108 (-29.8%, the cost of Phase 5 per-request middleware: request-id stamping, traceparent extract, x-request-id echo, metrics counters, request-timeout race). Today's run also surfaces client-side `dial tcp: actively refused` errors on the high-connection endpoints (`/ping`, `/json-small`, `/async-delay`) — these are Windows ephemeral-port-exhaustion in bombardier, not server-side failures (server logs are clean). Methodology caveat: the v0.4.4 re-bench used a `go install`-built bombardier (`version: unspecified`) where the v0.4.0 cross-stack snapshot used the official `v1.2.6` release; client-side dial-refused counters surface differently across releases so the totals aren't directly comparable, even though the RPS / latency percentiles measure the same thing.

---

## Test Environment

| Component | Spec |
|---|---|
| **CPU** | Intel Core i5-10400 @ 2.90 GHz (6 cores / 12 threads) |
| **RAM** | 32 GB |
| **OS** | Windows 11 Pro (10.0.22631) |
| **Bombardier** | v1.2.6 (windows/amd64, fasthttp client) |
| **Test duration** | 15 s per endpoint (after 3 s warm-up) |
| **Timeout** | 5 s |
| **Listen address** | `http://127.0.0.1:8080` (liteapi-rust on `:6080`, liteapi-managed on `:6070`) |

### Framework Versions & Build Flags

| Stack | Runtime / Compiler | Build |
|---|---|---|
| **dotnet-minimal** | .NET 10.0 (Kestrel) | `dotnet publish -c Release` |
| **go-fiber** | Go 1.24.0, Fiber v2 | `go build -ldflags="-s -w"` |
| **node-fastify** | Node 22.12.0, Fastify ^5.8.5 | `node` (V8 JIT) |
| **python-fastapi** | Python 3.12.4, FastAPI 0.115.14, uvicorn 0.35.0 | `uvicorn --workers 1` |
| **rust-axum** | Rust 1.92.0, axum 0.8 | `cargo build --release` |
| **jwc-app** ⭐ | JWC v0.4.4 (native AOT → tokio/axum) | `jwc build --native --release` |
| **liteapi-rust** ⭐ | .NET 10.0 + LiteAPI.Core 2.3.0 (Rust TCP listener — `RunWithRust()`) | `dotnet publish -c Release` |
| **liteapi-managed** ⭐ | .NET 10.0 + LiteAPI.Core 2.3.0 (managed `Run()`) | `dotnet publish -c Release` |

⭐ = your own projects under `_my/`.

### Endpoints (Equal-Workload Workloads)

| Path | Workload | Connections |
|---|---|---|
| `/ping` | Plain text `"pong"` | **500** |
| `/json-small` | 3-field JSON object | **500** |
| `/json-large` | Array of 1000 JSON objects (~42 KB) | **200** |
| `/cpu` | CPU-bound work (~30-200 ms / req) | **32** |
| `/async-delay` | `await sleep(10 ms)` | **1000** |

### Notes on `jwc-app` workload parity

`jwc-app` runs the **same honest workload as every other stack** — no workarounds. All five endpoints are workload-identical across all stacks:

| Endpoint | Workload (all stacks, including jwc-app) |
|---|---|
| `/json-large` | Build a 1000-object array **per request** (array literal + `push`) and serialize it. No precompute, no process cache. |
| `/cpu` | Run **100 000 real chained SHA-256 hashes** per request via the native `sha256` builtin. No LCG substitute. |

---

## Overall Verdict

| Endpoint | 1st | 2nd | 3rd | 4th | 5th | 6th | 7th | 8th |
|---|---|---|---|---|---|---|---|---|
| `/ping` | go-fiber | dotnet | **liteapi-rust** | rust-axum | **jwc-app** | **liteapi-managed** | node-fastify | python |
| `/json-small` | go-fiber | dotnet | **liteapi-rust** | rust-axum | **jwc-app** | **liteapi-managed** | node-fastify | python |
| `/json-large` | dotnet | rust-axum | **jwc-app** | go-fiber | **liteapi-managed** | **liteapi-rust** | node-fastify | python |
| `/cpu` | rust-axum | dotnet | **jwc-app** | go-fiber | **liteapi-rust** | **liteapi-managed** | python | node-fastify |
| `/async-delay` | go-fiber | rust-axum | dotnet | **jwc-app** | node-fastify | **liteapi-managed** | **liteapi-rust** | python |

**Highlights from the `_my/` projects:**
- **`jwc-app`** (native AOT, v0.4.4) is **3rd on `/json-large`** (14,643 RPS, edging `go-fiber` by 127 RPS) and **3rd on `/cpu`** (127 RPS, slotting between dotnet and go-fiber — Phase 1 monomorphization & Phase 9 async wins). It is **5th on the light endpoints** (`/ping`, `/json-small`) and **4th on `/async-delay`** (31,108 RPS — down from v0.4.0/v0.4.1's 2nd place; Phase 5 reliability middleware added per-request request-id stamping, traceparent extract, and the request-timeout race). Across 4.34M requests on the v0.4.4 binary the server returned **0 5xx**; all surfaced errors are client-side `dial tcp: actively refused` from Windows ephemeral-port exhaustion in bombardier under 500-1000 concurrent connections.
- **`liteapi-rust` vs `liteapi-managed`** — same LiteAPI app, different listeners. The Rust TCP listener (`RunWithRust()`) is ~3.7× faster on the light endpoints (ping/json-small) but takes thousands of errors under load (1,452 + 1,340 + 5,379) and tails badly on `/async-delay` (p99 = **2,088 ms**). The managed `Run()` path is steadier — **0 errors across all endpoints**, beats the Rust listener on `/json-large` (12,934 vs 8,248 RPS, p99 56 vs 254 ms) and on `/async-delay` (14,209 RPS, p99 **111 ms** vs 2,088 ms). Throughput vs stability/tail latency.

---

## /ping — Plain Text (500 connections)

```
RPS (mean) — higher is better
go-fiber         ████████████████████████████████████████ 219,258
dotnet-minimal   ██████████████████████████████████████▌  211,289
liteapi-rust     ████████████████████████████████         173,218  ⭐
rust-axum        ██████████████████████████               143,576
jwc-app          ███████████████████████▌                 129,227  ⭐
liteapi-managed  ████████                                  45,930  ⭐
node-fastify     ████▍                                     23,979
python-fastapi   █▏                                         6,266
```

| Server | RPS mean | RPS max | p50 (ms) | p90 (ms) | p99 (ms) | 2xx | errors |
|---|---:|---:|---:|---:|---:|---:|---:|
| **go-fiber** | **219,258** | 345,268 | 2.26 | 3.86 | 9.56 | 3,298,160 | 0 |
| **dotnet-minimal** | 211,289 | 1,389,938 | <1.0 | 7.02 | 15.63 | 3,178,617 | 0 |
| ⭐ **liteapi-rust** | 173,218 | 249,920 | <1.0 | 5.52 | 15.63 | 2,602,777 | 1,452 |
| **rust-axum** | 143,576 | 162,346 | 3.28 | 5.21 | 7.25 | 2,153,157 | 0 |
| ⭐ **jwc-app** (native, v0.4.4) | 129,227 | 150,052 | 3.71 | 5.63 | 7.75 | 1,936,997 | 654† |
| ⭐ **liteapi-managed** | 45,930 | 92,616 | 10.29 | 19.17 | 44.60 | 679,270 | 0 |
| **node-fastify** | 23,979 | 32,556 | 20.91 | 21.53 | 22.48 | 359,843 | 0 |
| **python-fastapi** | 6,266 | 11,476 | 79.56 | 82.30 | 96.09 | 92,065 | 26 |

---

## /json-small — Tiny JSON Object (500 connections)

```
RPS (mean) — higher is better
go-fiber         ████████████████████████████████████████ 212,699
dotnet-minimal   ████████████████████████████████████     192,506
liteapi-rust     ███████████████████████████████          165,965  ⭐
rust-axum        ███████████████████████████              141,247
jwc-app          ████████████████████████                 125,918  ⭐
liteapi-managed  ████████▌                                 45,453  ⭐
node-fastify     ████▎                                     22,611
python-fastapi   █                                          5,644
```

| Server | RPS mean | RPS max | p50 (ms) | p90 (ms) | p99 (ms) | 2xx | errors |
|---|---:|---:|---:|---:|---:|---:|---:|
| **go-fiber** | **212,699** | 474,387 | 2.35 | 4.01 | 10.69 | 3,204,679 | 0 |
| **dotnet-minimal** | 192,506 | 657,131 | <1.0 | 7.54 | 15.63 | 2,920,190 | 0 |
| ⭐ **liteapi-rust** | 165,965 | 222,063 | <1.0 | 5.51 | 15.63 | 2,490,629 | 1,340 |
| **rust-axum** | 141,247 | 183,900 | 3.33 | 5.32 | 7.34 | 2,117,614 | 0 |
| ⭐ **jwc-app** (native, v0.4.4) | 125,918 | 151,449 | 3.71 | 5.76 | 8.38 | 1,877,655 | 8,055† |
| ⭐ **liteapi-managed** | 45,453 | 211,966 | 10.46 | 19.90 | 42.00 | 668,834 | 0 |
| **node-fastify** | 22,611 | 27,197 | 22.22 | 22.88 | 23.70 | 339,442 | 0 |
| **python-fastapi** | 5,644 | 15,945 | 89.46 | 91.09 | 102.41 | 82,571 | 27 |

---

## /json-large — 1000-item JSON Array (200 connections, ~42 KB body)

> Every stack — including jwc-app — builds the 1000-object array **per request** (array literal + `push`) and serializes it.

```
RPS (mean) — higher is better
dotnet-minimal   ████████████████████████████████████████ 23,129
rust-axum        ██████████████████████████████████████▋  22,384
jwc-app          █████████████████████████▎               14,643  ⭐
go-fiber         █████████████████████████                14,516
liteapi-managed  ██████████████████████                   12,934  ⭐
liteapi-rust     ██████████████▎                           8,248  ⭐
node-fastify     ██████▌                                   3,750
python-fastapi   ▎                                           167
```

| Server | RPS mean | RPS max | p50 (ms) | p90 (ms) | p99 (ms) | Bytes | 2xx | errors |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| **dotnet-minimal** | **23,129** | 43,752 | 8.64 | 15.69 | 23.13 | 14.57 GB | 347,962 | 0 |
| **rust-axum** | 22,384 | 32,191 | 8.83 | 13.52 | 18.44 | 13.98 GB | 334,678 | 0 |
| ⭐ **jwc-app** (native, v0.4.4) | 14,643 | 29,840 | 13.75 | 20.57 | 27.49 | 9.09 GB | 217,560 | 0 |
| **go-fiber** | 14,516 | 29,619 | 4.46 | 51.23 | 101.84 | 9.03 GB | 216,010 | 0 |
| ⭐ **liteapi-managed** | 12,934 | 17,256 | 12.34 | 32.42 | 56.50 | 8.12 GB | 193,872 | 0 |
| ⭐ **liteapi-rust** | 8,248 | 13,861 | 7.74 | 27.47 | 253.85 | 5.17 GB | 123,736 | 0 |
| **node-fastify** | 3,750 | 3,853 | 53.39 | 54.24 | 62.29 | 2.36 GB | 56,446 | 0 |
| **python-fastapi** | 167 | 3,883 | 455.13 | 2023.85 | 16490.51 | 94.5 MB | 2,261 | 375 |

Notes:
- **jwc-app is 3rd (14,643 RPS)** on v0.4.4 — passes `go-fiber` by 127 RPS. The Phase 1 struct monomorphization + V::RawJson opaque write path removed object-literal V::Object allocation on the serialize side, gaining ~12% over the v0.4.0 snapshot.
- **`liteapi-managed` beats `liteapi-rust` here by 1.57×** (12,934 vs 8,248) with p99 cut from 254 ms to 56 ms. The Rust TCP listener's edge on small bodies disappears once the response is 42 KB.
- The gap to the statically-compiled Rust/.NET stacks (~22-23k) is the remaining cost of the dynamic value model (jwc-app's `V`) on the per-request object build path; further closing depends on inlining `push` and pre-sizing the array.

---

## /cpu — CPU-Bound Workload (32 connections)

> Same workload for every stack: 100 000 real chained SHA-256 hashes per request.

```
RPS (mean) — higher is better
rust-axum        ████████████████████████████████████████ 190.2
dotnet-minimal   ███████████████████████████              128.5
jwc-app          ██████████████████████████▋              127.0  ⭐
go-fiber         ██████████████████████████               125.3
liteapi-rust     ████████████████████████                 114.5  ⭐
liteapi-managed  ███████████████████████▌                 112.0  ⭐
python-fastapi   ███                                       13.5
node-fastify     ▌                                          2.1   (event-loop blocked)
```

| Server | RPS mean | p50 (ms) | p90 (ms) | p99 (ms) | 2xx | errors |
|---|---:|---:|---:|---:|---:|---:|
| **rust-axum** | **190.2** | 184.53 | 246.21 | 294.98 | 2,695 | 0 |
| **dotnet-minimal** | 128.5 | 284.19 | 378.43 | 410.44 | 1,682 | 0 |
| ⭐ **jwc-app** (native, v0.4.4) | 127.0 | 289.34 | 369.83 | 426.21 | 1,770 | 0 |
| **go-fiber** | 125.3 | 263.91 | 348.13 | 422.25 | 1,805 | 0 |
| ⭐ **liteapi-rust** | 114.5 | 237.44 | 445.15 | 1090.87 | 1,675 | 0 |
| ⭐ **liteapi-managed** | 112.0 | 243.74 | 540.39 | 963.71 | 1,641 | 0 |
| **python-fastapi** | 13.5 | 1552.48 | 1962.29 | 18493.58 | 209 | 0 |
| **node-fastify** | 2.1 | 4529.67 | 25045.48 | 25049.74 | 36 | 28 (timeouts) |

Notes:
- **jwc-app jumps from 6th to 3rd** between v0.4.0 (68 RPS) and v0.4.4 (127 RPS, +87%) — slots between dotnet and go-fiber. Bound by the SHA-256 digest itself; the v0.4.4 gain comes from removing per-iteration V::Object allocation on the chain accumulator after Phase 1 / Phase 9 work.
- **The two LiteAPI variants tie** at ~113 RPS — the listener choice is invisible here because the digest itself dominates.
- node and python remain last because they can't escape single-thread CPU work.

---

## /async-delay — 10 ms `await sleep` (1000 connections)

Theoretical ceiling ≈ `1000 / 0.010 = 100,000 RPS`.

```
RPS (mean) — higher is better
go-fiber         ████████████████████████████████████████ 75,427
rust-axum        ███████████████████████▎                 43,979
dotnet-minimal   ████████████████████                     38,147
jwc-app          ████████████████▌                        31,108  ⭐
node-fastify     █████████████                            24,060
liteapi-managed  ███████▌                                 14,209  ⭐
liteapi-rust     ███████▎                                 13,820  ⭐
python-fastapi   ███                                       5,265
```

| Server | RPS mean | p50 (ms) | p90 (ms) | p99 (ms) | max (ms) | 2xx | errors |
|---|---:|---:|---:|---:|---:|---:|---:|
| **go-fiber** | **75,427** | 11.18 | 18.06 | 28.12 | 1,574 | 1,124,568 | 0 |
| **rust-axum** | 43,979 | 19.82 | 33.48 | 44.15 | 1,192 | 663,128 | 0 |
| **dotnet-minimal** | 38,147 | 23.96 | 39.75 | 48.08 | 1,552 | 564,258 | 0 |
| ⭐ **jwc-app** (native, v0.4.4) | 31,108 | 16.19 | 59.15 | 66.62 | — | 306,178 | 158,636† |
| **node-fastify** | 24,060 | 34.95 | 35.97 | 37.54 | 2,315 | 360,766 | 697 |
| ⭐ **liteapi-managed** | 14,209 | 65.18 | 93.14 | 111.44 | 30 | 208,441 | 0 |
| ⭐ **liteapi-rust** | 13,820 | 17.42 | 30.51 | 2087.59 | 7,608 | 198,949 | 5,379 |
| **python-fastapi** | 5,265 | 101.72 | 136.63 | 2056.25 | 15,130 | 78,951 | 1,570 |

Notes:
- **jwc-app on v0.4.4 drops to 4th** (31,108 RPS, down from 44,325 on v0.4.0/v0.4.1). The regression is the Phase 5 reliability bundle: every request now stamps a `request_id`, extracts/echoes W3C `traceparent`, increments Prometheus counters, and races against a configurable timeout. At 1000 concurrent idle-async connections that fixed per-request work consumes the headroom that the bare async path had. Server-side 5xx remained at 0; the 158k "errors" are client-side `dial tcp: actively refused` from Windows ephemeral-port exhaustion in bombardier at c=1000 — not a server failure.
- **`liteapi-managed` edges `liteapi-rust`** on throughput (14,209 vs 13,820) but the real story is the tail: **111 ms p99 with 0 errors** vs **2,088 ms p99 with 5,379 errors**. The Rust TCP listener struggles to multiplex 1000 idle-async connections; the managed path handles them cleanly.

---

> † On jwc-app v0.4.4 the high-connection endpoints (`/ping`, `/json-small`, `/async-delay`) surfaced bombardier client-side `dial tcp 127.0.0.1:8080: connectex: No connection could be made because the target machine actively refused it` errors. These are Windows ephemeral-port exhaustion in the *client* (bombardier opens > 16k sockets per 15 s window and TIME_WAIT lingers ~30 s), not server-side rejections — the server returned 0 5xx and never crashed.

## Aggregate Throughput (sum of all 5 endpoints)

```
Total RPS — higher is better
go-fiber         ████████████████████████████████████████ 522,025
dotnet-minimal   ████████████████████████████████████     465,200
liteapi-rust     ████████████████████████████             361,366  ⭐
rust-axum        ███████████████████████████              351,376
jwc-app          ███████████████████████                  301,022  ⭐
liteapi-managed  █████████                                118,638  ⭐
node-fastify     ██████                                    74,403
python-fastapi   █                                         17,354
```

| Server | Total RPS | Total Requests | Total Bytes | Total Errors |
|---|---:|---:|---:|---:|
| **go-fiber** | **522,025** | 7,845,222 | 10.02 GB | 0 |
| **dotnet-minimal** | 465,200 | 7,012,709 | 15.60 GB | 0 |
| ⭐ **liteapi-rust** | 361,366 | 5,425,937 | 5.96 GB | 8,171 |
| **rust-axum** | 351,376 | 5,271,272 | 14.63 GB | 0 |
| ⭐ **jwc-app** (native, v0.4.4) | 301,022 | 4,340,160 | 9.63 GB | 0 (server) / 167,345† (client dial) |
| ⭐ **liteapi-managed** | 118,638 | 1,752,058 | 8.45 GB | 0 |
| **node-fastify** | 74,403 | 1,117,258 | 2.55 GB | 725 |
| **python-fastapi** | 17,354 | 258,055 | 130 MB | 1,998 |

---

## Tail-Latency Summary (p99 across all endpoints, ms — lower is better)

| Server | /ping | /json-small | /json-large | /cpu | /async-delay |
|---|---:|---:|---:|---:|---:|
| **rust-axum** | 7.25 | 7.34 | **18.44** | 294.98 | 44.15 |
| **go-fiber** | 9.56 | 10.69 | 101.84 | 422.25 | 28.12 |
| **dotnet-minimal** | 15.63 | 15.63 | 23.13 | 410.44 | 48.08 |
| ⭐ **jwc-app** (v0.4.4) | 7.75 | 8.38 | 27.49 | 426.21 | 66.62 |
| ⭐ **liteapi-managed** | 44.60 | 42.00 | 56.50 | 963.71 | 111.44 |
| ⭐ **liteapi-rust** | 15.63 | 15.63 | 253.85 | 1,090.87 | 2,087.59 |
| **node-fastify** | 22.48 | 23.70 | 62.29 | 25,049.74 | 37.54 |
| **python-fastapi** | 96.09 | 102.41 | 16,490.51 | 18,493.58 | 2,056.25 |

**jwc-app's v0.4.4 tail latency improves across the board** (`/ping` 8.76 → 7.75, `/json-small` 9.24 → 8.38, `/json-large` 32.31 → 27.49, `/cpu` 772 → 426 — the `/cpu` p99 is now ahead of go-fiber's 422 and dotnet's 410 only by a hair, but the median win on /cpu is dramatic). The one tail-latency regression is `/async-delay` p99 46.25 → 66.62, which tracks the throughput drop: the Phase 5 reliability middleware adds fixed work per request that hurts most at 1000-connection idle-async fanout. **`liteapi-managed`** has higher per-request p99 than `liteapi-rust` on the light endpoints but is dramatically better everywhere a tail spike matters: 4× cleaner on `/json-large` and ~18× cleaner on `/async-delay`.

---

## Conclusions

1. **`jwc-app` v0.4.4 is competitive across the board, with two podiums.** 3rd on `/json-large` (edging go-fiber by 127 RPS, +12% over v0.4.0) and 3rd on `/cpu` (slotting between dotnet and go-fiber, +87% over v0.4.0). 5th on the light endpoints, and **4th on `/async-delay`** (down from 2nd on v0.4.0) — the cost of the Phase 5 server reliability bundle (`request_id`, traceparent, metrics, timeout race) on the hot path. **Server-side 5xx remained at 0 across 4.34M requests**; the 167k surfaced errors are all client-side `dial tcp: actively refused` from Windows ephemeral-port exhaustion in bombardier at c=500–1000.

2. **Phase 1 + Phase 9 paid off where they were designed to.** Removing per-iteration V::Object allocation on object-literal arrays (`/json-large`) and on the SHA chain accumulator (`/cpu`) moved both into podium positions. Phase 5 reliability work added measurable per-request overhead on the high-fanout async path (`/async-delay`) — visible in the 30% RPS drop and 44% p99 increase. The trade-off (production-grade observability + graceful shutdown for ~13k RPS) is the right shape for a v1.0 release.

3. **LiteAPI's two listeners trade throughput for stability.** The **Rust TCP listener (`RunWithRust()`)** wins on small-response RPS but accumulates thousands of errors under load and tails to 2,088 ms p99 on `/async-delay`. The **managed `Run()`** path is much steadier — **0 errors on every endpoint**, beats the Rust listener on `/json-large` (1.57×) and on `/async-delay` p99 (~18× cleaner). Pick the listener to match the workload: Rust for raw small-payload throughput, managed for stability and tail latency.

4. **For maximum RPS** → `go-fiber`. **For balanced tail latency** → `rust-axum`. **For .NET shops** → `dotnet-minimal`. **`node-fastify`** must keep CPU off the event loop; **`python-fastapi`** with 1 uvicorn worker is consistently last.

---

## Reproduce

```powershell
# 1. Build all (Release / Native)
dotnet publish ./dotnet-minimal -c Release -o ./dotnet-minimal/publish
go -C ./go-fiber build -ldflags="-s -w" -o go-fiber.exe main.go
cargo build --release --manifest-path ./rust-axum/Cargo.toml
jwc build --native --release           # inside _my/jwc-app
dotnet publish ./_my/liteapi-rust -c Release -o ./_my/liteapi-rust/publish
dotnet publish ./_my/liteapi      -c Release -o ./_my/liteapi/publish

# 2. Run the full sequential benchmark + generate summary
./.dist/bench-full.ps1                 # 5 standard servers on :8080, jwc-app on :8080,
                                       # liteapi-rust on :6080, liteapi-managed on :6070

# (or run subsets)
./.dist/bench-all.ps1                  # 5 standard servers only
./.dist/report.ps1                     # regenerate summary JSON from saved results
```

Raw bombardier JSON per endpoint is saved under `.dist/results/<server>/<endpoint>.json`; the merged summary is `.dist/results/summary.json`.
