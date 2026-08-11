"""Tests for GET /analytics/weekly (Phase-1 polish, part 2): glucose TIR/
GMI/trend, the food-glucose correlation feature, health metric trends,
nutrition trends, and the insights gate.
"""

from __future__ import annotations

import json
import uuid
from datetime import datetime, timedelta, timezone

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import text

from app.api import analytics
from app.core.security import create_access_token
from app.database import get_db
from app.models.glucose_reading import GlucoseReadingModel
from app.models.health_metric import HealthMetric
from app.models.meal_log import MealLog
import app.services.analytics.weekly as weekly_mod

from .conftest import build_sqlite_db, build_sqlite_timescale_db, make_user


@pytest.fixture
async def app_and_db():
    engine, session_factory = await build_sqlite_db()
    ts_engine, ts_session_factory = await build_sqlite_timescale_db()

    async def _get_db():
        async with session_factory() as session:
            yield session

    app = FastAPI()
    app.include_router(analytics.router)
    app.dependency_overrides[get_db] = _get_db

    # build_weekly_analytics opens its own TimescaleSessionLocal() directly
    # (not a FastAPI Depends), same pattern as device_data.py/dashboard.py
    # tests -- swap the module-level session factory, not a dependency
    # override.
    original_ts_factory = weekly_mod.TimescaleSessionLocal
    weekly_mod.TimescaleSessionLocal = ts_session_factory

    with TestClient(app) as client:
        yield client, session_factory, ts_session_factory

    weekly_mod.TimescaleSessionLocal = original_ts_factory
    await engine.dispose()
    await ts_engine.dispose()


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


async def _reading(ts_session_factory, user_id, value_mgdl, at: datetime):
    async with ts_session_factory() as session:
        session.add(GlucoseReadingModel(
            id=uuid.uuid4(), user_id=user_id, value_mgdl=value_mgdl,
            recorded_at=at, source="MANUAL",
        ))
        await session.commit()


async def _meal(
    session_factory, user_id, meal_time, name,
    post_1hr=None, post_2hr=None, outcome=None, carbs_g=40.0,
) -> str:
    async with session_factory() as session:
        meal = MealLog(
            user_id=user_id, meal_time=meal_time, food_items=[{"name": name}],
            total_calories=300, total_carbs_g=carbs_g, total_protein_g=10.0,
            total_fat_g=8.0, total_fiber_g=3.0,
            post_meal_glucose_1hr=post_1hr, post_meal_glucose_2hr=post_2hr,
            glucose_outcome=outcome,
        )
        session.add(meal)
        await session.commit()
        await session.refresh(meal)
        return str(meal.id)


async def _meal_raw(session_factory, user_id, meal_time, name, calories=300, carbs_g=40.0) -> str:
    """Raw-SQL insert with a *dashed* user_id string -- for the nutrition-
    trends test specifically, which reads via load_todays_meals's raw SQL
    (`user_id = :user_id` bound as `str(user_id)`, i.e. dashed). `_meal()`
    above inserts through the ORM instead, which on sqlite serializes
    UUIDs as undashed hex (tests/conftest.py's PG_UUID shim) -- fine for
    the food-glucose correlation queries (also ORM-typed comparisons,
    same hex encoding on both sides) but invisible to a raw dashed-string
    comparison. Same split as test_nutrition_meals_endpoints.py's
    _insert_meal/_insert_meal_orm, for the identical reason. Real Postgres
    has no such split; this is sqlite-test-harness-only.
    """
    meal_id = str(uuid.uuid4())
    async with session_factory() as session:
        await session.execute(
            text("""
                INSERT INTO meal_logs
                    (id, user_id, meal_time, food_items, total_calories, total_carbs_g,
                     total_protein_g, total_fat_g, total_fiber_g)
                VALUES
                    (:id, :user_id, :meal_time, :food_items, :calories, :carbs_g, :protein_g, :fat_g, :fiber_g)
            """),
            {
                "id": meal_id, "user_id": str(user_id), "meal_time": meal_time,
                "food_items": json.dumps([{"name": name}]), "calories": calories,
                "carbs_g": carbs_g, "protein_g": 10.0, "fat_g": 8.0, "fiber_g": 3.0,
            },
        )
        await session.commit()
    return meal_id


async def _health_sample(session_factory, user_id, metric, value, unit, at: datetime):
    async with session_factory() as session:
        session.add(HealthMetric(
            user_id=user_id, metric=metric, value=value, unit=unit,
            started_at=at, ended_at=at, source="APPLE_HEALTH",
        ))
        await session.commit()


# ── Empty state ──────────────────────────────────────────────────────────

