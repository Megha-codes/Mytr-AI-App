"""Integration tests for /ws/app/stream and /ws/device/stream
(architecture-v3.md §2.6): auth via Sec-WebSocket-Protocol, hello on
connect, resume-on-reconnect, and live delivery through the fanout hub.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from starlette.websockets import WebSocketDisconnect

from app.api.websockets import realtime_stream
from app.core.security import create_access_token, create_device_access_token
from app.database import get_db
from app.models.device import Device
from app.models.glucose_reading import GlucoseReadingModel
from app.services.realtime.fanout_hub import fanout_hub

from .conftest import build_sqlite_db, build_sqlite_timescale_db, make_user


@pytest.fixture
async def stream_app():
    engine, session_factory = await build_sqlite_db()
    ts_engine, ts_session_factory = await build_sqlite_timescale_db()

    async def _get_db():
        async with session_factory() as session:
            yield session

    app = FastAPI()
    app.include_router(realtime_stream.router)
    app.dependency_overrides[get_db] = _get_db

    # resume() reads TimescaleDB directly (not via a FastAPI dependency) —
    # point the module's reference at the sqlite Timescale stand-in.
    original_ts_factory = realtime_stream.TimescaleSessionLocal
    realtime_stream.TimescaleSessionLocal = ts_session_factory

    # A companion endpoint standing in for LibreIngestionService/POST
    # /glucose/manual publishing on this same event loop, so tests can
    # trigger a live push without crossing TestClient's portal thread.
    @app.post("/probe/publish_reading")
    async def probe_publish_reading(user_id: str, mgdl: int = 130):
        fanout_hub.publish_glucose_reading(
            uuid.UUID(user_id), recorded_at=datetime.now(timezone.utc), mgdl=mgdl,
            trend="STABLE", trend_arrow="→", sensor_id="s1", source="LIBRE",
        )
        return {}

    yield app, session_factory, ts_session_factory

    realtime_stream.TimescaleSessionLocal = original_ts_factory
    await engine.dispose()
    await ts_engine.dispose()


def _user_token(user) -> str:
    return create_access_token(str(user.id), token_version=user.token_version)


async def _device_token(session_factory, user) -> str:
    device_id = uuid.uuid4()
    async with session_factory() as session:
        session.add(Device(id=device_id, hardware_id="pi-1", user_id=user.id, token_version=0))
        await session.commit()
    return create_device_access_token(str(device_id), str(user.id), token_version=0)


# ── Auth ─────────────────────────────────────────────────────────────────

async def test_app_stream_rejects_missing_credentials(stream_app):
    app, _, _ = stream_app
    with TestClient(app) as client:
        with pytest.raises(WebSocketDisconnect) as exc_info:
            with client.websocket_connect("/ws/app/stream"):
                pass
        assert exc_info.value.code == 1008


async def test_device_stream_rejects_missing_credentials(stream_app):
    app, _, _ = stream_app
    with TestClient(app) as client:
        with pytest.raises(WebSocketDisconnect) as exc_info:
            with client.websocket_connect("/ws/device/stream"):
                pass
        assert exc_info.value.code == 1008


async def test_app_stream_rejects_a_device_token(stream_app):
    app, session_factory, _ = stream_app
    user = await make_user(session_factory, "a@example.com")
    token = await _device_token(session_factory, user)
    with TestClient(app) as client:
        with pytest.raises(WebSocketDisconnect):
            with client.websocket_connect("/ws/app/stream", subprotocols=["bearer", token]):
                pass


# ── Hello on connect ─────────────────────────────────────────────────────

async def test_app_stream_sends_hello_on_connect(stream_app):
    app, session_factory, _ = stream_app
    user = await make_user(session_factory, "a@example.com")
    token = _user_token(user)
    with TestClient(app) as client:
        with client.websocket_connect("/ws/app/stream", subprotocols=["bearer", token]) as ws:
            hello = ws.receive_json()
    assert hello["type"] == "hello"
    assert hello["v"] == 1
    assert "server_time" in hello["data"]
    assert hello["data"]["heartbeat_s"] == 30


async def test_device_stream_sends_hello_on_connect(stream_app):
    app, session_factory, _ = stream_app
    user = await make_user(session_factory, "a@example.com")
    token = await _device_token(session_factory, user)
    with TestClient(app) as client:
        with client.websocket_connect("/ws/device/stream", subprotocols=["bearer", token]) as ws:
            hello = ws.receive_json()
    assert hello["type"] == "hello"


# ── Live delivery ────────────────────────────────────────────────────────

async def test_device_stream_receives_a_live_reading(stream_app):
    app, session_factory, _ = stream_app
    user = await make_user(session_factory, "a@example.com")
    token = await _device_token(session_factory, user)
    with TestClient(app) as client:
        with client.websocket_connect("/ws/device/stream", subprotocols=["bearer", token]) as ws:
            ws.receive_json()  # hello

            resp = client.post("/probe/publish_reading", params={"user_id": str(user.id), "mgdl": 145})
            assert resp.status_code == 200

            frame = ws.receive_json()
    assert frame["type"] == "glucose.reading"
    assert frame["data"]["mgdl"] == 145


async def test_app_stream_and_device_stream_both_receive_the_same_publish(stream_app):
    app, session_factory, _ = stream_app
    user = await make_user(session_factory, "a@example.com")
    app_token = _user_token(user)
    device_token = await _device_token(session_factory, user)
    with TestClient(app) as client:
        with client.websocket_connect("/ws/app/stream", subprotocols=["bearer", app_token]) as app_ws:
            with client.websocket_connect("/ws/device/stream", subprotocols=["bearer", device_token]) as dev_ws:
                app_ws.receive_json()
                dev_ws.receive_json()

                client.post("/probe/publish_reading", params={"user_id": str(user.id), "mgdl": 99})

                app_frame = app_ws.receive_json()
                dev_frame = dev_ws.receive_json()
    assert app_frame["data"]["mgdl"] == 99
    assert dev_frame["data"]["mgdl"] == 99


# ── Resume ───────────────────────────────────────────────────────────────

async def test_resume_since_zero_replays_recent_readings(stream_app):
    app, session_factory, ts_session_factory = stream_app
    user = await make_user(session_factory, "a@example.com")
    token = _user_token(user)

    async with ts_session_factory() as ts:
        ts.add(GlucoseReadingModel(
            user_id=user.id, value_mgdl=120, trend="STABLE", trend_arrow="→",
            device_type="LIBRE", is_continuous=True,
            recorded_at=datetime.now(timezone.utc) - timedelta(minutes=5),
            sensor_id="s1", source="LIBRE",
        ))
        await ts.commit()

    # since_seq=0 replaying the whole resume window only makes sense once
    # the hub's own seq counter for this user is past zero — a fresh user
    # with since_seq(0) == current_seq(0) is "already caught up" by
    # FanoutHub.resume()'s own contract (see test_fanout_hub_resume.py).
    fanout_hub.publish(user.id, "glucose.state", {"state": "LIVE", "since": "x"})

    with TestClient(app) as client:
        with client.websocket_connect("/ws/app/stream", subprotocols=["bearer", token]) as ws:
            ws.receive_json()  # hello
            ws.send_json({"type": "resume", "since_seq": 0})
            frame = ws.receive_json()
    assert frame["type"] == "glucose.reading"
    assert frame["data"]["mgdl"] == 120


async def test_resume_with_unreconcilable_seq_gets_resync(stream_app):
    app, session_factory, _ = stream_app
    user = await make_user(session_factory, "a@example.com")
    token = _user_token(user)

    with TestClient(app) as client:
        with client.websocket_connect("/ws/app/stream", subprotocols=["bearer", token]) as ws:
            ws.receive_json()  # hello
            ws.send_json({"type": "resume", "since_seq": 999})
            frame = ws.receive_json()
    assert frame == {"type": "resync"}
