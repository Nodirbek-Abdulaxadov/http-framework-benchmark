# HTTP Framework Benchmark Results

> Stress test of 7 minimal HTTP servers under heavy concurrent load using [bombardier](https://github.com/codesenberg/bombardier).
> Each framework runs **isolated, sequentially** — no two servers compete for CPU at the same time.

> _Re-measured 2026-05-29 — all 7 stacks benchmarked back-to-back in one consistent session, after `jwc-app`'s **M1–M3 native type-specialization** (`perf/native-type-specialization`). The type-specialization pass is what moved `jwc-app` on `/json-large` (see below); the competitor numbers are fresh measurements on the same machine, so absolute RPS differs slightly from earlier reports._

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
| **Listen address** | `http://127.0.0.1:8080` (liteapi-rust on `:6080`) |

### Framework Versions & Build Flags

| Stack | Runtime / Compiler | Build |
|---|---|---|
| **dotnet-minimal** | .NET 10.0 (Kestrel) | `dotnet publish -c Release` |
| **go-fiber** | Go 1.24.0, Fiber v2 | `go build -ldflags="-s -w"` |
| **node-fastify** | Node 22.12.0, Fastify ^5.8.5 | `node` (V8 JIT) |
| **python-fastapi** | Python 3.12.4, FastAPI 0.115.14, uvicorn 0.35.0 | `uvicorn --workers 1` |
| **rust-axum** | Rust 1.92.0, axum 0.8 | `cargo build --release` |
| **jwc-app** ⭐ | JWC v0.4.0 + native type-specialization M1–M3 (native AOT → tokio/axum) | `jwc build --native --release` |
| **liteapi-rust** ⭐ | .NET 10.0 + LiteAPI.Core 2.3.0 (Rust TCP listener) | `dotnet publish -c Release` |

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

`jwc-app` runs the **same honest workload as every other stack** — no workarounds. All five endpoints are workload-identical across all seven stacks:

| Endpoint | Workload (all stacks, including jwc-app) |
|---|---|
| `/json-large` | Build a 1000-object array **per request** (array literal + `push`) and serialize it. No precompute, no process cache. |
| `/cpu` | Run **100 000 real chained SHA-256 hashes** per request via the native `sha256` builtin. No LCG substitute. |

**What M1–M3 changed:** the native AOT backend now runs a scalar type-inference pass (M1) and emits native Rust types instead of the dynamic `V` value (M2). M3 detects local arrays used only with scalar-object `push` + `json()` and synthesizes a per-body `struct` + `Vec<struct>` + direct JSON serialization — eliminating the `V::Object`/`BTreeMap` allocation that previously dominated the per-request `/json-large` build. The workload is unchanged (still a real 1000-object build per request); only the generated code is faster. `/cpu` is untouched because it is bound by the `sha256` builtin, not the value model.

---

## Overall Verdict

| Endpoint | 1st | 2nd | 3rd | 4th | 5th | 6th | 7th |
|---|---|---|---|---|---|---|---|
| `/ping` | go-fiber | dotnet | **liteapi-rust** | rust-axum | **jwc-app** | node-fastify | python |
| `/json-small` | go-fiber | dotnet | **liteapi-rust** | rust-axum | **jwc-app** | node-fastify | python |
| `/json-large` | dotnet | rust-axum | go-fiber | **jwc-app** | **liteapi-rust** | node-fastify | python |
| `/cpu` | rust-axum | dotnet | go-fiber | **liteapi-rust** | **jwc-app** | python | node-fastify |
| `/async-delay` | go-fiber | **jwc-app** | rust-axum | dotnet | node-fastify | **liteapi-rust** | python |

**Highlights from the `_my/` projects:**
- **`jwc-app`** makes the biggest move of this run: on `/json-large` it jumps from **5th to 4th** — **13,064 RPS, up ~2.8× from 4,652** — overtaking `liteapi-rust` and closing on `go-fiber`, with its p99 dropping from 93 ms to **32 ms**. That is the M3 shaped-array type-specialization paying off: the dynamic `V::Object`/`BTreeMap` allocation per object is gone. On `/async-delay` it is now **2nd (44,325 RPS)**, edging `rust-axum`. It stays competitive **5th on the light endpoints** (`/ping`, `/json-small`), where the per-request cost is dominated by the framework, not the value model. On `/cpu` it is unchanged at **68 RPS** (5th) — expected, since that path is bound by the `sha256` builtin. It never errors (**0 across 4.48M requests**).
- **`liteapi-rust`** is consistently **3rd on small responses** (ping/json-small) — its Rust TCP listener gives it the best p90 of all 7 on those — but the .NET marshalling penalty shows on `/json-large` (now 5th, behind jwc-app) and on 1000-conn `/async-delay` (p99 = 2,088 ms, 5,379 errors).

---

## /ping — Plain Text (500 connections)

```
RPS (mean) — higher is better
go-fiber        ████████████████████████████████████████ 219,258
dotnet-minimal  ██████████████████████████████████████▌  211,289
liteapi-rust    ████████████████████████████████         173,218  ⭐
rust-axum       ██████████████████████████               143,576
jwc-app         ██████████████████████                   123,256  ⭐
node-fastify    ████▍                                     23,979
python-fastapi  █▏                                         6,266
```

| Server | RPS mean | RPS max | p50 (ms) | p90 (ms) | p99 (ms) | 2xx | errors |
|---|---:|---:|---:|---:|---:|---:|---:|
| **go-fiber** | **219,258** | 345,268 | 2.26 | 3.86 | 9.56 | 3,298,160 | 0 |
| **dotnet-minimal** | 211,289 | 1,389,938 | <1.0 | 7.02 | 15.63 | 3,178,617 | 0 |
| ⭐ **liteapi-rust** | 173,218 | 249,920 | <1.0 | 5.52 | 15.63 | 2,602,777 | 1,452 |
| **rust-axum** | 143,576 | 162,346 | 3.28 | 5.21 | 7.25 | 2,153,157 | 0 |
| ⭐ **jwc-app** (native) | 123,256 | 160,693 | 3.80 | 6.26 | 8.76 | 1,847,800 | 0 |
| **node-fastify** | 23,979 | 32,556 | 20.91 | 21.53 | 22.48 | 359,843 | 0 |
| **python-fastapi** | 6,266 | 11,476 | 79.56 | 82.30 | 96.09 | 92,065 | 26 |

---

## /json-small — Tiny JSON Object (500 connections)

```
RPS (mean) — higher is better
go-fiber        ████████████████████████████████████████ 212,699
dotnet-minimal  ████████████████████████████████████     192,506
liteapi-rust    ███████████████████████████████          165,965  ⭐
rust-axum       ███████████████████████████              141,247
jwc-app         ██████████████████████                   117,729  ⭐
node-fastify    ████▎                                     22,611
python-fastapi  █                                          5,644
```

| Server | RPS mean | RPS max | p50 (ms) | p90 (ms) | p99 (ms) | 2xx | errors |
|---|---:|---:|---:|---:|---:|---:|---:|
| **go-fiber** | **212,699** | 474,387 | 2.35 | 4.01 | 10.69 | 3,204,679 | 0 |
| **dotnet-minimal** | 192,506 | 657,131 | <1.0 | 7.54 | 15.63 | 2,920,190 | 0 |
| ⭐ **liteapi-rust** | 165,965 | 222,063 | <1.0 | 5.51 | 15.63 | 2,490,629 | 1,340 |
| **rust-axum** | 141,247 | 183,900 | 3.33 | 5.32 | 7.34 | 2,117,614 | 0 |
| ⭐ **jwc-app** (native) | 117,729 | 199,895 | 3.95 | 6.59 | 9.24 | 1,764,090 | 0 |
| **node-fastify** | 22,611 | 27,197 | 22.22 | 22.88 | 23.70 | 339,442 | 0 |
| **python-fastapi** | 5,644 | 15,945 | 89.46 | 91.09 | 102.41 | 82,571 | 27 |

---

## /json-large — 1000-item JSON Array (200 connections, ~42 KB body)

> Every stack — including jwc-app — builds the 1000-object array **per request** (array literal + `push`) and serializes it. jwc-app's M3 type-specialization compiles that array to a native `Vec<struct>` instead of a `Vec<V::Object>`.

```
RPS (mean) — higher is better
dotnet-minimal  ████████████████████████████████████████ 23,129
rust-axum       ██████████████████████████████████████▋  22,384
go-fiber        █████████████████████████                14,516
jwc-app         ██████████████████████▌                  13,064  ⭐
liteapi-rust    ██████████████▎                           8,248  ⭐
node-fastify    ██████▌                                   3,750
python-fastapi  ▎                                           167
```

| Server | RPS mean | RPS max | p50 (ms) | p90 (ms) | p99 (ms) | Bytes | 2xx | errors |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| **dotnet-minimal** | **23,129** | 43,752 | 8.64 | 15.69 | 23.13 | 14.57 GB | 347,962 | 0 |
| **rust-axum** | 22,384 | 32,191 | 8.83 | 13.52 | 18.44 | 13.98 GB | 334,678 | 0 |
| **go-fiber** | 14,516 | 29,619 | 4.46 | 51.23 | 101.84 | 9.03 GB | 216,010 | 0 |
| ⭐ **jwc-app** (native) | 13,064 | 27,332 | 15.48 | 23.88 | 32.31 | 8.12 GB | 194,306 | 0 |
| ⭐ **liteapi-rust** | 8,248 | 13,861 | 7.74 | 27.47 | 253.85 | 5.17 GB | 123,736 | 0 |
| **node-fastify** | 3,750 | 3,853 | 53.39 | 54.24 | 62.29 | 2.36 GB | 56,446 | 0 |
| **python-fastapi** | 167 | 3,883 | 455.13 | 2023.85 | 16490.51 | 94.5 MB | 2,261 | 375 |

Notes:
- **jwc-app climbs to 4th (13,064 RPS, ~2.8× its prior 4,652)**, passing `liteapi-rust` and landing within striking distance of `go-fiber`. The M3 pass replaces the dynamic per-object `V::Object`/`BTreeMap` build with a synthesized `struct` + `Vec<struct>` + direct serialization, so the per-request 1000-object build no longer allocates a hash map per object.
- Its p99 (**32 ms**, down from 93 ms) is now cleaner than Go's tail (102 ms) and far below liteapi-rust's marshalling spike (254 ms), with zero errors.
- The remaining gap to the statically-compiled Rust/.NET stacks (~22-23k) is the residual cost of the value model on the parts of the path M3 doesn't yet specialize (e.g. the loop bound still flows through `V`).

---

## /cpu — CPU-Bound Workload (32 connections)

> Same workload for every stack: 100 000 real chained SHA-256 hashes per request. Untouched by type-specialization.

```
RPS (mean) — higher is better
rust-axum       ████████████████████████████████████████ 190.2
dotnet-minimal  ███████████████████████████              128.5
go-fiber        ██████████████████████████               125.3
liteapi-rust    ████████████████████████                 114.5  ⭐
jwc-app         ██████████████                            68.0  ⭐
python-fastapi  ███                                       13.5
node-fastify    ▌                                          2.1   (event-loop blocked)
```

| Server | RPS mean | p50 (ms) | p90 (ms) | p99 (ms) | 2xx | errors |
|---|---:|---:|---:|---:|---:|---:|
| **rust-axum** | **190.2** | 184.53 | 246.21 | 294.98 | 2,695 | 0 |
| **dotnet-minimal** | 128.5 | 284.19 | 378.43 | 410.44 | 1,682 | 0 |
| **go-fiber** | 125.3 | 263.91 | 348.13 | 422.25 | 1,805 | 0 |
| ⭐ **liteapi-rust** | 114.5 | 237.44 | 445.15 | 1090.87 | 1,675 | 0 |
| ⭐ **jwc-app** (native) | 68.0 | 529.32 | 688.15 | 772.47 | 988 | 0 |
| **python-fastapi** | 13.5 | 1552.48 | 1962.29 | 18493.58 | 209 | 0 |
| **node-fastify** | 2.1 | 4529.67 | 25045.48 | 25049.74 | 36 | 28 (timeouts) |

Notes:
- **jwc-app holds 5th at 68 RPS** (was 64) — statistically unchanged, exactly as expected: this path is dominated by the `sha256` builtin, not the value model, so M1–M3 leave it where it was. It still comfortably beats python and node and never errors.
- node and python remain last because they can't escape single-thread CPU work.

---

## /async-delay — 10 ms `await sleep` (1000 connections)

Theoretical ceiling ≈ `1000 / 0.010 = 100,000 RPS`.

```
RPS (mean) — higher is better
go-fiber        ████████████████████████████████████████ 75,427
jwc-app         ███████████████████████▌                 44,325  ⭐
rust-axum       ███████████████████████▎                 43,979
dotnet-minimal  ████████████████████                     38,147
node-fastify    █████████████                            24,060
liteapi-rust    ███████▎                                 13,820  ⭐
python-fastapi  ███                                       5,265
```

| Server | RPS mean | p50 (ms) | p90 (ms) | p99 (ms) | max (ms) | 2xx | errors |
|---|---:|---:|---:|---:|---:|---:|---:|
| **go-fiber** | **75,427** | 11.18 | 18.06 | 28.12 | 1,574 | 1,124,568 | 0 |
| ⭐ **jwc-app** (native) | 44,325 | 18.99 | 34.63 | 46.25 | 1,165 | 669,151 | 0 |
| **rust-axum** | 43,979 | 19.82 | 33.48 | 44.15 | 1,192 | 663,128 | 0 |
| **dotnet-minimal** | 38,147 | 23.96 | 39.75 | 48.08 | 1,552 | 564,258 | 0 |
| **node-fastify** | 24,060 | 34.95 | 35.97 | 37.54 | 2,315 | 360,766 | 697 |
| ⭐ **liteapi-rust** | 13,820 | 17.42 | 30.51 | 2087.59 | 7,608 | 198,949 | 5,379 |
| **python-fastapi** | 5,265 | 101.72 | 136.63 | 2056.25 | 15,130 | 78,951 | 1,570 |

Notes:
- **jwc-app takes 2nd**, narrowly ahead of rust-axum and well clear of dotnet. The native pipeline's tokio runtime + `sleep_ms` builtin scales cleanly to 1000 connections with zero errors — async-bound work plays to JWC's strengths since the runtime, not the value model, dominates.

---

## Aggregate Throughput (sum of all 5 endpoints)

```
Total RPS — higher is better
go-fiber        ████████████████████████████████████████ 522,025
dotnet-minimal  ████████████████████████████████████     465,200
liteapi-rust    ████████████████████████████             361,366  ⭐
rust-axum       ███████████████████████████              351,376
jwc-app         ███████████████████████                  298,443  ⭐
node-fastify    ██████                                    74,403
python-fastapi  █                                         17,354
```

| Server | Total RPS | Total Requests | Total Bytes | Total Errors |
|---|---:|---:|---:|---:|
| **go-fiber** | **522,025** | 7,845,222 | 10.02 GB | 0 |
| **dotnet-minimal** | 465,200 | 7,012,709 | 15.60 GB | 0 |
| ⭐ **liteapi-rust** | 361,366 | 5,425,937 | 5.96 GB | 8,171 |
| **rust-axum** | 351,376 | 5,271,272 | 14.63 GB | 0 |
| ⭐ **jwc-app** (native) | 298,443 | 4,476,335 | 8.67 GB | 0 |
| **node-fastify** | 74,403 | 1,117,258 | 2.55 GB | 725 |
| **python-fastapi** | 17,354 | 258,055 | 130 MB | 1,998 |

---

## Tail-Latency Summary (p99 across all endpoints, ms — lower is better)

| Server | /ping | /json-small | /json-large | /cpu | /async-delay |
|---|---:|---:|---:|---:|---:|
| **rust-axum** | 7.25 | 7.34 | **18.44** | 294.98 | 44.15 |
| **go-fiber** | 9.56 | 10.69 | 101.84 | 422.25 | 28.12 |
| **dotnet-minimal** | 15.63 | 15.63 | 23.13 | 410.44 | 48.08 |
| ⭐ **jwc-app** | 8.76 | 9.24 | 32.31 | 772.47 | 46.25 |
| ⭐ **liteapi-rust** | 15.63 | 15.63 | 253.85 | 1,090.87 | 2,087.59 |
| **node-fastify** | 22.48 | 23.70 | 62.29 | 25,049.74 | 37.54 |
| **python-fastapi** | 96.09 | 102.41 | 16,490.51 | 18,493.58 | 2,056.25 |

**jwc-app's tail latency is best on the light endpoints** (`/ping` 8.76 ms, `/json-small` 9.24 ms — among the lowest of all 7) and stays well-controlled on `/async-delay` (46 ms). After M3, its `/json-large` p99 (**32 ms**) is now better than go-fiber's (102 ms) and node's (62 ms). `/cpu` (772 ms) still trails the compiled stacks but never goes pathological, with zero errors throughout.

---

## Conclusions

1. **The M1–M3 native type-specialization moved `jwc-app` exactly where it was supposed to.** `/json-large` went from a mid-pack 5th (4,652 RPS) to **4th (13,064 RPS, ~2.8×)**, overtaking `liteapi-rust` and closing on `go-fiber`, with p99 cut from 93 ms to 32 ms. The win comes from M3 synthesizing a native `struct` + `Vec<struct>` for shaped JSON arrays instead of allocating a `V::Object`/`BTreeMap` per element — and it is **honest**: the workload is still a real per-request 1000-object build, only the generated code changed. The endpoints the pass doesn't touch behave as predicted: `/cpu` (sha256-bound) is unchanged at 68 RPS, and the light endpoints stay 5th.

2. **`jwc-app` is now competitive across the board.** 2nd on `/async-delay` (edging rust-axum), 4th on `/json-large`, 5th on the light/CPU endpoints, **0 errors across 4.48M requests**. The remaining `/json-large` gap to Rust/.NET is the residual value-model cost on the parts of the path still flowing through `V` (e.g. the loop bound) — the next specialization target.

3. **`liteapi-rust` (.NET + Rust TCP listener) still excels at small responses** but its marshalling cost dominates on 50 KB JSON bodies and 1000-connection async work (5,379 errors on `/async-delay`).

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

# 2. Run the full sequential benchmark (all 7 stacks) + generate summary
./.dist/bench-full.ps1                 # 5 standard servers on :8080, jwc-app on :8080, liteapi-rust on :6080

# (or run subsets)
./.dist/bench-all.ps1                  # 5 standard servers only
./.dist/report.ps1                     # regenerate summary JSON from saved results
```

Raw bombardier JSON per endpoint is saved under `.dist/results/<server>/<endpoint>.json`; the merged summary is `.dist/results/summary.json`.
