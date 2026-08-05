"""Tests for compute_daily_rollup (architecture-v3.md §1.4): aggregation
strategy per metric, per-user timezone day boundaries, and the "absent, not
zero-filled" contract for unsynced metrics.
"""

from __future__ import annotations

from datetime import date, datetime, timedelta, timezone

from app.models.health_metric import HealthMetric
from app.services.health.daily_rollup import compute_daily_rollup

from .conftest import build_sqlite_db, make_user


async def _add_sample(session_factory, user_id, metric, value, started_at, source="APPLE_HEALTH", unit="count"):
    async with session_factory() as session:
        session.add(HealthMetric(
            user_id=user_id, metric=metric, value=value, unit=unit,
            started_at=started_at, ended_at=started_at, source=source,
        ))
        await session.commit()


async def test_steps_and_calories_sum_across_the_day():
    engine, session_factory = await build_sqlite_db()
    user = await make_user(session_factory, "a@example.com")
    day = date(2026, 8, 1)
    morning = datetime(2026, 8, 1, 9, 0, tzinfo=timezone.utc)
    evening = datetime(2026, 8, 1, 18, 0, tzinfo=timezone.utc)

    await _add_sample(session_factory, user.id, "steps", 1500, morning)
    await _add_sample(session_factory, user.id, "steps", 2710, evening)
    await _add_sample(session_factory, user.id, "active_energy_kcal", 120, morning, unit="kcal")
    await _add_sample(session_factory, user.id, "active_energy_kcal", 198, evening, unit="kcal")

    async with session_factory() as db:
        rollup = await compute_daily_rollup(db, user.id, day)

    assert rollup["steps"] == 4210
    assert rollup["active_energy_kcal"] == 318
    assert "updated_at" in rollup
    await engine.dispose()


async def test_heart_rate_and_hrv_average_across_samples():
    engine, session_factory = await build_sqlite_db()
    user = await make_user(session_factory, "a@example.com")
    day = date(2026, 8, 1)
    t1 = datetime(2026, 8, 1, 9, 0, tzinfo=timezone.utc)
    t2 = datetime(2026, 8, 1, 15, 0, tzinfo=timezone.utc)

    await _add_sample(session_factory, user.id, "heart_rate", 68, t1, unit="bpm")
    await _add_sample(session_factory, user.id, "heart_rate", 76, t2, unit="bpm")
    await _add_sample(session_factory, user.id, "hrv", 40.0, t1, unit="ms")
    await _add_sample(session_factory, user.id, "hrv", 50.0, t2, unit="ms")
    await _add_sample(session_factory, user.id, "resting_heart_rate", 58, t1, unit="bpm")

    async with session_factory() as db:
        rollup = await compute_daily_rollup(db, user.id, day)

    assert rollup["heart_rate"] == 72
    assert rollup["hrv"] == 45.0
    assert rollup["resting_heart_rate"] == 58
    await engine.dispose()


async def test_sleep_minutes_sums_multiple_segments():
    engine, session_factory = await build_sqlite_db()
    user = await make_user(session_factory, "a@example.com")
    day = date(2026, 8, 1)
    t1 = datetime(2026, 8, 1, 1, 0, tzinfo=timezone.utc)
    t2 = datetime(2026, 8, 1, 5, 0, tzinfo=timezone.utc)

    await _add_sample(session_factory, user.id, "sleep_minutes", 180, t1, unit="min")
    await _add_sample(session_factory, user.id, "sleep_minutes", 220, t2, unit="min")

    async with session_factory() as db:
        rollup = await compute_daily_rollup(db, user.id, day)
    assert rollup["sleep_minutes"] == 400
    await engine.dispose()


async def test_weight_uses_the_latest_sample_not_a_sum_or_average():
    engine, session_factory = await build_sqlite_db()
    user = await make_user(session_factory, "a@example.com")
    day = date(2026, 8, 1)
    earlier = datetime(2026, 8, 1, 7, 0, tzinfo=timezone.utc)
    later = datetime(2026, 8, 1, 19, 0, tzinfo=timezone.utc)

    await _add_sample(session_factory, user.id, "weight_kg", 70.2, earlier, unit="kg")
    await _add_sample(session_factory, user.id, "weight_kg", 70.0, later, unit="kg")

    async with session_factory() as db:
        rollup = await compute_daily_rollup(db, user.id, day)
    assert rollup["weight_kg"] == 70.0
    await engine.dispose()


