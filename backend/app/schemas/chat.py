"""Schemas for POST /chat (the analytics chatbot)."""

from __future__ import annotations

from typing import Literal, Optional

from pydantic import BaseModel


class ChatMessageIn(BaseModel):
    role: Literal["user", "assistant"]
    content: str


class ChatRequest(BaseModel):
    message: str
    # Client-managed conversation state — the server has no session to
    # resume, it just replays whatever history is sent. Logging
    # (services/chat/log.py) is a separate, independent audit trail, not
    # how context is reconstructed.
    history: list[ChatMessageIn] = []
    # Groups this turn with prior ones in the audit log. The server
    # generates one if omitted (a client's first message in a new
    # conversation) and returns it for the client to reuse on later turns.
    conversation_id: Optional[str] = None


class ChatResponse(BaseModel):
    reply: str
    conversation_id: str
    # Names of tools actually invoked to answer this turn — lets a client
    # (or a test) confirm the reply is grounded in a real lookup/log
    # action rather than the model just talking.
    tools_used: list[str] = []
