use axum::{
    extract::{Query, State},
    routing::get,
    Json,
    Router,
};
use deadpool_postgres::{Config, ManagerConfig, Pool, RecyclingMethod, Runtime};
use rand::Rng;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use tokio::time::{sleep, Duration};
use tokio_postgres::NoTls;

#[derive(Serialize)]
struct SmallResponse {
    id: i32,
    name: String,
    active: bool,
}

#[derive(Serialize)]
struct LargeResponse {
    id: i32,
    name: String,
    value: i32,
}

async fn ping() -> &'static str {
    "pong"
}

async fn json_small() -> Json<SmallResponse> {
    Json(SmallResponse {
        id: 1,
        name: "Test".to_string(),
        active: true,
    })
}

async fn json_large() -> Json<Vec<LargeResponse>> {
    let items: Vec<LargeResponse> = (0..1000)
        .map(|i| LargeResponse {
            id: i,
            name: format!("Item {}", i),
            value: i * 10,
        })
        .collect();

    Json(items)
}

async fn cpu() -> &'static str {
    let mut data = b"benchmark".to_vec();

    for _ in 0..100000 {
        let mut hasher = Sha256::new();
        hasher.update(&data);
        data = hasher.finalize().to_vec();
    }

    "done"
}

async fn async_delay() -> &'static str {
    sleep(Duration::from_millis(10)).await;
    "ok"
}

// -------------------- DB tier --------------------

#[derive(Serialize)]
struct World {
    id: i32,
    #[serde(rename = "randomNumber")]
    random_number: i32,
}

#[derive(Deserialize)]
struct QueriesParam {
    queries: Option<String>,
}

/// Missing or unparsable `?queries=` is 1; the value is pinned to 1..500.
fn clamp_queries(raw: Option<String>) -> usize {
    match raw.and_then(|s| s.parse::<i64>().ok()) {
        Some(n) if n < 1 => 1,
        Some(n) if n > 500 => 500,
        Some(n) => n as usize,
        None => 1,
    }
}

fn random_id() -> i32 {
    rand::thread_rng().gen_range(1..=10_000)
}

async fn fetch_world(pool: &Pool, id: i32) -> World {
    let client = pool.get().await.unwrap();
    let stmt = client
        .prepare_cached("SELECT id, randomnumber FROM world WHERE id = $1")
        .await
        .unwrap();
    let row = client.query_one(&stmt, &[&id]).await.unwrap();
    World {
        id: row.get(0),
        random_number: row.get(1),
    }
}

async fn db(State(pool): State<Pool>) -> Json<World> {
    Json(fetch_world(&pool, random_id()).await)
}

async fn queries(State(pool): State<Pool>, Query(q): Query<QueriesParam>) -> Json<Vec<World>> {
    let n = clamp_queries(q.queries);
    let mut rows = Vec::with_capacity(n);
    for _ in 0..n {
        rows.push(fetch_world(&pool, random_id()).await);
    }
    Json(rows)
}

async fn updates(State(pool): State<Pool>, Query(q): Query<QueriesParam>) -> Json<Vec<World>> {
    let n = clamp_queries(q.queries);
    let mut rows = Vec::with_capacity(n);
    for _ in 0..n {
        let mut world = fetch_world(&pool, random_id()).await;
        world.random_number = random_id();

        let client = pool.get().await.unwrap();
        let stmt = client
            .prepare_cached("UPDATE world SET randomnumber = $1 WHERE id = $2")
            .await
            .unwrap();
        client
            .execute(&stmt, &[&world.random_number, &world.id])
            .await
            .unwrap();

        rows.push(world);
    }
    Json(rows)
}

#[tokio::main]
async fn main() {
    // DB tier (/db, /queries, /updates). Pool capped at 64 to match jwc's
    // JWC_DB_POOL_SIZE default and the bench's 64 concurrent connections.
    let mut cfg = Config::new();
    cfg.url = Some(
        std::env::var("DATABASE_URL")
            .unwrap_or_else(|_| "postgres://postgres:1234@localhost:5432/BenchJWCDB".to_string()),
    );
    cfg.manager = Some(ManagerConfig {
        recycling_method: RecyclingMethod::Fast,
    });
    cfg.pool = Some(deadpool_postgres::PoolConfig::new(64));
    let pool = cfg.create_pool(Some(Runtime::Tokio1), NoTls).unwrap();

    let app = Router::new()
        .route("/ping", get(ping))
        .route("/json-small", get(json_small))
        .route("/json-large", get(json_large))
        .route("/cpu", get(cpu))
        .route("/async-delay", get(async_delay))
        .route("/db", get(db))
        .route("/queries", get(queries))
        .route("/updates", get(updates))
        .with_state(pool);

    let listener = tokio::net::TcpListener::bind("0.0.0.0:8080")
        .await
        .unwrap();

    axum::serve(listener, app).await.unwrap();
}