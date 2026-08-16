"""Integration tests for GET /api/v1/device/analytics/weekly — the
device-JWT twin of GET /analytics/weekly (api/analytics.py), built on the
same build_weekly_analytics so the desk and the app never disagree.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.api import device_data
from app.core.security import create_access_token, create_device_access_token
from app.database import get_db
from app.models.device import Device
from app.models.glucose_reading import GlucoseReadingModel

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

    # build_weekly_analytics opens its own TimescaleSessionLocal() directly,
    # imported into services/analytics/weekly.py's own namespace — patching
    # device_data.TimescaleSessionLocal (as the snapshot tests do) would not
    # reach it, so patch the module it actually lives in.
    import app.services.analytics.weekly as weekly_mod

    original_ts_factory = weekly_mod.TimescaleSessionLocal
    weekly_mod.TimescaleSessionLocal = ts_session_factory

    yield app, session_factory, ts_session_factory

    weekly_mod.TimescaleSessionLocal = original_ts_factory
    await engine.dispose()
    await ts_engine.dispose()


async def _device_token(session_factory, user) -> str:
    device_id = uuid.uuid4()
    async with session_factory() as session:
        session.add(Device(id=device_id, hardware_id="pi-1", user_id=user.id, token_version=0))
        await session.commit()
    return create_device_access_token(str(device_id), str(user.id), token_version=0)


async def _reading(ts_session_factory, user_id, value_mgdl, at: datetime):
    async with ts_session_factory() as session:
        session.add(GlucoseReadingModel(
            id=uuid.uuid4(), user_id=user_id, value_mgdl=value_mgdl,
            recorded_at=at, source="MANUAL",
        ))
        await session.commit()


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


async def test_requires_a_device_token(app_and_db):
    app, _, _ = app_and_db
    with TestClient(app) as client:
        resp = client.get("/device/analytics/weekly")
    assert resp.status_code == 401


async def test_rejects_a_user_token(app_and_db):
    """The point of the device twin: a device JWT is required, not merely
    any bearer token — a phone's user JWT must not authenticate here."""
    app, session_factory, _ = app_and_db
    user = await make_user(session_factory, "a@example.com")
    user_token = create_access_token(str(user.id), token_version=0)

    with TestClient(app) as client:
        resp = client.get("/device/analytics/weekly", headers=_auth(user_token))
    assert resp.status_code == 401


async def test_no_data_returns_empty_shape_not_fabricated_zeros(app_and_db):
    app, session_factory, _ = app_and_db
    user = await make_user(session_factory, "a@example.com")
    token = await _device_token(session_factory, user)

    with TestClient(app) as client:
        resp = client.get("/device/analytics/weekly", headers=_auth(token))
    assert resp.status_code == 200
    body = resp.json()
    assert body["glucose"]["has_data"] is False
    assert body["glucose"]["average_mgdl"] is None
    assert body["health_trends"]["steps"]["has_data"] is False
    assert body["nutrition_trends"]["has_data"] is False


async def test_matches_the_app_endpoint_for_the_same_data(app_and_db):
    """The device and app routes call the same builder — assert they agree
    rather than re-deriving the math here."""
    app, session_factory, ts_session_factory = app_and_db
    user = await make_user(session_factory, "a@example.com")
    device_token = await _device_token(session_factory, user)
    user_token = create_access_token(str(user.id), token_version=0)

    now = datetime.now(timezone.utc)
    await _reading(ts_session_factory, user.id, 120, now)
    await _reading(ts_session_factory, user.id, 140, now - timedelta(hours=1))

    from app.api import analytics as analytics_api
    app.include_router(analytics_api.router)

    with TestClient(app) as client:
        device_resp = client.get("/device/analytics/weekly", headers=_auth(device_token))
        app_resp = client.get("/analytics/weekly", headers=_auth(user_token))

    assert device_resp.status_code == 200
    assert app_resp.status_code == 200
    assert device_resp.json()["glucose"] == app_resp.json()["glucose"]
    assert device_resp.json()["health_trends"] == app_resp.json()["health_trends"]


async def test_honors_the_days_query_param(app_and_db):
    app, session_factory, _ = app_and_db
    user = await make_user(session_factory, "a@example.com")
    token = await _device_token(session_factory, user)

    with TestClient(app) as client:
        resp = client.get("/device/analytics/weekly", params={"days": 14}, headers=_auth(token))
    body = resp.json()
    start = datetime.fromisoformat(body["range"]["start"]).date()
    end = datetime.fromisoformat(body["range"]["end"]).date()
    assert (end - start).days == 13  # 14 inclusive days


async def test_rejects_an_out_of_bounds_days_param(app_and_db):
    app, session_factory, _ = app_and_db
    user = await make_user(session_factory, "a@example.com")
    token = await _device_token(session_factory, user)

    with TestClient(app) as client:
        resp = client.get("/device/analytics/weekly", params={"days": 1}, headers=_auth(token))
    assert resp.status_code == 422


# ── ETag ─────────────────────────────────────────────────────────────────

async def test_etag_matches_on_repeat_requests_for_unchanged_data(app_and_db):
    app, session_factory, _ = app_and_db
    user = await make_user(session_factory, "a@example.com")
    token = await _device_token(session_factory, user)

    with TestClient(app) as client:
        first = client.get("/device/analytics/weekly", headers=_auth(token))
        etag = first.headers["etag"]
        second = client.get(
            "/device/analytics/weekly", headers={**_auth(token), "If-None-Match": etag}
        )
    assert second.status_code == 304
