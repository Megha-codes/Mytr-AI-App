"""Capstone proof tests for Phase B (architecture-v3.md §2.4 / §2.5 / §2.6),
one per the phase's explicit "Prove:" requirement:

1. A device authed with a device JWT fetches a snapshot and receives live
   readings over /ws/device/stream.
2. Health samples ingest idempotently — re-sending the same external_id
   doesn't double-count.
3. GET /health/daily omits unsynced metrics rather than zeroing them.

Each earlier chunk already covers its own piece in isolation; these tests
exercise the same claims end-to-end, combining routers the way the real
app does.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.api import device_data, health as health_module
from app.api.websockets import realtime_stream
from app.core.security import create_access_token, create_device_access_token
from app.database import get_db
from app.models.device import Device
from app.models.glucose_reading import GlucoseReadingModel
from app.models.user import CGMDevice
from app.services.realtime.fanout_hub import fanout_hub

from .conftest import build_sqlite_db, build_sqlite_timescale_db, make_user


@pytest.fixture
async def phase_b_app():
    engine, session_factory = await build_sqlite_db()
    ts_engine, ts_session_factory = await build_sqlite_timescale_db()

    async def _get_db():
        async with session_factory() as session:
            yield session

    app = FastAPI()
    app.include_router(device_data.router)
    app.include_router(health_module.router)
    app.include_router(realtime_stream.router)
    app.dependency_overrides[get_db] = _get_db

    original_device_ts = device_data.TimescaleSessionLocal
    original_stream_ts = realtime_stream.TimescaleSessionLocal
    device_data.TimescaleSessionLocal = ts_session_factory
    realtime_stream.TimescaleSessionLocal = ts_session_factory

    @app.post("/probe/publish_reading")
    async def probe_publish_reading(user_id: str, mgdl: int = 130):
        # Stands in for LibreIngestionService: write the store, THEN publish
        # to the hub — the same order real ingestion uses, so a snapshot
        # fetched afterwards sees the same reading the socket just delivered.
        recorded_at = datetime.now(timezone.utc)
        async with ts_session_factory() as ts:
            ts.add(GlucoseReadingModel(
                user_id=uuid.UUID(user_id), value_mgdl=mgdl, trend="STABLE", trend_arrow="→",
                device_type="LIBRE", is_continuous=True, recorded_at=recorded_at,
                sensor_id="s1", source="LIBRE",
            ))
            await ts.commit()
        fanout_hub.publish_glucose_reading(
            uuid.UUID(user_id), recorded_at=recorded_at, mgdl=mgdl,
            trend="STABLE", trend_arrow="→", sensor_id="s1", source="LIBRE",
        )
        return {}

    yield app, session_factory, ts_session_factory

    device_data.TimescaleSessionLocal = original_device_ts
    realtime_stream.TimescaleSessionLocal = original_stream_ts
    await engine.dispose()
    await ts_engine.dispose()


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


# ── Prove 1: device fetches a snapshot, then receives a live reading ────

async def test_device_fetches_snapshot_then_receives_a_live_reading(phase_b_app):
    app, session_factory, _ = phase_b_app
    user = await make_user(session_factory, "device-e2e@example.com")
    device_id = uuid.uuid4()
    async with session_factory() as session:
        session.add(Device(id=device_id, hardware_id="pi-1", user_id=user.id, token_version=0))
        session.add(CGMDevice(id=uuid.uuid4(), user_id=user.id, device_type="LIBRE_3", is_active=True))
        await session.commit()
    device_token = create_device_access_token(str(device_id), str(user.id), token_version=0)

    with TestClient(app) as client:
        snapshot_resp = client.get("/device/snapshot", headers=_auth(device_token))
        assert snapshot_resp.status_code == 200
        snapshot = snapshot_resp.json()
        # Cold boot: no live data yet, but the object is fully shaped.
        assert snapshot["glucose"]["latest"] is None
        assert snapshot["glucose"]["state"] == "NO_SENSOR"

        with client.websocket_connect(
            "/ws/device/stream", subprotocols=["bearer", device_token]
        ) as ws:
            hello = ws.receive_json()
            assert hello["type"] == "hello"

            resp = client.post("/probe/publish_reading", params={"user_id": str(user.id), "mgdl": 142})
            assert resp.status_code == 200

            live_frame = ws.receive_json()

    assert live_frame["type"] == "glucose.reading"
    assert live_frame["data"]["mgdl"] == 142

    # And the snapshot now reflects it too — same underlying store.
    with TestClient(app) as client:
        second_snapshot = client.get("/device/snapshot", headers=_auth(device_token)).json()
    assert second_snapshot["glucose"]["latest"]["mgdl"] == 142
    assert second_snapshot["glucose"]["state"] == "LIVE"


# ── Prove 2: health sample ingest is idempotent on external_id ──────────

async def test_resending_the_same_external_id_does_not_double_count(phase_b_app):
    app, session_factory, _ = phase_b_app
    user = await make_user(session_factory, "idempotent-ingest@example.com")
    token = create_access_token(str(user.id), token_version=user.token_version)

    payload = {
        "samples": [{
            "metric": "steps", "value": 4000, "unit": "count",
            "started_at": "2026-08-01T09:00:00Z", "ended_at": "2026-08-01T09:00:00Z",
            "source": "APPLE_HEALTH", "external_id": "bucket:2026-08-01T09:00:00Z",
        }]
    }

    with TestClient(app) as client:
        first = client.post("/health/samples", json=payload, headers=_auth(token))
        assert first.json() == {"accepted": 1, "duplicates": 0}

        # A retry/overlapping-sync-window resend of the exact same sample.
        second = client.post("/health/samples", json=payload, headers=_auth(token))
        assert second.json() == {"accepted": 0, "duplicates": 1}

        daily = client.get("/health/daily", params={"date": "2026-08-01"}, headers=_auth(token))
    assert daily.json()["steps"] == 4000  # not 8000


# ── Prove 3: health.daily omits unsynced metrics, never zero-fills ──────

async def test_health_daily_omits_unsynced_metrics(phase_b_app):
    app, session_factory, _ = phase_b_app
    user = await make_user(session_factory, "absent-not-zero@example.com")
    token = create_access_token(str(user.id), token_version=user.token_version)

    # Only steps ever gets synced today — heart_rate, sleep_minutes, etc.
    # were never pushed at all (e.g. the app hasn't been opened).
    payload = {
        "samples": [{
            "metric": "steps", "value": 0, "unit": "count",
            "started_at": "2026-08-01T09:00:00Z", "ended_at": "2026-08-01T09:00:00Z",
            "source": "APPLE_HEALTH", "external_id": "s1",
        }]
    }

    with TestClient(app) as client:
        client.post("/health/samples", json=payload, headers=_auth(token))
        resp = client.get("/health/daily", params={"date": "2026-08-01"}, headers=_auth(token))
    body = resp.json()

    # Real zero steps IS synced data — it must be present, not dropped.
    assert body["steps"] == 0
    # Everything genuinely unsynced today must be ABSENT, not present as 0/null.
    for field in ("active_energy_kcal", "heart_rate", "resting_heart_rate", "sleep_minutes", "hrv"):
        assert field not in body, f"{field} should be absent, not zero-filled"
