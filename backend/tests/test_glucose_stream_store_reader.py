"""Tests for the glucose_stream.py websocket becoming a store reader
instead of an in-socket poller (architecture-v3.md §4.3 step 5):
_start_polling_loop is gone, and the CGM branch now reads
glucose_readings — written by the independent LibreIngestionService —
instead of hitting LibreLinkUp itself.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone

from app.models.glucose_reading import GlucoseReadingModel

from .conftest import build_sqlite_timescale_db


async def test_get_latest_stored_reading_returns_most_recent_row(monkeypatch):
    import app.timescale_database as ts_mod
    import app.api.websockets.glucose_stream as glucose_stream_mod

    engine, session_factory = await build_sqlite_timescale_db()
    monkeypatch.setattr(ts_mod, "TimescaleSessionLocal", session_factory)

    user_id = uuid.uuid4()
    older = datetime.now(timezone.utc) - timedelta(minutes=10)
    newer = datetime.now(timezone.utc)

    async with session_factory() as session:
        session.add_all([
            GlucoseReadingModel(
                id=uuid.uuid4(), user_id=user_id, value_mgdl=100, recorded_at=older,
                trend="STABLE", trend_arrow="→", sensor_id="s1", source="LIBRE",
            ),
            GlucoseReadingModel(
                id=uuid.uuid4(), user_id=user_id, value_mgdl=130, recorded_at=newer,
                trend="RISING", trend_arrow="↑", sensor_id="s1", source="LIBRE",
            ),
        ])
        await session.commit()

    reading = await glucose_stream_mod.get_latest_stored_reading(str(user_id), db=None)

    assert reading is not None
    assert reading.value == 130
    assert reading.trend == "RISING"
    assert reading.trend_arrow == "↑"
    await engine.dispose()


async def test_get_latest_stored_reading_returns_none_when_empty(monkeypatch):
    import app.timescale_database as ts_mod
    import app.api.websockets.glucose_stream as glucose_stream_mod

    engine, session_factory = await build_sqlite_timescale_db()
    monkeypatch.setattr(ts_mod, "TimescaleSessionLocal", session_factory)

    reading = await glucose_stream_mod.get_latest_stored_reading(str(uuid.uuid4()), db=None)
    assert reading is None
    await engine.dispose()


def test_glucose_stream_no_longer_polls_abbott_directly():
    """_start_polling_loop and its cgm_service_factory dependency are gone —
    the CGM branch reads the store instead."""
    import app.api.websockets.glucose_stream as glucose_stream_mod

    assert not hasattr(glucose_stream_mod, "_start_polling_loop")
    assert not hasattr(glucose_stream_mod, "cgm_service_factory")
    assert hasattr(glucose_stream_mod, "_start_store_reader_loop")
    assert hasattr(glucose_stream_mod, "get_latest_stored_reading")
