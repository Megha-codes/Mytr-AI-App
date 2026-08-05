"""Tests for the shared /ws/app/stream and /ws/device/stream auth helpers
(architecture-v3.md §2.6): token travels in Sec-WebSocket-Protocol, not the
query string.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone

import pytest
from fastapi import FastAPI, WebSocket
from fastapi.testclient import TestClient

from app.core.security import create_access_token, create_device_access_token
from app.database import get_db
from app.models.device import Device
from app.models.user import User
from sqlalchemy import select
from app.services.realtime.ws_auth import (
    authenticate_app_stream,
    authenticate_device_stream,
    extract_bearer_subprotocol_token,
)

from .conftest import build_sqlite_db, make_user


class _FakeWebSocket:
    def __init__(self, header_value):
        self.headers = {} if header_value is None else {"sec-websocket-protocol": header_value}


# ── extract_bearer_subprotocol_token (pure) ─────────────────────────────────

def test_extracts_token_from_well_formed_header():
    ws = _FakeWebSocket("bearer, my-jwt-value")
    assert extract_bearer_subprotocol_token(ws) == "my-jwt-value"


def test_returns_none_when_header_missing():
    assert extract_bearer_subprotocol_token(_FakeWebSocket(None)) is None


@pytest.mark.parametrize("value", ["bearer", "bearer,", "basic, token", "bearer, a, b"])
def test_returns_none_for_malformed_header(value):
    assert extract_bearer_subprotocol_token(_FakeWebSocket(value)) is None


# ── authenticate_app_stream / authenticate_device_stream (integration) ─────

@pytest.fixture
async def app_and_db():
    engine, session_factory = await build_sqlite_db()

    app = FastAPI()

    @app.websocket("/probe/app")
    async def probe_app(websocket: WebSocket):
        await websocket.accept(subprotocol="bearer")
        async with session_factory() as db:
            user = await authenticate_app_stream(websocket, db)
        await websocket.send_json({"ok": user is not None, "user_id": str(user.id) if user else None})
        await websocket.close()

    @app.websocket("/probe/device")
    async def probe_device(websocket: WebSocket):
        await websocket.accept(subprotocol="bearer")
        async with session_factory() as db:
            resolved = await authenticate_device_stream(websocket, db)
        if resolved is None:
            await websocket.send_json({"ok": False})
        else:
            device, user_id = resolved
            await websocket.send_json({"ok": True, "device_id": str(device.id), "user_id": user_id})
        await websocket.close()

    yield app, session_factory
    await engine.dispose()


async def test_app_stream_authenticates_a_valid_user_token(app_and_db):
    app, session_factory = app_and_db
    user = await make_user(session_factory, "a@example.com")
    token = create_access_token(str(user.id), token_version=user.token_version)

    with TestClient(app) as client:
        with client.websocket_connect("/probe/app", subprotocols=["bearer", token]) as ws:
            msg = ws.receive_json()
    assert msg == {"ok": True, "user_id": str(user.id)}


async def test_app_stream_rejects_a_device_token():
    engine, session_factory = await build_sqlite_db()
    app = FastAPI()

    @app.websocket("/probe/app")
    async def probe_app(websocket: WebSocket):
        await websocket.accept(subprotocol="bearer")
        async with session_factory() as db:
            user = await authenticate_app_stream(websocket, db)
        await websocket.send_json({"ok": user is not None})
        await websocket.close()

    user = await make_user(session_factory, "a@example.com")
    device_id = uuid.uuid4()
    async with session_factory() as session:
        session.add(Device(id=device_id, hardware_id="pi-1", user_id=user.id, token_version=0))
        await session.commit()
    device_token = create_device_access_token(str(device_id), str(user.id), token_version=0)

    with TestClient(app) as client:
        with client.websocket_connect("/probe/app", subprotocols=["bearer", device_token]) as ws:
            msg = ws.receive_json()
    assert msg == {"ok": False}
    await engine.dispose()


async def test_app_stream_rejects_a_stale_token_version(app_and_db):
    app, session_factory = app_and_db
    user = await make_user(session_factory, "a@example.com")
    token = create_access_token(str(user.id), token_version=0)
    async with session_factory() as session:
        result = await session.execute(select(User).where(User.id == user.id))
        fresh = result.scalar_one()
        fresh.token_version = 1
        await session.commit()

    with TestClient(app) as client:
        with client.websocket_connect("/probe/app", subprotocols=["bearer", token]) as ws:
            msg = ws.receive_json()
    assert msg["ok"] is False


async def test_app_stream_rejects_missing_credentials(app_and_db):
    app, _ = app_and_db
    with TestClient(app) as client:
        with client.websocket_connect("/probe/app") as ws:
            msg = ws.receive_json()
    assert msg == {"ok": False, "user_id": None}


async def test_device_stream_authenticates_a_valid_device_token(app_and_db):
    app, session_factory = app_and_db
    user = await make_user(session_factory, "a@example.com")
    device_id = uuid.uuid4()
    async with session_factory() as session:
        session.add(Device(id=device_id, hardware_id="pi-1", user_id=user.id, token_version=0))
        await session.commit()
    token = create_device_access_token(str(device_id), str(user.id), token_version=0)

    with TestClient(app) as client:
        with client.websocket_connect("/probe/device", subprotocols=["bearer", token]) as ws:
            msg = ws.receive_json()
    assert msg == {"ok": True, "device_id": str(device_id), "user_id": str(user.id)}


async def test_device_stream_rejects_a_revoked_device(app_and_db):
    app, session_factory = app_and_db
    user = await make_user(session_factory, "a@example.com")
    device_id = uuid.uuid4()
    async with session_factory() as session:
        session.add(Device(
            id=device_id, hardware_id="pi-1", user_id=user.id, token_version=0,
            revoked_at=datetime.now(timezone.utc),
        ))
        await session.commit()
    token = create_device_access_token(str(device_id), str(user.id), token_version=0)

    with TestClient(app) as client:
        with client.websocket_connect("/probe/device", subprotocols=["bearer", token]) as ws:
            msg = ws.receive_json()
    assert msg == {"ok": False}


async def test_device_stream_rejects_a_user_token():
    engine, session_factory = await build_sqlite_db()
    app = FastAPI()

    @app.websocket("/probe/device")
    async def probe_device(websocket: WebSocket):
        await websocket.accept(subprotocol="bearer")
        async with session_factory() as db:
            resolved = await authenticate_device_stream(websocket, db)
        await websocket.send_json({"ok": resolved is not None})
        await websocket.close()

    user = await make_user(session_factory, "a@example.com")
    token = create_access_token(str(user.id), token_version=user.token_version)

    with TestClient(app) as client:
        with client.websocket_connect("/probe/device", subprotocols=["bearer", token]) as ws:
            msg = ws.receive_json()
    assert msg == {"ok": False}
    await engine.dispose()
