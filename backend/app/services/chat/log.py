"""Audit logging for every chatbot turn (migrations/016_chat_logs.sql).

Raw SQL, not an ORM model — tool_arguments/tool_result are JSONB, which
(like meal_logs.food_items) has no sqlite compiler at all; see
services/nutrition/meals_today.py's docstring for the same rationale.
This table is write-only from the app's perspective (an audit trail,
never read back — the client sends its own conversation history each
request), so a full ORM model would buy nothing a documented raw INSERT
doesn't already give.
"""

from __future__ import annotations

import json
import uuid
from datetime import datetime, timezone
from typing import Any, Optional

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession


async def log_turn(
    db: AsyncSession,
    user_id,
    conversation_id,
    role: str,
    *,
    content: Optional[str] = None,
    tool_name: Optional[str] = None,
    tool_arguments: Optional[dict[str, Any]] = None,
    tool_result: Optional[dict[str, Any]] = None,
) -> None:
    """role is 'user' | 'assistant' | 'tool'. Commits immediately — this
    is a fire-and-forget audit write, not part of a larger transaction
    the caller might roll back."""
    await db.execute(
        text("""
            INSERT INTO chat_logs
                (id, user_id, conversation_id, role, content, tool_name,
                 tool_arguments, tool_result, created_at)
            VALUES
                (:id, :user_id, :conversation_id, :role, :content, :tool_name,
                 :tool_arguments, :tool_result, :created_at)
        """),
        {
            "id": str(uuid.uuid4()),
            "user_id": str(user_id),
            "conversation_id": str(conversation_id),
            "role": role,
            "content": content,
            "tool_name": tool_name,
            "tool_arguments": json.dumps(tool_arguments) if tool_arguments is not None else None,
            "tool_result": json.dumps(tool_result) if tool_result is not None else None,
            "created_at": datetime.now(timezone.utc),
        },
    )
    await db.commit()
