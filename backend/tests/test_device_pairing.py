"""Integration tests for the pairing flow and device management
(architecture-v3.md §2.2), against the real router mounted with a SQLite DB.
"""

from __future__ import annotations

import uuid

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.database import get_db
from app.core.security import create_access_token, create_device_refresh_token
from app.api import devices as devices_module
from app.models.device import Device

from .conftest import build_sqlite_db, make_user


def _hw() -> str:
    return f"pi-{uuid.uuid4()}"


@pytest.fixture
async def client_and_db():
    engine, session_factory = await build_sqlite_db()

    async def _get_db():
        async with session_factory() as session:
            yield session

    app = FastAPI()
    app.include_router(devices_module.router)
    app.dependency_overrides[get_db] = _get_db

    # Isolate rate-limit state between tests (module-level dicts persist for
    # the whole test process otherwise).
    devices_module._pair_start_attempts.clear()
    devices_module._pair_poll_failures.clear()

    with TestClient(app) as client:
        yield client, session_factory

    await engine.dispose()


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


# ── Full happy path ────────────────────────────────────────────────────────────

async def test_full_pairing_flow_issues_device_tokens(client_and_db):
    client, session_factory = client_and_db
    hardware_id = _hw()
    user = await make_user(session_factory, "a@example.com")
    user_token = create_access_token(str(user.id), token_version=user.token_version)

    start_resp = client.post(
        "/device/pair/start", json={"hardware_id": hardware_id, "firmware_version": "1.0.0"}
    )
    assert start_resp.status_code == 200
    code = start_resp.json()["code"]
    assert start_resp.json()["expires_in"] == 600
    assert "-" in code  # formatted XXXX-XXXX

    claim_resp = client.post(
        "/devices/pair", json={"code": code, "name": "Bedside"}, headers=_auth(user_token)
    )
    assert claim_resp.status_code == 200
    assert claim_resp.json()["name"] == "Bedside"

    poll_resp = client.post("/device/pair/poll", json={"hardware_id": hardware_id, "code": code})
    assert poll_resp.status_code == 200
    body = poll_resp.json()
    assert body["user_id"] == str(user.id)
    assert body["device_name"] == "Bedside"
    assert body["expires_in"] == 3600
    assert body["device_access_token"]
    assert body["device_refresh_token"]

    # Single-use: the code is gone after pickup.
    second_poll = client.post("/device/pair/poll", json={"hardware_id": hardware_id, "code": code})
    assert second_poll.status_code == 404


async def test_poll_returns_pending_before_claim(client_and_db, monkeypatch):
    client, _session_factory = client_and_db
    hardware_id = _hw()
    monkeypatch.setattr(devices_module, "_POLL_TIMEOUT_SECONDS", 0.05)
    monkeypatch.setattr(devices_module, "_POLL_INTERVAL_SECONDS", 0.01)

    start_resp = client.post("/device/pair/start", json={"hardware_id": hardware_id})
    code = start_resp.json()["code"]

    poll_resp = client.post("/device/pair/poll", json={"hardware_id": hardware_id, "code": code})
    assert poll_resp.status_code == 202
    assert poll_resp.json()["status"] == "pending"


async def test_poll_unknown_code_is_404(client_and_db):
    client, _session_factory = client_and_db
    resp = client.post("/device/pair/poll", json={"hardware_id": _hw(), "code": "ZZZZ9999"})
    assert resp.status_code == 404


# ── Claim edge cases ───────────────────────────────────────────────────────────

async def test_claim_unknown_code_is_404(client_and_db):
    client, session_factory = client_and_db
    user = await make_user(session_factory, "a@example.com")
    token = create_access_token(str(user.id), token_version=0)

    resp = client.post("/devices/pair", json={"code": "ZZZZ9999"}, headers=_auth(token))
    assert resp.status_code == 404


async def test_claim_already_claimed_code_is_409(client_and_db):
    client, session_factory = client_and_db
    hardware_id = _hw()
    user_a = await make_user(session_factory, "a@example.com")
    user_b = await make_user(session_factory, "b@example.com")
    token_a = create_access_token(str(user_a.id), token_version=0)
    token_b = create_access_token(str(user_b.id), token_version=0)

    start_resp = client.post("/device/pair/start", json={"hardware_id": hardware_id})
    code = start_resp.json()["code"]

    first_claim = client.post("/devices/pair", json={"code": code}, headers=_auth(token_a))
    assert first_claim.status_code == 200

    second_claim = client.post("/devices/pair", json={"code": code}, headers=_auth(token_b))
    assert second_claim.status_code == 409


