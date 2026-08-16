"""Integration tests for GET /api/v1/device/snapshot (architecture-v3.md
§2.4) — the device's cold-boot object, plus its ETag support (§2.4:
"every GET returns ETag; the device sends If-None-Match and handles 304").
"""

from __future__ import annotations

import json
import uuid
from datetime import datetime, timedelta, timezone

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import text

from app.api import device_data
from app.core.security import create_device_access_token
from app.database import get_db
from app.models.device import Device
from app.models.glucose_reading import GlucoseReadingModel
from app.models.health_metric import HealthMetric
from app.models.user import CGMDevice, InsulinProfile

from .conftest import build_sqlite_db, build_sqlite_timescale_db, make_user


@pytest.fixture
async def app_and_db():
    engine, session_factory = await build_sqlite_db()
    ts_engine, ts_session_factory = await build_sqlite_timescale_db()

    async def _get_db():
        async with session_factory() as session:
            yield session

    app = FastAPI()
    app.include_router(device_data.router)
    app.dependency_overrides[get_db] = _get_db

    original_ts_factory = device_data.TimescaleSessionLocal
    device_data.TimescaleSessionLocal = ts_session_factory

    yield app, session_factory, ts_session_factory

    device_data.TimescaleSessionLocal = original_ts_factory
    await engine.dispose()
    await ts_engine.dispose()


async def _device_token(session_factory, user) -> str:
    device_id = uuid.uuid4()
    async with session_factory() as session:
        session.add(Device(id=device_id, hardware_id="pi-1", user_id=user.id, token_version=0))
        await session.commit()
    return create_device_access_token(str(device_id), str(user.id), token_version=0)


async def _insert_meal(session_factory, user_id, meal_time, name, calories, carbs_g):
    async with session_factory() as session:
        await session.execute(
            text("""
                INSERT INTO meal_logs (id, user_id, meal_time, food_items, total_calories, total_carbs_g)
                VALUES (:id, :user_id, :meal_time, :food_items, :calories, :carbs_g)
            """),
            {
                "id": str(uuid.uuid4()), "user_id": str(user_id), "meal_time": meal_time,
                "food_items": json.dumps([{"name": name}]), "calories": calories, "carbs_g": carbs_g,
            },
        )
        await session.commit()


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


# ── Auth ─────────────────────────────────────────────────────────────────

async def test_snapshot_requires_a_device_token(app_and_db):
    app, _, _ = app_and_db
    with TestClient(app) as client:
        resp = client.get("/device/snapshot")
    assert resp.status_code == 401


# ── Shape with no data at all ───────────────────────────────────────────

async def test_snapshot_with_no_data_is_still_200_with_defaults(app_and_db):
    app, session_factory, _ = app_and_db
    user = await make_user(session_factory, "a@example.com")
    token = await _device_token(session_factory, user)

    with TestClient(app) as client:
        resp = client.get("/device/snapshot", headers=_auth(token))
    assert resp.status_code == 200
    body = resp.json()
    assert body["user"]["name"] == user.name
    assert body["user"]["target_low"] == 70
    assert body["user"]["target_high"] == 180
    assert body["glucose"]["latest"] is None
    assert body["glucose"]["readings"] == []
    assert body["glucose"]["state"] == "NOT_CONNECTED"
    assert body["health"]["steps"] is None
    assert body["calories"]["consumed_kcal"] == 0
    assert body["calories"]["meals"] == []


# ── Glucose section ──────────────────────────────────────────────────────

async def test_snapshot_reflects_a_live_reading_and_active_cgm(app_and_db):
    app, session_factory, ts_session_factory = app_and_db
    user = await make_user(session_factory, "a@example.com")
    token = await _device_token(session_factory, user)

    async with session_factory() as session:
        session.add(CGMDevice(id=uuid.uuid4(), user_id=user.id, device_type="LIBRE_3", is_active=True))
        await session.commit()

    recorded_at = datetime.now(timezone.utc) - timedelta(minutes=2)
    async with ts_session_factory() as ts:
        ts.add(GlucoseReadingModel(
            user_id=user.id, value_mgdl=132, trend="STABLE", trend_arrow="→",
            device_type="LIBRE", is_continuous=True, recorded_at=recorded_at,
            sensor_id="a1b2c3", source="LIBRE",
        ))
        await ts.commit()

    with TestClient(app) as client:
        resp = client.get("/device/snapshot", headers=_auth(token))
    body = resp.json()
    assert body["glucose"]["state"] == "LIVE"
    assert body["glucose"]["latest"]["mgdl"] == 132
    assert body["glucose"]["latest"]["sensor_id"] == "a1b2c3"
    assert len(body["glucose"]["readings"]) == 1


