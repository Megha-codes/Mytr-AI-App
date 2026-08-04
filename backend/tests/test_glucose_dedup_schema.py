"""Structural tests for migration 011: glucose_readings.sensor_id/source +
the dedup unique index, and cgm_devices.region_base (architecture-v3.md
§1.3 / §4.3 step 3).
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone

from sqlalchemy import func, select
from sqlalchemy.dialects.sqlite import insert as sqlite_insert
from sqlalchemy import text

from app.models.glucose_reading import GlucoseReadingModel
from app.models.user import CGMDevice

from .conftest import build_sqlite_db, build_sqlite_timescale_db, make_user


async def test_source_defaults_to_libre():
    engine, session_factory = await build_sqlite_timescale_db()
    async with session_factory() as session:
        reading = GlucoseReadingModel(
            id=uuid.uuid4(),
            user_id=uuid.uuid4(),
            value_mgdl=100,
            recorded_at=datetime.now(timezone.utc),
        )
        session.add(reading)
        await session.commit()
        await session.refresh(reading)
    assert reading.source == "LIBRE"
    assert reading.sensor_id is None
    await engine.dispose()


async def test_dedup_index_ignores_duplicate_sensor_reading():
    engine, session_factory = await build_sqlite_timescale_db()
    user_id = uuid.uuid4()
    recorded_at = datetime.now(timezone.utc)

    async def _insert():
        stmt = sqlite_insert(GlucoseReadingModel).values(
            id=uuid.uuid4(),
            user_id=user_id,
            value_mgdl=120,
            recorded_at=recorded_at,
            sensor_id="sensor-1",
            source="LIBRE",
            device_type="LIBRE",
            is_continuous=True,
        ).on_conflict_do_nothing(
            index_elements=["user_id", "sensor_id", "recorded_at"],
            index_where=text("sensor_id IS NOT NULL"),
        )
        async with session_factory() as session:
            await session.execute(stmt)
            await session.commit()

    await _insert()
    await _insert()  # exact duplicate — must be ignored, not error

    async with session_factory() as session:
        result = await session.execute(select(func.count()).select_from(GlucoseReadingModel))
        assert result.scalar() == 1
    await engine.dispose()


async def test_dedup_index_does_not_apply_when_sensor_id_is_null():
    """Manual entries (no sensor_id) must not collide with each other just
    because they share a user_id/recorded_at — the index is partial."""
    engine, session_factory = await build_sqlite_timescale_db()
    user_id = uuid.uuid4()
    recorded_at = datetime.now(timezone.utc)

    async with session_factory() as session:
        session.add_all([
            GlucoseReadingModel(
                id=uuid.uuid4(), user_id=user_id, value_mgdl=100,
                recorded_at=recorded_at, source="MANUAL",
            ),
            GlucoseReadingModel(
                id=uuid.uuid4(), user_id=user_id, value_mgdl=105,
                recorded_at=recorded_at, source="MANUAL",
            ),
        ])
        await session.commit()

    async with session_factory() as session:
        result = await session.execute(select(func.count()).select_from(GlucoseReadingModel))
        assert result.scalar() == 2
    await engine.dispose()


async def test_cgm_device_region_base_is_nullable_and_settable():
    engine, session_factory = await build_sqlite_db()
    user = await make_user(session_factory, "a@example.com")

    async with session_factory() as session:
        device = CGMDevice(user_id=user.id, device_type="LIBRE_3")
        session.add(device)
        await session.commit()
        await session.refresh(device)
        assert device.region_base is None

        device.region_base = "https://api-eu.libreview.io"
        await session.commit()
        await session.refresh(device)
        assert device.region_base == "https://api-eu.libreview.io"
    await engine.dispose()
