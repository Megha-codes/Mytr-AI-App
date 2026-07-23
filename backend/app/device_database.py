"""Async engine + session for the mytr-desk device pipeline store.

The device-facing endpoints (pairing, /v1/readings backfill, the WSS stream)
and the Libre poller persist through a dedicated store, kept on its own engine
so it can be pointed at SQLite for the offline end-to-end proof and the test
suite without disturbing the main app's Postgres config.

In production `DEVICE_DATABASE_URL` is unset and this falls back to the same
`DATABASE_URL` as the rest of the backend, so the `devices` / `device_readings`
tables (migrations/010) live alongside `users` in the main Postgres and the
`devices.user_id -> users.id` foreign key resolves normally.
"""

from __future__ import annotations

import os

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import declarative_base

# Prefer an explicit override (used by the offline proof / tests), otherwise
# ride on the main database URL so device tables sit in the same Postgres.
DEVICE_DATABASE_URL = os.getenv("DEVICE_DATABASE_URL") or os.getenv(
    "DATABASE_URL",
    "postgresql+asyncpg://mytai_user:mytai_password@localhost:5432/mytai_db",
)

device_engine = create_async_engine(DEVICE_DATABASE_URL, echo=False)

DeviceSessionLocal = async_sessionmaker(
    bind=device_engine,
    class_=AsyncSession,
    expire_on_commit=False,
)

DeviceBase = declarative_base()


async def get_device_db():
    async with DeviceSessionLocal() as session:
        yield session


async def init_device_schema() -> None:
    """Create the device-pipeline tables if they don't already exist.

    Mirrors ``init_timescale_schema``: programmatic, idempotent
    (checkfirst=True), and safe to run on every startup. On Postgres the raw
    SQL in migrations/010 is the source of truth; this create_all is a no-op
    there once the migration has run, and is what stands the schema up on the
    SQLite store used by the proof/tests.
    """
    # Import models so their tables are registered on DeviceBase.metadata.
    from .models import device as _device  # noqa: F401

    async with device_engine.begin() as conn:
        await conn.run_sync(DeviceBase.metadata.create_all)
