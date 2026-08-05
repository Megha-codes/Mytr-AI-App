"""Integration tests for POST /api/v1/health/samples and GET
/api/v1/health/daily (architecture-v3.md §1.4 / §2.5), against the real
router mounted with a SQLite DB.
"""

from __future__ import annotations

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.database import get_db
from app.core.security import create_access_token
from app.api import health as health_module
from app.models.activity import ActivityLog
from app.services.realtime.fanout_hub import fanout_hub
from sqlalchemy import select

from .conftest import build_sqlite_db, make_user


@pytest.fixture
async def client_and_db():
    engine, session_factory = await build_sqlite_db()

    async def _get_db():
        async with session_factory() as session:
            yield session

    app = FastAPI()
    app.include_router(health_module.router)
    app.dependency_overrides[get_db] = _get_db

    with TestClient(app) as client:
        yield client, session_factory

    await engine.dispose()


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _sample(metric, value, unit, started_at, external_id=None, source="APPLE_HEALTH"):
    return {
        "metric": metric, "value": value, "unit": unit,
        "started_at": started_at, "ended_at": started_at,
        "source": source, "external_id": external_id,
    }


# ── Ingest ────────────────────────────────────────────────────────────────

async def test_ingest_accepts_new_samples(client_and_db):
    client, session_factory = client_and_db
    user = await make_user(session_factory, "a@example.com")
    token = create_access_token(str(user.id), token_version=user.token_version)

    resp = client.post(
        "/health/samples",
        json={"samples": [
            _sample("steps", 500, "count", "2026-08-01T09:00:00Z", external_id="s1"),
            _sample("heart_rate", 70, "bpm", "2026-08-01T09:00:00Z", external_id="hr1"),
        ]},
        headers=_auth(token),
    )
    assert resp.status_code == 200
    assert resp.json() == {"accepted": 2, "duplicates": 0}


async def test_ingest_is_idempotent_on_external_id(client_and_db):
    client, session_factory = client_and_db
    user = await make_user(session_factory, "a@example.com")
    token = create_access_token(str(user.id), token_version=user.token_version)

    payload = {"samples": [_sample("steps", 500, "count", "2026-08-01T09:00:00Z", external_id="dup-1")]}
    first = client.post("/health/samples", json=payload, headers=_auth(token))
    assert first.json() == {"accepted": 1, "duplicates": 0}

    second = client.post("/health/samples", json=payload, headers=_auth(token))
    assert second.json() == {"accepted": 0, "duplicates": 1}

    daily = client.get("/health/daily", params={"date": "2026-08-01"}, headers=_auth(token))
    assert daily.json()["steps"] == 500  # not double-counted


async def test_samples_without_external_id_are_never_deduped(client_and_db):
    client, session_factory = client_and_db
    user = await make_user(session_factory, "a@example.com")
    token = create_access_token(str(user.id), token_version=user.token_version)

    payload = {"samples": [_sample("steps", 100, "count", "2026-08-01T09:00:00Z")]}
    first = client.post("/health/samples", json=payload, headers=_auth(token))
    second = client.post("/health/samples", json=payload, headers=_auth(token))
    assert first.json() == {"accepted": 1, "duplicates": 0}
    assert second.json() == {"accepted": 1, "duplicates": 0}


async def test_ingest_rejects_batches_over_1000():
    samples = [_sample("steps", 1, "count", "2026-08-01T09:00:00Z", external_id=str(i)) for i in range(1001)]
    engine, session_factory = await build_sqlite_db()

    async def _get_db():
        async with session_factory() as session:
            yield session

    app = FastAPI()
    app.include_router(health_module.router)
    app.dependency_overrides[get_db] = _get_db
    with TestClient(app) as client:
        user = await make_user(session_factory, "a@example.com")
        token = create_access_token(str(user.id), token_version=user.token_version)
        resp = client.post("/health/samples", json={"samples": samples}, headers=_auth(token))
        assert resp.status_code == 422
    await engine.dispose()


async def test_ingest_recomputes_the_activity_log_projection(client_and_db):
    client, session_factory = client_and_db
    user = await make_user(session_factory, "a@example.com")
    token = create_access_token(str(user.id), token_version=user.token_version)

    client.post(
        "/health/samples",
        json={"samples": [
            _sample("steps", 3000, "count", "2026-08-01T09:00:00Z", external_id="s1"),
            _sample("active_energy_kcal", 200, "kcal", "2026-08-01T09:00:00Z", external_id="c1"),
        ]},
        headers=_auth(token),
    )

    async with session_factory() as db:
        result = await db.execute(select(ActivityLog).where(ActivityLog.user_id == user.id))
        row = result.scalar_one()
    assert row.steps_today == 3000
    assert row.calories_burned == 200


async def test_ingest_publishes_health_updated_for_affected_dates(client_and_db):
    client, session_factory = client_and_db
    user = await make_user(session_factory, "a@example.com")
    token = create_access_token(str(user.id), token_version=user.token_version)

    queue = fanout_hub.subscribe(user.id)
    try:
        client.post(
            "/health/samples",
            json={"samples": [_sample("steps", 100, "count", "2026-08-01T09:00:00Z", external_id="s1")]},
            headers=_auth(token),
        )
        assert not queue.empty()
        envelope = queue.get_nowait()
        assert envelope["type"] == "health.updated"
        assert envelope["data"] == {"date": "2026-08-01"}
    finally:
        fanout_hub.unsubscribe(user.id, queue)


async def test_duplicate_only_ingest_does_not_republish(client_and_db):
    client, session_factory = client_and_db
    user = await make_user(session_factory, "a@example.com")
    token = create_access_token(str(user.id), token_version=user.token_version)
    payload = {"samples": [_sample("steps", 100, "count", "2026-08-01T09:00:00Z", external_id="s1")]}
    client.post("/health/samples", json=payload, headers=_auth(token))

    queue = fanout_hub.subscribe(user.id)
    try:
        client.post("/health/samples", json=payload, headers=_auth(token))
        assert queue.empty()
    finally:
        fanout_hub.unsubscribe(user.id, queue)


# ── GET /health/daily ────────────────────────────────────────────────────

async def test_daily_omits_unsynced_metrics_rather_than_zeroing(client_and_db):
    client, session_factory = client_and_db
    user = await make_user(session_factory, "a@example.com")
    token = create_access_token(str(user.id), token_version=user.token_version)

    client.post(
        "/health/samples",
        json={"samples": [_sample("steps", 42, "count", "2026-08-01T09:00:00Z", external_id="s1")]},
        headers=_auth(token),
    )
    resp = client.get("/health/daily", params={"date": "2026-08-01"}, headers=_auth(token))
    body = resp.json()
    assert body["steps"] == 42
    assert "heart_rate" not in body
    assert "sleep_minutes" not in body


async def test_daily_with_no_data_returns_200_not_404(client_and_db):
    client, session_factory = client_and_db
    user = await make_user(session_factory, "a@example.com")
    token = create_access_token(str(user.id), token_version=user.token_version)

    resp = client.get("/health/daily", params={"date": "2026-08-01"}, headers=_auth(token))
    assert resp.status_code == 200
    body = resp.json()
    assert body["date"] == "2026-08-01"
    assert "steps" not in body
