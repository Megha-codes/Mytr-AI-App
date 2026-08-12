"""Reads today's meal_logs for the device snapshot / calories endpoints.

Raw SQL, not the `MealLog` ORM model: `food_items` is Postgres-only JSONB,
which has no sqlite compiler at all (unlike the UUID/JSON types elsewhere
that at least degrade gracefully) — going through the ORM here would make
this feature untestable against the sqlite harness. Raw SQL sidesteps
SQLAlchemy's type system entirely, which also matches production: asyncpg
returns JSON/JSONB scalar columns from a plain `text()` query as JSON text
(no auto-decode without a registered type codec, and none is registered
here), so `food_items` needs a manual `json.loads()` on both dialects —
this is the same code path, not a test-only workaround.
"""

from __future__ import annotations

import json
from datetime import date as date_type, datetime
from typing import Optional

from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession

from ...models.meal_log import MealLog
from ...schemas.nutrition import DailyMealResponse, DailyTotalsResponse


async def load_todays_meals(db: AsyncSession, user_id, start: datetime, end: datetime) -> list[dict]:
    result = await db.execute(
        text("""
            SELECT id, meal_time, food_items, total_calories, total_carbs_g,
                   total_protein_g, total_fat_g, total_fiber_g
            FROM meal_logs
            WHERE user_id = :user_id AND meal_time >= :start AND meal_time < :end
            ORDER BY meal_time ASC
        """),
        {"user_id": str(user_id), "start": start, "end": end},
    )
    meals = []
    for row in result.mappings():
        food_items = row["food_items"]
        if isinstance(food_items, str):
            food_items = json.loads(food_items)
        meal_time = row["meal_time"]
        if isinstance(meal_time, str):
            meal_time = datetime.fromisoformat(meal_time)
        meals.append({
            "id": str(row["id"]),
            "meal_time": meal_time,
            "food_items": food_items or [],
            "total_calories": row["total_calories"],
            "total_carbs_g": row["total_carbs_g"],
            "total_protein_g": row["total_protein_g"],
            "total_fat_g": row["total_fat_g"],
            "total_fiber_g": row["total_fiber_g"],
        })
    return meals


def meal_label(food_items: list) -> str:
    if food_items and isinstance(food_items[0], dict) and food_items[0].get("name"):
        return food_items[0]["name"]
    return "Meal"


async def list_meals_for_user(
    db: AsyncSession, user_id, from_: Optional[datetime] = None,
    to: Optional[datetime] = None, limit: int = 500,
) -> list[MealLog]:
    """Shared by GET /nutrition/meals and the analytics chatbot's
    get_meals tool. Unlike load_todays_meals above, this goes through the
    MealLog ORM directly rather than raw SQL — proven safe against the
    sqlite test harness (tests/conftest.py's meal_logs mirror table is
    hand-written specifically to support ORM reads/writes, not just raw
    SQL), and GET /nutrition/meals has used the ORM here since it was
    added, with its own passing tests. load_todays_meals predates that and
    was never revisited; the two aren't inconsistent so much as written at
    different times.
    """
    stmt = select(MealLog).where(MealLog.user_id == user_id)
    if from_ is not None:
        stmt = stmt.where(MealLog.meal_time >= from_)
    if to is not None:
        stmt = stmt.where(MealLog.meal_time < to)
    stmt = stmt.order_by(MealLog.meal_time.desc()).limit(limit)

    result = await db.execute(stmt)
    return list(result.scalars().all())


async def daily_nutrition_totals(
    db: AsyncSession, user_id, start: datetime, end: datetime, target_date: date_type,
) -> DailyTotalsResponse:
    """Shared by GET /nutrition/daily and the chatbot's get_daily_nutrition
    tool. [start, end) is the caller-computed local-day window (see
    services/health/daily_rollup.py's local_date_bounds)."""
    meals = await load_todays_meals(db, user_id, start, end)

    return DailyTotalsResponse(
        date=target_date,
        consumed_kcal=sum(m["total_calories"] or 0 for m in meals),
        carbs_g=float(sum(m["total_carbs_g"] or 0 for m in meals)),
        protein_g=float(sum(m["total_protein_g"] or 0 for m in meals)),
        fat_g=float(sum(m["total_fat_g"] or 0 for m in meals)),
        fiber_g=float(sum(m["total_fiber_g"] or 0 for m in meals)),
        meals=[
            DailyMealResponse(
                id=m["id"],
                meal_time=m["meal_time"],
                label=meal_label(m["food_items"]),
                calories=m["total_calories"],
                carbs_g=float(m["total_carbs_g"]) if m["total_carbs_g"] is not None else None,
            )
            for m in meals
        ],
    )
