# JWC v0.8.0 — native backend defects

Found while porting `_my/jwc-app` (the HTTP benchmark app) to v0.8.0 and adding
a TechEmpower-shaped DB tier. Every item below is reproduced against a real
Postgres and confirmed by reading the Rust the compiler emitted into
`.jwc-build/src/main.rs` — none of it is inferred from behaviour alone.

```
jwc 0.8.0
build target: x86_64-pc-windows-msvc
build profile: release
git commit:   bdeebade6dd8
rustc 1.97.1 (8bab26f4f 2026-07-14)
OS:           Windows 11 Pro 10.0.22631
Postgres:     local, database BenchJWCDB
```

Shared schema for all repros:

```jwc
dbcontext BenchDb : Postgres;

entity World of BenchDb {
    id           int pk;
    randomNumber int;
}
```

```sql
CREATE TABLE world (
    id integer NOT NULL PRIMARY KEY,
    randomnumber integer NOT NULL
);
INSERT INTO world SELECT g, floor(random()*10000)::int FROM generate_series(1,10000) g;
```

| # | Defect | Severity | Silent? |
|---|---|---|---|
| [1](#1-native-update-binds-the-set-value-with-the-wrong-type) | Native `update … set` cannot write an `int` column | blocker | no — panics |
| [2](#2-wrong-arity-raw_sql-compiles-to-a-no-op) | Wrong-arity `raw_sql` compiles to a no-op | blocker | **yes** |
| [3](#3-the-two-backends-disagree-on-column-name-casing) | Native lower-cases column names, interpreter doesn't | high | no |
| [4](#4-a-db-error-panics-the-worker-instead-of-returning-500) | DB error panics the worker instead of returning 500 | high | no |
| [5](#5-serve-silently-accepts-a-host-argument-and-loses-the-port) | `serve(host, port)` loses the port, binds `:0` | high | **yes** |
| [6](#6-native-binaries-bind-ipv6-only) | Native binaries bind IPv6-only | medium | no |
| [7](#7-native-builtin-gaps) | Native builtin gaps (`unix_timestamp`, `random_int`) | low | no |

---

## 1. Native `update … set` binds the SET value with the wrong type

**Severity: blocker.** No form of `update … set <int column> = …` works in a
native build.

### Repro

```jwc
route GET "/u" {
    let id = 1;
    let v = 4242;
    update BenchDb.World set randomNumber = v where World.id == @id;
    let r = select World from BenchDb.World where World.id == @id first;
    return json(r);
}
```

```
jwc build --native --release
```

### Generated Rust (`.jwc-build/src/main.rs`)

```rust
let __params: DbParams = vec![
    jwc_param_str(new_val.clone()),   // <-- SET value bound as TEXT
    jwc_param_int(id.clone()),        // <-- WHERE value bound as int, correctly
];
let _ = jwc_db_exec("UPDATE \"world\" SET \"randomnumber\" = $1 WHERE \"id\" = $2", __params).await;
```

`jwc_param_str` is unconditional for the SET value:

```rust
fn jwc_param_str(v: V) -> Box<dyn tokio_postgres::types::ToSql + Sync + Send> {
    match v {
        V::Null => Box::new(None::<String>),
        V::Str(s) => Box::new(s.into_owned()),
        other => Box::new(other.to_string()),   // V::Int(4242) -> "4242"
    }
}
```

### Observed

```
thread 'tokio-rt-worker' (5876) panicked at src\main.rs:2241:29:
execute failed: error serializing parameter 0
SQL: UPDATE "world" SET "randomnumber" = $1 WHERE "id" = $2
```

### A literal doesn't help either

```jwc
update BenchDb.World set randomNumber = 4242 where World.id == @id;
```

```rust
let __params: DbParams = vec![
    jwc_param_bigint(V::Int(4242i64)),   // int8, not int4
    jwc_param_int(id.clone()),
];
```

Still wrong for an `int4` column — just a different wrong type. `set randomNumber = @v`
is a parse error, so that route is closed too.

### Expected

The SET value should be bound using the entity field's declared type, exactly as
the `where … == @id` path already does. The mechanism exists (`jwc_param_int` is
right there in the same `vec![]`); it simply isn't applied to the left-hand side
of a `set`.

### Workaround

See defect 2 — `raw_sql` binds `V::Int` correctly:

```jwc
raw_sql("UPDATE world SET randomnumber = $1 WHERE id = $2",
        "[" + new_val + "," + id + "]");
```

---

## 2. Wrong-arity `raw_sql` compiles to a no-op

**Severity: blocker. Fails silently — this is the worst of the set.**

`raw_sql` takes exactly two arguments: the SQL, and a JSON array *string* of
positional parameters. Calling it with the parameters spread as separate
arguments — the shape most people will try first, and the shape that mirrors
every other database API — compiles cleanly, passes `jwc check`, returns
**HTTP 200**, and does nothing at all.

### Repro

```jwc
route GET "/a" {
    let id = 1;
    let v = 4242;
    raw_sql("UPDATE world SET randomnumber = $1 WHERE id = $2", v, id);   // 3 args
    let r = select World from BenchDb.World where World.id == @id first;
    return json(r);
}
```

```
$ jwc check main.jwc
OK
$ jwc build --native --release
Native build complete (release)

$ curl 'http://[::1]:8081/a'
{"id":1,"randomNumber":7172}      # 200 OK — and 7172 is the OLD value
```

Verified independently against the database: the row was never touched.

### Generated Rust

```rust
let _ = jwc_b_raw_sql(V::Null, v_str("[]")).await;
```

Both the SQL text and the parameters are gone. `jwc_b_raw_sql` bails out on the
first line:

```rust
async fn jwc_b_raw_sql(sql: V, params_json: V) -> V {
    let sql_s: String = match sql {
        V::Str(s) => s.into_owned(),
        _ => return V::Null,          // <-- V::Null arrives here, returns immediately
    };
```

The codegen comment explains where the `V::Null` comes from:

```rust
// `params_json` is a JSON-encoded array of values bound positionally as $1, $2,
// .... It's variadic in JWC source (1 or 2 args); the codegen pads the missing
// param to `V::Str("[]")`.
```

With three arguments the padding logic evidently mis-fires and pads *both*
slots, discarding the arguments that were actually supplied.

### The correct call does work

```jwc
raw_sql("UPDATE world SET randomnumber = $1 WHERE id = $2", "[4242,1]");
```

```rust
jwc_b_raw_sql(v_str("UPDATE world SET randomnumber = $1 WHERE id = $2"), v_str("[4242,1]"))
```

```
$ curl 'http://[::1]:8081/a'
{"id":1,"randomNumber":4242}      # correct
```

Runtime-built parameter strings work too:

```jwc
let p = "[" + v + "," + id + "]";
raw_sql("UPDATE world SET randomnumber = $1 WHERE id = $2", p);
```

And the parameter coercion inside `jwc_b_raw_sql` is exactly what defect 1 is
missing — it picks the Postgres type from the runtime value:

```rust
.map(|p| match p {
    V::Int(n) => {
        if (i32::MIN as i64..=i32::MAX as i64).contains(&n) {
            Box::new(n as i32) as Box<dyn ToSql + Sync + Send>   // int4
        } else {
            Box::new(n)                                          // int8
        }
    }
    V::Float(_) => jwc_param_float(p),
    V::Bool(_)  => jwc_param_bool(p),
    _           => jwc_param_str(p),
})
```

### Expected

`raw_sql(sql, a, b)` should be either a compile error (`E0xx: raw_sql takes 2
arguments, 3 given`) or supported as genuine varargs. What it must not do is
compile to a statement that discards the query and reports success.

---

## 3. The two backends disagree on column-name casing

**Severity: high.** The same `.jwc` source needs two different database schemas
depending on how it is built.

| Backend | Emitted SQL |
|---|---|
| interpreter (`jwc build`) | `UPDATE "world" SET "randomNumber" = $1 WHERE "id" = $2` |
| native (`jwc build --native`) | `UPDATE "world" SET "randomnumber" = $1 WHERE "id" = $2` |

Against a lower-case column the interpreter fails:

```
[JWC-ERROR] Message: Failed to prepare SQL statement
[JWC-ERROR] Caused by[1]: ERROR: column "randomNumber" of relation "world" does not exist
```

Against a quoted camelCase column the native build fails with the defect-1
panic (or, once the type is fixed, `column "randomnumber" does not exist`).

Reads are unaffected, because `select` never names columns:

```rust
jwc_db_query_rows("SELECT * FROM \"world\" WHERE \"id\" = $1 LIMIT 1", __params)
```

and the row is decoded **positionally**, with the JSON key taken from the entity
field name rather than the database:

```rust
impl JwcEnt_World {
    fn jwc_from_row(row: &Row) -> Self {
        JwcEnt_World {
            id:           row.try_get::<_, i32>(0).unwrap_or_default(),
            randomNumber: row.try_get::<_, i32>(1).unwrap_or_default(),
        }
    }
    fn jwc_write_json(&self, out: &mut String) {
        out.push_str("\"randomNumber\":");
        ...
    }
}
```

### Expected

One casing rule, applied by both backends. Whichever is chosen, `gen-sql` must
emit a schema that both can query.

---

## 4. A DB error panics the worker instead of returning 500

**Severity: high.**

When the defect-1 bind failure happens in a native build, the client gets **no
HTTP response at all** — the connection is closed mid-request:

```
$ curl -s -m 25 -w '[%{http_code}]' 'http://[::1]:8080/updates?queries=3'
[000]
```

```
thread 'tokio-rt-worker' (5876) panicked at src\main.rs:2241:29:
execute failed: error serializing parameter 0
```

The process survives — a following `/ping` still answers 200 — but every failing
request panics a worker thread. Under 15 s of load at 64 connections that is
~26,000 panics.

The interpreter handles the identical failure correctly, with the v0.7 unified
envelope:

```json
{"code":"internal_error","error":"Internal server error. Check the server log for the matching x-request-id.","status":500}
```

Contributing factor: the generated code discards the result, so there is nothing
to check even if a caller wanted to.

```rust
let _ = jwc_db_exec("UPDATE ...", __params).await;
//  ^ result dropped
```

### Expected

Native builds should map a database error onto the same `{error, status, code,
details}` envelope the interpreter produces, not unwind the worker.

---

## 5. `serve()` silently accepts a host argument and loses the port

**Severity: high. Fails silently.**

```jwc
function main() { serve("0.0.0.0", 8081); }
```

```
$ jwc check main.jwc
OK
$ jwc build --native --release
Native build complete (release)
$ ./bin/release/nprobe.exe
[jwc] listening on http://[::]:0
```

Port `0` — the OS assigns an arbitrary ephemeral port, so the server is
effectively unreachable. There is no diagnostic at check time, build time, or
runtime. `serve(8081, "0.0.0.0")` and `serve("0.0.0.0:8081")` also pass `jwc check`.

### Expected

Either support a host argument, or reject the call at check time. Silently
dropping the one argument that *was* valid (the port) is the worst outcome.

---

## 6. Native binaries bind IPv6-only

**Severity: medium** (platform-specific).

`serve(8080)` in a native build binds `[::]`, and Windows defaults
`IPV6_V6ONLY` to on, so the server is unreachable on `127.0.0.1`:

```
$ ./bin/release/jwc-app.exe
[jwc] listening on http://[::]:8080

$ curl http://127.0.0.1:8080/ping     # fails
$ curl http://[::1]:8080/ping         # pong
```

The interpreter build of the same source is reachable on both. This is the
dual-stack fix listed in the v0.7 notes not reaching the native codegen path.
There is no environment variable to override the bind address — `JWC_PRINT_CONFIG`
lists ~38 settings and none of them is a host/bind knob.

Practical impact: any tooling that health-checks `127.0.0.1` (load generators,
container probes, reverse proxies configured for IPv4) sees the server as down.
The benchmark harness needed a dedicated `-BindHost '[::1]'` parameter for jwc
alone.

---

## 7. Native builtin gaps

**Severity: low** — the diagnostics here are good, this is a coverage gap rather
than a defect.

```
Native build does not yet support call to `unix_timestamp(...)` — unknown function.
Native build does not yet support call to `random_int(...)` — unknown function.
```

`random_int` is the more painful of the two: without an RNG the natural way to
pick a random row id in a native build doesn't exist. This app works around it
by parsing `now()`:

```jwc
let t = now();                                       // "2026-07-28T06:36:44.521Z"
let seed = int(substring(t, 17, 2)) * 1000           // seconds
         + int(substring(t, 20, 3));                 // milliseconds  -> 0..59999
let id = (seed * 7919 + i * 104729) % 10000 + 1;
```

Confirmed working in native builds: `now`, `uuid`, `substring`, `length`, `int`,
`replace`, `sha256`, `push`, `query_param`, `json`, `sleep_ms`, `raw_sql`, and
`select` / `update` against a `dbcontext`.

Confirmed missing: `unix_timestamp`, `random_int`, `substr`, `len`, `timestamp`,
`random`, `rand`, `unix_time`, `epoch_ms`, `now_ms`, `current_timestamp`,
`nanotime`.

---

## Suggested fix order

1. **Defect 2** — a silent no-op that reports success is the most dangerous
   behaviour here. Either reject the arity or support it.
2. **Defect 1** — bind the SET value by the entity field's type. The correct
   helper is already selected for the WHERE clause in the same statement.
3. **Defect 5** — same class as 2: silently discarding a supplied argument.
4. **Defect 4** — route database errors into the unified error envelope.
5. **Defect 3** — pick one casing rule for both backends.
6. **Defect 6**, **7** — dual-stack bind and the two missing builtins.

Defects 1, 2 and 4 together mean that a native JWC service which writes to an
`int` column will either crash on every write or silently drop them, with no
compile-time signal in either case. Read paths are unaffected and, on this
benchmark, genuinely fast — `/db` runs at 50k–55k req/s with a ~2.2 ms p99,
level with hand-written `tokio-postgres` + `deadpool`.