async def test_no_data_at_all_is_honest_not_zero_filled(app_and_db):
    client, session_factory, _ts = app_and_db
    user = await make_user(session_factory, "a@example.com")
    token = create_access_token(subject=str(user.id), token_version=user.token_version)

    resp = client.get("/analytics/weekly", headers=_auth(token))
    assert resp.status_code == 200
    body = resp.json()

    assert body["glucose"]["has_data"] is False
    assert body["glucose"]["average_mgdl"] is None
    assert len(body["glucose"]["daily"]) == 7
    assert all(d["avg_mgdl"] is None for d in body["glucose"]["daily"])
    assert body["food_glucose_correlations"] == []
    assert body["health_trends"]["steps"]["has_data"] is False
    assert body["nutrition_trends"]["has_data"] is False
    assert body["insights"] == []


# ── Glucose summary ──────────────────────────────────────────────────────

async def test_glucose_summary_computes_average_gmi_and_tir(app_and_db):
    client, session_factory, ts = app_and_db
    user = await make_user(session_factory, "a@example.com")
    token = create_access_token(subject=str(user.id), token_version=user.token_version)

    now = datetime.now(timezone.utc)
    for value in (60, 120, 130, 200):  # below, target, target, above (default 70-180)
        await _reading(ts, user.id, value, now - timedelta(hours=1))

    resp = client.get("/analytics/weekly", headers=_auth(token))
    glucose = resp.json()["glucose"]

    assert glucose["has_data"] is True
    assert glucose["reading_count"] == 4
    assert glucose["average_mgdl"] == pytest.approx(127.5, abs=0.1)
    # GMI = 3.31 + 0.02392 * mean
    assert glucose["gmi_percent"] == pytest.approx(3.31 + 0.02392 * 127.5, abs=0.05)
    assert glucose["tir"] == {"below": 0.25, "target": 0.5, "above": 0.25}


async def test_glucose_daily_series_has_one_point_per_day_with_nulls_for_missing(app_and_db):
    client, session_factory, ts = app_and_db
    user = await make_user(session_factory, "a@example.com")
    token = create_access_token(subject=str(user.id), token_version=user.token_version)

    now = datetime.now(timezone.utc)
    await _reading(ts, user.id, 110, now - timedelta(hours=1))
    await _reading(ts, user.id, 150, now - timedelta(hours=2))

    resp = client.get("/analytics/weekly", headers=_auth(token))
    daily = resp.json()["glucose"]["daily"]

    assert len(daily) == 7
    today_point = daily[-1]
    assert today_point["reading_count"] == 2
    assert today_point["avg_mgdl"] == 130.0
    assert today_point["min_mgdl"] == 110
    assert today_point["max_mgdl"] == 150
    # No data on the other 6 days.
    assert all(d["reading_count"] == 0 and d["avg_mgdl"] is None for d in daily[:-1])


# ── Food-glucose correlation (the lead feature) ─────────────────────────

async def test_correlation_computes_delta_from_baseline_and_2hr_reading(app_and_db):
    client, session_factory, ts = app_and_db
    user = await make_user(session_factory, "a@example.com")
    token = create_access_token(subject=str(user.id), token_version=user.token_version)

    meal_time = datetime.now(timezone.utc) - timedelta(hours=3)
    await _reading(ts, user.id, 100, meal_time - timedelta(minutes=10))  # baseline
    await _meal(session_factory, user.id, meal_time, "Dosa", post_2hr=180, outcome="HIGH")

    resp = client.get("/analytics/weekly", headers=_auth(token))
    correlations = resp.json()["food_glucose_correlations"]

    assert len(correlations) == 1
    c = correlations[0]
    assert c["label"] == "Dosa"
    assert c["baseline_mgdl"] == 100
    assert c["post_meal_mgdl"] == 180
    assert c["delta_mgdl"] == 80
    assert c["window"] == "2hr"
    assert c["outcome"] == "HIGH"


async def test_correlation_falls_back_to_1hr_when_2hr_is_missing(app_and_db):
    client, session_factory, ts = app_and_db
    user = await make_user(session_factory, "a@example.com")
    token = create_access_token(subject=str(user.id), token_version=user.token_version)

    meal_time = datetime.now(timezone.utc) - timedelta(hours=1)
    await _reading(ts, user.id, 100, meal_time - timedelta(minutes=5))
    await _meal(session_factory, user.id, meal_time, "Rice", post_1hr=140)

    resp = client.get("/analytics/weekly", headers=_auth(token))
    c = resp.json()["food_glucose_correlations"][0]

    assert c["window"] == "1hr"
    assert c["delta_mgdl"] == 40


async def test_meal_with_no_post_meal_reading_is_excluded(app_and_db):
    client, session_factory, ts = app_and_db
    user = await make_user(session_factory, "a@example.com")
    token = create_access_token(subject=str(user.id), token_version=user.token_version)

    meal_time = datetime.now(timezone.utc) - timedelta(minutes=10)
    await _reading(ts, user.id, 100, meal_time - timedelta(minutes=5))
    await _meal(session_factory, user.id, meal_time, "Just logged")  # no post_1hr/2hr yet

    resp = client.get("/analytics/weekly", headers=_auth(token))
    assert resp.json()["food_glucose_correlations"] == []


