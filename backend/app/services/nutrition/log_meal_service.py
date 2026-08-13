"""Shared meal-logging logic: resolve nutrition (client-supplied per-100g
values if given, otherwise IFCT -> USDA -> Gemini estimate via
source_router.resolve_nutrition), scale by portion, persist a MealLog
row. Used by both POST /nutrition/log-meal and the analytics chatbot's
log_meal tool (services/chat/tools.py) -- one real implementation of
"log a meal", not a second one reimplemented for the chat path.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Optional

from sqlalchemy.ext.asyncio import AsyncSession

from ...models.meal_log import MealLog
from ...models.user import User
from ..meal_enrichment_service import RawFoodItem
from ..shared_instances import gemini_service, meal_enrichment_service, usda_service
from .source_router import resolve_nutrition


@dataclass
class LoggedMealResult:
    meal_log: MealLog
    source: str
    verified: bool
    calories: float
    protein_g: float
    carbs_g: float
    fat_g: float
    fiber_g: float
    glycaemic_load: float


async def log_meal_for_user(
    db: AsyncSession,
    user: User,
    food_name: str,
    portion_grams: int,
    *,
    meal_time: Optional[datetime] = None,
    fdc_id: Optional[str] = None,
    calories_per_100g: Optional[float] = None,
    protein_per_100g: Optional[float] = None,
    carbs_per_100g: Optional[float] = None,
    fat_per_100g: Optional[float] = None,
    fiber_per_100g: Optional[float] = None,
) -> LoggedMealResult:
    ratio = portion_grams / 100.0

    if calories_per_100g is not None:
        # Caller already resolved nutrition itself (the existing client-
        # searched-USDA-then-picked-a-result flow) — honor it as given.
        source = "usda"
        verified = True
        c_per_100g = calories_per_100g
        p_per_100g = protein_per_100g or 0.0
        cb_per_100g = carbs_per_100g or 0.0
        f_per_100g = fat_per_100g or 0.0
        fi_per_100g = fiber_per_100g or 0.0
    else:
        # No explicit macros: resolve server-side, IFCT -> USDA -> Gemini
        # estimate. This is the path both Gemini image-recognition and the
        # chatbot's log_meal tool take — a food name and a portion, nothing
        # else.
        resolved = await resolve_nutrition(db, food_name, usda_service, gemini_service)
        source = resolved.source
        verified = resolved.verified
        c_per_100g = resolved.calories_per_100g
        p_per_100g = resolved.protein_per_100g
        cb_per_100g = resolved.carbs_per_100g
        f_per_100g = resolved.fat_per_100g
        fi_per_100g = resolved.fiber_per_100g

    raw = RawFoodItem(
        name=food_name,
        portion_grams=portion_grams,
        calories=c_per_100g * ratio,
        carbs_g=cb_per_100g * ratio,
        protein_g=p_per_100g * ratio,
        fat_g=f_per_100g * ratio,
        fiber_g=fi_per_100g * ratio,
        confidence=1.0,
    )
    enriched = meal_enrichment_service.enrich([raw], confidence=1.0)

    resolved_meal_time = meal_time or datetime.now(timezone.utc)
    if resolved_meal_time.tzinfo is None:
        resolved_meal_time = resolved_meal_time.replace(tzinfo=timezone.utc)

    meal_log = MealLog(
        user_id=user.id,
        meal_time=resolved_meal_time,
        food_items=[{
            "name": food_name,
            "fdc_id": fdc_id,
            "portion_grams": portion_grams,
            "carbs_g": enriched.total_carbs_g,
            "gl": enriched.glycaemic_load,
        }],
        recognition_confidence=None,
        total_calories=enriched.total_calories,
        total_carbs_g=enriched.total_carbs_g,
        total_protein_g=enriched.total_protein_g,
        total_fat_g=enriched.total_fat_g,
        total_fiber_g=enriched.total_fiber_g,
        glycaemic_load=enriched.glycaemic_load,
        nutrition_source=source,
        nutrition_verified=verified,
    )
    db.add(meal_log)
    await db.commit()
    await db.refresh(meal_log)

    return LoggedMealResult(
        meal_log=meal_log,
        source=source,
        verified=verified,
        calories=enriched.total_calories,
        protein_g=enriched.total_protein_g,
        carbs_g=enriched.total_carbs_g,
        fat_g=enriched.total_fat_g,
        fiber_g=enriched.total_fiber_g,
        glycaemic_load=enriched.glycaemic_load,
    )
