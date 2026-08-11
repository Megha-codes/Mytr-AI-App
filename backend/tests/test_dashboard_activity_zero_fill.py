"""GET /dashboard's `activity` section must not zero-fill: no synced data
for today is a different fact from a genuine 0, and the frontend renders
those two states differently (docs/health-data-setup.md). Covers the bug
this was actually filed against: steps_today/calories_burned silently
defaulted to 0 when no activity_logs row existed for the day, and
active_minutes was hardcoded to 0 unconditionally (no real data source for
it exists at all).
"""

from __future__ import annotations

from datetime import date

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.api import dashboard
from app.core.security import create_access_token
from app.database import get_db
from app.models.activity import ActivityLog

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
        yield client, session_factory

    dashboard.TimescaleSessionLocal = original_ts_factory
    await engine.dispose()
    await ts_engine.dispose()


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


async def test_activity_is_null_not_zero_when_nothing_synced_today(app_and_db):
    client, session_factory = app_and_db
    user = await make_user(session_factory, "a@example.com")
    token = create_access_token(subject=str(user.id), token_version=user.token_version)

    resp = client.get("/dashboard", headers=_auth(token))
    assert resp.status_code == 200
    activity = resp.json()["activity"]

    assert activity["steps_today"] is None
    assert activity["calories_burned"] is None


async def test_active_minutes_is_always_null_no_real_source_yet(app_and_db):
    client, session_factory = app_and_db
    user = await make_user(session_factory, "a@example.com")
    token = create_access_token(subject=str(user.id), token_version=user.token_version)

    async with session_factory() as session:
        session.add(ActivityLog(
            user_id=user.id, date=date.today(), steps_today=6000, calories_burned=250, heart_rate=70,
        ))
        await session.commit()

    resp = client.get("/dashboard", headers=_auth(token))
    activity = resp.json()["activity"]

    # steps/calories reflect the real row now that one exists...
    assert activity["steps_today"] == 6000
    assert activity["calories_burned"] == 250
    # ...but active_minutes stays null regardless — there's no column or
    # rollup that ever populates it, so a real ActivityLog row existing
    # must not make it look like real data appeared.
    assert activity["active_minutes"] is None


async def test_activity_reflects_a_real_zero_when_the_row_says_so(app_and_db):
    """A genuine 0 (synced, and truly zero steps so far) must still come
    through as 0, not get swallowed into the same null bucket as
    never-synced-at-all — these are different facts."""
    client, session_factory = app_and_db
    user = await make_user(session_factory, "a@example.com")
    token = create_access_token(subject=str(user.id), token_version=user.token_version)

    async with session_factory() as session:
        session.add(ActivityLog(
            user_id=user.id, date=date.today(), steps_today=0, calories_burned=0, heart_rate=0,
        ))
        await session.commit()

    resp = client.get("/dashboard", headers=_auth(token))
    activity = resp.json()["activity"]

    assert activity["steps_today"] == 0
    assert activity["calories_burned"] == 0
