import hashlib
import asyncio

from fastapi import FastAPI

app = FastAPI()


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