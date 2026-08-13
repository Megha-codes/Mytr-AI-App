"""Tests for services/chat/conversation.py's run_conversation — the
tool-call loop that turns a Groq reply into either a real tool execution
or a final answer, and logs every turn.

Groq itself is faked (a scripted sequence of canned replies), not
mocked at the HTTP layer — groq_service.py's own HTTP handling isn't
what these tests are about. What they prove is: when the "model" asks
for a tool, the real tool executes against real data and its real
result is what gets fed back as the next message (not something the
fake just made up) — and when the "model" doesn't call a tool at all
(the insulin-deferral case), its text passes through untouched and no
tool ever runs.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone

import pytest
from sqlalchemy import select, text

import app.services.analytics.weekly as weekly_mod
from app.models.glucose_reading import GlucoseReadingModel
from app.models.health_metric import HealthMetric
from app.services.chat.conversation import run_conversation
from app.services.groq_service import GroqReply, ToolCall

from .conftest import build_sqlite_db, build_sqlite_timescale_db, make_user


class FakeGroqService:
    """Returns each of `replies` in sequence on successive .chat() calls —
    simulates the real multi-turn tool-calling protocol without a live
    API call. Records every `messages` list it was handed, so a test can
    assert the real tool result actually reached the "model" on the next
    call, not just that some result exists somewhere.
    """

    def __init__(self, replies: list[GroqReply]):
        self._replies = list(replies)
        self.calls: list[list[dict]] = []

    async def chat(self, messages, tools=None, temperature=0.2):
        self.calls.append(messages)
        return self._replies.pop(0)


@pytest.fixture
async def db_and_user():
    engine, session_factory = await build_sqlite_db()
    ts_engine, ts_session_factory = await build_sqlite_timescale_db()

    original_ts_factory = weekly_mod.TimescaleSessionLocal
    weekly_mod.TimescaleSessionLocal = ts_session_factory

    user = await make_user(session_factory, "chat@example.com")

    async with session_factory() as session:
        yield session, user, ts_session_factory

    weekly_mod.TimescaleSessionLocal = original_ts_factory
    await engine.dispose()
    await ts_engine.dispose()


async def _chat_log_rows(db, user_id):
    result = await db.execute(text("SELECT role, tool_name, content FROM chat_logs WHERE user_id = :uid ORDER BY created_at"), {"uid": str(user_id)})
    return list(result.mappings())


# ── "how was my glucose this week" -> real tool, real numbers ───────────

async def test_glucose_question_calls_the_real_tool_and_reports_real_numbers(db_and_user):
    db, user, ts_session_factory = db_and_user
    now = datetime.now(timezone.utc)
    async with ts_session_factory() as ts:
        ts.add(GlucoseReadingModel(id=uuid.uuid4(), user_id=user.id, value_mgdl=110, recorded_at=now, source="MANUAL"))
        ts.add(GlucoseReadingModel(id=uuid.uuid4(), user_id=user.id, value_mgdl=130, recorded_at=now, source="MANUAL"))
        await ts.commit()

    fake = FakeGroqService(replies=[
        GroqReply(content=None, tool_calls=[ToolCall(id="call_1", name="get_glucose_analytics", arguments={"days": 7})]),
        GroqReply(content="Your average glucose this week was 120 mg/dL."),
    ])

    result = await run_conversation(db, user, "how was my glucose this week", history=[], groq=fake)

    assert result["tools_used"] == ["get_glucose_analytics"]
    assert "120" in result["reply"]

    # The tool result Groq was handed back must be the *real* computed
    # average (120.0 = mean(110, 130)), not something the fake invented —
    # proving the loop actually executed the real tool in between the two
    # scripted replies rather than just concatenating them.
    second_call_messages = fake.calls[1]
    tool_messages = [m for m in second_call_messages if m.get("role") == "tool"]
    assert len(tool_messages) == 1
    assert '"average_mgdl": 120.0' in tool_messages[0]["content"]

    logs = await _chat_log_rows(db, user.id)
    roles = [row["role"] for row in logs]
    assert roles == ["user", "tool", "assistant"]
    assert logs[1]["tool_name"] == "get_glucose_analytics"


# ── "I ate 2 rotis" -> logs a real meal via the real nutrition pipeline ──

async def test_eating_a_meal_logs_it_via_the_real_nutrition_pipeline(db_and_user):
    from app.models.ifct_food import IFCTFood
    from app.models.meal_log import MealLog

    db, user, _ts = db_and_user
    db.add(IFCTFood(
        id=uuid.uuid4(), code="R001", name="roti",
        energy_kcal=120.0, available_carb_g=18.0, protein_g=3.0,
        fat_g=3.5, fibre_g=2.0, sugars_g=0.5,
    ))
    await db.commit()

    fake = FakeGroqService(replies=[
        GroqReply(content=None, tool_calls=[ToolCall(id="call_1", name="log_meal", arguments={"food_name": "roti", "portion_grams": 80})]),
        GroqReply(content="Logged 2 rotis (~80g) — about 96 kcal, 14.4g carbs."),
    ])

    result = await run_conversation(db, user, "I ate 2 rotis", history=[], groq=fake)

    assert result["tools_used"] == ["log_meal"]
    meals = (await db.execute(select(MealLog).where(MealLog.user_id == user.id))).scalars().all()
    assert len(meals) == 1
    assert meals[0].nutrition_source == "ifct"
    assert float(meals[0].total_carbs_g) == pytest.approx(18.0 * 0.8, abs=0.1)


# ── "log a glass of water" -> real water entry ───────────────────────────

async def test_log_water_actually_persists(db_and_user):
    db, user, _ts = db_and_user

    fake = FakeGroqService(replies=[
        GroqReply(content=None, tool_calls=[ToolCall(id="call_1", name="log_water", arguments={"amount_ml": 250})]),
        GroqReply(content="Logged 250ml of water."),
    ])

    result = await run_conversation(db, user, "log a glass of water", history=[], groq=fake)

    assert result["tools_used"] == ["log_water"]
    rows = (await db.execute(select(HealthMetric).where(HealthMetric.user_id == user.id, HealthMetric.metric == "water_ml"))).scalars().all()
    assert len(rows) == 1
    assert rows[0].value == 250.0


# ── "how much insulin should I take" -> safe deferral, no fabricated number ──

async def test_insulin_dose_question_gets_the_safe_deferral_not_a_number(db_and_user):
    db, user, _ts = db_and_user

    deferral_text = (
        "I can't calculate or suggest insulin doses — that has to come from "
        "your doctor or diabetes care team. I can show you your own logged "
        "glucose, meals, and other data if that would help."
    )
    fake = FakeGroqService(replies=[GroqReply(content=deferral_text, tool_calls=[])])

    result = await run_conversation(db, user, "how much insulin should I take", history=[], groq=fake)

    assert result["reply"] == deferral_text
    # No tool was called at all -- there is no data path that could have
    # produced a real dose number, and the deferral text itself contains
    # none either.
    assert result["tools_used"] == []
    assert not any(char.isdigit() for char in result["reply"])

    logs = await _chat_log_rows(db, user.id)
    assert [row["role"] for row in logs] == ["user", "assistant"]


async def test_system_prompt_forbids_dosing_regardless_of_framing():
    from app.services.chat.conversation import SYSTEM_PROMPT
    lowered = SYSTEM_PROMPT.lower()
    assert "insulin dose" in lowered or "dosing" in lowered
    assert "clinician" in lowered or "doctor" in lowered or "care team" in lowered


# ── iteration cap ─────────────────────────────────────────────────────────

async def test_hits_iteration_cap_gracefully_instead_of_looping_forever(db_and_user):
    db, user, _ts = db_and_user
    # Always wants another tool call, never settles — proves the loop has
    # a hard stop rather than hanging or erroring past it.
    endless = [
        GroqReply(content=None, tool_calls=[ToolCall(id=f"call_{i}", name="get_water_daily", arguments={})])
        for i in range(10)
    ]
    fake = FakeGroqService(replies=endless)

    result = await run_conversation(db, user, "keep asking", history=[], groq=fake)
    assert "wasn't able to finish" in result["reply"].lower()
