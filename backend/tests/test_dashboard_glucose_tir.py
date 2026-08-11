"""GET /dashboard's `glucose.time_in_range_breakdown` used to be hardcoded
to {below: 0, target: 0, above: 0} on the *frontend* regardless of real
data, because the backend never sent it at all. This is the real
computation (backend/app/api/dashboard.py), covering the bug it was
actually filed against.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.api import dashboard
from app.core.security import create_access_token
from app.database import get_db
from app.models.glucose_reading import GlucoseReadingModel
from app.models.user import InsulinProfile

from .conftest import build_sqlite_db, build_sqlite_timescale_db, make_user


@pytest.fixture
async def app_and_db():
    engine, session_factory = await build_sqlite_db()
    ts_engine, ts_session_factory = await build_sqlite_timescale_db()

    async def _get_db():
        async with session_factory() as session:
            yield session

    app = FastAPI()
    app.include_router(dashboard.router, prefix="/dashboard")
    app.dependency_overrides[get_db] = _get_db

    original_ts_factory = dashboard.TimescaleSessionLocal
    dashboard.TimescaleSessionLocal = ts_session_factory

    with TestClient(app) as client:
        yield client, session_factory, ts_session_factory

    dashboard.TimescaleSessionLocal = original_ts_factory
    await engine.dispose()
    await ts_engine.dispose()


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


async def _insert_reading(ts_session_factory, user_id, value_mgdl, minutes_ago):
    async with ts_session_factory() as session:
        session.add(GlucoseReadingModel(
            id=uuid.uuid4(), user_id=user_id, value_mgdl=value_mgdl,
            recorded_at=datetime.now(timezone.utc) - timedelta(minutes=minutes_ago),
            source="MANUAL",
        ))
        await session.commit()


async def test_breakdown_is_null_with_no_readings(app_and_db):
    client, session_factory, _ts = app_and_db
    user = await make_user(session_factory, "a@example.com")
    token = create_access_token(subject=str(user.id), token_version=user.token_version)

    resp = client.get("/dashboard", headers=_auth(token))
    assert resp.status_code == 200
    assert resp.json()["glucose"]["time_in_range_breakdown"] is None


async def test_breakdown_reflects_real_readings(app_and_db):
    client, session_factory, ts_session_factory = app_and_db
    user = await make_user(session_factory, "a@example.com")
    token = create_access_token(subject=str(user.id), token_version=user.token_version)

    # Default target range (no InsulinProfile row) is 70-180 per dashboard.py.
    await _insert_reading(ts_session_factory, user.id, 60, 5)    # below
    await _insert_reading(ts_session_factory, user.id, 120, 10)  # in range
    await _insert_reading(ts_session_factory, user.id, 130, 15)  # in range
    await _insert_reading(ts_session_factory, user.id, 200, 20)  # above

    resp = client.get("/dashboard", headers=_auth(token))
    breakdown = resp.json()["glucose"]["time_in_range_breakdown"]

    assert breakdown == {"below": 0.25, "target": 0.5, "above": 0.25}


async def test_breakdown_uses_the_users_own_target_range(app_and_db):
    client, session_factory, ts_session_factory = app_and_db
    user = await make_user(session_factory, "a@example.com")
    token = create_access_token(subject=str(user.id), token_version=user.token_version)

    async with session_factory() as session:
        session.add(InsulinProfile(
            id=uuid.uuid4(), user_id=user.id, icr=10, isf=40,
            basal_rate=1.0, target_glucose_min=100, target_glucose_max=140,
            insulin_type="rapid",
        ))
        await session.commit()

    # 90 is "in range" under the default 70-180 but "below" under this
    # user's own 100-140 target.
    await _insert_reading(ts_session_factory, user.id, 90, 5)

    resp = client.get("/dashboard", headers=_auth(token))
    breakdown = resp.json()["glucose"]["time_in_range_breakdown"]

    assert breakdown == {"below": 1.0, "target": 0.0, "above": 0.0}
