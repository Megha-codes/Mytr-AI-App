"""Water intake logging (Phase-1 polish, part 3): POST /water/log,
GET /water/daily, and the device twin GET /device/water/daily. Stored as
an ordinary health_metrics row (metric='water_ml') -- see
app/api/water.py's module docstring.
"""

from __future__ import annotations

import uuid

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.api import device_data, water
from app.core.security import create_access_token, create_device_access_token
from app.database import get_db
from app.models.device import Device

from .conftest import build_sqlite_db, make_user


@pytest.fixture
async def app_and_db():
    engine, session_factory = await build_sqlite_db()

    async def _get_db():
        async with session_factory() as session:
            yield session

    app = FastAPI()
    app.include_router(water.router)
    app.include_router(device_data.router)
    app.dependency_overrides[get_db] = _get_db

    with TestClient(app) as client:
        yield client, session_factory

    await engine.dispose()


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


async def _device_token(session_factory, user) -> str:
    device_id = uuid.uuid4()
    async with session_factory() as session:
        session.add(Device(id=device_id, hardware_id="pi-1", user_id=user.id, token_version=0))
        await session.commit()
    return create_device_access_token(str(device_id), str(user.id), token_version=0)


# ── POST /water/log ──────────────────────────────────────────────────────

async def test_log_requires_authentication(app_and_db):
    client, _ = app_and_db
    resp = client.post("/water/log", json={"amount_ml": 250})
    assert resp.status_code == 401


async def test_log_a_glass_returns_the_running_total(app_and_db):
    client, session_factory = app_and_db
    user = await make_user(session_factory, "a@example.com")
    token = create_access_token(subject=str(user.id), token_version=user.token_version)

    resp = client.post("/water/log", json={"amount_ml": 250}, headers=_auth(token))
    assert resp.status_code == 201
    assert resp.json() == {"success": True, "total_ml_today": 250}

    resp2 = client.post("/water/log", json={"amount_ml": 500}, headers=_auth(token))
    assert resp2.json() == {"success": True, "total_ml_today": 750}


@pytest.mark.parametrize("amount", [0, -50, 2001])
async def test_log_rejects_unreasonable_amounts(app_and_db, amount):
    client, session_factory = app_and_db
    user = await make_user(session_factory, "a@example.com")
    token = create_access_token(subject=str(user.id), token_version=user.token_version)

    resp = client.post("/water/log", json={"amount_ml": amount}, headers=_auth(token))
    assert resp.status_code == 422


async def test_log_is_scoped_to_the_caller(app_and_db):
    client, session_factory = app_and_db
    user_a = await make_user(session_factory, "a@example.com")
    user_b = await make_user(session_factory, "b@example.com")
    token_a = create_access_token(subject=str(user_a.id), token_version=user_a.token_version)
    token_b = create_access_token(subject=str(user_b.id), token_version=user_b.token_version)

    client.post("/water/log", json={"amount_ml": 500}, headers=_auth(token_a))

    resp_b = client.get("/water/daily", headers=_auth(token_b))
    assert resp_b.json()["total_ml"] is None


# ── GET /water/daily ─────────────────────────────────────────────────────

async def test_daily_requires_authentication(app_and_db):
    client, _ = app_and_db
    resp = client.get("/water/daily")
    assert resp.status_code == 401


async def test_daily_is_null_not_zero_with_nothing_logged(app_and_db):
    client, session_factory = app_and_db
    user = await make_user(session_factory, "a@example.com")
    token = create_access_token(subject=str(user.id), token_version=user.token_version)

    resp = client.get("/water/daily", headers=_auth(token))
    assert resp.status_code == 200
    body = resp.json()
    assert body["total_ml"] is None
    assert body["goal_ml"] == 2000


async def test_daily_reflects_logged_entries(app_and_db):
    client, session_factory = app_and_db
    user = await make_user(session_factory, "a@example.com")
    token = create_access_token(subject=str(user.id), token_version=user.token_version)

    client.post("/water/log", json={"amount_ml": 250}, headers=_auth(token))
    client.post("/water/log", json={"amount_ml": 250}, headers=_auth(token))

    resp = client.get("/water/daily", headers=_auth(token))
    assert resp.json()["total_ml"] == 500


# ── GET /device/water/daily ──────────────────────────────────────────────

async def test_device_twin_requires_a_device_token(app_and_db):
    client, _ = app_and_db
    resp = client.get("/device/water/daily")
    assert resp.status_code == 401


async def test_device_twin_matches_the_user_endpoint(app_and_db):
    client, session_factory = app_and_db
    user = await make_user(session_factory, "a@example.com")
    user_token = create_access_token(subject=str(user.id), token_version=user.token_version)
    device_token = await _device_token(session_factory, user)

    client.post("/water/log", json={"amount_ml": 750}, headers=_auth(user_token))

    user_view = client.get("/water/daily", headers=_auth(user_token)).json()
    device_view = client.get("/device/water/daily", headers=_auth(device_token)).json()

    assert user_view["total_ml"] == device_view["total_ml"] == 750
    assert user_view["goal_ml"] == device_view["goal_ml"] == 2000
