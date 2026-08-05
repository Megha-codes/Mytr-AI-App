"""Integration tests for GET /api/v1/device/glucose/latest and
GET /api/v1/device/glucose/range (architecture-v3.md §2.4).
"""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.api import device_data
from app.core.security import create_device_access_token
from app.database import get_db
from app.models.device import Device
from app.models.glucose_reading import GlucoseReadingModel
from app.models.user import CGMDevice

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


async def _activate_cgm(session_factory, user_id):
    async with session_factory() as session:
        session.add(CGMDevice(id=uuid.uuid4(), user_id=user_id, device_type="LIBRE_3", is_active=True))
        await session.commit()


async def _add_reading(ts_session_factory, user_id, recorded_at, mgdl=120, sensor_id="s1"):
    async with ts_session_factory() as ts:
        ts.add(GlucoseReadingModel(
            user_id=user_id, value_mgdl=mgdl, trend="STABLE", trend_arrow="→",
            device_type="LIBRE", is_continuous=True, recorded_at=recorded_at,
            sensor_id=sensor_id, source="LIBRE",
        ))
        await ts.commit()


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


# ── /device/glucose/latest ──────────────────────────────────────────────

async def test_latest_requires_a_device_token(app_and_db):
    app, _, _ = app_and_db
    with TestClient(app) as client:
        resp = client.get("/device/glucose/latest")
    assert resp.status_code == 401


async def test_latest_with_no_readings_is_200_with_nulls_and_not_connected(app_and_db):
    app, session_factory, _ = app_and_db
    user = await make_user(session_factory, "a@example.com")
    token = await _device_token(session_factory, user)

    with TestClient(app) as client:
        resp = client.get("/device/glucose/latest", headers=_auth(token))
    assert resp.status_code == 200
    body = resp.json()
    assert body["mgdl"] is None
    assert body["state"] == "NOT_CONNECTED"


async def test_latest_with_a_fresh_reading_is_live(app_and_db):
    app, session_factory, ts_session_factory = app_and_db
    user = await make_user(session_factory, "a@example.com")
    token = await _device_token(session_factory, user)
    await _activate_cgm(session_factory, user.id)
    await _add_reading(ts_session_factory, user.id, datetime.now(timezone.utc) - timedelta(minutes=1), mgdl=145)

    with TestClient(app) as client:
        resp = client.get("/device/glucose/latest", headers=_auth(token))
    body = resp.json()
    assert body["mgdl"] == 145
    assert body["state"] == "LIVE"


async def test_latest_with_an_old_reading_is_stale(app_and_db):
    app, session_factory, ts_session_factory = app_and_db
    user = await make_user(session_factory, "a@example.com")
    token = await _device_token(session_factory, user)
    await _activate_cgm(session_factory, user.id)
    await _add_reading(ts_session_factory, user.id, datetime.now(timezone.utc) - timedelta(hours=1), mgdl=110)

    with TestClient(app) as client:
        resp = client.get("/device/glucose/latest", headers=_auth(token))
    body = resp.json()
    assert body["mgdl"] == 110
    assert body["state"] == "STALE"


async def test_latest_etag_304_on_repeat_request(app_and_db):
    app, session_factory, ts_session_factory = app_and_db
    user = await make_user(session_factory, "a@example.com")
    token = await _device_token(session_factory, user)
    await _activate_cgm(session_factory, user.id)
    await _add_reading(ts_session_factory, user.id, datetime.now(timezone.utc), mgdl=100)

    with TestClient(app) as client:
        first = client.get("/device/glucose/latest", headers=_auth(token))
        etag = first.headers["etag"]
        second = client.get("/device/glucose/latest", headers={**_auth(token), "If-None-Match": etag})
    assert second.status_code == 304


# ── /device/glucose/range ───────────────────────────────────────────────

async def test_range_requires_the_from_parameter(app_and_db):
    app, session_factory, _ = app_and_db
    user = await make_user(session_factory, "a@example.com")
    token = await _device_token(session_factory, user)

    with TestClient(app) as client:
        resp = client.get("/device/glucose/range", headers=_auth(token))
    assert resp.status_code == 422


async def test_range_returns_readings_ascending_within_window(app_and_db):
    app, session_factory, ts_session_factory = app_and_db
    user = await make_user(session_factory, "a@example.com")
    token = await _device_token(session_factory, user)
    now = datetime.now(timezone.utc)

    await _add_reading(ts_session_factory, user.id, now - timedelta(hours=3), mgdl=100)
    await _add_reading(ts_session_factory, user.id, now - timedelta(hours=1), mgdl=110)
    await _add_reading(ts_session_factory, user.id, now - timedelta(minutes=1), mgdl=120)

    from_epoch = int((now - timedelta(hours=6)).timestamp())
    with TestClient(app) as client:
        resp = client.get("/device/glucose/range", params={"from": from_epoch}, headers=_auth(token))
    body = resp.json()
    assert [r["mgdl"] for r in body["readings"]] == [100, 110, 120]
    assert body["truncated"] is False


async def test_range_excludes_readings_outside_the_window(app_and_db):
    app, session_factory, ts_session_factory = app_and_db
    user = await make_user(session_factory, "a@example.com")
    token = await _device_token(session_factory, user)
    now = datetime.now(timezone.utc)

    await _add_reading(ts_session_factory, user.id, now - timedelta(days=2), mgdl=999)
    await _add_reading(ts_session_factory, user.id, now - timedelta(minutes=5), mgdl=130)

    from_epoch = int((now - timedelta(hours=6)).timestamp())
    with TestClient(app) as client:
        resp = client.get("/device/glucose/range", params={"from": from_epoch}, headers=_auth(token))
    body = resp.json()
    assert [r["mgdl"] for r in body["readings"]] == [130]


async def test_range_truncates_and_keeps_the_most_recent_points(app_and_db):
    app, session_factory, ts_session_factory = app_and_db
    user = await make_user(session_factory, "a@example.com")
    token = await _device_token(session_factory, user)
    now = datetime.now(timezone.utc)

    for i in range(5):
        await _add_reading(ts_session_factory, user.id, now - timedelta(minutes=(5 - i)), mgdl=100 + i)

    from_epoch = int((now - timedelta(hours=1)).timestamp())
    with TestClient(app) as client:
        resp = client.get(
            "/device/glucose/range",
            params={"from": from_epoch, "max_points": 3},
            headers=_auth(token),
        )
    body = resp.json()
    assert body["truncated"] is True
    assert [r["mgdl"] for r in body["readings"]] == [102, 103, 104]  # the 3 most recent, ascending
