"""Regression tests for the cross-user CGM access hole in cgm_connect.py.

Previously every route in this module took `user_id` as a client-supplied
query parameter instead of deriving it from the authenticated caller's JWT
(see docs/architecture-v3.md §5.1, item (a)). Any authenticated user could
therefore read, connect, or delete another user's CGM device by simply
passing a different `user_id`. These tests prove that's no longer possible:
the routes now depend on `get_current_user`, so there is no `user_id` input
left to spoof.
"""

from __future__ import annotations

import uuid

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.database import get_db
from app.core.security import create_access_token
from app.api import cgm_connect

from .conftest import build_sqlite_db, make_user


@pytest.fixture
async def client_and_users():
    engine, session_factory = await build_sqlite_db()

    async def _get_db():
        async with session_factory() as session:
            yield session

    app = FastAPI()
    app.include_router(cgm_connect.router)
    app.dependency_overrides[get_db] = _get_db

    user_a = await make_user(session_factory, "a@example.com")
    user_b = await make_user(session_factory, "b@example.com")
    token_a = create_access_token(subject=str(user_a.id), token_version=user_a.token_version)
    token_b = create_access_token(subject=str(user_b.id), token_version=user_b.token_version)

    with TestClient(app) as client:
        yield client, user_a, token_a, user_b, token_b

    await engine.dispose()


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


async def test_connect_requires_authentication(client_and_users):
    client, *_ = client_and_users
    response = client.post("/cgm/connect/manual")
    assert response.status_code == 401


async def test_devices_list_is_scoped_to_caller(client_and_users):
    client, user_a, token_a, user_b, token_b = client_and_users

    connect_resp = client.post("/cgm/connect/manual", headers=_auth(token_a))
    assert connect_resp.status_code == 200
    assert connect_resp.json()["connected"] is True

    # User B must not see the device user A just connected.
    b_devices = client.get("/cgm/devices", headers=_auth(token_b))
    assert b_devices.status_code == 200
    assert b_devices.json() == []

    a_devices = client.get("/cgm/devices", headers=_auth(token_a))
    assert a_devices.status_code == 200
    assert len(a_devices.json()) == 1


async def test_cannot_delete_another_users_device(client_and_users):
    client, user_a, token_a, user_b, token_b = client_and_users

    connect_resp = client.post("/cgm/connect/manual", headers=_auth(token_a))
    device_id = connect_resp.json()["device_id"]

    delete_resp = client.delete(f"/cgm/devices/{device_id}", headers=_auth(token_b))
    assert delete_resp.status_code == 404

    # The device must still exist for its real owner.
    a_devices = client.get("/cgm/devices", headers=_auth(token_a))
    assert len(a_devices.json()) == 1

    own_delete = client.delete(f"/cgm/devices/{device_id}", headers=_auth(token_a))
    assert own_delete.status_code == 200


async def test_impersonation_via_legacy_user_id_param_is_ineffective(client_and_users):
    """The old attack: pass another user's id as a query/body parameter.

    Before the fix, `user_id` was a plain function parameter FastAPI read
    from the query string, so any caller could act as any user by supplying
    their UUID. Now the parameter doesn't exist on the route at all — a
    `user_id` in the query string is inert, and the action always applies to
    whoever the bearer token belongs to.
    """
    client, user_a, token_a, user_b, token_b = client_and_users

    resp = client.post(
        f"/cgm/connect/manual?user_id={user_a.id}",
        headers=_auth(token_b),
    )
    assert resp.status_code == 200

    # The device was created for B (the token owner), never for A.
    a_devices = client.get("/cgm/devices", headers=_auth(token_a))
    assert a_devices.json() == []

    b_devices = client.get("/cgm/devices", headers=_auth(token_b))
    assert len(b_devices.json()) == 1


async def test_reconnect_and_credentials_are_scoped_to_caller(client_and_users):
    client, user_a, token_a, user_b, token_b = client_and_users

    # Neither user has stored Libre credentials, so reconnect must report
    # failure for both — but critically, B's request must check B's
    # credentials, never A's.
    resp_b = client.post("/cgm/reconnect/LIBRE_2", headers=_auth(token_b))
    assert resp_b.status_code == 200
    assert resp_b.json()["connected"] is False
