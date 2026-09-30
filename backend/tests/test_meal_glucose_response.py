"""Tests for GET /nutrition/meals/{meal_id}/glucose-response — the
meal-detail screen's real CGM-response section. Same dual-database pattern
as test_analytics_weekly.py: meal_logs/insulin_profiles live in the main
DB, glucose_readings in TimescaleDB, and the service opens its own
TimescaleSessionLocal() directly rather than via FastAPI Depends.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.api import nutrition
from app.core.security import create_access_token
from app.database import get_db
from app.models.glucose_reading import GlucoseReadingModel
from app.models.meal_log import MealLog
from app.models.user import InsulinProfile
import app.services.nutrition.meal_glucose_response as meal_glucose_response_mod

from .conftest import build_sqlite_db, build_sqlite_timescale_db, make_user


@pytest.fixture
async def app_and_db():
    engine, session_factory = await build_sqlite_db()
    ts_engine, ts_session_factory = await build_sqlite_timescale_db()

    async def _get_db():
        async with session_factory() as session:
            yield session

    app = FastAPI()
    app.include_router(nutrition.router, prefix="/nutrition")
    app.dependency_overrides[get_db] = _get_db

    original_ts_factory = meal_glucose_response_mod.TimescaleSessionLocal
    meal_glucose_response_mod.TimescaleSessionLocal = ts_session_factory

    with TestClient(app) as client:
        yield client, session_factory, ts_session_factory

    meal_glucose_response_mod.TimescaleSessionLocal = original_ts_factory
    await engine.dispose()
    await ts_engine.dispose()


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


async def _token_for(session_factory, email: str) -> tuple:
    user = await make_user(session_factory, email)
    return user, create_access_token(subject=str(user.id), token_version=user.token_version)


async def _insert_meal(session_factory, user_id, meal_time, **overrides) -> str:
    async with session_factory() as session:
        meal = MealLog(
            user_id=user_id, meal_time=meal_time, food_items=[{"name": "Test meal"}],
            total_calories=300, total_carbs_g=40.0, total_protein_g=10.0,
            total_fat_g=8.0, total_fiber_g=3.0, glycaemic_load=20.0,
            nutrition_source="usda", nutrition_verified=True,
            **overrides,
        )
        session.add(meal)
        await session.commit()
        await session.refresh(meal)
        return str(meal.id)


async def _reading(ts_session_factory, user_id, value_mgdl, at: datetime):
    async with ts_session_factory() as session:
        session.add(GlucoseReadingModel(
            id=uuid.uuid4(), user_id=user_id, value_mgdl=value_mgdl,
            recorded_at=at, source="LIBRE", sensor_id="s1",
        ))
        await session.commit()


async def test_requires_authentication(app_and_db):
    client, _, _ = app_and_db
    resp = client.get(f"/nutrition/meals/{uuid.uuid4()}/glucose-response")
    assert resp.status_code in (401, 403)


async def test_404s_for_another_users_meal(app_and_db):
    client, session_factory, _ = app_and_db
    user_a, token_a = await _token_for(session_factory, "a@example.com")
    user_b, _ = await _token_for(session_factory, "b@example.com")
    meal_id = await _insert_meal(session_factory, user_b.id, datetime.now(timezone.utc))

    resp = client.get(f"/nutrition/meals/{meal_id}/glucose-response", headers=_auth(token_a))
    assert resp.status_code == 404


async def test_no_readings_in_window_is_a_clean_empty_state(app_and_db):
    """No CGM connected, or nothing landed yet — has_data False, no
    fabricated graph, not an error."""
    client, session_factory, _ = app_and_db
    user, token = await _token_for(session_factory, "a@example.com")
    meal_id = await _insert_meal(session_factory, user.id, datetime.now(timezone.utc))

    resp = client.get(f"/nutrition/meals/{meal_id}/glucose-response", headers=_auth(token))
    assert resp.status_code == 200
    body = resp.json()
    assert body["has_data"] is False
    assert body["readings"] == []
    assert body["baseline_mgdl"] is None
    assert body["outcome"] is None


async def test_real_readings_and_outcome_are_returned(app_and_db):
    client, session_factory, ts_session_factory = app_and_db
    user, token = await _token_for(session_factory, "a@example.com")
    meal_time = datetime(2026, 1, 1, 12, 0, tzinfo=timezone.utc)
    meal_id = await _insert_meal(
        session_factory, user.id, meal_time,
        post_meal_glucose_1hr=105, post_meal_glucose_2hr=98, glucose_outcome="IN_RANGE",
    )
    async with session_factory() as session:
        session.add(InsulinProfile(user_id=user.id, target_glucose_min=70, target_glucose_max=180))
        await session.commit()

    await _reading(ts_session_factory, user.id, 90, meal_time - timedelta(minutes=10))
    await _reading(ts_session_factory, user.id, 105, meal_time + timedelta(hours=1))
    await _reading(ts_session_factory, user.id, 98, meal_time + timedelta(hours=2))

    resp = client.get(f"/nutrition/meals/{meal_id}/glucose-response", headers=_auth(token))
    assert resp.status_code == 200
    body = resp.json()

    assert body["has_data"] is True
    assert len(body["readings"]) == 3
    assert body["baseline_mgdl"] == 90
    # 2hr takes priority over 1hr when both are present.
    assert body["post_meal_mgdl"] == 98
    assert body["post_meal_window"] == "2hr"
    assert body["delta_mgdl"] == 8
    assert body["outcome"] == "IN_RANGE"
    assert body["target_min"] == 70
    assert body["target_max"] == 180


async def test_readings_outside_the_window_are_excluded(app_and_db):
    client, session_factory, ts_session_factory = app_and_db
    user, token = await _token_for(session_factory, "a@example.com")
    meal_time = datetime(2026, 1, 1, 12, 0, tzinfo=timezone.utc)
    meal_id = await _insert_meal(session_factory, user.id, meal_time)

    await _reading(ts_session_factory, user.id, 200, meal_time - timedelta(hours=5))  # way before
    await _reading(ts_session_factory, user.id, 95, meal_time + timedelta(minutes=30))  # in window
    await _reading(ts_session_factory, user.id, 300, meal_time + timedelta(hours=10))  # way after

    resp = client.get(f"/nutrition/meals/{meal_id}/glucose-response", headers=_auth(token))
    body = resp.json()

    assert len(body["readings"]) == 1
    assert body["readings"][0]["value_mgdl"] == 95


async def test_no_target_range_without_an_insulin_profile(app_and_db):
    client, session_factory, ts_session_factory = app_and_db
    user, token = await _token_for(session_factory, "a@example.com")
    meal_time = datetime(2026, 1, 1, 12, 0, tzinfo=timezone.utc)
    meal_id = await _insert_meal(session_factory, user.id, meal_time)
    await _reading(ts_session_factory, user.id, 95, meal_time)

    resp = client.get(f"/nutrition/meals/{meal_id}/glucose-response", headers=_auth(token))
    body = resp.json()

    assert body["has_data"] is True
    assert body["target_min"] is None
    assert body["target_max"] is None