async def test_snapshot_insulin_targets_use_the_most_recent_profile(app_and_db):
    app, session_factory, _ = app_and_db
    user = await make_user(session_factory, "a@example.com")
    token = await _device_token(session_factory, user)

    async with session_factory() as session:
        session.add(InsulinProfile(id=uuid.uuid4(), user_id=user.id, target_glucose_min=80, target_glucose_max=160))
        await session.commit()

    with TestClient(app) as client:
        resp = client.get("/device/snapshot", headers=_auth(token))
    body = resp.json()
    assert body["user"]["target_low"] == 80
    assert body["user"]["target_high"] == 160


# ── Health section ───────────────────────────────────────────────────────

async def test_snapshot_health_reflects_todays_samples(app_and_db):
    app, session_factory, _ = app_and_db
    user = await make_user(session_factory, "a@example.com")
    token = await _device_token(session_factory, user)

    now = datetime.now(timezone.utc)
    async with session_factory() as session:
        session.add(HealthMetric(
            user_id=user.id, metric="steps", value=2500, unit="count",
            started_at=now, ended_at=now, source="APPLE_HEALTH",
        ))
        session.add(HealthMetric(
            user_id=user.id, metric="hrv", value=55, unit="ms",
            started_at=now, ended_at=now, source="APPLE_HEALTH",
        ))
        session.add(HealthMetric(
            user_id=user.id, metric="sleep_minutes", value=410, unit="min",
            started_at=now, ended_at=now, source="APPLE_HEALTH",
        ))
        await session.commit()

    with TestClient(app) as client:
        resp = client.get("/device/snapshot", headers=_auth(token))
    body = resp.json()
    assert body["health"]["steps"] == 2500
    assert body["health"]["heart_rate"] is None  # unsynced — absent, not zero
    # Same fields /device/health/daily and GET /health/daily already surface
    # — the snapshot's health sub-object must not be a narrower cut of them.
    assert body["health"]["hrv"] == 55
    assert body["health"]["sleep_minutes"] == 410


# ── Calories section ─────────────────────────────────────────────────────

async def test_snapshot_calories_aggregates_todays_meals(app_and_db):
    app, session_factory, _ = app_and_db
    user = await make_user(session_factory, "a@example.com")
    token = await _device_token(session_factory, user)

    now = datetime.now(timezone.utc)
    await _insert_meal(session_factory, user.id, now, "Poha", 320, 48.0)
    await _insert_meal(session_factory, user.id, now, "Dal", 200, 20.0)

    with TestClient(app) as client:
        resp = client.get("/device/snapshot", headers=_auth(token))
    body = resp.json()
    assert body["calories"]["consumed_kcal"] == 520
    assert body["calories"]["carbs_g"] == 68.0
    assert len(body["calories"]["meals"]) == 2
    assert {m["label"] for m in body["calories"]["meals"]} == {"Poha", "Dal"}


async def test_snapshot_excludes_meals_from_other_days(app_and_db):
    app, session_factory, _ = app_and_db
    user = await make_user(session_factory, "a@example.com")
    token = await _device_token(session_factory, user)

    yesterday = datetime.now(timezone.utc) - timedelta(days=1)
    await _insert_meal(session_factory, user.id, yesterday, "Old meal", 999, 99.0)

    with TestClient(app) as client:
        resp = client.get("/device/snapshot", headers=_auth(token))
    body = resp.json()
    assert body["calories"]["meals"] == []
    assert body["calories"]["consumed_kcal"] == 0


# ── ETag ─────────────────────────────────────────────────────────────────

async def test_etag_matches_on_repeat_requests_for_unchanged_data(app_and_db):
    app, session_factory, _ = app_and_db
    user = await make_user(session_factory, "a@example.com")
    token = await _device_token(session_factory, user)

    with TestClient(app) as client:
        first = client.get("/device/snapshot", headers=_auth(token))
        etag = first.headers["etag"]
        second = client.get(
            "/device/snapshot", headers={**_auth(token), "If-None-Match": etag}
        )
    assert second.status_code == 304


async def test_etag_changes_when_underlying_data_changes(app_and_db):
    app, session_factory, _ = app_and_db
    user = await make_user(session_factory, "a@example.com")
    token = await _device_token(session_factory, user)

    with TestClient(app) as client:
        first = client.get("/device/snapshot", headers=_auth(token))
        etag_before = first.headers["etag"]

        await _insert_meal(session_factory, user.id, datetime.now(timezone.utc), "Snack", 150, 15.0)

        second = client.get(
            "/device/snapshot", headers={**_auth(token), "If-None-Match": etag_before}
        )
    assert second.status_code == 200
    assert second.headers["etag"] != etag_before
