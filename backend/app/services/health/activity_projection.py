"""activity_logs as a projection recomputed from health_metrics
(architecture-v3.md §4.2), not an independently-written source.

`POST /activity/sync` (backend/app/api/activity.py) keeps upserting
activity_logs directly for older app builds — untouched, per §4.2 step 4:
"retire POST /activity/sync only once client telemetry shows no old builds
calling it." This module is the *new* write path: POST /health/samples
calls `recompute_activity_log_projection` for every date a batch touches,
so activity_logs reflects whatever health_metrics now has for that day
regardless of which endpoint last wrote to it.
"""

from __future__ import annotations

from datetime import date as date_type

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from .daily_rollup import compute_daily_rollup


async def recompute_activity_log_projection(
    db: AsyncSession, user_id, target_date: date_type, user_timezone: str = "UTC"
) -> None:
    rollup = await compute_daily_rollup(db, user_id, target_date, user_timezone)
    steps = int(rollup.get("steps") or 0)
    calories = int(rollup.get("active_energy_kcal") or 0)
    heart_rate = int(rollup.get("heart_rate") or 0)

    # Same upsert shape as POST /activity/sync — one row per user per day,
    # last write wins, just fed from health_metrics instead of a direct
    # client payload.
    await db.execute(
        text("""
            INSERT INTO activity_logs (user_id, date, steps_today, calories_burned, heart_rate, synced_at)
            VALUES (:user_id, :date, :steps, :calories, :hr, now())
            ON CONFLICT (user_id, date)
            DO UPDATE SET
                steps_today     = EXCLUDED.steps_today,
                calories_burned = EXCLUDED.calories_burned,
                heart_rate      = EXCLUDED.heart_rate,
                synced_at       = now()
        """),
        {
            # `.hex` (no dashes), not `str()`: on sqlite (tests), the ORM's
            # UUID bind processor stores as `.hex` — raw SQL must match that
            # exact text or an ORM `WHERE user_id == ...` read never finds
            # this row. Postgres's native uuid type is agnostic to either
            # format, so this is a no-op change in production.
            "user_id": user_id.hex,
            "date": target_date,
            "steps": steps,
            "calories": calories,
            "hr": heart_rate,
        },
    )
