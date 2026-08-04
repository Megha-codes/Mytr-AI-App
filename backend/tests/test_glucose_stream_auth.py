"""Regression tests for the unauthenticated glucose websocket hole.

Previously `/ws/glucose/{user_id}` took the user id straight from the URL
path with no auth check at all (see docs/architecture-v3.md §5.1, item (b))
— anyone who knew (or guessed) a UUID could stream that user's glucose. The
route is now `/ws/glucose?token=<access_token>`: the user comes from the
verified JWT, and there is no path segment left to spoof.
"""

from __future__ import annotations

import uuid

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from starlette.websockets import WebSocketDisconnect

from app.database import get_db
from app.core.security import create_access_token
from app.api.websockets import glucose_stream

from .conftest import build_sqlite_db, make_user


@pytest.fixture
async def ws_client():
    engine, session_factory = await build_sqlite_db()

    async def _get_db():
        async with session_factory() as session:
            yield session

    app = FastAPI()
    app.include_router(glucose_stream.router)
    app.dependency_overrides[get_db] = _get_db

    user_a = await make_user(session_factory, "a@example.com")
    token_a = create_access_token(subject=str(user_a.id), token_version=user_a.token_version)

    with TestClient(app) as client:
        yield client, user_a, token_a

    await engine.dispose()


async def test_missing_token_is_rejected_before_accept(ws_client):
    client, _user_a, _token_a = ws_client
    with pytest.raises(WebSocketDisconnect):
        with client.websocket_connect("/ws/glucose"):
            pass


async def test_invalid_token_is_rejected(ws_client):
    client, _user_a, _token_a = ws_client
    with pytest.raises(WebSocketDisconnect) as exc_info:
        with client.websocket_connect("/ws/glucose?token=not-a-real-token"):
            pass
    assert exc_info.value.code == 1008


async def test_valid_token_authenticates_as_the_token_owner(ws_client):
    client, user_a, token_a = ws_client
    with client.websocket_connect(f"/ws/glucose?token={token_a}"):
        # The manager must key the connection by the *token's* subject —
        # there is no other input that could name a different user.
        assert str(user_a.id) in glucose_stream.manager.active_connections


async def test_unknown_user_token_is_rejected(ws_client):
    """A well-formed, correctly-signed token for a user that doesn't exist
    (e.g. a deleted account) must not be treated as authenticated."""
    client, _user_a, _token_a = ws_client
    phantom_token = create_access_token(subject=str(uuid.uuid4()), token_version=0)
    with pytest.raises(WebSocketDisconnect) as exc_info:
        with client.websocket_connect(f"/ws/glucose?token={phantom_token}"):
            pass
    assert exc_info.value.code == 1008


async def test_stale_token_version_is_rejected(ws_client):
    """A token minted before a token_version bump (logout-all / revocation)
    must be rejected, exactly like the HTTP `get_current_user` dependency."""
    client, user_a, _token_a = ws_client
    stale_token = create_access_token(subject=str(user_a.id), token_version=user_a.token_version + 1)
    with pytest.raises(WebSocketDisconnect) as exc_info:
        with client.websocket_connect(f"/ws/glucose?token={stale_token}"):
            pass
    assert exc_info.value.code == 1008
