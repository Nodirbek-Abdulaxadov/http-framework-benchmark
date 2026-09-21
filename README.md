# HTTP Framework Benchmark Results

> 8 minimal HTTP servers under [bombardier](https://github.com/codesenberg/bombardier),
> one server at a time, 8 endpoints, 15 s per endpoint after a 3 s warm-up.
> Rankings are **2xx/s** — successful responses per second — not bombardier's `rps`.

**Current run: Linux, 2026-09-21, `jwc-app` on JWC 1.0.0.** The Windows run of
2026-07-28 (`jwc-app` on JWC v0.8.0) is kept below it. Raw bombardier JSON for
the current run is under `.dist/results/<server>/<endpoint>.json`; earlier
Linux runs (09-15, 09-18) under `.dist/results-prev/`.

---

## Test Environment

| Component | Spec |
|---|---|
| **CPU** | Intel Core Ultra 7 265KF (20 cores) |
| **RAM** | 30 GiB |
| **OS** | Ubuntu 26.04, Linux 7.0.0-31-generic |
| **Bombardier** | v1.2.6 (linux/amd64, fasthttp client) |
| **Postgres** | 16.15 (snap), local `BenchJWCDB`, `world` table seeded with 10,000 rows |
| **JWC** | 1.0.0 native release build (`jwc build --release`) |
| **Test duration** | 15 s per endpoint (after 3 s warm-up) |
| **Timeout** | 5 s |
| **Listen address** | `http://127.0.0.1:8080` (liteapi-rust on `:6080`, liteapi-managed on `:6070`) |

⭐ = projects under `_my/`.

### Framework Versions & Build Flags

| Stack | Runtime / Compiler | DB driver | Build |
|---|---|---|---|
| **dotnet-minimal** | .NET 10.0 (Kestrel) | Npgsql 9.0.3 | `dotnet publish -c Release` |
| **go-fiber** | Go 1.24.0, Fiber v2 | pgx/v5 5.10.0 | `go build -ldflags="-s -w"` |
| **node-fastify** | Node 22.12.0, Fastify ^5.8.5 | pg 8.22.0 | `node` (V8 JIT) |
| **python-fastapi** | Python 3.12.4, FastAPI 0.115.14, uvicorn 0.35.0 | asyncpg 0.31.0 | `uvicorn --workers 1` |
| **rust-axum** | Rust 1.92.0, axum 0.8 | tokio-postgres 0.7 + deadpool 0.14 | `cargo build --release` |
| **jwc-app** ⭐ | JWC 1.0.0 (native AOT → tokio/axum); Windows numbers below are from v0.8.0 | built-in (`database … : Postgres`) | `jwc build --release` |
| **liteapi-rust** ⭐ | .NET 10.0 + LiteAPI.Core 2.3.0 (Rust TCP listener — `RunWithRust()`) | Npgsql 9.0.3 | `dotnet publish -c Release` |
| **liteapi-managed** ⭐ | .NET 10.0 + LiteAPI.Core 2.3.0 (managed `Run()`) | Npgsql 9.0.3 | `dotnet publish -c Release` |

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

| Endpoint | Workload (all stacks) |
|---|---|
| `/json-large` | Build a 1000-object array **per request** and serialize it. No precompute, no process cache. |
| `/cpu` | Run **100,000 real chained SHA-256 hashes** per request. No arithmetic substitute. |
| `/db`, `/queries` | `SELECT id, randomnumber FROM world WHERE id = $1`, one round-trip per row, ids drawn across the full 1..10,000 range. |
| `/updates` | Same read, then `UPDATE world SET randomnumber = $1 WHERE id = $2` per row. |
| `?queries=` | Missing or unparsable → 1; the value is clamped to 1..500. |

The `world` table is reset before every server (`TRUNCATE` + reseed +
`VACUUM FULL`, autovacuum disabled on the table — [`.dist/reset-db.js`](.dist/reset-db.js)).

---

## Linux — 2026-09-21

### Successful Responses Per Second

| Endpoint | 1st | 2nd | 3rd | 4th | 5th | 6th | 7th | 8th |
|---|---|---|---|---|---|---|---|---|
| `/ping` | rust-axum **1,235,521** | jwc-app **1,175,270** | liteapi-rust **1,079,125** | go-fiber **949,848** | dotnet **892,412** | liteapi-managed **145,348** | node **141,561** | python **13,249** |
| `/json-small` | rust-axum **1,243,634** | jwc-app **1,181,567** | liteapi-rust **1,028,211** | go-fiber **939,176** | dotnet **844,297** | node **136,709** | liteapi-managed **98,428** | python **11,871** |
| `/json-large` | rust-axum **129,480** | dotnet **98,924** | go-fiber **87,486** | liteapi-rust **40,960** | liteapi-managed **14,095** | node **10,944** | jwc-app **9,405** | python **524** |
| `/cpu` | rust-axum **6,052** | jwc-app **2,139** | go-fiber **1,154** | dotnet **91** | liteapi-rust **88** | liteapi-managed **80** | python **65** | node **9** |
| `/async-delay` | go-fiber **92,355** | dotnet **92,259** | liteapi-rust **87,292** | jwc-app **86,346** | rust-axum **84,248** | node **70,481** | liteapi-managed **19,319** | python **11,800** |
| `/db` | go-fiber **406,141** | rust-axum **293,533** | jwc-app **287,660** | dotnet **229,559** | liteapi-rust **226,428** | liteapi-managed **82,308** | node **65,530** | python **7,607** |
| `/queries` | go-fiber **39,392** | rust-axum **31,788** | jwc-app **29,114** | dotnet **27,416** | liteapi-rust **22,768** | liteapi-managed **15,389** | node **6,149** | python **2,599** |
| `/updates` | rust-axum **7,389** | go-fiber **7,127** | jwc-app **6,484** | dotnet **5,624** | liteapi-rust **5,383** | liteapi-managed **4,584** | node **3,171** | python **1,717** |

### Detailed Endpoint Results

`2xx/s` is completed successful responses per second; `rps` is bombardier's
request rate and can include failed attempts.

#### `/ping` — Plain Text (500 connections)

| Server | 2xx/s | RPS mean* | p50 (ms) | p90 (ms) | p99 (ms) | 2xx | non-2xx | client errors |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| **rust-axum** | **1,235,521** | 1,235,749 | 0.32 | 0.74 | 1.50 | 18,533,089 | 0 | 0 |
| **jwc-app** | **1,175,270** | 1,175,187 | 0.37 | 0.73 | 1.28 | 17,629,221 | 0 | 0 |
| **liteapi-rust** | **1,079,125** | 1,079,996 | 0.14 | 0.80 | 6.64 | 16,187,148 | 0 | 0 |
| **go-fiber** | **949,848** | 950,233 | 0.13 | 1.55 | 3.69 | 14,249,834 | 0 | 0 |
| **dotnet-minimal** | **892,412** | 893,198 | 0.50 | 0.91 | 1.82 | 13,387,532 | 0 | 0 |
| **liteapi-managed** | **145,348** | 145,403 | 1.23 | 8.15 | 12.63 | 2,180,863 | 0 | 0 |
| **node-fastify** | **141,561** | 141,579 | 3.50 | 3.67 | 3.86 | 2,123,884 | 0 | 0 |
| **python-fastapi** | **13,249** | 13,254 | 37.65 | 38.17 | 38.58 | 199,230 | 0 | 0 |

#### `/json-small` — Tiny JSON Object (500 connections)

| Server | 2xx/s | RPS mean* | p50 (ms) | p90 (ms) | p99 (ms) | 2xx | non-2xx | client errors |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| **rust-axum** | **1,243,634** | 1,243,835 | 0.32 | 0.74 | 1.47 | 18,655,038 | 0 | 0 |
| **jwc-app** | **1,181,567** | 1,182,716 | 0.37 | 0.72 | 1.26 | 17,723,840 | 0 | 0 |
| **liteapi-rust** | **1,028,211** | 1,029,148 | 0.15 | 0.97 | 6.31 | 15,423,391 | 0 | 0 |
| **go-fiber** | **939,176** | 939,872 | 0.13 | 1.58 | 3.74 | 14,089,194 | 0 | 0 |
| **dotnet-minimal** | **844,297** | 845,017 | 0.53 | 0.95 | 2.09 | 12,664,649 | 0 | 0 |
| **node-fastify** | **136,709** | 136,773 | 3.64 | 3.79 | 3.95 | 2,051,117 | 0 | 0 |
| **liteapi-managed** | **98,428** | 98,524 | 1.35 | 12.05 | 17.21 | 1,476,696 | 0 | 0 |
| **python-fastapi** | **11,871** | 11,879 | 42.05 | 42.93 | 43.33 | 178,532 | 0 | 0 |

#### `/json-large` — 1000-item JSON Array (200 connections, ~42 KB body)

| Server | 2xx/s | RPS mean* | p50 (ms) | p90 (ms) | p99 (ms) | 2xx | non-2xx | client errors |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| **rust-axum** | **129,480** | 129,544 | 1.58 | 2.40 | 3.27 | 1,942,255 | 0 | 0 |
| **dotnet-minimal** | **98,924** | 98,959 | 1.81 | 3.08 | 6.42 | 1,484,067 | 0 | 0 |
| **go-fiber** | **87,486** | 87,497 | 0.33 | 2.59 | 25.64 | 1,312,930 | 0 | 0 |
| **liteapi-rust** | **40,960** | 40,960 | 1.38 | 14.67 | 40.16 | 615,115 | 0 | 0 |
| **liteapi-managed** | **14,095** | 14,106 | 12.80 | 19.15 | 28.25 | 211,693 | 0 | 0 |
| **node-fastify** | **10,944** | 10,944 | 18.37 | 18.84 | 19.21 | 164,341 | 0 | 0 |
| **jwc-app** | **9,405** | 9,406 | 20.78 | 32.65 | 44.96 | 141,267 | 0 | 0 |
| **python-fastapi** | **524** | 524 | 381.57 | 383.87 | 385.46 | 8,066 | 0 | 0 |

#### `/cpu` — CPU-Bound Workload (32 connections)

| Server | 2xx/s | RPS mean* | p50 (ms) | p90 (ms) | p99 (ms) | 2xx | non-2xx | client errors |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| **rust-axum** | **6,052** | 6,052 | 5.21 | 6.69 | 9.40 | 90,805 | 0 | 0 |
| **jwc-app** | **2,139** | 2,139 | 14.81 | 16.72 | 18.61 | 32,114 | 0 | 0 |
| **go-fiber** | **1,154** | 1,154 | 27.16 | 35.88 | 44.34 | 17,337 | 0 | 0 |
| **dotnet-minimal** | **91** | 90 | 350.11 | 447.29 | 523.11 | 1,374 | 0 | 0 |
| **liteapi-rust** | **88** | 87 | 356.88 | 458.65 | 524.74 | 1,343 | 0 | 0 |
| **liteapi-managed** | **80** | 79 | 393.24 | 501.77 | 602.13 | 1,216 | 0 | 0 |
| **python-fastapi** | **65** | 65 | 490.01 | 491.58 | 492.52 | 1,011 | 0 | 0 |
| **node-fastify** | **9** | 10 | 1581.76 | 2660.00 | 21392.38 | 186 | 0 | 0 |

#### `/async-delay` — 10 ms `await sleep` (1000 connections)

| Server | 2xx/s | RPS mean* | p50 (ms) | p90 (ms) | p99 (ms) | 2xx | non-2xx | client errors |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| **go-fiber** | **92,355** | 92,480 | 10.71 | 11.54 | 12.37 | 1,386,492 | 0 | 0 |
| **dotnet-minimal** | **92,259** | 92,408 | 10.75 | 11.66 | 12.89 | 1,384,745 | 0 | 0 |
| **liteapi-rust** | **87,292** | 87,494 | 10.77 | 14.33 | 17.95 | 1,310,274 | 0 | 0 |
| **jwc-app** | **86,346** | 86,463 | 11.58 | 12.19 | 12.83 | 1,296,187 | 0 | 0 |
| **rust-axum** | **84,248** | 84,415 | 11.52 | 12.12 | 12.64 | 1,264,699 | 0 | 0 |
| **node-fastify** | **70,481** | 70,680 | 12.34 | 13.47 | 14.59 | 1,058,106 | 0 | 0 |
| **liteapi-managed** | **19,319** | 19,358 | 53.07 | 59.29 | 64.44 | 290,812 | 0 | 0 |
| **python-fastapi** | **11,800** | 11,798 | 83.73 | 91.93 | 93.87 | 177,729 | 0 | 0 |

#### `/db` — Single Random Row (64 connections)

| Server | 2xx/s | RPS mean* | p50 (ms) | p90 (ms) | p99 (ms) | 2xx | non-2xx | client errors |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| **go-fiber** | **406,141** | 406,159 | 0.15 | 0.23 | 0.50 | 6,092,124 | 0 | 0 |
| **rust-axum** | **293,533** | 293,537 | 0.17 | 0.41 | 0.70 | 4,403,031 | 0 | 0 |
| **jwc-app** | **287,660** | 287,665 | 0.19 | 0.34 | 0.73 | 4,314,932 | 0 | 0 |
| **dotnet-minimal** | **229,559** | 229,568 | 0.25 | 0.40 | 0.81 | 3,443,399 | 0 | 0 |
| **liteapi-rust** | **226,428** | 226,445 | 0.23 | 0.41 | 1.73 | 3,396,419 | 0 | 0 |
| **liteapi-managed** | **82,308** | 82,287 | 0.30 | 0.66 | 8.76 | 1,234,627 | 0 | 0 |
| **node-fastify** | **65,530** | 65,534 | 0.95 | 1.22 | 1.47 | 983,006 | 0 | 0 |
| **python-fastapi** | **7,607** | 7,608 | 8.16 | 8.45 | 8.86 | 114,151 | 0 | 0 |

#### `/queries` — 20 Random Rows per Request (64 connections)

| Server | 2xx/s | RPS mean* | p50 (ms) | p90 (ms) | p99 (ms) | 2xx | non-2xx | client errors |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| **go-fiber** | **39,392** | 39,393 | 1.55 | 2.18 | 2.82 | 590,927 | 0 | 0 |
| **rust-axum** | **31,788** | 31,789 | 1.95 | 2.57 | 3.27 | 476,861 | 0 | 0 |
| **jwc-app** | **29,114** | 29,114 | 2.13 | 2.77 | 3.54 | 436,739 | 0 | 0 |
| **dotnet-minimal** | **27,416** | 27,420 | 2.17 | 2.96 | 4.49 | 411,286 | 0 | 0 |
| **liteapi-rust** | **22,768** | 22,770 | 2.44 | 4.35 | 5.59 | 341,551 | 0 | 0 |
| **liteapi-managed** | **15,389** | 15,395 | 2.42 | 9.91 | 15.24 | 230,916 | 0 | 0 |
| **node-fastify** | **6,149** | 6,149 | 10.12 | 10.86 | 19.19 | 92,276 | 0 | 0 |
| **python-fastapi** | **2,599** | 2,598 | 24.41 | 25.77 | 27.89 | 39,021 | 0 | 0 |

#### `/updates` — 20 Read+Write Rows per Request (64 connections)

| Server | 2xx/s | RPS mean* | p50 (ms) | p90 (ms) | p99 (ms) | 2xx | non-2xx | client errors |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| **rust-axum** | **7,389** | 7,389 | 8.47 | 8.85 | 9.88 | 110,893 | 0 | 0 |
| **go-fiber** | **7,127** | 7,128 | 8.79 | 9.29 | 11.35 | 106,972 | 0 | 0 |
| **jwc-app** | **6,484** | 6,485 | 9.58 | 11.00 | 15.06 | 97,335 | 0 | 0 |
| **dotnet-minimal** | **5,624** | 5,625 | 11.23 | 12.29 | 14.31 | 84,416 | 0 | 0 |
| **liteapi-rust** | **5,383** | 5,384 | 11.57 | 13.45 | 15.77 | 80,807 | 0 | 0 |
| **liteapi-managed** | **4,584** | 4,585 | 11.88 | 18.44 | 20.77 | 68,808 | 0 | 0 |
| **node-fastify** | **3,171** | 3,171 | 19.92 | 21.48 | 25.45 | 47,608 | 0 | 0 |
| **python-fastapi** | **1,717** | 1,717 | 37.22 | 38.20 | 42.09 | 25,790 | 0 | 0 |

### Tail Latency (p99, ms)

| Server | `/ping` | `/json-small` | `/json-large` | `/cpu` | `/async-delay` | `/db` | `/queries` | `/updates` |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| **dotnet-minimal** | 1.82 | 2.09 | 6.42 | 523.11 | 12.89 | 0.81 | 4.49 | 14.31 |
| **go-fiber** | 3.69 | 3.74 | 25.64 | 44.34 | **12.37** | **0.50** | **2.82** | 11.35 |
| **node-fastify** | 3.86 | 3.95 | 19.21 | 21,392.38 | 14.59 | 1.47 | 19.19 | 25.45 |
| **python-fastapi** | 38.58 | 43.33 | 385.46 | 492.52 | 93.87 | 8.86 | 27.89 | 42.09 |
| **rust-axum** | 1.50 | 1.47 | **3.27** | **9.40** | 12.64 | 0.70 | 3.27 | **9.88** |
| **jwc-app** | **1.28** | **1.26** | 44.96 | 18.61 | 12.83 | 0.73 | 3.54 | 15.06 |
| **liteapi-rust** | 6.64 | 6.31 | 40.16 | 524.74 | 17.95 | 1.73 | 5.59 | 15.77 |
| **liteapi-managed** | 12.63 | 17.21 | 28.25 | 602.13 | 64.44 | 8.76 | 15.24 | 20.77 |

---

## Windows — 2026-07-28

`jwc-app` on JWC v0.8.0. Bombardier counts client-side `dial tcp: actively
refused` attempts (ephemeral-port exhaustion at 500–1000 connections) in
`rps`; the tables rank `2xx/s`.

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

### Ranking (2xx/s)

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

### /ping — Plain Text (500 connections)

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

### /json-small — Tiny JSON Object (500 connections)

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

### /json-large — 1000-item JSON Array (200 connections, ~42 KB body)

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

### /cpu — CPU-Bound Workload (32 connections)

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

### /async-delay — 10 ms `await sleep` (1000 connections)

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

### /db — Single Random Row (64 connections)

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

### /queries — 20 Random Rows per Request (64 connections)

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

### /updates — 20 Read+Write Rows per Request (64 connections)

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

### Aggregate Throughput (sum of all 8 endpoints)

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

### Tail-Latency Summary (p99 across all endpoints, ms — lower is better)

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

For comparable cross-stack numbers, run on a clean Linux box with dedicated CPU:

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
