"""Proves POST /glucose/manual publishes through the same FanoutHub as
LibreIngestionService (architecture-v3.md §2.6) — manual and Libre readings
must be indistinguishable downstream.
"""

from __future__ import annotations

from datetime import datetime, timezone

import app.services.glucose.manual_log_service as manual_log_module
from app.api.glucose import ManualGlucoseRequest, log_manual_glucose
from app.services.realtime.fanout_hub import FanoutHub

from .conftest import build_sqlite_timescale_db, make_user, build_sqlite_db


async def test_manual_entry_publishes_a_glucose_reading_frame(monkeypatch):
    db_engine, db_session_factory = await build_sqlite_db()
    ts_engine, ts_session_factory = await build_sqlite_timescale_db()
    user = await make_user(db_session_factory, "manual-entry@example.com")

    hub = FanoutHub()
    queue = hub.subscribe(user.id)
    monkeypatch.setattr(manual_log_module, "fanout_hub", hub)
    monkeypatch.setattr(manual_log_module, "TimescaleSessionLocal", ts_session_factory)

    timestamp = datetime.now(timezone.utc)
    async with db_session_factory() as db:
        await log_manual_glucose(
            ManualGlucoseRequest(value_mgdl=145, timestamp=timestamp),
            current_user=user,
            db=db,
        )

    frame = queue.get_nowait()
    assert queue.empty()
    assert frame["type"] == "glucose.reading"
    assert frame["data"]["mgdl"] == 145
    assert frame["data"]["source"] == "MANUAL"
    assert frame["data"]["sensor_id"] is None

    await db_engine.dispose()
    await ts_engine.dispose()


async def test_manual_and_libre_readings_share_the_same_envelope_shape(monkeypatch):
    """The explicit §2.6 requirement: manual and CGM readings must be
    indistinguishable downstream — same data keys, only source/sensor_id
    differ."""
    db_engine, db_session_factory = await build_sqlite_db()
    ts_engine, ts_session_factory = await build_sqlite_timescale_db()
    user = await make_user(db_session_factory, "parity-check@example.com")

    hub = FanoutHub()
    queue = hub.subscribe(user.id)
    monkeypatch.setattr(manual_log_module, "fanout_hub", hub)
    monkeypatch.setattr(manual_log_module, "TimescaleSessionLocal", ts_session_factory)

    async with db_session_factory() as db:
        await log_manual_glucose(
            ManualGlucoseRequest(value_mgdl=130, timestamp=datetime.now(timezone.utc)),
            current_user=user,
            db=db,
        )
    manual_frame = queue.get_nowait()

    libre_frame = hub.publish_glucose_reading(
        user.id, recorded_at=datetime.now(timezone.utc), mgdl=130,
        trend="STABLE", trend_arrow="→", sensor_id="sensor-1", source="LIBRE",
    )

    assert set(manual_frame.keys()) == set(libre_frame.keys())
    assert set(manual_frame["data"].keys()) == set(libre_frame["data"].keys())
    assert manual_frame["type"] == libre_frame["type"] == "glucose.reading"

    await db_engine.dispose()
    await ts_engine.dispose()
