"""Shared water-logging logic (Phase-1 polish, part 3): insert one
water_ml health_metrics row, read today's total against the daily goal.
Used by both /water/* (app/api/water.py) and the analytics chatbot's
log_water/get_water_daily tools (services/chat/tools.py) -- one real
implementation, not reimplemented for the chat path.
"""

from __future__ import annotations

from datetime import date as date_type, datetime, timezone
from typing import Optional

from sqlalchemy.ext.asyncio import AsyncSession

from ...models.health_metric import HealthMetric
from ...models.user import User
from ...schemas.water import WaterDailyResponse
from ..health.daily_rollup import compute_daily_rollup, local_date

# A round, commonly-cited daily target (~8 glasses) -- same status as
# dashboard.py's steps_goal/calorie_target: a fixed default, not a
# per-user setting yet. Shared by every water surface (app route, device
# twin, chatbot) so none of them can disagree about what "the goal" is.
DEFAULT_WATER_GOAL_ML = 2000


async def log_water_entry(db: AsyncSession, user: User, amount_ml: int) -> int:
    """Inserts one water_ml health_metrics row and returns the day's new
    running total."""
    now = datetime.now(timezone.utc)
    db.add(HealthMetric(
        user_id=user.id,
        metric="water_ml",
        value=float(amount_ml),
        unit="ml",
        started_at=now,
        ended_at=now,
        source="MANUAL",
    ))
    await db.commit()

    today = local_date(now, user.timezone)
    rollup = await compute_daily_rollup(db, user.id, today, user.timezone)
    return int(rollup.get("water_ml") or amount_ml)


async def get_water_summary(
    db: AsyncSession, user: User, target_date: Optional[date_type] = None,
) -> WaterDailyResponse:
    target_date = target_date or local_date(datetime.now(timezone.utc), user.timezone)
    rollup = await compute_daily_rollup(db, user.id, target_date, user.timezone)
    total = rollup.get("water_ml")

    return WaterDailyResponse(
        date=target_date,
        total_ml=int(total) if total is not None else None,
        goal_ml=DEFAULT_WATER_GOAL_ML,
    )
