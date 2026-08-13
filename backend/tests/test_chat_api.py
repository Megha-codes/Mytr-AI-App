"""HTTP-level tests for POST /chat — auth, request/response shape, and
that the route really drives services/chat/conversation.py's real loop
(faking only the Groq client, same as test_chat_conversation.py).
"""

from __future__ import annotations

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

import app.services.chat.conversation as conversation_module
from app.api import chat
from app.core.security import create_access_token
from app.database import get_db
from app.services.groq_service import GroqReply, ToolCall

from .test_chat_conversation import FakeGroqService
from .conftest import build_sqlite_db, make_user


@pytest.fixture
async def app_and_db():
    engine, session_factory = await build_sqlite_db()

    async def _get_db():
        async with session_factory() as session:
            yield session

    app = FastAPI()
    app.include_router(chat.router)
    app.dependency_overrides[get_db] = _get_db

    with TestClient(app) as client:
        yield client, session_factory

    await engine.dispose()


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


async def test_chat_requires_authentication(app_and_db):
    client, _ = app_and_db
    resp = client.post("/chat", json={"message": "hi"})
    assert resp.status_code == 401


async def test_chat_returns_a_reply_grounded_in_a_real_tool_result(app_and_db, monkeypatch):
    client, session_factory = app_and_db
    user = await make_user(session_factory, "a@example.com")
    token = create_access_token(subject=str(user.id), token_version=user.token_version)

    fake = FakeGroqService(replies=[
        GroqReply(content=None, tool_calls=[ToolCall(id="c1", name="get_water_daily", arguments={})]),
        GroqReply(content="You haven't logged any water today yet."),
    ])
    monkeypatch.setattr(conversation_module, "_build_groq_service", lambda: fake)

    resp = client.post("/chat", json={"message": "how much water have I had today?"}, headers=_auth(token))
    assert resp.status_code == 200
    body = resp.json()

    assert body["reply"] == "You haven't logged any water today yet."
    assert body["tools_used"] == ["get_water_daily"]
    assert body["conversation_id"]


async def test_chat_reuses_a_client_supplied_conversation_id(app_and_db, monkeypatch):
    client, session_factory = app_and_db
    user = await make_user(session_factory, "a@example.com")
    token = create_access_token(subject=str(user.id), token_version=user.token_version)

    monkeypatch.setattr(
        conversation_module, "_build_groq_service",
        lambda: FakeGroqService(replies=[GroqReply(content="ok", tool_calls=[])]),
    )

    resp = client.post(
        "/chat",
        json={"message": "hi again", "conversation_id": "11111111-1111-1111-1111-111111111111"},
        headers=_auth(token),
    )
    assert resp.json()["conversation_id"] == "11111111-1111-1111-1111-111111111111"
