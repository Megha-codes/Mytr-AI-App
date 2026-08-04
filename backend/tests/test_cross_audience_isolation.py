"""The explicit requirement for this pass: a device token must never
authenticate as a user, and a user token must never authenticate as a
device (architecture-v3.md §2.1's "two token audiences" table).

Covers both directions at two levels:
- direct dependency calls (get_current_user / get_current_device in
  isolation, no HTTP layer)
- real HTTP requests against the actual user-JWT-protected routes in
  api/devices.py (GET/PATCH/DELETE /devices, POST /devices/pair)

(cgm_connect.py is not used as a fixture here: on this branch, off plain
master, it still takes user_id as a client-supplied parameter rather than
Depends(get_current_user) — that fix lives on a separate branch. devices.py
is the real, already-authenticated production surface available here.)
"""

from __future__ import annotations

import uuid

import pytest
from fastapi import FastAPI, HTTPException
from fastapi.testclient import TestClient

from app.api.auth import get_current_user
from app.api import devices as devices_module
from app.core.device_auth import get_current_device
from app.core.security import (
    create_access_token,
    create_device_access_token,
    create_device_refresh_token,
    create_refresh_token,
)
from app.database import get_db
from app.models.device import Device

from .conftest import build_sqlite_db, make_user


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


# ── Direct dependency calls ───────────────────────────────────────────────────

async def test_get_current_user_rejects_a_device_access_token():
    engine, session_factory = await build_sqlite_db()
    user = await make_user(session_factory, "a@example.com")
    device = Device(id=uuid.uuid4(), hardware_id="pi-1", user_id=user.id, token_version=0)
    async with session_factory() as session:
        session.add(device)
        await session.commit()

    device_token = create_device_access_token(device.id, user.id, token_version=0)

    async with session_factory() as session:
        with pytest.raises(HTTPException) as exc_info:
            await get_current_user(authorization=f"Bearer {device_token}", db=session)
    assert exc_info.value.status_code == 401
    await engine.dispose()


async def test_get_current_user_rejects_a_device_refresh_token():
    engine, session_factory = await build_sqlite_db()
    user = await make_user(session_factory, "a@example.com")
    device_refresh = create_device_refresh_token(uuid.uuid4(), user.id, token_version=0)

    async with session_factory() as session:
        with pytest.raises(HTTPException) as exc_info:
            await get_current_user(authorization=f"Bearer {device_refresh}", db=session)
    assert exc_info.value.status_code == 401
    await engine.dispose()


async def test_get_current_device_rejects_a_user_access_token():
    engine, session_factory = await build_sqlite_db()
    user = await make_user(session_factory, "a@example.com")
    user_token = create_access_token(str(user.id), token_version=0)

    async with session_factory() as session:
        with pytest.raises(HTTPException) as exc_info:
            await get_current_device(authorization=f"Bearer {user_token}", db=session)
    assert exc_info.value.status_code == 401
    await engine.dispose()


async def test_get_current_device_rejects_a_user_refresh_token():
    engine, session_factory = await build_sqlite_db()
    user = await make_user(session_factory, "a@example.com")
    user_refresh = create_refresh_token(str(user.id), token_version=0)

    async with session_factory() as session:
        with pytest.raises(HTTPException) as exc_info:
            await get_current_device(authorization=f"Bearer {user_refresh}", db=session)
    assert exc_info.value.status_code == 401
    await engine.dispose()


# ── Real HTTP endpoints ──────────────────────────────────────────────────────

@pytest.fixture
async def devices_client():
    engine, session_factory = await build_sqlite_db()

    async def _get_db():
        async with session_factory() as session:
            yield session

    app = FastAPI()
    app.include_router(devices_module.router)
    app.dependency_overrides[get_db] = _get_db
    devices_module._pair_start_attempts.clear()
    devices_module._pair_poll_failures.clear()

    with TestClient(app) as client:
        yield client, session_factory

    await engine.dispose()


async def test_device_token_cannot_list_devices(devices_client):
    client, session_factory = devices_client
    user = await make_user(session_factory, "a@example.com")
    device = Device(id=uuid.uuid4(), hardware_id="pi-1", user_id=user.id, token_version=0)
    async with session_factory() as session:
        session.add(device)
        await session.commit()
    device_token = create_device_access_token(device.id, user.id, token_version=0)

    resp = client.get("/devices", headers=_auth(device_token))
    assert resp.status_code == 401


async def test_device_token_cannot_claim_a_pairing_code(devices_client):
    client, session_factory = devices_client
    user = await make_user(session_factory, "a@example.com")
    device = Device(id=uuid.uuid4(), hardware_id="pi-1", user_id=user.id, token_version=0)
    async with session_factory() as session:
        session.add(device)
        await session.commit()
    device_token = create_device_access_token(device.id, user.id, token_version=0)

    start_resp = client.post("/device/pair/start", json={"hardware_id": "pi-2"})
    code = start_resp.json()["code"]

    resp = client.post("/devices/pair", json={"code": code}, headers=_auth(device_token))
    assert resp.status_code == 401


async def test_device_token_cannot_rename_or_delete_a_device(devices_client):
    client, session_factory = devices_client
    user = await make_user(session_factory, "a@example.com")
    target_device = Device(id=uuid.uuid4(), hardware_id="pi-1", user_id=user.id, token_version=0)
    other_device = Device(id=uuid.uuid4(), hardware_id="pi-2", user_id=user.id, token_version=0)
    async with session_factory() as session:
        session.add_all([target_device, other_device])
        await session.commit()
    device_token = create_device_access_token(other_device.id, user.id, token_version=0)

    rename_resp = client.patch(
        f"/devices/{target_device.id}", json={"name": "Hijacked"}, headers=_auth(device_token)
    )
    assert rename_resp.status_code == 401

    delete_resp = client.delete(f"/devices/{target_device.id}", headers=_auth(device_token))
    assert delete_resp.status_code == 401


async def test_user_token_cannot_be_used_as_a_device_refresh_token(devices_client):
    """The device refresh endpoint takes the token in the body (there's no
    device Authorization header on this route), so the cross-audience check
    happens via decode_token_payload's type discrimination instead."""
    client, session_factory = devices_client
    user = await make_user(session_factory, "a@example.com")
    user_refresh = create_refresh_token(str(user.id), token_version=0)

    resp = client.post("/device/token/refresh", json={"refresh_token": user_refresh})
    assert resp.status_code == 401