async def test_unrecognized_metric_defaults_to_average():
    engine, session_factory = await build_sqlite_db()
    user = await make_user(session_factory, "a@example.com")
    day = date(2026, 8, 1)
    t1 = datetime(2026, 8, 1, 7, 0, tzinfo=timezone.utc)
    t2 = datetime(2026, 8, 1, 19, 0, tzinfo=timezone.utc)

    await _add_sample(session_factory, user.id, "blood_oxygen_pct", 96, t1, unit="pct")
    await _add_sample(session_factory, user.id, "blood_oxygen_pct", 98, t2, unit="pct")

    async with session_factory() as db:
        rollup = await compute_daily_rollup(db, user.id, day)
    assert rollup["blood_oxygen_pct"] == 97
    await engine.dispose()


async def test_absent_metric_is_not_present_in_the_rollup_at_all():
    engine, session_factory = await build_sqlite_db()
    user = await make_user(session_factory, "a@example.com")
    day = date(2026, 8, 1)
    await _add_sample(session_factory, user.id, "steps", 100, datetime(2026, 8, 1, 9, 0, tzinfo=timezone.utc))

    async with session_factory() as db:
        rollup = await compute_daily_rollup(db, user.id, day)

    assert "steps" in rollup
    assert "heart_rate" not in rollup  # never zero-filled — just absent
    await engine.dispose()


async def test_no_data_for_the_day_returns_empty_dict():
    engine, session_factory = await build_sqlite_db()
    user = await make_user(session_factory, "a@example.com")

    async with session_factory() as db:
        rollup = await compute_daily_rollup(db, user.id, date(2026, 8, 1))
    assert rollup == {}
    await engine.dispose()


async def test_samples_outside_the_day_are_excluded():
    engine, session_factory = await build_sqlite_db()
    user = await make_user(session_factory, "a@example.com")
    day = date(2026, 8, 1)

    await _add_sample(session_factory, user.id, "steps", 100, datetime(2026, 7, 31, 23, 0, tzinfo=timezone.utc))
    await _add_sample(session_factory, user.id, "steps", 200, datetime(2026, 8, 2, 0, 0, tzinfo=timezone.utc))

    async with session_factory() as db:
        rollup = await compute_daily_rollup(db, user.id, day)
    assert rollup == {}
    await engine.dispose()


async def test_day_boundary_respects_user_timezone():
    """9pm Aug 1 in Asia/Kolkata (UTC+5:30) is 3:30pm UTC — still Aug 1
    locally, so it must count toward Aug 1's rollup even though a naive UTC
    day boundary would place it correctly too; the real test is the reverse:
    11pm Aug 1 Kolkata is 5:30pm UTC (still Aug 1 UTC) but late enough
    locally to matter for day-boundary correctness generally. We assert the
    concrete case that would fail under a UTC-only day boundary: 1am Aug 2
    India time (that's 7:30pm Aug 1 UTC) must NOT count toward Aug 1 in
    India-local rollups, and *must* count toward Aug 2."""
    engine, session_factory = await build_sqlite_db()
    user = await make_user(session_factory, "a@example.com")
    # 1:00 AM Aug 2 IST == 19:30 Aug 1 UTC
    ist_1am_aug2 = datetime(2026, 8, 1, 19, 30, tzinfo=timezone.utc)
    await _add_sample(session_factory, user.id, "steps", 55, ist_1am_aug2)

    async with session_factory() as db:
        aug1_rollup = await compute_daily_rollup(db, user.id, date(2026, 8, 1), user_timezone="Asia/Kolkata")
        aug2_rollup = await compute_daily_rollup(db, user.id, date(2026, 8, 2), user_timezone="Asia/Kolkata")

    assert aug1_rollup == {}
    assert aug2_rollup["steps"] == 55
    await engine.dispose()


async def test_invalid_timezone_falls_back_to_utc():
    engine, session_factory = await build_sqlite_db()
    user = await make_user(session_factory, "a@example.com")
    await _add_sample(session_factory, user.id, "steps", 10, datetime(2026, 8, 1, 12, 0, tzinfo=timezone.utc))

    async with session_factory() as db:
        rollup = await compute_daily_rollup(db, user.id, date(2026, 8, 1), user_timezone="Not/ARealZone")
    assert rollup["steps"] == 10
    await engine.dispose()