async def test_meal_with_no_baseline_reading_nearby_is_excluded(app_and_db):
    client, session_factory, ts = app_and_db
    user = await make_user(session_factory, "a@example.com")
    token = create_access_token(subject=str(user.id), token_version=user.token_version)

    meal_time = datetime.now(timezone.utc) - timedelta(hours=3)
    # Reading exists, but well outside the 30-minute baseline tolerance.
    await _reading(ts, user.id, 100, meal_time - timedelta(hours=2))
    await _meal(session_factory, user.id, meal_time, "Untethered", post_2hr=180)

    resp = client.get("/analytics/weekly", headers=_auth(token))
    assert resp.json()["food_glucose_correlations"] == []


# ── Health + nutrition trends ────────────────────────────────────────────

async def test_health_trend_has_nulls_for_days_without_samples(app_and_db):
    client, session_factory, _ts = app_and_db
    user = await make_user(session_factory, "a@example.com")
    token = create_access_token(subject=str(user.id), token_version=user.token_version)

    now = datetime.now(timezone.utc)
    await _health_sample(session_factory, user.id, "steps", 6000, "count", now)

    resp = client.get("/analytics/weekly", headers=_auth(token))
    steps = resp.json()["health_trends"]["steps"]

    assert steps["has_data"] is True
    assert steps["daily"][-1]["value"] == 6000
    assert all(d["value"] is None for d in steps["daily"][:-1])


async def test_nutrition_trend_reflects_daily_totals(app_and_db):
    client, session_factory, _ts = app_and_db
    user = await make_user(session_factory, "a@example.com")
    token = create_access_token(subject=str(user.id), token_version=user.token_version)

    now = datetime.now(timezone.utc)
    await _meal_raw(session_factory, user.id, now, "Poha")

    resp = client.get("/analytics/weekly", headers=_auth(token))
    nutrition = resp.json()["nutrition_trends"]

    assert nutrition["has_data"] is True
    assert nutrition["daily"][-1]["calories"] == 300
    assert nutrition["daily"][-1]["carbs_g"] == 40.0


# ── Insights: gated on enough data + a real difference ──────────────────

async def test_no_insight_with_fewer_than_minimum_days(app_and_db):
    client, session_factory, ts = app_and_db
    user = await make_user(session_factory, "a@example.com")
    token = create_access_token(subject=str(user.id), token_version=user.token_version)

    now = datetime.now(timezone.utc)
    # Only 2 days of paired steps+glucose data -- below MIN_DAYS_FOR_INSIGHT.
    await _health_sample(session_factory, user.id, "steps", 3000, "count", now)
    await _reading(ts, user.id, 150, now)
    await _health_sample(session_factory, user.id, "steps", 9000, "count", now - timedelta(days=1))
    await _reading(ts, user.id, 110, now - timedelta(days=1))

    resp = client.get("/analytics/weekly", headers=_auth(token))
    assert resp.json()["insights"] == []


async def test_insight_appears_with_enough_days_and_a_real_difference(app_and_db):
    client, session_factory, ts = app_and_db
    user = await make_user(session_factory, "a@example.com")
    token = create_access_token(subject=str(user.id), token_version=user.token_version)

    now = datetime.now(timezone.utc)
    # 4 days: low-step days have clearly higher glucose than high-step days.
    day_data = [
        (3000, 180), (3200, 175),   # low steps, high glucose
        (9000, 110), (9500, 105),   # high steps, low glucose
    ]
    for i, (steps, glucose) in enumerate(day_data):
        day = now - timedelta(days=i)
        await _health_sample(session_factory, user.id, "steps", steps, "count", day)
        await _reading(ts, user.id, glucose, day)

    resp = client.get("/analytics/weekly", headers=_auth(token))
    insights = resp.json()["insights"]

    steps_insights = [i for i in insights if i["kind"] == "steps_glucose"]
    assert len(steps_insights) == 1
    assert "lower" in steps_insights[0]["text"]
    assert "more steps" in steps_insights[0]["text"]


async def test_no_insight_when_difference_is_within_noise(app_and_db):
    client, session_factory, ts = app_and_db
    user = await make_user(session_factory, "a@example.com")
    token = create_access_token(subject=str(user.id), token_version=user.token_version)

    now = datetime.now(timezone.utc)
    # 4 days, but glucose barely differs between low- and high-step days
    # (well under MIN_MEANINGFUL_GLUCOSE_DELTA).
    day_data = [(3000, 120), (3200, 122), (9000, 121), (9500, 119)]
    for i, (steps, glucose) in enumerate(day_data):
        day = now - timedelta(days=i)
        await _health_sample(session_factory, user.id, "steps", steps, "count", day)
        await _reading(ts, user.id, glucose, day)

    resp = client.get("/analytics/weekly", headers=_auth(token))
    steps_insights = [i for i in resp.json()["insights"] if i["kind"] == "steps_glucose"]
    assert steps_insights == []


async def test_requires_authentication(app_and_db):
    client, _session_factory, _ts = app_and_db
    resp = client.get("/analytics/weekly")
    assert resp.status_code == 401
