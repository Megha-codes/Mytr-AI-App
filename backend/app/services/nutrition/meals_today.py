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
from datetime import datetime

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession


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
