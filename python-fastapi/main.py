import hashlib
import asyncio
import os
import random

import asyncpg
from fastapi import FastAPI

app = FastAPI()

DSN = os.getenv("DATABASE_URL", "postgres://postgres:1234@localhost:5432/BenchJWCDB")

pool: asyncpg.Pool | None = None


@app.on_event("startup")
async def startup():
    # DB tier (/db, /queries, /updates). Pool capped at 64 to match jwc's
    # JWC_DB_POOL_SIZE default and the bench's 64 concurrent connections.
    global pool
    pool = await asyncpg.create_pool(DSN, min_size=8, max_size=64)


def clamp_queries(raw: str | None) -> int:
    """Missing or unparsable ?queries= is 1; the value is pinned to 1..500."""
    try:
        n = int(raw)
    except (TypeError, ValueError):
        return 1
    return 1 if n < 1 else 500 if n > 500 else n


async def fetch_world(conn, world_id: int) -> dict:
    row = await conn.fetchrow(
        "SELECT id, randomnumber FROM world WHERE id = $1", world_id)
    return {"id": row["id"], "randomNumber": row["randomnumber"]}


@app.get("/ping")
async def ping():
    return "pong"


@app.get("/json-small")
async def json_small():
    return {
        "id": 1,
        "name": "Test",
        "active": True
    }


@app.get("/json-large")
async def json_large():
    return [
        {
            "id": i,
            "name": f"Item {i}",
            "value": i * 10
        }
        for i in range(1000)
    ]


@app.get("/cpu")
async def cpu():
    data = b"benchmark"

    for _ in range(100000):
        data = hashlib.sha256(data).digest()

    return "done"


@app.get("/async-delay")
async def async_delay():
    await asyncio.sleep(0.01)
    return "ok"


# -------------------- DB tier --------------------


@app.get("/db")
async def db():
    async with pool.acquire() as conn:
        return await fetch_world(conn, random.randint(1, 10000))


@app.get("/queries")
async def queries(queries: str | None = None):
    n = clamp_queries(queries)
    async with pool.acquire() as conn:
        return [await fetch_world(conn, random.randint(1, 10000)) for _ in range(n)]


@app.get("/updates")
async def updates(queries: str | None = None):
    n = clamp_queries(queries)
    rows = []
    async with pool.acquire() as conn:
        for _ in range(n):
            row = await fetch_world(conn, random.randint(1, 10000))
            row["randomNumber"] = random.randint(1, 10000)
            await conn.execute(
                "UPDATE world SET randomnumber = $1 WHERE id = $2",
                row["randomNumber"], row["id"])
            rows.append(row)
    return rows