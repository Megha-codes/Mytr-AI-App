"""Shared test setup.

Pins the device store to a throwaway SQLite file and supplies a dummy
JWT_SECRET *before* any app module is imported, so tests run fully offline with
no Postgres / Timescale / real credentials. Each test gets a freshly-created
device schema.
"""

from __future__ import annotations

import os
import tempfile
from pathlib import Path

import pytest
import pytest_asyncio

# Must be set before importing app.* (config reads env at import; security.py
# raises if JWT_SECRET is missing; device_database binds its engine at import).
os.environ.setdefault("JWT_SECRET", "test-secret-not-used-anywhere-real")
_TMP_DB = Path(tempfile.mkdtemp(prefix="mytr-devtest-")) / "device.db"
os.environ["DEVICE_DATABASE_URL"] = f"sqlite+aiosqlite:///{_TMP_DB.as_posix()}"
os.environ.setdefault("LIBRE_POLLER_ENABLED", "false")


@pytest_asyncio.fixture(autouse=True)
async def fresh_device_schema():
    """Drop and recreate the device tables around every test for isolation."""
    from app.device_database import DeviceBase, device_engine
    from app.models import device  # noqa: F401  (register tables on metadata)

    async with device_engine.begin() as conn:
        await conn.run_sync(DeviceBase.metadata.drop_all)
        await conn.run_sync(DeviceBase.metadata.create_all)
    yield
    async with device_engine.begin() as conn:
        await conn.run_sync(DeviceBase.metadata.drop_all)
