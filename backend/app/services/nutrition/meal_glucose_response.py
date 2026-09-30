"""Meal -> glucose response for the meal-detail screen: the real CGM
readings around a logged meal, plus the pre-computed baseline/post-meal/
outcome fields the post_meal Celery task already writes onto MealLog.

Deliberately its own module rather than folded into meals_today.py — it
reads TimescaleDB (glucose_readings) in addition to the main DB (meal_logs,
insulin_profiles), matching the same two-database pattern
services/analytics/weekly.py already uses for its food-glucose correlation
feature, not a new pattern.
"""

from __future__ import annotations

from datetime import timedelta

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ...models.glucose_reading import GlucoseReadingModel
from ...models.meal_log import MealLog
from ...models.user import InsulinProfile
from ...timescale_database import TimescaleSessionLocal
from ...schemas.nutrition import GlucoseResponsePoint, MealGlucoseResponse

# How far before/after the meal to pull raw readings for the graph. Before:
# just enough to show a short pre-meal baseline segment for context (the
# reference design shows a few readings leading into the meal marker).
# After: long enough to cover the 2hr post-meal window the outcome
# classification itself uses, with a little slack.
_PRE_MEAL_WINDOW = timedelta(minutes=30)
_POST_MEAL_WINDOW = timedelta(hours=3)


async def get_meal_glucose_response(db: AsyncSession, meal: MealLog) -> MealGlucoseResponse:
    async with TimescaleSessionLocal() as ts:
        result = await ts.execute(
            select(GlucoseReadingModel)
            .where(
                GlucoseReadingModel.user_id == meal.user_id,
                GlucoseReadingModel.recorded_at >= meal.meal_time - _PRE_MEAL_WINDOW,
                GlucoseReadingModel.recorded_at <= meal.meal_time + _POST_MEAL_WINDOW,
            )
            .order_by(GlucoseReadingModel.recorded_at.asc())
        )
        readings = result.scalars().all()

    if not readings:
        # No CGM connected, or nothing landed in this window yet (meal was
        # logged moments ago) — the caller renders a clean empty state,
        # never a fabricated graph.
        return MealGlucoseResponse(meal_id=str(meal.id), has_data=False)

    baseline = None
    for r in readings:
        if r.recorded_at <= meal.meal_time:
            baseline = r.value_mgdl  # keep advancing — want the closest one *before* the meal
        else:
            break
    if baseline is None:
        # Every reading we found is after meal_time (logged right as the
        # first post-meal reading arrived) — first available point is the
        # closest honest stand-in rather than inventing one.
        baseline = readings[0].value_mgdl

    post_meal_mgdl = meal.post_meal_glucose_2hr
    window = "2hr"
    if post_meal_mgdl is None:
        post_meal_mgdl = meal.post_meal_glucose_1hr
        window = "1hr"
    if post_meal_mgdl is None:
        window = None

    target_result = await db.execute(
        select(InsulinProfile).where(InsulinProfile.user_id == meal.user_id)
    )
    profile = target_result.scalar_one_or_none()

    return MealGlucoseResponse(
        meal_id=str(meal.id),
        has_data=True,
        target_min=profile.target_glucose_min if profile else None,
        target_max=profile.target_glucose_max if profile else None,
        baseline_mgdl=baseline,
        post_meal_mgdl=post_meal_mgdl,
        post_meal_window=window,
        delta_mgdl=(post_meal_mgdl - baseline) if post_meal_mgdl is not None else None,
        outcome=meal.glucose_outcome,
        readings=[
            GlucoseResponsePoint(recorded_at=r.recorded_at, value_mgdl=r.value_mgdl)
            for r in readings
        ],
    )
