"""End-to-end pairing flow + device-token auth, exercised against the real
FastAPI routes in-process (SQLite store, mocked mobile user).

Covers: open session -> poll pending -> claim -> device receives token once ->
second poll is 'consumed' (token not re-served); token gates /v1/readings and
/v1/voice/query; and the claim error paths (bad code, double claim, expired).
"""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta

import pytest_asyncio
from httpx import ASGITransport, AsyncClient


class _FakeUser:
    def __init__(self) -> None:
        self.id = uuid.uuid4()


@pytest_asyncio.fixture
async def client():
    from app.api.auth import get_current_user
    from app.device_app import app

    app.dependency_overrides[get_current_user] = lambda: _FakeUser()
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        yield c
    app.dependency_overrides.clear()


async def test_full_pairing_flow_delivers_token_once(client):
    # 1. Device opens a pairing session.
    r = await client.post("/v1/devices/pair", json={})
    assert r.status_code == 200
    opened = r.json()
    assert opened["status"] == "pending"
    pairing_id, code = opened["pairing_id"], opened["pairing_code"]

    # 2. Device polls before the app has claimed it.
    r = await client.post("/v1/devices/pair", json={"pairing_id": pairing_id})
    assert r.json()["status"] == "pending"

    # 3. Mobile app (authed user) claims the code.
    r = await client.post("/v1/devices/pair/claim", json={"pairing_code": code})
    assert r.status_code == 200
    assert r.json()["status"] == "claimed"

    # 4. Device's next poll receives the token exactly once.
    r = await client.post("/v1/devices/pair", json={"pairing_id": pairing_id})
    body = r.json()
    assert body["status"] == "claimed"
    token = body["device_token"]
    assert token

    # 5. A second poll must NOT re-serve the raw token.
    r = await client.post("/v1/devices/pair", json={"pairing_id": pairing_id})
    assert r.json()["status"] == "consumed"
    assert "device_token" not in r.json()

    # 6. The token authenticates the device endpoints.
    auth = {"Authorization": f"Bearer {token}"}
    r = await client.get("/v1/readings?since=0", headers=auth)
    assert r.status_code == 200
    assert r.json() == {"readings": []}


async def test_readings_requires_valid_device_token(client):
    r = await client.get("/v1/readings?since=0")
    assert r.status_code == 401

    r = await client.get("/v1/readings?since=0", headers={"Authorization": "Bearer nope"})
    assert r.status_code == 401


async def test_voice_query_authed_but_not_implemented(client):
    # Mint a token via the flow.
    code = (await client.post("/v1/devices/pair", json={})).json()["pairing_code"]
    await client.post("/v1/devices/pair/claim", json={"pairing_code": code})
    pid = None
    # Reopen to get an id we can poll — simpler: open+claim+poll in one path.
    r = await client.post("/v1/devices/pair", json={})
    pid, code2 = r.json()["pairing_id"], r.json()["pairing_code"]
    await client.post("/v1/devices/pair/claim", json={"pairing_code": code2})
    token = (await client.post("/v1/devices/pair", json={"pairing_id": pid})).json()["device_token"]
    auth = {"Authorization": f"Bearer {token}"}

    # Without a token -> 401 (auth is wired).
    assert (await client.post("/v1/voice/query")).status_code == 401
    # With a token -> 501 (Phase 4 fills the body).
    r = await client.post("/v1/voice/query", headers=auth)
    assert r.status_code == 501


async def test_claim_unknown_code_is_404(client):
    r = await client.post("/v1/devices/pair/claim", json={"pairing_code": "ZZZZZZ"})
    assert r.status_code == 404


async def test_claim_twice_is_conflict(client):
    code = (await client.post("/v1/devices/pair", json={})).json()["pairing_code"]
    assert (await client.post("/v1/devices/pair/claim", json={"pairing_code": code})).status_code == 200
    r = await client.post("/v1/devices/pair/claim", json={"pairing_code": code})
    assert r.status_code == 409


async def test_claim_expired_code_is_410(client):
    # Open a session, then force it expired directly in the store.
    from sqlalchemy import select

    from app.device_database import DeviceSessionLocal
    from app.models.device import PairingSession

    opened = (await client.post("/v1/devices/pair", json={})).json()
    async with DeviceSessionLocal() as s:
        ps = (
            await s.execute(select(PairingSession).where(PairingSession.id == opened["pairing_id"]))
        ).scalar_one()
        ps.expires_at = datetime.utcnow() - timedelta(minutes=1)
        await s.commit()

    r = await client.post("/v1/devices/pair/claim", json={"pairing_code": opened["pairing_code"]})
    assert r.status_code == 410
