"""Tests for recompute_activity_log_projection (architecture-v3.md §4.2):
activity_logs as a projection recomputed from health_metrics.
"""

from __future__ import annotations

from datetime import date, datetime, timezone

from sqlalchemy import select

from app.models.activity import ActivityLog
from app.models.health_metric import HealthMetric
from app.services.health.activity_projection import recompute_activity_log_projection

from .conftest import build_sqlite_db, make_user


async def _add_sample(session_factory, user_id, metric, value, started_at, unit="count"):
    async with session_factory() as session:
        session.add(HealthMetric(
            user_id=user_id, metric=metric, value=value, unit=unit,
            started_at=started_at, ended_at=started_at, source="APPLE_HEALTH",
        ))
        await session.commit()


async def test_recompute_creates_a_new_activity_log_row():
    engine, session_factory = await build_sqlite_db()
    user = await make_user(session_factory, "a@example.com")
    day = date(2026, 8, 1)
    ts = datetime(2026, 8, 1, 9, 0, tzinfo=timezone.utc)

    await _add_sample(session_factory, user.id, "steps", 4210, ts)
    await _add_sample(session_factory, user.id, "active_energy_kcal", 318, ts, unit="kcal")
    await _add_sample(session_factory, user.id, "heart_rate", 72, ts, unit="bpm")

    async with session_factory() as db:
        await recompute_activity_log_projection(db, user.id, day)
        await db.commit()

    async with session_factory() as db:
        result = await db.execute(select(ActivityLog).where(ActivityLog.user_id == user.id))
        row = result.scalar_one()
    assert row.steps_today == 4210
    assert row.calories_burned == 318
    assert row.heart_rate == 72
    await engine.dispose()


async def test_recompute_updates_an_existing_row_rather_than_duplicating():
    engine, session_factory = await build_sqlite_db()
    user = await make_user(session_factory, "a@example.com")
    day = date(2026, 8, 1)

    await _add_sample(session_factory, user.id, "steps", 1000, datetime(2026, 8, 1, 9, 0, tzinfo=timezone.utc))
    async with session_factory() as db:
        await recompute_activity_log_projection(db, user.id, day)
        await db.commit()

    await _add_sample(session_factory, user.id, "steps", 2000, datetime(2026, 8, 1, 18, 0, tzinfo=timezone.utc))
    async with session_factory() as db:
        await recompute_activity_log_projection(db, user.id, day)
        await db.commit()

    async with session_factory() as db:
        result = await db.execute(select(ActivityLog).where(ActivityLog.user_id == user.id))
        rows = result.scalars().all()
    assert len(rows) == 1
    assert rows[0].steps_today == 3000  # both samples now counted
    await engine.dispose()


async def test_recompute_with_no_health_data_zeroes_the_projection():
    """activity_logs' own columns are NOT NULL with a 0 default (§4.2's
    projection target predates the "absent, not zero" rule health_metrics
    itself follows) — recomputing from nothing correctly reflects that as
    0, matching what POST /activity/sync already does for an unsynced day."""
    engine, session_factory = await build_sqlite_db()
    user = await make_user(session_factory, "a@example.com")

    async with session_factory() as db:
        await recompute_activity_log_projection(db, user.id, date(2026, 8, 1))
        await db.commit()

    async with session_factory() as db:
        result = await db.execute(select(ActivityLog).where(ActivityLog.user_id == user.id))
        row = result.scalar_one()
    assert row.steps_today == 0
    assert row.calories_burned == 0
    assert row.heart_rate == 0
    await engine.dispose()


async def test_recompute_only_touches_the_targeted_users_row():
    engine, session_factory = await build_sqlite_db()
    user_a = await make_user(session_factory, "a@example.com")
    user_b = await make_user(session_factory, "b@example.com")
    day = date(2026, 8, 1)

    await _add_sample(session_factory, user_a.id, "steps", 500, datetime(2026, 8, 1, 9, 0, tzinfo=timezone.utc))
    await _add_sample(session_factory, user_b.id, "steps", 900, datetime(2026, 8, 1, 9, 0, tzinfo=timezone.utc))

    async with session_factory() as db:
        await recompute_activity_log_projection(db, user_a.id, day)
        await db.commit()

    async with session_factory() as db:
        result = await db.execute(select(ActivityLog))
        rows = result.scalars().all()
    assert len(rows) == 1
    assert rows[0].user_id == user_a.id
    assert rows[0].steps_today == 500
    await engine.dispose()
