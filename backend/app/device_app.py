"""Isolated ASGI app exposing only the mytr-desk device pipeline.

Same routes and poller as the full app, but without the mobile app's Timescale
/ main-Postgres startup — so it can run fully offline (SQLite store,
``DEVICE_DATABASE_URL=sqlite+aiosqlite:///...``) for the end-to-end proof and
local dev against syncd. Production serves these routes from app.main instead.

Run:  uvicorn app.device_app:app --host 0.0.0.0 --port 8000
"""

from __future__ import annotations

from fastapi import FastAPI

from .api.devices import router as devices_router
from .api.websockets import device_stream
from .device_runtime import start_device_pipeline, stop_device_pipeline

app = FastAPI(title="Mytr.AI Device Pipeline", version="1.0.0")


@app.on_event("startup")
async def startup() -> None:
    await start_device_pipeline()


@app.on_event("shutdown")
async def shutdown() -> None:
    await stop_device_pipeline()


app.include_router(devices_router, prefix="/v1", tags=["devices"])
app.include_router(device_stream.router, tags=["websockets"])
