"""Nutrition source resolution for a food name: IFCT first, USDA fallback,
Gemini estimate as a last resort. Used when a meal is logged from Gemini's
dish recognition (analyze_image) rather than an explicit USDA search pick —
see app/api/nutrition.py's /log-meal.

Priority, and why:
  1. IFCT — Indian Food Composition Tables. Best match for Indian
     ingredients/dishes specifically, and the dataset this app's users are
     most likely to actually eat from day to day.
  2. USDA FoodData Central — broad Western/international coverage, existing
     integration (services/usda_service.py), used for anything IFCT doesn't
     have.
  3. Gemini's own estimate — no database hit anywhere. A guess, not a
     lookup; always stamped unverified.

All three return values are per-100g, matching the pre-existing USDA
convention (nutrition.py's `*_per_100g` fields) — portion scaling is the
caller's job (ratio = portion_grams / 100), not this module's.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Literal, Optional

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from ...models.ifct_food import IFCTFood
from ..gemini_service import GeminiVisionService
from ..usda_service import USDAService

NutritionSource = Literal["ifct", "usda", "gemini_estimate"]

# Trigram similarity threshold (Postgres only) — permissive enough for short
# or partially-misspelled queries ("dosa" vs "Dosa, plain") while still
# excluding unrelated foods. Tuned empirically, not derived from anything.
_TRIGRAM_THRESHOLD = 0.2


@dataclass
class ResolvedNutrition:
    name: str
    source: NutritionSource
    verified: bool
    calories_per_100g: float
    protein_per_100g: float
    carbs_per_100g: float
    fat_per_100g: float
    fiber_per_100g: float
    ifct_code: Optional[str] = None
    fdc_id: Optional[str] = None


async def search_ifct_foods(db: AsyncSession, query: str, limit: int = 5) -> list[IFCTFood]:
    """Fuzzy name search over ifct_foods. Postgres uses pg_trgm similarity
    (backed by the GIN index in migrations/014_ifct_foods.sql); sqlite (the
    test harness — see tests/conftest.py) has no pg_trgm, so it falls back
    to a plain case-insensitive substring match. Correctness is the same on
    both; only ranking quality on partial/misspelled queries differs.
    """
    query = query.strip()
    if not query:
        return []

    # Exact match (case-insensitive) always wins outright, on either
    # dialect — no reason to rank a fuzzy match above e.g. "banana" typed
    # exactly against an IFCT row literally named "Banana, ripe, robusta"...
    # well, that one wouldn't be exact, but a genuinely exact name should
    # never lose to a shorter/higher-similarity distractor.
    exact = await db.execute(select(IFCTFood).where(func.lower(IFCTFood.name) == query.lower()))
    exact_hit = exact.scalar_one_or_none()
    if exact_hit is not None:
        return [exact_hit]

    if db.bind.dialect.name == "postgresql":
        similarity = func.similarity(IFCTFood.name, query)
        stmt = (
            select(IFCTFood)
            .where(similarity > _TRIGRAM_THRESHOLD)
            .order_by(similarity.desc())
            .limit(limit)
        )
    else:
        stmt = (
            select(IFCTFood)
            .where(IFCTFood.name.ilike(f"%{query}%"))
            .order_by(func.length(IFCTFood.name))
            .limit(limit)
        )

    result = await db.execute(stmt)
    return list(result.scalars().all())


async def resolve_nutrition(
    db: AsyncSession,
    food_name: str,
    usda_service: USDAService,
    gemini_service: Optional[GeminiVisionService] = None,
) -> ResolvedNutrition:
    """IFCT -> USDA -> Gemini estimate, in that order. Never raises — a
    lookup failure at any tier (network error, no API key, no match) just
    falls through to the next one, since the caller (meal logging) should
    not fail outright just because nutrition enrichment couldn't find a
    perfect source."""
    ifct_hits = await search_ifct_foods(db, food_name, limit=1)
    if ifct_hits:
        food = ifct_hits[0]
        return ResolvedNutrition(
            name=food.name,
            source="ifct",
            verified=True,
            calories_per_100g=float(food.energy_kcal),
            protein_per_100g=float(food.protein_g),
            carbs_per_100g=float(food.available_carb_g),
            fat_per_100g=float(food.fat_g),
            fiber_per_100g=float(food.fibre_g),
            ifct_code=food.code,
        )

    try:
        usda_hits = await usda_service.search(food_name, page_size=1)
    except Exception:
        usda_hits = []
    if usda_hits:
        food = usda_hits[0]
        return ResolvedNutrition(
            name=food.name,
            source="usda",
            verified=True,
            calories_per_100g=food.calories,
            protein_per_100g=food.protein_g,
            carbs_per_100g=food.carbs_g,
            fat_per_100g=food.fat_g,
            fiber_per_100g=food.fiber_g,
            fdc_id=food.fdc_id,
        )

    estimate = None
    if gemini_service is not None:
        estimate = await gemini_service.estimate_nutrition(food_name)
    if estimate is not None:
        return ResolvedNutrition(
            name=food_name,
            source="gemini_estimate",
            verified=False,
            calories_per_100g=estimate.calories_per_100g,
            protein_per_100g=estimate.protein_per_100g,
            carbs_per_100g=estimate.carbs_per_100g,
            fat_per_100g=estimate.fat_per_100g,
            fiber_per_100g=estimate.fiber_per_100g,
        )

    # Nothing anywhere matched, or the Gemini estimate itself failed (no
    # API key, network error, unparseable response) — still tagged
    # gemini_estimate/unverified rather than raising, so a meal can be
    # logged (at zero macros, correctable later) instead of the whole
    # request failing because no nutrition source had an answer.
    return ResolvedNutrition(
        name=food_name,
        source="gemini_estimate",
        verified=False,
        calories_per_100g=0.0,
        protein_per_100g=0.0,
        carbs_per_100g=0.0,
        fat_per_100g=0.0,
        fiber_per_100g=0.0,
    )
