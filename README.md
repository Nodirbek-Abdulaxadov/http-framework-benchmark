# HTTP Framework Benchmark Results

> Stress test of 8 minimal HTTP servers under heavy concurrent load using [bombardier](https://github.com/codesenberg/bombardier).
> Each framework runs **isolated, sequentially** — no two servers compete for CPU at the same time, and every stack is measured back-to-back in one session on the same machine.

> **Current snapshot — 2026-07-28.** All 8 stacks × 8 endpoints, one server at a time, 15 s per endpoint after a 3 s warm-up. Two things changed since the previous snapshot:
>
> 1. **The DB tier is now cross-stack.** `/db`, `/queries` and `/updates` were previously implemented only by `jwc-app`, so the other seven stacks answered 404 and the numbers meant nothing. All eight now run the same TechEmpower-shaped workload against the same `world(id, randomnumber)` table in the same Postgres instance, each with its pool capped at 64.
> 2. **`jwc-app` moved to JWC v0.8.0.** `jwc build --native --release` works again. Its `/updates` route goes through `raw_sql` rather than `update … set`, because the native backend cannot bind a value into an `int` column.
>
> **2026-09-15/16 — `jwc-app` rewritten for JWC 1.0.0-rc.4, re-measured on rc.5.** `_my/jwc-app` now uses the 1.0 language (`namespace`/`database`/`table`/`routes`/`service`, `jwc build --release`, `jwc migrate` + a data sidecar) and its `/updates` route is back on idiomatic `update … set` — the `int`-column bug is gone. The `raw_sql` notes below describe the 0.8.0 build the Windows numbers were taken on, not the current source. See the [Linux re-run](#linux-re-run--2026-09-15) for current numbers.
>
> Rankings are stated in **2xx/s** — successful responses per second — not bombardier's `rps`. On this Windows box the 500- and 1000-connection endpoints generate large numbers of client-side `dial tcp: connectex: actively refused` failures from ephemeral-port exhaustion, and bombardier counts those attempts in `rps`. The two figures agree closely at 64 connections and diverge sharply at 1000, where `node-fastify` reports 16,606 rps against **80** successful responses.

---

## Test Environment

| Component | Spec |
|---|---|
| **CPU** | Intel Core i5-10400 @ 2.90 GHz (6 cores / 12 threads) |
| **RAM** | 32 GB |
| **OS** | Windows 11 Pro (10.0.22631) |
| **Bombardier** | v1.2.6 (windows/amd64, fasthttp client) |
| **Postgres** | 5432, database `BenchJWCDB`, `world` table seeded with 10,000 rows |
| **Test duration** | 15 s per endpoint (after 3 s warm-up) |
| **Timeout** | 5 s |
| **Listen address** | `http://127.0.0.1:8080` (liteapi-rust on `:6080`, liteapi-managed on `:6070`, jwc-app on `http://[::1]:8080`) |

`jwc-app` is reached over IPv6 because its native binary binds `[::]` and Windows
defaults `IPV6_V6ONLY` to on, making `127.0.0.1` unreachable. Loopback IPv6 and
IPv4 perform equivalently here; `.dist/bench.ps1` takes a `-BindHost` parameter
for exactly this case.

### Framework Versions & Build Flags

| Stack | Runtime / Compiler | DB driver | Build |
|---|---|---|---|
| **dotnet-minimal** | .NET 10.0 (Kestrel) | Npgsql 9.0.3 | `dotnet publish -c Release` |
| **go-fiber** | Go 1.24.0, Fiber v2 | pgx/v5 5.10.0 | `go build -ldflags="-s -w"` |
| **node-fastify** | Node 22.12.0, Fastify ^5.8.5 | pg 8.22.0 | `node` (V8 JIT) |
| **python-fastapi** | Python 3.12.4, FastAPI 0.115.14, uvicorn 0.35.0 | asyncpg 0.31.0 | `uvicorn --workers 1` |
| **rust-axum** | Rust 1.92.0, axum 0.8 | tokio-postgres 0.7 + deadpool 0.14 | `cargo build --release` |
| **jwc-app** ⭐ | JWC 1.0.0-rc.5 (native AOT → tokio/axum); Windows numbers below are from v0.8.0 | built-in (`database … : Postgres`) | `jwc build --release` |
| **liteapi-rust** ⭐ | .NET 10.0 + LiteAPI.Core 2.3.0 (Rust TCP listener — `RunWithRust()`) | Npgsql 9.0.3 | `dotnet publish -c Release` |
| **liteapi-managed** ⭐ | .NET 10.0 + LiteAPI.Core 2.3.0 (managed `Run()`) | Npgsql 9.0.3 | `dotnet publish -c Release` |

⭐ = your own projects under `_my/`.

### Endpoints

| Path | Workload | Connections |
|---|---|---|
| `/ping` | Plain text `"pong"` | **500** |
| `/json-small` | 3-field JSON object | **500** |
| `/json-large` | Array of 1000 JSON objects (~42 KB) | **200** |
| `/cpu` | 100,000 chained SHA-256 hashes | **32** |
| `/async-delay` | `await sleep(10 ms)` | **1000** |
| `/db` | One row by random id | **64** |
| `/queries?queries=20` | 20 rows by random id | **64** |
| `/updates?queries=20` | 20 rows read, then written back | **64** |

### Workload parity

Every stack runs the identical workload — no stack gets a shortcut:

| Endpoint | Workload (all stacks) |
|---|---|
| `/json-large` | Build a 1000-object array **per request** and serialize it. No precompute, no process cache. |
| `/cpu` | Run **100,000 real chained SHA-256 hashes** per request. No arithmetic substitute. |
| `/db`, `/queries` | `SELECT id, randomnumber FROM world WHERE id = $1`, one round-trip per row, ids drawn across the full 1..10,000 range. |
| `/updates` | Same read, then `UPDATE world SET randomnumber = $1 WHERE id = $2` per row. |
| `?queries=` | Missing or unparsable → 1; the value is clamped to 1..500. |

Seven stacks draw ids from their language's RNG. `jwc-app` derives them
arithmetically from `now()` (`ss * 1000 + mmm`, scrambled per iteration)
because JWC's native backend has no RNG builtin — the per-request database
work is identical, only the id source differs.

**The `world` table is reset before every server** (`TRUNCATE` + reseed +
`VACUUM FULL`, autovacuum disabled on the table — see [`.dist/reset-db.js`](.dist/reset-db.js)).
This matters: `/updates` rewrites ~500k rows per 15 s window, and in an earlier
session an autovacuum that happened to fire during `dotnet-minimal`'s DB tier
cost it **5.8× on `/db`** (7,423 vs 42,913 2xx/s) purely from run order.

---

## Overall Verdict

Ranked by successful responses per second:

| Endpoint | 1st | 2nd | 3rd | 4th | 5th | 6th | 7th | 8th |
|---|---|---|---|---|---|---|---|---|
| `/ping` | go-fiber | dotnet | **jwc-app** | rust-axum | **liteapi-rust** | **liteapi-managed** | node | python |
| `/json-small` | go-fiber | dotnet | rust-axum | **jwc-app** | **liteapi-rust** | **liteapi-managed** | node | python |
| `/json-large` | dotnet | rust-axum | **jwc-app** | go-fiber | **liteapi-managed** | **liteapi-rust** | node | python |
| `/cpu` | rust-axum | go-fiber | **jwc-app** | dotnet | **liteapi-rust** | **liteapi-managed** | python | node |
| `/async-delay` | **jwc-app** | rust-axum | **liteapi-rust** | **liteapi-managed** | go-fiber | dotnet | python | node |
| `/db` | go-fiber | rust-axum | **jwc-app** | dotnet | **liteapi-rust** | **liteapi-managed** | node | python |
| `/queries` | go-fiber | rust-axum | **jwc-app** | dotnet | **liteapi-rust** | **liteapi-managed** | node | python |
| `/updates` | go-fiber | rust-axum | **jwc-app** | dotnet | **liteapi-rust** | **liteapi-managed** | node | python |

**Highlights:**

- **`jwc-app` wins `/async-delay`** at 20,453 2xx/s, 7% ahead of `rust-axum`, and takes **3rd on six of the eight endpoints**. It is the most consistent stack in the suite: never below 3rd except `/json-small` (4th, 0.7% behind rust-axum).
- **`jwc-app` is level with hand-written `rust-axum` on the read-only DB tier** — `/db` 51,535 vs 52,565 (−2.0%), `/queries` 5,198 vs 5,263 (−1.2%), with a marginally *better* `/queries` p99 (18.69 vs 18.99 ms). For a server the compiler generates rather than one written by hand, that is the standout result.
- **`jwc-app` ties `rust-axum` exactly on `/ping`** — 127,723 vs 127,722 2xx/s. Its tail is worse there (22.44 vs 8.48 ms p99).
- **`go-fiber` wins the DB tier outright** — 66,018 2xx/s on `/db`, 26% ahead of the next stack — and the aggregate. pgx's binary protocol and Fiber's low per-request overhead compound.
- **`liteapi-managed` is the only stack with zero errors on every endpoint**, all 8/8, including 1000-connection `/async-delay`. It gives up roughly a third of `liteapi-rust`'s light-endpoint throughput to get there.
- **`node-fastify` and `python-fastapi` collapse at 1000 connections** — 80 and 6,908 successful responses respectively, against ~249k and ~235k attempts. Their `rps` figures on that endpoint are almost entirely failed dials.

### Note on `jwc-app`'s `/updates` implementation

Every other stack writes with its driver's ordinary parameterised update.
`jwc-app` cannot: JWC v0.8.0's native codegen binds the SET value as text
(`jwc_param_str`), or as `int8` when it is a literal, so an `int4` column is
unwritable and the request panics its worker thread. The working form is
`raw_sql`, which types parameters from the runtime value:

```jwc
raw_sql("UPDATE world SET randomnumber = $1 WHERE id = $2",
        "[" + new_val + "," + id + "]");
```

The workload is therefore equivalent — one `UPDATE` per row, same table, same
parameters — but `jwc-app` additionally builds a short JSON string per row,
which the others do not. At ~32 ms per request that overhead is not material,
but it is a real difference and worth stating.

An earlier revision of this benchmark reported 0 successful responses for this
endpoint. That was a mistake on my side: `raw_sql` had been called with the
parameters as separate arguments (`raw_sql(sql, v, id)`), a form that compiles
and returns 200 while silently discarding the query. Its own defect, now
documented as #2 in the bug write-up.

---

## /ping — Plain Text (500 connections)

```
Successful RPS (2xx/s) — higher is better
go-fiber         ████████████████████████████████████████ 197,311
dotnet-minimal   ████████████████████████████████         156,705
jwc-app          ██████████████████████████               127,723  ⭐
rust-axum        ██████████████████████████               127,722
liteapi-rust     █████████████████                        84,833  ⭐
liteapi-managed  ███████████                              54,085  ⭐
node-fastify     ████                                     20,503
python-fastapi   █                                        4,202
```

| Server | 2xx/s | RPS mean* | p50 (ms) | p90 (ms) | p99 (ms) | 2xx | non-2xx | client errors |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| **go-fiber** | **197,311** | 198,901 | <1.0 | 1.00 | 1.53 | 2,960,369 | 15,538 | 15,538 |
| **dotnet-minimal** | 156,705 | 157,541 | <1.0 | 1.01 | 4.93 | 2,352,688 | 18,938 | 18,938 |
| ⭐ **jwc-app** | 127,723 | 129,865 | 3.17 | 5.49 | 22.44 | 1,916,291 | 30,727 | 30,727 |
| **rust-axum** | 127,722 | 127,936 | 3.72 | 5.87 | 8.48 | 1,916,266 | 69 | 69 |
| ⭐ **liteapi-rust** | 84,833 | 116,383 | 2.35 | 3.96 | 42.97 | 1,664,036 | 80,754 | 80,754 |
| ⭐ **liteapi-managed** | 54,085 | 54,075 | 10.47 | 12.15 | 24.29 | 811,754 | 0 | 0 |
| **node-fastify** | 20,503 | 22,158 | 21.98 | 24.02 | 29.16 | 307,994 | 24,509 | 24,509 |
| **python-fastapi** | 4,202 | 9,421 | 23.14 | 85.87 | 107.12 | 63,361 | 78,340 | 78,340 |

\* bombardier's `rps`, which counts failed dial attempts as requests.

`jwc-app` and `rust-axum` land 1 request/s apart — 1,916,291 vs 1,916,266
successful responses. They get there differently: rust-axum took **69** client
errors, jwc-app 30,727, and rust-axum's tail is 2.6× tighter.
`liteapi-rust` shows the widest gap between the two throughput columns — 116,383
rps against 84,833 successful, i.e. over a quarter of its attempts never completed.

---

## /json-small — Tiny JSON Object (500 connections)

```
Successful RPS (2xx/s) — higher is better
go-fiber         ████████████████████████████████████████ 192,866
dotnet-minimal   ███████████████████████████████          150,530
rust-axum        ██████████████████████████               125,890
jwc-app          ██████████████████████████               124,984  ⭐
liteapi-rust     ████████████████████████                 114,405  ⭐
liteapi-managed  ███████████                              53,281  ⭐
node-fastify     ████                                     19,464
python-fastapi   █                                        3,711
```

| Server | 2xx/s | RPS mean* | p50 (ms) | p90 (ms) | p99 (ms) | 2xx | non-2xx | client errors |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| **go-fiber** | **192,866** | 193,570 | <1.0 | 1.01 | 2.36 | 2,893,729 | 12,327 | 12,327 |
| **dotnet-minimal** | 150,530 | 152,123 | <1.0 | 1.00 | 80.01 | 2,260,631 | 25,141 | 25,141 |
| **rust-axum** | 125,890 | 126,086 | 3.76 | 5.99 | 8.82 | 1,888,720 | 408 | 408 |
| ⭐ **jwc-app** | 124,984 | 127,648 | 3.11 | 5.62 | 25.49 | 1,875,275 | 32,534 | 32,534 |
| ⭐ **liteapi-rust** | 114,405 | 119,602 | 1.74 | 3.45 | 40.48 | 1,716,371 | 71,643 | 71,643 |
| ⭐ **liteapi-managed** | 53,281 | 53,305 | 10.62 | 12.74 | 22.44 | 799,602 | 0 | 0 |
| **node-fastify** | 19,464 | 21,004 | 23.52 | 24.86 | 32.22 | 292,426 | 22,364 | 22,364 |
| **python-fastapi** | 3,711 | 9,307 | 19.86 | 93.24 | 110.60 | 55,924 | 83,990 | 83,990 |

Serializing three fields costs almost nothing anywhere; the deltas are within a
few percent of `/ping`. `dotnet-minimal`'s p99 of 80.01 ms against a p90 of
1.00 ms is an outlier spike, not a sustained cost.

---

## /json-large — 1000-item JSON Array (200 connections, ~42 KB body)

> Every stack builds the 1000-object array **per request** and serializes it.

```
Successful RPS (2xx/s) — higher is better
dotnet-minimal   ████████████████████████████████████████ 20,439
rust-axum        ████████████████████████████████████████ 20,352
jwc-app          █████████████████████████████            14,645  ⭐
go-fiber         ███████████████████████████              13,737
liteapi-managed  █████████████████████                    10,917  ⭐
liteapi-rust     ██████████████                           7,134  ⭐
node-fastify     ███████                                  3,603
python-fastapi   █                                        114
```

| Server | 2xx/s | RPS mean* | p50 (ms) | p90 (ms) | p99 (ms) | 2xx | non-2xx | client errors |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| **dotnet-minimal** | **20,439** | 20,184 | 9.60 | 13.29 | 26.18 | 306,630 | 0 | 0 |
| **rust-axum** | 20,352 | 20,453 | 9.56 | 14.48 | 20.07 | 305,461 | 0 | 0 |
| ⭐ **jwc-app** | 14,645 | 14,783 | 13.37 | 20.01 | 27.72 | 219,717 | 0 | 0 |
| **go-fiber** | 13,737 | 13,930 | 4.54 | 50.06 | 102.78 | 206,258 | 0 | 0 |
| ⭐ **liteapi-managed** | 10,917 | 10,927 | 14.21 | 38.56 | 68.06 | 163,991 | 0 | 0 |
| ⭐ **liteapi-rust** | 7,134 | 7,636 | 8.68 | 34.43 | 413.84 | 107,192 | 7,416 | 7,416 |
| **node-fastify** | 3,603 | 3,603 | 56.83 | 61.48 | 74.75 | 54,238 | 0 | 0 |
| **python-fastapi** | 114 | 8,603 | 6.79 | 11.03 | 521.02 | 1,910 | 127,450 | 127,450 |

Notes:
- 200 connections is low enough that most stacks take **zero** client errors, so the two throughput columns agree — this is the cleanest comparison in the suite.
- `dotnet-minimal` and `rust-axum` finish 0.4% apart at the top.
- `jwc-app` is 3rd at 14,645, 6.6% clear of `go-fiber`, and holds a far tighter tail (p99 27.72 ms vs 102.78). The gap to dotnet/rust is the cost of the dynamic value model on the per-request object-build path.
- `liteapi-managed` beats `liteapi-rust` by **1.53×** here with p99 cut from 414 ms to 68 ms. The Rust listener's small-body advantage inverts once the response is 42 KB.
- `python-fastapi` effectively fails this endpoint: 1,910 successful responses against 127,450 failures.

---

## /cpu — CPU-Bound Workload (32 connections)

> Same workload for every stack: 100,000 real chained SHA-256 hashes per request.

```
Successful RPS (2xx/s) — higher is better
rust-axum        ████████████████████████████████████████ 166
go-fiber         ████████████████████████████             118
jwc-app          ██████████████████████████               109  ⭐
dotnet-minimal   ██████████████████████████               109
liteapi-rust     █████████████████████████                105  ⭐
liteapi-managed  ███████████████████████                  96  ⭐
python-fastapi   ██                                       10
node-fastify     █                                        1
```

| Server | 2xx/s | RPS mean* | p50 (ms) | p90 (ms) | p99 (ms) | 2xx | non-2xx | client errors |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| **rust-axum** | **166** | 167 | 192.37 | 260.39 | 312.15 | 2,514 | 0 | 0 |
| **go-fiber** | 118 | 117 | 267.45 | 361.19 | 457.29 | 1,783 | 0 | 0 |
| ⭐ **jwc-app** | 109 | 109 | 295.71 | 400.28 | 470.57 | 1,669 | 0 | 0 |
| **dotnet-minimal** | 109 | 123 | 288.52 | 387.76 | 434.19 | 1,648 | 0 | 0 |
| ⭐ **liteapi-rust** | 105 | 104 | 245.30 | 500.50 | 964.52 | 1,598 | 0 | 0 |
| ⭐ **liteapi-managed** | 96 | 97 | 270.33 | 598.84 | 1,086.42 | 1,474 | 0 | 0 |
| **python-fastapi** | 10 | 11 | 1,571.43 | 2,371.60 | 18,957.31 | 196 | 0 | 0 |
| **node-fastify** | 1 | 2 | 25,001.86 | 25,003.98 | 25,004.49 | 26 | 31 | 31 |

Notes:
- `rust-axum` is 41% ahead of the pack; the digest itself dominates and everything from `go-fiber` down to `liteapi-managed` lands within **23%** of each other (96–118). Ranking inside that band is noise.
- `node-fastify` blocks its event loop and times out almost every request (26 successes in 15 s).

---

## /async-delay — 10 ms `await sleep` (1000 connections)

Theoretical ceiling ≈ `1000 / 0.010 = 100,000 RPS`.

```
Successful RPS (2xx/s) — higher is better
jwc-app          ████████████████████████████████████████ 20,453  ⭐
rust-axum        ██████████████████████████████████████   19,183
liteapi-rust     ███████████████████████████████          15,626  ⭐
liteapi-managed  █████████████████████████████            14,925  ⭐
go-fiber         █████████████████████████████            14,622
dotnet-minimal   █████████████                            6,568
python-fastapi   █                                        458
node-fastify     █                                        5
```

| Server | 2xx/s | RPS mean* | p50 (ms) | p90 (ms) | p99 (ms) | 2xx | non-2xx | client errors |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| ⭐ **jwc-app** | **20,453** | 31,941 | 16.11 | 52.64 | 64.37 | 307,178 | 172,575 | 172,575 |
| **rust-axum** | 19,183 | 31,174 | 16.29 | 52.71 | 63.79 | 288,336 | 180,028 | 180,028 |
| ⭐ **liteapi-rust** | 15,626 | 28,726 | 16.77 | 57.87 | 72.57 | 234,711 | 196,603 | 196,603 |
| ⭐ **liteapi-managed** | 14,925 | 14,939 | 63.15 | 78.60 | 93.94 | 224,671 | 0 | 0 |
| **go-fiber** | 14,622 | 29,137 | 13.09 | 54.11 | 60.14 | 219,714 | 215,953 | 215,953 |
| **dotnet-minimal** | 6,568 | 17,004 | 66.29 | 86.11 | 105.84 | 98,693 | 155,270 | 155,270 |
| **python-fastapi** | 458 | 16,090 | 47.92 | 59.16 | 298.60 | 6,908 | 234,517 | 234,517 |
| **node-fastify** | 5 | 16,606 | 55.29 | 60.09 | 80.76 | 80 | 248,743 | 248,743 |

Notes:
- This is the endpoint where the `rps`-vs-`2xx/s` distinction matters most. Read the `rps` column alone and `node-fastify` looks mid-pack at 16,606; it completed **80 requests**.
- `jwc-app` takes 1st at 20,453, 6.6% ahead of `rust-axum`, and completed 307,178 requests — the most of any stack — with a p99 within half a millisecond of rust-axum's.
- `liteapi-managed` is 4th on throughput **with zero errors**, the only stack to hold 1000 concurrent connections cleanly. Compare `liteapi-rust`: same application, Rust listener, 196,603 failed dials.

---

## /db — Single Random Row (64 connections)

```
Successful RPS (2xx/s) — higher is better
go-fiber         ████████████████████████████████████████ 66,018
rust-axum        ████████████████████████████████         52,565
jwc-app          ███████████████████████████████          51,535  ⭐
dotnet-minimal   ████████████████████████                 39,109
liteapi-rust     ███████████████████                      31,020  ⭐
liteapi-managed  █████████████                            22,050  ⭐
node-fastify     ██████                                   10,110
python-fastapi   █                                        2,463
```

| Server | 2xx/s | RPS mean* | p50 (ms) | p90 (ms) | p99 (ms) | 2xx | non-2xx | client errors |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| **go-fiber** | **66,018** | 65,994 | <1.0 | 1.51 | 2.97 | 990,459 | 0 | 0 |
| **rust-axum** | 52,565 | 52,587 | 1.14 | 1.75 | 2.49 | 788,522 | 0 | 0 |
| ⭐ **jwc-app** | 51,535 | 51,544 | 1.15 | 1.78 | 2.59 | 773,075 | 0 | 0 |
| **dotnet-minimal** | 39,109 | 39,114 | 1.46 | 2.33 | 6.05 | 586,658 | 0 | 0 |
| ⭐ **liteapi-rust** | 31,020 | 31,033 | 1.63 | 3.31 | 8.28 | 465,317 | 0 | 0 |
| ⭐ **liteapi-managed** | 22,050 | 22,092 | 1.69 | 8.60 | 16.06 | 330,761 | 0 | 0 |
| **node-fastify** | 10,110 | 10,112 | 6.07 | 6.83 | 9.72 | 151,697 | 0 | 0 |
| **python-fastapi** | 2,463 | 2,462 | 23.35 | 25.68 | 44.52 | 36,973 | 0 | 0 |

Notes:
- **Zero errors across all eight stacks** — 64 connections is well inside what Windows can sustain, so this and the other DB endpoints are the most trustworthy numbers in the suite.
- `go-fiber` + pgx is 26% ahead of second place.
- `jwc-app` sits 2.0% behind `rust-axum` on throughput and 0.1 ms behind on p99 — a tie. Both are ~32% ahead of Npgsql. A generated data layer keeping pace with hand-written `tokio-postgres` + `deadpool` is the headline result of this run.

---

## /queries — 20 Random Rows per Request (64 connections)

```
Successful RPS (2xx/s) — higher is better
go-fiber         ████████████████████████████████████████ 5,506
rust-axum        ██████████████████████████████████████   5,263
jwc-app          ██████████████████████████████████████   5,198  ⭐
dotnet-minimal   ███████████████████████                  3,104
liteapi-rust     █████████████████████                    2,908  ⭐
liteapi-managed  ████████████████████                     2,753  ⭐
node-fastify     ███████                                  1,011
python-fastapi   ████                                     534
```

| Server | 2xx/s | RPS mean* | p50 (ms) | p90 (ms) | p99 (ms) | 2xx | non-2xx | client errors |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| **go-fiber** | **5,506** | 5,506 | 10.14 | 14.03 | 61.59 | 82,678 | 0 | 0 |
| **rust-axum** | 5,263 | 5,264 | 11.84 | 13.89 | 18.99 | 78,978 | 0 | 0 |
| ⭐ **jwc-app** | 5,198 | 5,199 | 11.98 | 14.21 | 18.69 | 78,000 | 0 | 0 |
| **dotnet-minimal** | 3,104 | 3,106 | 19.61 | 25.23 | 37.18 | 46,598 | 0 | 0 |
| ⭐ **liteapi-rust** | 2,908 | 2,924 | 21.30 | 26.29 | 37.79 | 43,668 | 0 | 0 |
| ⭐ **liteapi-managed** | 2,753 | 2,765 | 22.48 | 28.71 | 40.26 | 41,331 | 0 | 0 |
| **node-fastify** | 1,011 | 1,007 | 61.84 | 67.30 | 88.22 | 15,168 | 0 | 0 |
| **python-fastapi** | 534 | 533 | 113.62 | 120.17 | 179.10 | 8,041 | 0 | 0 |

Notes:
- Twenty sequential round-trips per request; the ranking tracks per-round-trip driver overhead almost exactly.
- `jwc-app` is 1.2% behind `rust-axum` and has the **better p99 of the two** (18.69 vs 18.99 ms). Both are ~67% ahead of Npgsql.
- `go-fiber` leads on throughput but carries the **worst p99 of the three leaders** (61.59 ms vs ~19) — pgx's pool shows more jitter here than deadpool or JWC's built-in pool.

---

## /updates — 20 Read+Write Rows per Request (64 connections)

```
Successful RPS (2xx/s) — higher is better
go-fiber         ████████████████████████████████████████ 2,150
rust-axum        ████████████████████████████████████████ 2,129
jwc-app          ██████████████████████████████████       1,841  ⭐
dotnet-minimal   █████████████████████████                1,323
liteapi-rust     ████████████████████████                 1,272  ⭐
liteapi-managed  ██████████████████████                   1,201  ⭐
node-fastify     █████████                                497
python-fastapi   ██████                                   324
```

| Server | 2xx/s | RPS mean* | p50 (ms) | p90 (ms) | p99 (ms) | 2xx | non-2xx | client errors |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| **go-fiber** | **2,150** | 2,160 | 26.04 | 42.26 | 98.61 | 32,298 | 0 | 0 |
| **rust-axum** | 2,129 | 2,132 | 28.27 | 36.13 | 54.96 | 32,017 | 0 | 0 |
| ⭐ **jwc-app** | 1,841 | 1,846 | 31.96 | 46.69 | 68.19 | 27,682 | 0 | 0 |
| **dotnet-minimal** | 1,323 | 1,332 | 45.84 | 60.54 | 80.74 | 19,887 | 0 | 0 |
| ⭐ **liteapi-rust** | 1,272 | 1,274 | 47.91 | 60.82 | 87.38 | 19,107 | 0 | 0 |
| ⭐ **liteapi-managed** | 1,201 | 1,204 | 50.71 | 64.49 | 91.61 | 18,069 | 0 | 0 |
| **node-fastify** | 497 | 496 | 126.06 | 139.62 | 157.12 | 7,488 | 0 | 0 |
| **python-fastapi** | 324 | 322 | 195.12 | 204.94 | 270.06 | 4,881 | 0 | 0 |

Notes:
- Adding a write per row costs the leaders ~2.6× against `/queries` (5,506 → 2,150) and roughly 2.3× for the Npgsql stacks.
- `jwc-app` is 3rd at 1,841 — 39% ahead of Npgsql — despite routing its writes through `raw_sql` with a hand-built JSON parameter string per row.
- `go-fiber` and `rust-axum` are within 1% of each other; `rust-axum` has the much better tail (54.96 vs 98.61 ms p99).
- Every stack ran clean here — 0 non-2xx across all eight.

---

## Aggregate Throughput (sum of all 8 endpoints)

```
Total successful RPS (2xx/s) — higher is better
go-fiber         ████████████████████████████████████████ 492,329
dotnet-minimal   ███████████████████████████████          377,886
rust-axum        █████████████████████████████            353,269
jwc-app          ████████████████████████████             346,489  ⭐
liteapi-rust     █████████████████████                    257,303  ⭐
liteapi-managed  █████████████                            159,307  ⭐
node-fastify     ████                                     55,193
python-fastapi   █                                        11,816
```

| Server | Total 2xx/s | Total 2xx | Total Bytes | non-2xx | Client Errors | Endpoints |
|---|---:|---:|---:|---:|---:|---:|
| **go-fiber** | **492,329** | 7,387,288 | 8.98 GB | 243,818 | 243,818 | 8/8 |
| **dotnet-minimal** | 377,886 | 5,673,433 | 12.79 GB | 199,349 | 199,349 | 8/8 |
| **rust-axum** | 353,269 | 5,300,814 | 12.56 GB | 180,505 | 180,505 | 8/8 |
| ⭐ **jwc-app** | 346,489 | 5,198,887 | 9.22 GB | 235,836 | 235,836 | 8/8 |
| ⭐ **liteapi-rust** | 257,303 | 4,252,000 | 4.79 GB | 356,416 | 356,416 | 8/8 |
| ⭐ **liteapi-managed** | 159,307 | 2,391,653 | 6.88 GB | 0 | 0 | 8/8 |
| **node-fastify** | 55,193 | 829,117 | 2.26 GB | 295,647 | 295,647 | 8/8 |
| **python-fastapi** | 11,816 | 178,194 | 108.34 MB | 524,297 | 524,297 | 8/8 |

`rust-axum` and `jwc-app` finish 1.9% apart — a tie. `dotnet-minimal` sits above
both on the aggregate almost entirely on the strength of `/ping`, `/json-small`
and `/json-large`; it is 4th on all three DB endpoints.

---

## Tail-Latency Summary (p99 across all endpoints, ms — lower is better)

| Server | `/ping` | `/json-small` | `/json-large` | `/cpu` | `/async-delay` | `/db` | `/queries` | `/updates` |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| **go-fiber** | **1.53** | **2.36** | 102.78 | 457.29 | **60.14** | 2.97 | 61.59 | 98.61 |
| **dotnet-minimal** | 4.93 | 80.01 | 26.18 | 434.19 | 105.84 | 6.05 | 37.18 | 80.74 |
| **rust-axum** | 8.48 | 8.82 | **20.07** | **312.15** | 63.79 | **2.49** | 18.99 | **54.96** |
| ⭐ **jwc-app** | 22.44 | 25.49 | 27.72 | 470.57 | 64.37 | 2.59 | **18.69** | 68.19 |
| ⭐ **liteapi-managed** | 24.29 | 22.44 | 68.06 | 1,086.42 | 93.94 | 16.06 | 40.26 | 91.61 |
| **node-fastify** | 29.16 | 32.22 | 74.75 | 25,004.49 | 80.76 | 9.72 | 88.22 | 157.12 |
| ⭐ **liteapi-rust** | 42.97 | 40.48 | 413.84 | 964.52 | 72.57 | 8.28 | 37.79 | 87.38 |
| **python-fastapi** | 107.12 | 110.60 | 521.02 | 18,957.31 | 298.60 | 44.52 | 179.10 | 270.06 |

`rust-axum` takes the tail on four of the eight endpoints and is the most
consistent stack overall. `go-fiber` wins the light endpoints by a wide margin
but has the worst `/json-large` and `/updates` tails of the top four. `jwc-app`
is best-in-field on `/queries` and second on `/db`; its weak columns are the
500-connection endpoints, where its p99 is ~2.6× rust-axum's.

---

## Conclusions

1. **`jwc-app` is genuinely competitive.** It wins `/async-delay`, takes 3rd on six of eight endpoints, and lands within 2% of hand-written `rust-axum` on `/db`, `/queries` and `/ping` — beating it on `/queries` p99. For a language that generates its server rather than having one hand-tuned, keeping pace with tokio-postgres + deadpool is the standout result.

2. **`jwc-app`'s DB tier only works because of an escape hatch.** The idiomatic `update … set randomNumber = v` cannot write an `int` column in a native build at all — the value is bound as text, or as `int8` when it is a literal. The route works via `raw_sql` with a hand-formatted JSON parameter string. That and six other native-backend defects — including a wrong-arity `raw_sql` call that compiles clean, returns 200 and silently discards the query — are written up in [JWC-0.8.0-NATIVE-BUGS.md](_my/jwc-app/JWC-0.8.0-NATIVE-BUGS.md).

3. **`go-fiber` wins the DB tier and the aggregate**; `dotnet-minimal` wins `/json-large`; `rust-axum` wins `/cpu` and most tail-latency columns. No stack sweeps.

4. **LiteAPI's two listeners still trade throughput for stability.** `liteapi-rust` is faster on small bodies but takes 356,416 client errors across the suite and tails to 414 ms on `/json-large`. `liteapi-managed` is **the only stack in the suite with zero errors on all eight endpoints**, including 1000-connection `/async-delay`.

5. **`node-fastify` and `python-fastapi` are not viable at these concurrencies** on this platform — 80 and 6,908 successful responses respectively on `/async-delay`, and node blocks its event loop on `/cpu` badly enough to time out.

6. **Measurement hygiene changed the answers.** Resetting the `world` table between servers moved `dotnet-minimal`'s `/db` from 7,423 to 39,109 2xx/s, and reading `2xx/s` instead of `rps` moved `node-fastify` on `/async-delay` from an apparent 16,606 to an actual 5. Both are worth carrying into any future run of this suite.

---

## Linux Re-run — 2026-09-15

The Windows results above are unchanged. This is a separate full run on the
Linux workstation, using the same 8 stacks, 8 endpoints, connection counts,
15-second measurements, 3-second warm-up, 5-second timeout, and sequential
server order. The `world` table was reset and reseeded before every server.

**`jwc-app` was re-measured on 2026-09-16** with the same schedule after moving
to JWC 1.0.0-rc.5 (which fixed the quadratic `array.push`) and rewriting the
`/updates` route around a compiler bug that turned 87% of its rc.4 responses
into 404s (details under [Linux Run Notes](#linux-run-notes)). Its eight rows
below are from that run; the other seven stacks are unchanged from 09-15.

### Test Environment

| Component | Spec |
|---|---|
| **CPU** | Intel Core Ultra 7 265KF (20 cores) |
| **RAM** | 30 GiB |
| **OS** | Ubuntu 26.04, Linux 7.0.0-31-generic |
| **Bombardier** | v1.2.6 (linux/amd64, fasthttp client) |
| **Postgres** | 18.6, local `BenchJWCDB`, `world` table seeded with 10,000 rows |
| **JWC** | 1.0.0-rc.5 native release build (`jwc-app` rows; the 09-15 run used rc.4) |
| **Test duration** | 15 s per endpoint (after 3 s warm-up) |

### Successful Responses Per Second

These are completed 2xx responses per second, not Bombardier's `rps` field.
Higher is better.

| Endpoint | 1st | 2nd | 3rd | 4th | 5th | 6th | 7th | 8th |
|---|---|---|---|---|---|---|---|---|
| `/ping` | rust-axum **1,250,978** | jwc-app **1,125,699** | liteapi-rust **1,033,420** | go-fiber **924,214** | dotnet **831,050** | liteapi-managed **150,829** | node **133,078** | python **12,073** |
| `/json-small` | rust-axum **1,215,154** | jwc-app **1,132,636** | liteapi-rust **965,371** | go-fiber **903,831** | dotnet **794,112** | node **130,621** | liteapi-managed **128,014** | python **11,205** |
| `/json-large` | rust-axum **127,738** | dotnet **93,589** | go-fiber **82,260** | liteapi-rust **42,314** | liteapi-managed **19,180** | node **10,979** | jwc-app **9,211** | python **501** |
| `/cpu` | rust-axum **5,982** | jwc-app **2,046** | go-fiber **1,143** | dotnet **92** | liteapi-rust **90** | liteapi-managed **90** | python **63** | node **7** |
| `/async-delay` | dotnet **92,648** | go-fiber **92,535** | rust-axum **87,066** | jwc-app **86,097** | liteapi-rust **85,854** | node **74,696** | liteapi-managed **20,546** | python **10,601** |
| `/db` | go-fiber **389,148** | rust-axum **282,926** | jwc-app **273,707** | liteapi-rust **216,252** | dotnet **209,246** | liteapi-managed **94,840** | node **64,641** | python **7,431** |
| `/queries` | go-fiber **37,337** | rust-axum **28,750** | jwc-app **26,688** | dotnet **24,279** | liteapi-rust **21,222** | liteapi-managed **17,179** | node **5,912** | python **2,553** |
| `/updates` | rust-axum **7,191** | go-fiber **6,999** | jwc-app **6,210** | dotnet **5,204** | liteapi-rust **5,095** | liteapi-managed **4,618** | node **3,085** | python **1,664** |

### Detailed Endpoint Results

The detailed tables below use the same fields as the Windows tables above.
`2xx/s` is completed successful responses per second; `rps` is Bombardier's
request rate and can include failed attempts.

#### `/ping` — Plain Text (500 connections)

| Server | 2xx/s | RPS mean* | p50 (ms) | p90 (ms) | p99 (ms) | 2xx | non-2xx | client errors |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| **rust-axum** | **1,250,978** | 1,251,692 | 0.32 | 0.71 | 1.41 | 18,765,607 | 0 | 0 |
| **jwc-app** | **1,125,699** | 1,126,359 | 0.38 | 0.77 | 1.37 | 16,885,801 | 0 | 0 |
| **liteapi-rust** | **1,033,419** | 1,033,610 | 0.14 | 0.80 | 7.28 | 15,501,505 | 0 | 0 |
| **go-fiber** | **924,214** | 924,671 | 0.13 | 1.58 | 3.74 | 13,864,469 | 0 | 0 |
| **dotnet-minimal** | **831,050** | 831,508 | 0.53 | 0.98 | 2.00 | 12,465,798 | 0 | 0 |
| **liteapi-managed** | **150,829** | 150,994 | 1.22 | 7.28 | 12.06 | 2,263,086 | 0 | 0 |
| **node-fastify** | **133,078** | 133,099 | 3.69 | 3.98 | 4.52 | 1,996,640 | 0 | 0 |
| **python-fastapi** | **12,073** | 12,079 | 41.31 | 41.89 | 42.53 | 181,551 | 0 | 0 |

#### `/json-small` — Tiny JSON Object (500 connections)

| Server | 2xx/s | RPS mean* | p50 (ms) | p90 (ms) | p99 (ms) | 2xx | non-2xx | client errors |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| **rust-axum** | **1,215,154** | 1,215,876 | 0.33 | 0.76 | 1.50 | 18,227,511 | 0 | 0 |
| **jwc-app** | **1,132,636** | 1,133,015 | 0.38 | 0.76 | 1.33 | 16,989,861 | 0 | 0 |
| **liteapi-rust** | **965,371** | 965,383 | 0.15 | 0.96 | 7.45 | 14,481,433 | 0 | 0 |
| **go-fiber** | **903,831** | 904,120 | 0.14 | 1.61 | 3.81 | 13,558,603 | 0 | 0 |
| **dotnet-minimal** | **794,112** | 794,730 | 0.56 | 1.02 | 2.03 | 11,912,026 | 0 | 0 |
| **node-fastify** | **130,621** | 130,709 | 3.79 | 4.01 | 4.30 | 1,959,812 | 0 | 0 |
| **liteapi-managed** | **128,014** | 128,156 | 1.24 | 8.89 | 14.24 | 1,920,314 | 0 | 0 |
| **python-fastapi** | **11,205** | 11,218 | 44.56 | 45.06 | 45.59 | 168,482 | 0 | 0 |

#### `/json-large` — 1000-item JSON Array (200 connections)

| Server | 2xx/s | RPS mean* | p50 (ms) | p90 (ms) | p99 (ms) | 2xx | non-2xx | client errors |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| **rust-axum** | **127,738** | 127,803 | 1.61 | 2.40 | 3.30 | 1,916,226 | 0 | 0 |
| **dotnet-minimal** | **93,589** | 93,606 | 1.87 | 3.39 | 6.87 | 1,403,990 | 0 | 0 |
| **go-fiber** | **82,260** | 82,268 | 0.35 | 11.02 | 25.41 | 1,234,602 | 0 | 0 |
| **liteapi-rust** | **42,314** | 42,376 | 1.37 | 14.20 | 40.09 | 635,740 | 0 | 0 |
| **liteapi-managed** | **19,180** | 19,198 | 9.73 | 13.85 | 19.38 | 288,015 | 0 | 0 |
| **node-fastify** | **10,979** | 10,979 | 18.13 | 18.50 | 19.17 | 164,886 | 0 | 0 |
| **jwc-app** | **9,211** | 9,215 | 21.20 | 33.36 | 45.37 | 138,361 | 0 | 0 |
| **python-fastapi** | **501** | 501 | 399.06 | 403.38 | 407.40 | 7,712 | 0 | 0 |

#### `/cpu` — CPU-Bound Workload (32 connections)

| Server | 2xx/s | RPS mean* | p50 (ms) | p90 (ms) | p99 (ms) | 2xx | non-2xx | client errors |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| **rust-axum** | **5,982** | 5,982 | 5.27 | 6.84 | 9.54 | 89,760 | 0 | 0 |
| **jwc-app** | **2,046** | 2,046 | 15.40 | 17.71 | 21.98 | 30,707 | 0 | 0 |
| **go-fiber** | **1,143** | 1,144 | 27.45 | 37.46 | 47.13 | 17,164 | 0 | 0 |
| **dotnet-minimal** | **92** | 91 | 343.25 | 446.32 | 537.37 | 1,386 | 0 | 0 |
| **liteapi-rust** | **90** | 89 | 353.34 | 429.88 | 489.76 | 1,368 | 0 | 0 |
| **liteapi-managed** | **89** | 89 | 356.00 | 418.03 | 476.58 | 1,366 | 0 | 0 |
| **python-fastapi** | **63** | 63 | 510.36 | 514.68 | 517.03 | 971 | 0 | 0 |
| **node-fastify** | **7** | 10 | 1,091.91 | 20,564.34 | 25,004.55 | 167 | 8 | 8 |

#### `/async-delay` — 10 ms `await sleep` (1000 connections)

| Server | 2xx/s | RPS mean* | p50 (ms) | p90 (ms) | p99 (ms) | 2xx | non-2xx | client errors |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| **dotnet-minimal** | **92,648** | 92,808 | 10.72 | 11.57 | 12.94 | 1,390,631 | 0 | 0 |
| **go-fiber** | **92,535** | 92,614 | 10.74 | 11.45 | 12.07 | 1,388,861 | 0 | 0 |
| **rust-axum** | **87,066** | 87,250 | 11.48 | 12.02 | 12.50 | 1,306,755 | 0 | 0 |
| **jwc-app** | **86,097** | 86,235 | 11.63 | 12.22 | 12.81 | 1,292,394 | 0 | 0 |
| **liteapi-rust** | **85,854** | 86,011 | 10.78 | 14.39 | 18.51 | 1,288,769 | 0 | 0 |
| **node-fastify** | **74,696** | 74,816 | 12.46 | 13.64 | 14.71 | 1,121,472 | 0 | 0 |
| **liteapi-managed** | **20,546** | 20,580 | 47.59 | 55.64 | 58.98 | 308,935 | 0 | 0 |
| **python-fastapi** | **10,601** | 10,590 | 95.55 | 99.63 | 101.66 | 159,641 | 0 | 0 |

#### `/db` — Single Random Row (64 connections)

| Server | 2xx/s | RPS mean* | p50 (ms) | p90 (ms) | p99 (ms) | 2xx | non-2xx | client errors |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| **go-fiber** | **389,148** | 389,162 | 0.15 | 0.25 | 0.59 | 5,837,424 | 0 | 0 |
| **rust-axum** | **282,926** | 282,933 | 0.18 | 0.42 | 0.72 | 4,243,919 | 0 | 0 |
| **jwc-app** | **273,707** | 273,723 | 0.20 | 0.36 | 0.74 | 4,105,687 | 0 | 0 |
| **liteapi-rust** | **216,252** | 216,272 | 0.23 | 0.44 | 1.78 | 3,243,793 | 0 | 0 |
| **dotnet-minimal** | **209,246** | 209,430 | 0.27 | 0.45 | 0.95 | 3,138,888 | 0 | 0 |
| **liteapi-managed** | **94,840** | 94,859 | 0.31 | 0.67 | 6.82 | 1,422,628 | 0 | 0 |
| **node-fastify** | **64,641** | 64,647 | 0.96 | 1.19 | 1.59 | 969,648 | 0 | 0 |
| **python-fastapi** | **7,431** | 7,432 | 8.34 | 8.60 | 9.03 | 111,506 | 0 | 0 |

#### `/queries` — 20 Random Rows per Request (64 connections)

| Server | 2xx/s | RPS mean* | p50 (ms) | p90 (ms) | p99 (ms) | 2xx | non-2xx | client errors |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| **go-fiber** | **37,337** | 37,338 | 1.62 | 2.35 | 3.24 | 560,093 | 0 | 0 |
| **rust-axum** | **28,750** | 28,750 | 2.12 | 2.94 | 4.26 | 431,297 | 0 | 0 |
| **jwc-app** | **26,688** | 26,689 | 2.30 | 3.08 | 4.20 | 400,368 | 0 | 0 |
| **dotnet-minimal** | **24,279** | 24,283 | 2.41 | 3.61 | 5.42 | 364,281 | 0 | 0 |
| **liteapi-rust** | **21,222** | 21,226 | 2.64 | 4.62 | 5.98 | 318,421 | 0 | 0 |
| **liteapi-managed** | **17,179** | 17,181 | 2.54 | 7.89 | 10.59 | 257,726 | 0 | 0 |
| **node-fastify** | **5,912** | 5,912 | 10.68 | 11.38 | 15.83 | 88,719 | 0 | 0 |
| **python-fastapi** | **2,553** | 2,553 | 24.89 | 26.08 | 28.28 | 38,326 | 0 | 0 |

#### `/updates` — 20 Read+Write Rows per Request (64 connections)

| Server | 2xx/s | RPS mean* | p50 (ms) | p90 (ms) | p99 (ms) | 2xx | non-2xx | client errors |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| **rust-axum** | **7,191** | 7,192 | 8.73 | 9.23 | 10.66 | 107,935 | 0 | 0 |
| **go-fiber** | **6,999** | 7,000 | 8.88 | 9.53 | 15.52 | 105,050 | 0 | 0 |
| **jwc-app** | **6,210** | 6,210 | 10.05 | 11.60 | 13.79 | 93,209 | 0 | 0 |
| **dotnet-minimal** | **5,204** | 5,205 | 12.02 | 13.52 | 18.93 | 78,108 | 0 | 0 |
| **liteapi-rust** | **5,095** | 5,096 | 12.24 | 14.32 | 16.68 | 76,483 | 0 | 0 |
| **liteapi-managed** | **4,618** | 4,619 | 12.57 | 17.36 | 20.85 | 69,317 | 0 | 0 |
| **node-fastify** | **3,085** | 3,084 | 20.46 | 22.11 | 26.23 | 46,316 | 0 | 0 |
| **python-fastapi** | **1,664** | 1,662 | 38.48 | 39.36 | 60.16 | 24,987 | 0 | 0 |

#### Linux Tail Latency Summary (p99, ms)

| Server | `/ping` | `/json-small` | `/json-large` | `/cpu` | `/async-delay` | `/db` | `/queries` | `/updates` |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| **dotnet-minimal** | 2.00 | 2.03 | 6.87 | 537.37 | 12.94 | 0.95 | 5.42 | 18.93 |
| **go-fiber** | 3.74 | 3.81 | 25.41 | 47.13 | **12.07** | **0.59** | **3.24** | 15.52 |
| **node-fastify** | 4.52 | 4.30 | 19.17 | 25,004.55 | 14.71 | 1.59 | 15.83 | 26.23 |
| **python-fastapi** | 42.53 | 45.59 | 407.40 | 517.03 | 101.66 | 9.03 | 28.28 | 60.16 |
| **rust-axum** | 1.41 | 1.50 | **3.30** | **9.54** | 12.50 | 0.72 | 4.26 | **10.66** |
| **jwc-app** | **1.37** | **1.33** | 45.37 | 21.98 | 12.81 | 0.74 | 4.20 | 13.79 |
| **liteapi-rust** | 7.28 | 7.45 | 40.09 | 489.76 | 18.51 | 1.78 | 5.98 | 16.68 |
| **liteapi-managed** | 12.06 | 14.24 | 19.38 | 476.58 | 58.98 | 6.82 | 10.59 | 20.85 |

### Linux Run Notes

- Linux produced no client-side dial errors in the suite. The only non-2xx responses were 8 HTTP 400s from `node-fastify` on `/cpu`; the table ranks successful responses only.
- **`jwc-app` on 09-15 (rc.4)** measured 28 2xx/s on `/json-large` and 1,978 2xx/s with 195,733 non-2xx on `/updates`. Both were JWC defects, not workload differences, and both are gone in the 09-16 re-measurement:
  - `/json-large`: rc.4's `array.push` copied the array on every iteration, making the 1000-item build quadratic (641 responses in 23 s, p99 22.5 s). rc.5 moves the local into the call and appends in place — 9,211 2xx/s, p99 45 ms.
  - `/updates`: the non-2xx were **404s**, not 400s. rc.4/rc.5 lower `update … as { … } first` to `UPDATE … WHERE x.ctid = (SELECT y.ctid … FOR UPDATE LIMIT 1) RETURNING …`. Under 64 concurrent writers the inner `FOR UPDATE` waits out a competing update and answers the *new* tuple's ctid, which the outer statement's snapshot cannot see — zero rows, `null`, and the route's `or throw NotFound` became a 404 (87% of requests). Sequentially it never fails. The route now issues a bare `update … set … where W.id == @id` (lowered to a plain `UPDATE … WHERE x.id = $2`, no race) followed by a `select … first` — one UPDATE + one SELECT per row, the same two statements the other stacks issue — and answers 6,210 2xx/s with zero non-2xx. (`jwc explain` also omits the UPDATE from its query list — "1 query" for a program with two.)
- `jwc-app` was measured on port 8090 instead of 8080 on 09-16 (another service held 8080); the workload and schedule are otherwise identical.
- Raw results are saved under `.dist/results/<server>/<endpoint>.json`; this run produced all 64 files.

---

## Reproduce

```powershell
# 1. Build all (Release / Native)
dotnet publish ./dotnet-minimal -c Release -o ./dotnet-minimal/publish
go -C ./go-fiber build -ldflags="-s -w" -o go-fiber.exe main.go
cargo build --release --manifest-path ./rust-axum/Cargo.toml
jwc build --release                    # inside _my/jwc-app (needs a Rust toolchain)
dotnet publish ./_my/liteapi-rust -c Release -o ./_my/liteapi-rust/publish
dotnet publish ./_my/liteapi      -c Release -o ./_my/liteapi/publish

# 2. Seed the DB tier once (inside _my/jwc-app; DATABASE_URL from .env)
jwc migrate up --create-db             # creates + seeds world(id, randomnumber)

# 3. Run the full sequential benchmark + generate summary
./.dist/bench-full.ps1                 # resets the world table before each server

# (or one server at a time)
./.dist/bench.ps1 -Name jwc-app -StartCmd './bin/release/jwc-app.exe' `
                  -WorkDir "$PWD\_my\jwc-app" -Port 8080 -BindHost '[::1]'

./.dist/report.ps1                     # regenerate summary JSON from saved results
```

All stacks read `DATABASE_URL` and fall back to
`postgres://postgres:1234@localhost:5432/BenchJWCDB`. `jwc-app` additionally
reads `PG_HOST` / `PG_PORT` / `PG_USER` / `PG_PASSWORD` / `PG_DATABASE` from
`_my/jwc-app/.env`.

Raw bombardier JSON per endpoint is saved under `.dist/results/<server>/<endpoint>.json`;
the merged summary is `.dist/results/summary.json`.

### Run on a cloud server (Linux)

The published numbers are from a Windows desktop (i5-10400, 32 GB). Windows
surfaces a lot of bombardier-side `dial tcp: actively refused` under high
connection churn (ephemeral port exhaustion) that doesn't show up on Linux —
which is exactly why the tables above lead with `2xx/s`. For comparable
cross-stack numbers, run on a clean Linux box with dedicated CPU:

| Provider | SKU | Cores / RAM | Hourly |
|---|---|---|---|
| **Hetzner Cloud** | CCX33 (AMD dedicated) | 16 vCPU / 64 GB | ~€0.10 |
| AWS EC2 | c7i.4xlarge | 16 vCPU / 32 GB | ~$0.71 |
| DigitalOcean | CPU-Optimized 8GP | 8 vCPU / 16 GB | $0.36 |

Recommended: Hetzner CCX33 — dedicated cores, hourly billing, one-line
provision via cloud-init.

**One-shot run** (pastes the suite onto a fresh Ubuntu 24.04 VM, builds
every stack, benches, leaves results at `/opt/bench-results.tgz`):

1. Create the VM with `.dist/cloud-init.yaml` as user data.
2. Wait ~45 min (`tail -f /var/log/bench-setup.log` on SSH).
3. `scp root@<ip>:/opt/bench-results.tgz .` and tear down the VM.

**Manual / iterative**:

```bash
# On the Linux box, as root or via sudo:
git clone https://github.com/Nodirbek-Abdulaxadov/http-framework-benchmark.git
git clone https://github.com/Nodirbek-Abdulaxadov/jwc-lang.git /opt/jwc-lang
cd http-framework-benchmark
bash .dist/setup-linux.sh        # installs Go / Rust / .NET / Node / Python, builds all
bash .dist/bench-all.sh          # 8 stacks × 8 endpoints × 15s
```

Results land under `.dist/results/<stack>/<endpoint>.json` — same layout
as the Windows PowerShell variant. Either run `.dist/report.ps1` from a
Windows machine or write a small jq pipeline to roll them up.
