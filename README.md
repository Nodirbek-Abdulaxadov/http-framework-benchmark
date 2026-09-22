# HTTP Framework Benchmark Results

> 8 minimal HTTP servers under [bombardier](https://github.com/codesenberg/bombardier),
> one server at a time, 8 endpoints, 15 s per endpoint after a 3 s warm-up.
> Rankings are **2xx/s** — successful responses per second — not bombardier's `rps`.

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

## Linux

| Component | Spec |
|---|---|
| **CPU** | Intel Core Ultra 7 265KF (20 cores) |
| **RAM** | 30 GiB |
| **OS** | Ubuntu 26.04, Linux 7.0.0-31-generic |
| **Bombardier** | v1.2.6 (linux/amd64, fasthttp client) |
| **Postgres** | 16.15 (snap), local `BenchJWCDB`, `world` table seeded with 10,000 rows |
| **JWC** | 1.0.1 native release build (`jwc build --release`, installed from the GitHub release) |
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
| **jwc-app** ⭐ | JWC 1.0.1 (native AOT → tokio/axum) | built-in (`database … : Postgres`) | `jwc build --release` |
| **liteapi-rust** ⭐ | .NET 10.0 + LiteAPI.Core 2.3.0 (Rust TCP listener — `RunWithRust()`) | Npgsql 9.0.3 | `dotnet publish -c Release` |
| **liteapi-managed** ⭐ | .NET 10.0 + LiteAPI.Core 2.3.0 (managed `Run()`) | Npgsql 9.0.3 | `dotnet publish -c Release` |

---

### Successful Responses Per Second

| Endpoint | 1st | 2nd | 3rd | 4th | 5th | 6th | 7th | 8th |
|---|---|---|---|---|---|---|---|---|
| `/ping` | rust-axum **1,235,521** | jwc-app **1,180,194** | liteapi-rust **1,079,125** | go-fiber **949,848** | dotnet **892,412** | liteapi-managed **145,348** | node **141,561** | python **13,249** |
| `/json-small` | rust-axum **1,243,634** | jwc-app **1,181,997** | liteapi-rust **1,028,211** | go-fiber **939,176** | dotnet **844,297** | node **136,709** | liteapi-managed **98,428** | python **11,871** |
| `/json-large` | rust-axum **129,480** | dotnet **98,924** | go-fiber **87,486** | jwc-app **84,972** | liteapi-rust **40,960** | liteapi-managed **14,095** | node **10,944** | python **524** |
| `/cpu` | rust-axum **6,052** | jwc-app **2,167** | go-fiber **1,154** | dotnet **91** | liteapi-rust **88** | liteapi-managed **80** | python **65** | node **9** |
| `/async-delay` | go-fiber **92,355** | dotnet **92,259** | liteapi-rust **87,292** | jwc-app **86,080** | rust-axum **84,248** | node **70,481** | liteapi-managed **19,319** | python **11,800** |
| `/db` | go-fiber **406,141** | rust-axum **293,533** | jwc-app **285,773** | dotnet **229,559** | liteapi-rust **226,428** | liteapi-managed **82,308** | node **65,530** | python **7,607** |
| `/queries` | go-fiber **39,392** | rust-axum **31,788** | jwc-app **30,239** | dotnet **27,416** | liteapi-rust **22,768** | liteapi-managed **15,389** | node **6,149** | python **2,599** |
| `/updates` | rust-axum **7,389** | go-fiber **7,127** | jwc-app **6,452** | dotnet **5,624** | liteapi-rust **5,383** | liteapi-managed **4,584** | node **3,171** | python **1,717** |

### Detailed Endpoint Results

`2xx/s` is completed successful responses per second; `rps` is bombardier's
request rate and can include failed attempts.

#### `/ping` — Plain Text (500 connections)

| Server | 2xx/s | RPS mean* | p50 (ms) | p90 (ms) | p99 (ms) | 2xx | non-2xx | client errors |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| **rust-axum** | **1,235,521** | 1,235,749 | 0.32 | 0.74 | 1.50 | 18,533,089 | 0 | 0 |
| **jwc-app** | **1,180,194** | 1,180,146 | 0.36 | 0.72 | 1.28 | 17,703,351 | 0 | 0 |
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
| **jwc-app** | **1,181,997** | 1,182,026 | 0.36 | 0.72 | 1.30 | 17,730,406 | 0 | 0 |
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
| **jwc-app** | **84,972** | 85,068 | 2.40 | 3.58 | 4.89 | 1,274,646 | 0 | 0 |
| **liteapi-rust** | **40,960** | 40,960 | 1.38 | 14.67 | 40.16 | 615,115 | 0 | 0 |
| **liteapi-managed** | **14,095** | 14,106 | 12.80 | 19.15 | 28.25 | 211,693 | 0 | 0 |
| **node-fastify** | **10,944** | 10,944 | 18.37 | 18.84 | 19.21 | 164,341 | 0 | 0 |
| **python-fastapi** | **524** | 524 | 381.57 | 383.87 | 385.46 | 8,066 | 0 | 0 |

#### `/cpu` — CPU-Bound Workload (32 connections)

| Server | 2xx/s | RPS mean* | p50 (ms) | p90 (ms) | p99 (ms) | 2xx | non-2xx | client errors |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| **rust-axum** | **6,052** | 6,052 | 5.21 | 6.69 | 9.40 | 90,805 | 0 | 0 |
| **jwc-app** | **2,167** | 2,168 | 14.58 | 16.63 | 18.63 | 32,533 | 0 | 0 |
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
| **jwc-app** | **86,080** | 86,196 | 11.62 | 12.24 | 12.86 | 1,292,154 | 0 | 0 |
| **rust-axum** | **84,248** | 84,415 | 11.52 | 12.12 | 12.64 | 1,264,699 | 0 | 0 |
| **node-fastify** | **70,481** | 70,680 | 12.34 | 13.47 | 14.59 | 1,058,106 | 0 | 0 |
| **liteapi-managed** | **19,319** | 19,358 | 53.07 | 59.29 | 64.44 | 290,812 | 0 | 0 |
| **python-fastapi** | **11,800** | 11,798 | 83.73 | 91.93 | 93.87 | 177,729 | 0 | 0 |

#### `/db` — Single Random Row (64 connections)

| Server | 2xx/s | RPS mean* | p50 (ms) | p90 (ms) | p99 (ms) | 2xx | non-2xx | client errors |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| **go-fiber** | **406,141** | 406,159 | 0.15 | 0.23 | 0.50 | 6,092,124 | 0 | 0 |
| **rust-axum** | **293,533** | 293,537 | 0.17 | 0.41 | 0.70 | 4,403,031 | 0 | 0 |
| **jwc-app** | **285,773** | 285,789 | 0.19 | 0.34 | 0.73 | 4,286,602 | 0 | 0 |
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
| **jwc-app** | **30,239** | 30,241 | 2.05 | 2.62 | 3.36 | 453,629 | 0 | 0 |
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
| **jwc-app** | **6,452** | 6,452 | 9.65 | 11.06 | 12.99 | 96,843 | 0 | 0 |
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
| **jwc-app** | **1.28** | **1.30** | 4.89 | 18.63 | 12.86 | 0.73 | 3.36 | 12.99 |
| **liteapi-rust** | 6.64 | 6.31 | 40.16 | 524.74 | 17.95 | 1.73 | 5.59 | 15.77 |
| **liteapi-managed** | 12.63 | 17.21 | 28.25 | 602.13 | 64.44 | 8.76 | 15.24 | 20.77 |

---

## Windows

Same CPU and RAM as the Linux run above, and the same JWC 1.0.1 build, so the
two sections differ by operating system rather than by hardware or version.

Bombardier still counts client-side `dial tcp: actively refused` attempts in
`rps`; the tables rank `2xx/s`. Windows' default ephemeral-port range is
16,384 ports (49152–65535) against a 120 s `TIME_WAIT`, so at 500–1000
connections some dials are refused no matter how fast the server is. The range
was left at the default, as in the previous Windows run.

Refused dials are not spread evenly, though. On `/ping` go-fiber loses 2,949
and rust-axum 1,090, while liteapi-rust loses 1,163,072 — more than a third of
every dial it was offered — and python-fastapi 85,566. Whatever the port range
costs, liteapi-rust's embedded Rust listener and uvicorn are dropping
connections on top of it, so their `2xx/s` sits far below their `rps`.

| Component | Spec |
|---|---|
| **CPU** | Intel Core Ultra 7 265KF (20 cores) |
| **RAM** | 31.6 GB |
| **OS** | Windows 11 Pro 26H1 (10.0.28000) |
| **Bombardier** | v1.2.6 (windows/amd64, fasthttp client) |
| **Postgres** | 18.6 (x64 service), local `BenchJWCDB`, `world` table seeded with 10,000 rows |
| **JWC** | 1.0.1 native release build (`jwc build --release`) |
| **Test duration** | 15 s per endpoint (after 3 s warm-up) |
| **Timeout** | 5 s |
| **Ephemeral ports** | Windows default — 49152–65535 (16,384), `TIME_WAIT` 120 s |
| **Listen address** | `http://127.0.0.1:8080` (liteapi-rust on `:6080`, liteapi-managed on `:6070`) |

### Toolchains on this run

| Stack | Runtime / Compiler | DB driver |
|---|---|---|
| **dotnet-minimal** | .NET SDK 10.0.401, ASP.NET Core 10.0.12 (Kestrel) | Npgsql 9.0.3 |
| **go-fiber** | Go 1.27.1, Fiber v2.52.13 | pgx/v5 5.10.0 |
| **node-fastify** | Node 24.21.0, Fastify 5.8.5 | pg 8.22.0 |
| **python-fastapi** | Python 3.13.15, FastAPI 0.141.1, uvicorn 0.53.0 | asyncpg 0.31.0 |
| **rust-axum** | Rust 1.98.1, axum 0.8.9 | tokio-postgres 0.7.18 + deadpool 0.12.3 |
| **jwc-app** ⭐ | JWC 1.0.1 (native AOT → tokio/axum), rustc 1.98.1 | built-in (`database … : Postgres`) |
| **liteapi-rust** ⭐ | .NET 10.0 + LiteAPI.Core 2.3.0 (Rust TCP listener) | Npgsql 9.0.3 |
| **liteapi-managed** ⭐ | .NET 10.0 + LiteAPI.Core 2.3.0 (managed `Run()`) | Npgsql 9.0.3 |

### Successful Responses Per Second

| Endpoint | 1st | 2nd | 3rd | 4th | 5th | 6th | 7th | 8th |
|---|---|---|---|---|---|---|---|---|
| `/ping` | go-fiber **838,840** | dotnet **789,702** | rust-axum **244,488** | jwc-app **224,385** | liteapi-rust **131,703** | node **94,883** | liteapi-managed **93,547** | python **15,371** |
| `/json-small` | go-fiber **851,093** | dotnet **785,855** | rust-axum **240,984** | jwc-app **240,455** | liteapi-rust **139,469** | liteapi-managed **104,759** | node **96,625** | python **13,826** |
| `/json-large` | dotnet **132,828** | jwc-app **95,016** | rust-axum **86,260** | go-fiber **57,906** | liteapi-rust **32,650** | liteapi-managed **29,290** | node **9,640** | python **388** |
| `/cpu` | rust-axum **3,875** | jwc-app **2,065** | go-fiber **1,052** | liteapi-managed **94** | dotnet **83** | liteapi-rust **73** | python **40** | node **13** |
| `/async-delay` | go-fiber **95,176** | jwc-app **61,733** | rust-axum **61,625** | dotnet **59,676** | node **31,957** | liteapi-managed **13,848** | liteapi-rust **12,154** | python **11,143** |
| `/db` | go-fiber **241,838** | dotnet **233,534** | liteapi-rust **154,114** | rust-axum **108,452** | jwc-app **101,438** | liteapi-managed **54,817** | node **44,167** | python **6,686** |
| `/queries` | go-fiber **24,377** | dotnet **16,823** | liteapi-rust **13,394** | liteapi-managed **13,156** | rust-axum **11,093** | jwc-app **10,203** | node **4,336** | python **1,619** |
| `/updates` | go-fiber **6,454** | dotnet **5,347** | liteapi-rust **4,821** | rust-axum **4,676** | liteapi-managed **4,623** | jwc-app **4,375** | node **1,574** | python **919** |

### Detailed Endpoint Results

`2xx/s` is completed successful responses per second; `rps` is bombardier's
request rate and can include failed attempts.

#### `/ping` — Plain Text (500 connections)

| Server | 2xx/s | RPS mean* | p50 (ms) | p90 (ms) | p99 (ms) | 2xx | non-2xx | client errors |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| **go-fiber** | **838,840** | 839,254 | 0.00 | 1.74 | 2.50 | 12,582,700 | 0 | 2,949 |
| **dotnet-minimal** | **789,702** | 789,901 | 0.50 | 1.74 | 2.17 | 11,846,353 | 0 | 2,697 |
| **rust-axum** | **244,488** | 244,629 | 1.96 | 2.97 | 4.11 | 3,667,829 | 0 | 1,090 |
| **jwc-app** | **224,385** | 224,472 | 2.16 | 3.33 | 4.63 | 3,366,136 | 0 | 721 |
| **liteapi-rust** | **131,703** | 227,656 | 1.03 | 5.38 | 11.32 | 2,232,068 | 0 | 1,163,072 |
| **node-fastify** | **94,883** | 95,154 | 5.23 | 5.87 | 9.47 | 1,423,775 | 0 | 3,905 |
| **liteapi-managed** | **93,547** | 93,467 | 1.59 | 13.37 | 23.56 | 1,403,407 | 0 | 0 |
| **python-fastapi** | **15,371** | 21,048 | 31.20 | 32.65 | 42.53 | 230,915 | 0 | 85,566 |

#### `/json-small` — Tiny JSON Object (500 connections)

| Server | 2xx/s | RPS mean* | p50 (ms) | p90 (ms) | p99 (ms) | 2xx | non-2xx | client errors |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| **go-fiber** | **851,093** | 852,577 | 0.50 | 1.74 | 2.51 | 12,766,696 | 0 | 4,221 |
| **dotnet-minimal** | **785,855** | 785,983 | 0.50 | 1.74 | 2.25 | 11,788,753 | 0 | 4,024 |
| **rust-axum** | **240,984** | 241,192 | 2.02 | 3.05 | 4.31 | 3,615,055 | 0 | 1,987 |
| **jwc-app** | **240,455** | 240,603 | 2.02 | 3.08 | 4.35 | 3,607,270 | 0 | 1,700 |
| **liteapi-rust** | **139,469** | 216,546 | 1.05 | 5.43 | 12.39 | 2,093,021 | 0 | 1,138,511 |
| **liteapi-managed** | **104,759** | 104,888 | 1.56 | 12.52 | 17.26 | 1,572,361 | 0 | 0 |
| **node-fastify** | **96,625** | 96,914 | 5.10 | 5.53 | 6.16 | 1,449,852 | 0 | 3,994 |
| **python-fastapi** | **13,826** | 20,649 | 34.40 | 35.84 | 45.66 | 207,728 | 0 | 103,441 |

#### `/json-large` — 1000-item JSON Array (200 connections, ~42 KB body)

| Server | 2xx/s | RPS mean* | p50 (ms) | p90 (ms) | p99 (ms) | 2xx | non-2xx | client errors |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| **dotnet-minimal** | **132,828** | 132,874 | 1.50 | 2.45 | 3.98 | 1,992,470 | 0 | 0 |
| **jwc-app** | **95,016** | 95,055 | 2.06 | 3.09 | 4.13 | 1,425,382 | 0 | 0 |
| **rust-axum** | **86,260** | 86,281 | 2.23 | 3.45 | 4.91 | 1,294,108 | 0 | 0 |
| **go-fiber** | **57,906** | 57,915 | 1.23 | 10.90 | 22.43 | 868,781 | 0 | 0 |
| **liteapi-rust** | **32,650** | 32,676 | 4.14 | 10.19 | 48.64 | 489,841 | 0 | 0 |
| **liteapi-managed** | **29,290** | 29,325 | 5.04 | 16.23 | 29.87 | 439,491 | 0 | 0 |
| **node-fastify** | **9,640** | 9,641 | 20.61 | 21.39 | 22.67 | 144,799 | 0 | 0 |
| **python-fastapi** | **388** | 22,871 | 0.00 | 0.00 | 269.76 | 6,122 | 0 | 338,119 |

#### `/cpu` — CPU-Bound Workload (32 connections)

| Server | 2xx/s | RPS mean* | p50 (ms) | p90 (ms) | p99 (ms) | 2xx | non-2xx | client errors |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| **rust-axum** | **3,875** | 3,874 | 8.13 | 10.71 | 12.69 | 58,171 | 0 | 0 |
| **jwc-app** | **2,065** | 2,069 | 15.32 | 17.82 | 20.49 | 31,000 | 0 | 0 |
| **go-fiber** | **1,052** | 1,052 | 28.89 | 37.08 | 64.81 | 15,792 | 0 | 0 |
| **liteapi-managed** | **94** | 97 | 312.81 | 476.67 | 700.64 | 1,431 | 0 | 0 |
| **dotnet-minimal** | **83** | 87 | 370.90 | 483.45 | 528.55 | 1,270 | 0 | 0 |
| **liteapi-rust** | **73** | 88 | 420.77 | 574.15 | 675.24 | 1,117 | 0 | 0 |
| **python-fastapi** | **40** | 44 | 792.75 | 799.07 | 3170.54 | 624 | 0 | 0 |
| **node-fastify** | **13** | 12 | 2309.80 | 2665.26 | 2720.11 | 228 | 0 | 0 |

#### `/async-delay` — 10 ms `await sleep` (1000 connections)

| Server | 2xx/s | RPS mean* | p50 (ms) | p90 (ms) | p99 (ms) | 2xx | non-2xx | client errors |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| **go-fiber** | **95,176** | 95,585 | 10.39 | 10.82 | 11.51 | 1,428,658 | 0 | 4,667 |
| **jwc-app** | **61,733** | 61,914 | 15.85 | 17.20 | 25.27 | 927,045 | 0 | 3,682 |
| **rust-axum** | **61,625** | 62,189 | 15.88 | 17.29 | 25.09 | 925,085 | 0 | 8,336 |
| **dotnet-minimal** | **59,676** | 60,457 | 16.20 | 19.29 | 25.09 | 895,305 | 0 | 10,978 |
| **node-fastify** | **31,957** | 32,257 | 31.74 | 32.58 | 37.08 | 479,759 | 0 | 4,662 |
| **liteapi-managed** | **13,848** | 13,859 | 68.54 | 84.84 | 101.16 | 208,789 | 0 | 0 |
| **liteapi-rust** | **12,154** | 87,050 | 10.29 | 19.09 | 31.12 | 182,386 | 0 | 1,123,268 |
| **python-fastapi** | **11,143** | 35,579 | 4.95 | 84.58 | 105.73 | 167,781 | 0 | 365,179 |

#### `/db` — Single Random Row (64 connections)

| Server | 2xx/s | RPS mean* | p50 (ms) | p90 (ms) | p99 (ms) | 2xx | non-2xx | client errors |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| **go-fiber** | **241,838** | 241,869 | 0.00 | 0.56 | 1.27 | 3,627,492 | 0 | 0 |
| **dotnet-minimal** | **233,534** | 233,586 | 0.00 | 0.59 | 2.57 | 3,503,127 | 0 | 0 |
| **liteapi-rust** | **154,114** | 154,148 | 0.00 | 0.59 | 6.16 | 2,311,696 | 0 | 0 |
| **rust-axum** | **108,452** | 108,463 | 0.53 | 1.04 | 1.16 | 1,626,743 | 0 | 0 |
| **jwc-app** | **101,438** | 101,469 | 0.54 | 1.06 | 1.19 | 1,521,605 | 0 | 0 |
| **liteapi-managed** | **54,817** | 54,904 | 0.51 | 0.95 | 13.73 | 822,273 | 0 | 0 |
| **node-fastify** | **44,167** | 44,222 | 1.54 | 1.69 | 2.11 | 662,529 | 0 | 0 |
| **python-fastapi** | **6,686** | 6,686 | 8.79 | 9.92 | 15.33 | 100,316 | 0 | 0 |

#### `/queries` — 20 Random Rows per Request (64 connections)

| Server | 2xx/s | RPS mean* | p50 (ms) | p90 (ms) | p99 (ms) | 2xx | non-2xx | client errors |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| **go-fiber** | **24,377** | 24,382 | 2.10 | 4.76 | 11.61 | 365,683 | 0 | 0 |
| **dotnet-minimal** | **16,823** | 16,828 | 3.12 | 7.00 | 18.50 | 252,399 | 0 | 0 |
| **liteapi-rust** | **13,394** | 13,403 | 3.12 | 9.36 | 33.54 | 200,992 | 0 | 0 |
| **liteapi-managed** | **13,156** | 13,167 | 3.21 | 10.36 | 22.05 | 197,383 | 0 | 0 |
| **rust-axum** | **11,093** | 11,093 | 5.74 | 6.54 | 7.30 | 166,419 | 0 | 0 |
| **jwc-app** | **10,203** | 10,203 | 6.24 | 7.12 | 7.95 | 153,075 | 0 | 0 |
| **node-fastify** | **4,336** | 4,336 | 14.63 | 15.44 | 19.16 | 65,083 | 0 | 0 |
| **python-fastapi** | **1,619** | 1,619 | 39.15 | 40.76 | 46.14 | 24,314 | 0 | 0 |

#### `/updates` — 20 Read+Write Rows per Request (64 connections)

| Server | 2xx/s | RPS mean* | p50 (ms) | p90 (ms) | p99 (ms) | 2xx | non-2xx | client errors |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| **go-fiber** | **6,454** | 6,457 | 9.00 | 11.62 | 25.35 | 96,854 | 0 | 0 |
| **dotnet-minimal** | **5,347** | 5,351 | 11.10 | 14.20 | 31.78 | 80,257 | 0 | 0 |
| **liteapi-rust** | **4,821** | 4,823 | 12.35 | 16.66 | 28.71 | 72,378 | 0 | 0 |
| **rust-axum** | **4,676** | 4,676 | 13.49 | 14.77 | 19.94 | 70,175 | 0 | 0 |
| **liteapi-managed** | **4,623** | 4,625 | 12.50 | 19.39 | 35.03 | 69,377 | 0 | 0 |
| **jwc-app** | **4,375** | 4,375 | 14.40 | 16.02 | 21.62 | 65,656 | 0 | 0 |
| **node-fastify** | **1,574** | 1,574 | 40.49 | 42.60 | 54.49 | 23,651 | 0 | 0 |
| **python-fastapi** | **919** | 918 | 69.03 | 71.72 | 89.18 | 13,821 | 0 | 0 |

\* bombardier's `rps`, which counts failed dial attempts as requests.

### Tail Latency (p99, ms)

| Server | `/ping` | `/json-small` | `/json-large` | `/cpu` | `/async-delay` | `/db` | `/queries` | `/updates` |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| **dotnet-minimal** | **2.17** | **2.25** | **3.98** | 528.55 | 25.09 | 2.57 | 18.50 | 31.78 |
| **go-fiber** | 2.50 | 2.51 | 22.43 | 64.81 | **11.51** | 1.27 | 11.61 | 25.35 |
| **node-fastify** | 9.47 | 6.16 | 22.67 | 2,720.11 | 37.08 | 2.11 | 19.16 | 54.49 |
| **python-fastapi** | 42.53 | 45.66 | 269.76 | 3,170.54 | 105.73 | 15.33 | 46.14 | 89.18 |
| **rust-axum** | 4.11 | 4.31 | 4.91 | **12.69** | 25.09 | **1.16** | **7.30** | **19.94** |
| **jwc-app** | 4.63 | 4.35 | 4.13 | 20.49 | 25.27 | 1.19 | 7.95 | 21.62 |
| **liteapi-rust** | 11.32 | 12.39 | 48.64 | 675.24 | 31.12 | 6.16 | 33.54 | 28.71 |
| **liteapi-managed** | 23.56 | 17.26 | 29.87 | 700.64 | 101.16 | 13.73 | 22.05 | 35.03 |

---

## Reproduce

```powershell
# 0. Load generator + interpreted-stack deps
go install github.com/codesenberg/bombardier@v1.2.6   # or drop bombardier.exe in .dist/
npm --prefix ./node-fastify install
pip install fastapi "uvicorn[standard]" asyncpg

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
                  -WorkDir "$PWD\_my\jwc-app" -Port 8080

./.dist/report.ps1                     # regenerate summary JSON from saved results
python ./.dist/gen-tables.py ./.dist/results   # regenerate the README tables
```

The scripts resolve the repo root from their own location, and take bombardier
from `.dist/bombardier.exe` if present, otherwise from `PATH`. `-BindHost` only
matters for a server that does not listen on IPv4; JWC binds dual-stack from
1.0.1 on, so the `[::1]` workaround needed up to v0.8.0 is gone.

All stacks read `DATABASE_URL` and fall back to
`postgres://postgres:1234@localhost:5432/BenchJWCDB`. `jwc-app` reads
`DATABASE_URL` (or `JWC_DATABASE_URL`) and `PORT` from `_my/jwc-app/.env`; the
older `PG_HOST` / `PG_PORT` / `PG_USER` / `PG_PASSWORD` / `PG_DATABASE` split is
JWC 0.x only.

Raw bombardier JSON per endpoint is saved under `.dist/results/<server>/<endpoint>.json`;
the merged summary is `.dist/results/summary.json`.