async def test_cannot_steal_an_already_paired_device_with_a_fresh_code(client_and_db):
    """A device actively paired to user A must not be claimable by user B
    just because the device (physically, presumably by A) generated a new
    pairing code — re-pairing to a different user requires an explicit
    unpair first (architecture-v3.md §1.2)."""
    client, session_factory = client_and_db
    hardware_id = _hw()
    user_a = await make_user(session_factory, "a@example.com")
    user_b = await make_user(session_factory, "b@example.com")
    token_a = create_access_token(str(user_a.id), token_version=0)
    token_b = create_access_token(str(user_b.id), token_version=0)

    first_start = client.post("/device/pair/start", json={"hardware_id": hardware_id})
    first_code = first_start.json()["code"]
    claim = client.post("/devices/pair", json={"code": first_code}, headers=_auth(token_a))
    assert claim.status_code == 200

    second_start = client.post("/device/pair/start", json={"hardware_id": hardware_id})
    second_code = second_start.json()["code"]
    hijack_attempt = client.post("/devices/pair", json={"code": second_code}, headers=_auth(token_b))
    assert hijack_attempt.status_code == 409

    # Still owned by A.
    a_devices = client.get("/devices", headers=_auth(token_a))
    assert len(a_devices.json()) == 1
    b_devices = client.get("/devices", headers=_auth(token_b))
    assert b_devices.json() == []


async def test_reclaim_by_same_owner_is_idempotent(client_and_db):
    client, session_factory = client_and_db
    hardware_id = _hw()
    user = await make_user(session_factory, "a@example.com")
    token = create_access_token(str(user.id), token_version=0)

    first_start = client.post("/device/pair/start", json={"hardware_id": hardware_id})
    claim1 = client.post(
        "/devices/pair", json={"code": first_start.json()["code"]}, headers=_auth(token)
    )
    assert claim1.status_code == 200

    second_start = client.post("/device/pair/start", json={"hardware_id": hardware_id})
    claim2 = client.post(
        "/devices/pair", json={"code": second_start.json()["code"]}, headers=_auth(token)
    )
    assert claim2.status_code == 200
    assert claim2.json()["device_id"] == claim1.json()["device_id"]


# ── Rate limiting ──────────────────────────────────────────────────────────────

async def test_pair_start_rate_limited_at_5_per_hour(client_and_db):
    client, _session_factory = client_and_db
    hardware_id = _hw()

    for _ in range(5):
        resp = client.post("/device/pair/start", json={"hardware_id": hardware_id})
        assert resp.status_code == 200

    sixth = client.post("/device/pair/start", json={"hardware_id": hardware_id})
    assert sixth.status_code == 429


async def test_pair_poll_wrong_code_rate_limited_at_10_per_minute(client_and_db):
    client, _session_factory = client_and_db
    hardware_id = _hw()

    for _ in range(10):
        resp = client.post("/device/pair/poll", json={"hardware_id": hardware_id, "code": "ZZZZ9999"})
        assert resp.status_code == 404

    eleventh = client.post("/device/pair/poll", json={"hardware_id": hardware_id, "code": "ZZZZ9999"})
    assert eleventh.status_code == 429


# ── Device management (user JWT) ────────────────────────────────────────────────

async def _pair_a_device(client, session_factory, user, name="Bedside"):
    token = create_access_token(str(user.id), token_version=user.token_version)
    hardware_id = _hw()
    start_resp = client.post("/device/pair/start", json={"hardware_id": hardware_id})
    code = start_resp.json()["code"]
    claim_resp = client.post(
        "/devices/pair", json={"code": code, "name": name}, headers=_auth(token)
    )
    return claim_resp.json()["device_id"], hardware_id, code


async def test_devices_list_scoped_to_caller(client_and_db):
    client, session_factory = client_and_db
    user_a = await make_user(session_factory, "a@example.com")
    user_b = await make_user(session_factory, "b@example.com")
    token_a = create_access_token(str(user_a.id), token_version=0)
    token_b = create_access_token(str(user_b.id), token_version=0)

    await _pair_a_device(client, session_factory, user_a)

    assert len(client.get("/devices", headers=_auth(token_a)).json()) == 1
    assert client.get("/devices", headers=_auth(token_b)).json() == []


async def test_rename_device(client_and_db):
    client, session_factory = client_and_db
    user = await make_user(session_factory, "a@example.com")
    token = create_access_token(str(user.id), token_version=0)
    device_id, *_ = await _pair_a_device(client, session_factory, user)

    resp = client.patch(f"/devices/{device_id}", json={"name": "Living Room"}, headers=_auth(token))
    assert resp.status_code == 200
    assert resp.json()["name"] == "Living Room"


