"""Structural tests for migration 013: health_metrics (architecture-v3.md
§1.4) — the dedup index and the metric-agnostic column.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone

from sqlalchemy import func, select
from sqlalchemy import text
from sqlalchemy.dialects.sqlite import insert as sqlite_insert

from app.models.health_metric import HealthMetric

from .conftest import build_sqlite_db, make_user


async def test_metric_column_accepts_any_string_including_hrv_and_new_metrics():
    """Metric-agnostic: not a CHECK-constrained enum."""
    engine, session_factory = await build_sqlite_db()
    user = await make_user(session_factory, "a@example.com")
    now = datetime.now(timezone.utc)

    async with session_factory() as session:
        for metric, unit in [
            ("steps", "count"), ("active_energy_kcal", "kcal"), ("heart_rate", "bpm"),
            ("resting_heart_rate", "bpm"), ("hrv", "ms"), ("sleep_minutes", "min"),
            ("weight_kg", "kg"), ("some_brand_new_metric_nobody_has_seen_yet", "widgets"),
        ]:
            session.add(HealthMetric(
                user_id=user.id, metric=metric, value=1.0, unit=unit,
                started_at=now, ended_at=now, source="APPLE_HEALTH",
            ))
        await session.commit()

    async with session_factory() as session:
        result = await session.execute(select(func.count()).select_from(HealthMetric))
        assert result.scalar() == 8
    await engine.dispose()


async def test_dedup_index_ignores_duplicate_external_id():
    engine, session_factory = await build_sqlite_db()
    user = await make_user(session_factory, "a@example.com")
    now = datetime.now(timezone.utc)

    async def _insert():
        stmt = sqlite_insert(HealthMetric).values(
            id=uuid.uuid4(), user_id=user.id, metric="steps", value=100, unit="count",
            started_at=now, ended_at=now, source="APPLE_HEALTH", external_id="sample-1",
        ).on_conflict_do_nothing(
            index_elements=["user_id", "source", "metric", "external_id"],
            index_where=text("external_id IS NOT NULL"),
        )
        async with session_factory() as session:
            await session.execute(stmt)
            await session.commit()

    await _insert()
    await _insert()

    async with session_factory() as session:
        result = await session.execute(select(func.count()).select_from(HealthMetric))
        assert result.scalar() == 1
    await engine.dispose()


async def test_dedup_index_does_not_apply_when_external_id_is_null():
    """Aggregated step buckets without a stable id (the app sends
    external_id = "{metric}:{bucket_start_iso}" for those per §1.4 — but the
    schema itself must not silently collapse legitimately-null rows)."""
    engine, session_factory = await build_sqlite_db()
    user = await make_user(session_factory, "a@example.com")
    now = datetime.now(timezone.utc)

    async with session_factory() as session:
        session.add_all([
            HealthMetric(
                user_id=user.id, metric="heart_rate", value=70, unit="bpm",
                started_at=now, ended_at=now, source="MANUAL", external_id=None,
            ),
            HealthMetric(
                user_id=user.id, metric="heart_rate", value=72, unit="bpm",
                started_at=now, ended_at=now, source="MANUAL", external_id=None,
            ),
        ])
        await session.commit()

    async with session_factory() as session:
        result = await session.execute(select(func.count()).select_from(HealthMetric))
        assert result.scalar() == 2
    await engine.dispose()


async def test_dedup_is_scoped_per_source_and_metric():
    """The same external_id from two different sources, or for two
    different metrics, must not collide — the index is on the full
    (user_id, source, metric, external_id) tuple."""
    engine, session_factory = await build_sqlite_db()
    user = await make_user(session_factory, "a@example.com")
    now = datetime.now(timezone.utc)

    async with session_factory() as session:
        session.add_all([
            HealthMetric(
                user_id=user.id, metric="steps", value=100, unit="count",
                started_at=now, ended_at=now, source="APPLE_HEALTH", external_id="sample-x",
            ),
            HealthMetric(
                user_id=user.id, metric="steps", value=100, unit="count",
                started_at=now, ended_at=now, source="GOOGLE_HEALTH_CONNECT", external_id="sample-x",
            ),
            HealthMetric(
                user_id=user.id, metric="active_energy_kcal", value=50, unit="kcal",
                started_at=now, ended_at=now, source="APPLE_HEALTH", external_id="sample-x",
            ),
        ])
        await session.commit()

    async with session_factory() as session:
        result = await session.execute(select(func.count()).select_from(HealthMetric))
        assert result.scalar() == 3
    await engine.dispose()
