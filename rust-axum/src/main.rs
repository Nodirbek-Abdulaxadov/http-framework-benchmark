use axum::{
    routing::get,
    Json,
    Router,
};
use serde::Serialize;
use sha2::{Digest, Sha256};
use tokio::time::{sleep, Duration};

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

#[tokio::main]
async fn main() {
    let app = Router::new()
        .route("/ping", get(ping))
        .route("/json-small", get(json_small))
        .route("/json-large", get(json_large))
        .route("/cpu", get(cpu))
        .route("/async-delay", get(async_delay));

    let listener = tokio::net::TcpListener::bind("0.0.0.0:8080")
        .await
        .unwrap();

    axum::serve(listener, app).await.unwrap();
}