async def test_cannot_rename_or_delete_another_users_device(client_and_db):
    client, session_factory = client_and_db
    user_a = await make_user(session_factory, "a@example.com")
    user_b = await make_user(session_factory, "b@example.com")
    token_b = create_access_token(str(user_b.id), token_version=0)
    device_id, *_ = await _pair_a_device(client, session_factory, user_a)

    rename_resp = client.patch(f"/devices/{device_id}", json={"name": "Hijacked"}, headers=_auth(token_b))
    assert rename_resp.status_code == 404

    delete_resp = client.delete(f"/devices/{device_id}", headers=_auth(token_b))
    assert delete_resp.status_code == 404


async def test_unpair_revokes_and_bumps_token_version(client_and_db):
    client, session_factory = client_and_db
    user = await make_user(session_factory, "a@example.com")
    token = create_access_token(str(user.id), token_version=0)
    device_id, hardware_id, code = await _pair_a_device(client, session_factory, user)

    # Pick up the device tokens before unpairing.
    poll_resp = client.post("/device/pair/poll", json={"hardware_id": hardware_id, "code": code})
    device_refresh_token = poll_resp.json()["device_refresh_token"]

    delete_resp = client.delete(f"/devices/{device_id}", headers=_auth(token))
    assert delete_resp.status_code == 200

    # No longer listed.
    assert client.get("/devices", headers=_auth(token)).json() == []

    # The device's own tokens are now invalid — token_version moved on.
    refresh_resp = client.post(
        "/device/token/refresh", json={"refresh_token": device_refresh_token}
    )
    assert refresh_resp.status_code == 401

    async with session_factory() as session:
        from sqlalchemy import select

        result = await session.execute(select(Device).where(Device.id == device_id))
        device = result.scalar_one()
        assert device.revoked_at is not None
        assert device.token_version == 1


async def test_unpair_then_repair_reactivates_device(client_and_db):
    client, session_factory = client_and_db
    user = await make_user(session_factory, "a@example.com")
    token = create_access_token(str(user.id), token_version=0)
    device_id, hardware_id, _first_code = await _pair_a_device(client, session_factory, user)

    assert client.delete(f"/devices/{device_id}", headers=_auth(token)).status_code == 200
    assert client.get("/devices", headers=_auth(token)).json() == []

    new_start = client.post("/device/pair/start", json={"hardware_id": hardware_id})
    new_code = new_start.json()["code"]
    reclaim = client.post("/devices/pair", json={"code": new_code}, headers=_auth(token))
    assert reclaim.status_code == 200
    assert reclaim.json()["device_id"] == device_id

    devices = client.get("/devices", headers=_auth(token)).json()
    assert len(devices) == 1
    assert devices[0]["device_id"] == device_id


# ── Device token refresh ─────────────────────────────────────────────────────

async def test_device_token_refresh_rotates_tokens(client_and_db):
    client, session_factory = client_and_db
    user = await make_user(session_factory, "a@example.com")
    _device_id, hardware_id, code = await _pair_a_device(client, session_factory, user)
    poll_resp = client.post("/device/pair/poll", json={"hardware_id": hardware_id, "code": code})
    old_refresh = poll_resp.json()["device_refresh_token"]

    refresh_resp = client.post("/device/token/refresh", json={"refresh_token": old_refresh})
    assert refresh_resp.status_code == 200
    body = refresh_resp.json()
    assert body["device_access_token"]
    assert body["device_refresh_token"]

    # The new refresh token must itself work (a fresh, valid device refresh
    # token was actually minted — not just the same one echoed back).
    second_refresh = client.post(
        "/device/token/refresh", json={"refresh_token": body["device_refresh_token"]}
    )
    assert second_refresh.status_code == 200


async def test_device_token_refresh_rejects_stale_and_wrong_type(client_and_db):
    client, session_factory = client_and_db
    user = await make_user(session_factory, "a@example.com")
    device_id, hardware_id, code = await _pair_a_device(client, session_factory, user)
    poll_resp = client.post("/device/pair/poll", json={"hardware_id": hardware_id, "code": code})
    refresh_token = poll_resp.json()["device_refresh_token"]

    # A user access token presented where a device refresh token is expected.
    user_access_token = create_access_token(str(user.id), token_version=0)
    wrong_type_resp = client.post(
        "/device/token/refresh", json={"refresh_token": user_access_token}
    )
    assert wrong_type_resp.status_code == 401

    # A stale device refresh token (device_id valid, but tv doesn't match
    # anymore) minted directly, bypassing the real flow.
    async with session_factory() as session:
        from sqlalchemy import select

        result = await session.execute(select(Device).where(Device.id == uuid.UUID(device_id)))
        device = result.scalar_one()
    stale_refresh = create_device_refresh_token(device.id, user.id, token_version=device.token_version + 5)
    stale_resp = client.post("/device/token/refresh", json={"refresh_token": stale_refresh})
    assert stale_resp.status_code == 401
