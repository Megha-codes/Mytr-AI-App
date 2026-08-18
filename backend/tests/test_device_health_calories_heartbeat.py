"""Integration tests for GET /api/v1/device/health/daily,
GET /api/v1/device/calories/daily, and POST /api/v1/device/heartbeat
(architecture-v3.md §2.3 / §2.4).
"""

from __future__ import annotations

import json
import uuid
from datetime import datetime, timedelta, timezone

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import select, text

from app.api import device_data
from app.core.security import create_device_access_token
from app.database import get_db
from app.models.device import Device
from app.models.health_metric import HealthMetric

from .conftest import build_sqlite_db, make_user


@pytest.fixture
async def app_and_db():
    engine, session_factory = await build_sqlite_db()

    async def _get_db():
        async with session_factory() as session:
            yield session

    app = FastAPI()
    app.include_router(device_data.router)
    app.dependency_overrides[get_db] = _get_db

    yield app, session_factory

    await engine.dispose()


async def _device_token(session_factory, user) -> str:
    device_id = uuid.uuid4()
    async with session_factory() as session:
        session.add(Device(id=device_id, hardware_id="pi-1", user_id=user.id, token_version=0))
        await session.commit()
    return device_id, create_device_access_token(str(device_id), str(user.id), token_version=0)


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


# ── GET /device/health/daily ─────────────────────────────────────────────

async def test_health_daily_requires_a_device_token(app_and_db):
    app, _ = app_and_db
    with TestClient(app) as client:
        resp = client.get("/device/health/daily")
    assert resp.status_code == 401


async def test_health_daily_with_no_data_is_200_with_nulls(app_and_db):
    app, session_factory = app_and_db
    user = await make_user(session_factory, "a@example.com")
    _device_id, token = await _device_token(session_factory, user)

    with TestClient(app) as client:
        resp = client.get("/device/health/daily", headers=_auth(token))
    assert resp.status_code == 200
    body = resp.json()
    assert body["steps"] is None
    assert body["sleep_minutes"] is None


async def test_health_daily_reflects_todays_samples(app_and_db):
    app, session_factory = app_and_db
    user = await make_user(session_factory, "a@example.com")
    _device_id, token = await _device_token(session_factory, user)

    now = datetime.now(timezone.utc)
    async with session_factory() as session:
        session.add(HealthMetric(
            user_id=user.id, metric="steps", value=6000, unit="count",
            started_at=now, ended_at=now, source="APPLE_HEALTH",
        ))
        session.add(HealthMetric(
            user_id=user.id, metric="resting_heart_rate", value=58, unit="bpm",
            started_at=now, ended_at=now, source="APPLE_HEALTH",
        ))
        await session.commit()

    with TestClient(app) as client:
        resp = client.get("/device/health/daily", headers=_auth(token))
    body = resp.json()
    assert body["steps"] == 6000
    assert body["resting_heart_rate"] == 58
    assert body["active_energy_kcal"] is None


async def test_health_daily_includes_hrv(app_and_db):
    """hrv is a real aggregated metric (daily_rollup.py's _AGGREGATION) that
    GET /health/daily already surfaces -- the device twin must too, not
    silently drop a field the app already shows."""
    app, session_factory = app_and_db
    user = await make_user(session_factory, "a@example.com")
    _device_id, token = await _device_token(session_factory, user)

    now = datetime.now(timezone.utc)
    async with session_factory() as session:
        session.add(HealthMetric(
            user_id=user.id, metric="hrv", value=42, unit="ms",
            started_at=now, ended_at=now, source="APPLE_HEALTH",
        ))
        await session.commit()

    with TestClient(app) as client:
        resp = client.get("/device/health/daily", headers=_auth(token))
    assert resp.json()["hrv"] == 42


async def test_health_daily_honors_explicit_date_param(app_and_db):
    app, session_factory = app_and_db
    user = await make_user(session_factory, "a@example.com")
    _device_id, token = await _device_token(session_factory, user)

    yesterday = datetime.now(timezone.utc) - timedelta(days=1)
    async with session_factory() as session:
        session.add(HealthMetric(
            user_id=user.id, metric="steps", value=1234, unit="count",
            started_at=yesterday, ended_at=yesterday, source="APPLE_HEALTH",
        ))
        await session.commit()

    yesterday_date = yesterday.date().isoformat()
    with TestClient(app) as client:
        resp = client.get("/device/health/daily", params={"date": yesterday_date}, headers=_auth(token))
        today_resp = client.get("/device/health/daily", headers=_auth(token))
    assert resp.json()["steps"] == 1234
    assert today_resp.json()["steps"] is None


# ── GET /device/calories/daily ───────────────────────────────────────────

async def test_calories_daily_requires_a_device_token(app_and_db):
    app, _ = app_and_db
    with TestClient(app) as client:
        resp = client.get("/device/calories/daily")
    assert resp.status_code == 401


async def test_calories_daily_with_no_meals_is_zeroed(app_and_db):
    app, session_factory = app_and_db
    user = await make_user(session_factory, "a@example.com")
    _device_id, token = await _device_token(session_factory, user)

    with TestClient(app) as client:
        resp = client.get("/device/calories/daily", headers=_auth(token))
    body = resp.json()
    assert body["consumed_kcal"] == 0
    assert body["meals"] == []


async def test_calories_daily_aggregates_meals_for_the_date(app_and_db):
    app, session_factory = app_and_db
    user = await make_user(session_factory, "a@example.com")
    _device_id, token = await _device_token(session_factory, user)

    now = datetime.now(timezone.utc)
    await _insert_meal(session_factory, user.id, now, "Poha", 320, 48.0)
    yesterday = now - timedelta(days=1)
    await _insert_meal(session_factory, user.id, yesterday, "Old", 999, 99.0)

    with TestClient(app) as client:
        resp = client.get("/device/calories/daily", headers=_auth(token))
    body = resp.json()
    assert body["consumed_kcal"] == 320
    assert [m["label"] for m in body["meals"]] == ["Poha"]


# ── POST /device/heartbeat ───────────────────────────────────────────────

async def test_heartbeat_requires_a_device_token(app_and_db):
    app, _ = app_and_db
    with TestClient(app) as client:
        resp = client.post("/device/heartbeat", json={})
    assert resp.status_code == 401


async def test_heartbeat_updates_last_seen_at(app_and_db):
    app, session_factory = app_and_db
    user = await make_user(session_factory, "a@example.com")
    device_id, token = await _device_token(session_factory, user)

    with TestClient(app) as client:
        resp = client.post(
            "/device/heartbeat",
            json={"firmware_version": "1.2.0", "uptime_s": 3600, "last_reading_ts": 1234567890, "alarm_state": "none"},
            headers=_auth(token),
        )
    assert resp.status_code == 200
    assert resp.json() == {}

    async with session_factory() as session:
        result = await session.execute(select(Device).where(Device.id == device_id))
        device = result.scalar_one()
    assert device.last_seen_at is not None


async def test_heartbeat_accepts_an_empty_body(app_and_db):
    app, session_factory = app_and_db
    user = await make_user(session_factory, "a@example.com")
    _device_id, token = await _device_token(session_factory, user)

    with TestClient(app) as client:
        resp = client.post("/device/heartbeat", json={}, headers=_auth(token))
    assert resp.status_code == 200
