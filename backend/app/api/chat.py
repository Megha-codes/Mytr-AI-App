"""POST /chat: the analytics chatbot (Groq tool-calling). The actual
orchestration lives in services/chat/conversation.py; the tools it can
call (all thin wrappers over real, already-tested backend functions —
never model-fabricated data) live in services/chat/tools.py.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from ..database import get_db
from ..models.user import User
from ..schemas.chat import ChatRequest, ChatResponse
from ..services.chat.conversation import run_conversation
from .auth import get_current_user

router = APIRouter()


@router.post("/chat", response_model=ChatResponse)
async def chat(
    request: ChatRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await run_conversation(
        db,
        current_user,
        request.message,
        [{"role": m.role, "content": m.content} for m in request.history],
        conversation_id=request.conversation_id,
    )
    return ChatResponse(**result)
