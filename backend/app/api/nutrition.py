import base64
import logging
from datetime import date as date_type, datetime, timezone
from typing import Optional
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..database import get_db
from ..models.meal_log import MealLog
from ..models.user import LifestyleBaseline, User
from ..schemas.nutrition import (
    AnalyzeImageRequest,
    AnalyzeImageResponse,
    DailyTotalsResponse,
    FoodItemResponse,
    FoodSearchRequest,
    FoodSearchResponse,
    MealListResponse,
    MealPatchRequest,
    MealSummaryResponse,
    SaveMealRequest,
    SaveMealResponse,
    ManualLogRequest,
    NutritionDataResponse,
)
from ..services.health.daily_rollup import local_date, local_date_bounds
from ..services.meal_enrichment_service import RawFoodItem
from ..services.nutrition.log_meal_service import log_meal_for_user
from ..services.nutrition.meals_today import (
    daily_nutrition_totals,
    list_meals_for_user,
    meal_label,
)
from ..services.shared_instances import gemini_service, meal_enrichment_service, usda_service
from .auth import get_current_user

# Sanity cap on GET /meals with no from/to bound — a demo/personal-use app
# has no legitimate reason to return tens of thousands of rows in one
# response, and this is cheaper than adding pagination for a gap-filling
# endpoint (architecture-v3.md §2.5 calls it a read-access gap, not a new
# feature with its own pagination contract).
MAX_MEALS_LISTED = 500

logger = logging.getLogger(__name__)

router = APIRouter()


# ── Helper: time since last bolus (used by inference callers downstream) ──────

async def get_time_since_last_bolus(user_id: UUID, db: AsyncSession) -> float:
    result = await db.execute(
        select(MealLog)
        .where(MealLog.user_id == user_id)
        .order_by(MealLog.meal_time.desc())
        .limit(1)
    )
    last_meal = result.scalar_one_or_none()
    if last_meal and last_meal.meal_time:
        meal_time = last_meal.meal_time
        if meal_time.tzinfo is None:
            meal_time = meal_time.replace(tzinfo=timezone.utc)
        hrs = (datetime.now(timezone.utc) - meal_time).total_seconds() / 3600
        return round(min(hrs, 24.0), 2)
    return 4.5


# ── POST /analyze-image ───────────────────────────────────────────────────────

@router.post(
    "/analyze-image",
    response_model=AnalyzeImageResponse,
    summary="Identify foods in an image using Gemini Vision",
)
async def analyze_image(
    request: AnalyzeImageRequest,
    current_user: User = Depends(get_current_user),
):
    if not gemini_service.api_key:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="GOOGLE_API_KEY is not configured",
        )

    try:
        image_bytes = base64.b64decode(request.base64_image)
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid base64 image data",
        )

    if len(image_bytes) > 10 * 1024 * 1024:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Image exceeds 10 MB limit",
        )

    try:
        food_items = await gemini_service.analyze_image(image_bytes)
    except ValueError as exc:
        logger.warning("Gemini parsing error: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=str(exc),
        )
    except Exception as exc:
        logger.error("Gemini API error: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Food recognition service temporarily unavailable",
        )

    return AnalyzeImageResponse(
        food_items=[
            FoodItemResponse(
                name=item.name,
                portion=item.portion,
                portion_grams=item.portion_grams,
            )
            for item in food_items
        ]
    )


# ── POST /search ──────────────────────────────────────────────────────────────

@router.post(
    "/search",
    response_model=FoodSearchResponse,
    summary="Look up nutrition data from USDA FoodData Central",
)
async def search_food(
    request: FoodSearchRequest,
    current_user: User = Depends(get_current_user),
):
    try:
        results = await usda_service.search(request.food_name)
    except Exception as exc:
        logger.error("USDA API error: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Nutrition database temporarily unavailable",
        )

    return FoodSearchResponse(
        results=[
            NutritionDataResponse(
                name=r.name,
                calories=round(r.calories, 1),
                protein_g=round(r.protein_g, 2),
                carbs_g=round(r.carbs_g, 2),
                fat_g=round(r.fat_g, 2),
                fiber_g=round(r.fiber_g, 2),
                fdc_id=r.fdc_id,
            )
            for r in results
        ]
    )


# ── POST /log-meal ────────────────────────────────────────────────────────────

@router.post(
    "/log-meal",
    response_model=SaveMealResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Calculate macros from portion size and save to meal_logs",
)
async def log_meal(
    request: SaveMealRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await log_meal_for_user(
        db, current_user, request.food_name, request.portion_grams,
        meal_time=request.meal_time,
        fdc_id=request.fdc_id,
        calories_per_100g=request.calories_per_100g,
        protein_per_100g=request.protein_per_100g,
        carbs_per_100g=request.carbs_per_100g,
        fat_per_100g=request.fat_per_100g,
        fiber_per_100g=request.fiber_per_100g,
    )

    logger.info(
        "Meal logged: user=%s food=%s portion=%dg calories=%.0f source=%s verified=%s",
        current_user.id,
        request.food_name,
        request.portion_grams,
        result.calories,
        result.source,
        result.verified,
    )

    return SaveMealResponse(
        meal_id=str(result.meal_log.id),
        food_name=request.food_name,
        portion_grams=request.portion_grams,
        calories=result.calories,
        protein_g=result.protein_g,
        carbs_g=result.carbs_g,
        fat_g=result.fat_g,
        fiber_g=result.fiber_g,
        glycaemic_load=result.glycaemic_load,
        nutrition_source=result.source,
        nutrition_verified=result.verified,
    )


# ── POST /log (backward-compat manual log) ───────────────────────────────────

@router.post(
    "/log",
    summary="Manually log a meal by providing nutrition totals directly",
)
async def log_meal_manual(
    request: ManualLogRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    meal_time = request.meal_time
    if meal_time.tzinfo is None:
        meal_time = meal_time.replace(tzinfo=timezone.utc)

    # Compute GL for manual entries (no per-item GI known)
    raw = RawFoodItem(
        name=request.name,
        portion_grams=0,
        calories=float(request.calories),
        carbs_g=request.carbs_g,
        protein_g=request.protein_g,
        fat_g=request.fat_g,
    )
    enriched = meal_enrichment_service.enrich([raw])

    meal_log = MealLog(
        user_id=current_user.id,
        meal_time=meal_time,
        food_items=[{"name": request.name, "carbs_g": request.carbs_g, "gl": enriched.glycaemic_load}],
        total_calories=request.calories,
        total_carbs_g=request.carbs_g,
        total_protein_g=request.protein_g,
        total_fat_g=request.fat_g,
        total_fiber_g=0,
        glycaemic_load=enriched.glycaemic_load,
        # User-entered totals, not resolved through the source router at
        # all — "manual" is its own source, not folded into ifct/usda/
        # gemini_estimate. Verified=True: it's the user's own number, not a
        # guess.
        nutrition_source="manual",
        nutrition_verified=True,
    )
    db.add(meal_log)
    await db.commit()
    await db.refresh(meal_log)

    return {"success": True, "meal_log_id": str(meal_log.id)}


# ── GET /meals, PATCH /meals/{id}, DELETE /meals/{id} (architecture-v3.md §2.5) ──
# meal_logs has always been write-only over the API before this — these three
# close that gap: list what's been logged, correct a mis-logged entry, undo
# one entirely.

def _meal_summary(meal: MealLog) -> MealSummaryResponse:
    return MealSummaryResponse(
        id=str(meal.id),
        meal_time=meal.meal_time,
        food_name=meal_label(meal.food_items),
        calories=meal.total_calories,
        carbs_g=float(meal.total_carbs_g) if meal.total_carbs_g is not None else None,
        protein_g=float(meal.total_protein_g) if meal.total_protein_g is not None else None,
        fat_g=float(meal.total_fat_g) if meal.total_fat_g is not None else None,
        fiber_g=float(meal.total_fiber_g) if meal.total_fiber_g is not None else None,
        glycaemic_load=float(meal.glycaemic_load) if meal.glycaemic_load is not None else None,
        nutrition_source=meal.nutrition_source,
        nutrition_verified=meal.nutrition_verified,
    )


async def _load_owned_meal(db: AsyncSession, meal_id: UUID, user_id) -> MealLog:
    result = await db.execute(
        select(MealLog).where(MealLog.id == meal_id, MealLog.user_id == user_id)
    )
    meal = result.scalar_one_or_none()
    if meal is None:
        # Deliberately the same 404 whether the meal doesn't exist at all or
        # belongs to someone else — confirming "that id exists, just not
        # yours" would leak other users' meal ids.
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Meal not found")
    return meal


@router.get("/meals", response_model=MealListResponse)
async def list_meals(
    from_: Optional[datetime] = Query(None, alias="from"),
    to: Optional[datetime] = Query(None),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    meals = await list_meals_for_user(db, current_user.id, from_, to, MAX_MEALS_LISTED)
    return MealListResponse(meals=[_meal_summary(m) for m in meals])


@router.patch("/meals/{meal_id}", response_model=MealSummaryResponse)
async def patch_meal(
    meal_id: UUID,
    request: MealPatchRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    meal = await _load_owned_meal(db, meal_id, current_user.id)

    if request.food_name is not None:
        food_items = list(meal.food_items or [{}])
        food_items[0] = {**food_items[0], "name": request.food_name}
        meal.food_items = food_items  # reassign (not in-place mutate) so the ORM sees the change
    if request.meal_time is not None:
        meal_time = request.meal_time
        if meal_time.tzinfo is None:
            meal_time = meal_time.replace(tzinfo=timezone.utc)
        meal.meal_time = meal_time
    if request.calories is not None:
        meal.total_calories = round(request.calories)
    if request.carbs_g is not None:
        meal.total_carbs_g = request.carbs_g
    if request.protein_g is not None:
        meal.total_protein_g = request.protein_g
    if request.fat_g is not None:
        meal.total_fat_g = request.fat_g
    if request.fiber_g is not None:
        meal.total_fiber_g = request.fiber_g

    if request.carbs_g is not None or request.food_name is not None:
        # Carbs and/or the GI lookup key (food name) changed — glycaemic
        # load is derived from both, so it goes stale otherwise.
        raw = RawFoodItem(
            name=meal_label(meal.food_items),
            portion_grams=0,
            calories=float(meal.total_calories or 0),
            carbs_g=float(meal.total_carbs_g or 0),
            protein_g=float(meal.total_protein_g or 0),
            fat_g=float(meal.total_fat_g or 0),
            fiber_g=float(meal.total_fiber_g or 0),
        )
        enriched = meal_enrichment_service.enrich([raw])
        meal.glycaemic_load = enriched.glycaemic_load

    meal.user_corrected = True
    await db.commit()
    await db.refresh(meal)
    return _meal_summary(meal)


@router.delete("/meals/{meal_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_meal(
    meal_id: UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    meal = await _load_owned_meal(db, meal_id, current_user.id)
    await db.delete(meal)
    await db.commit()


# ── GET /daily (architecture-v3.md §2.5) ──────────────────────────────────────
# User-JWT twin of GET /device/calories/daily (app/api/device_data.py) —
# same aggregation (services/nutrition/meals_today.py), same response shape,
# different auth.

@router.get("/daily", response_model=DailyTotalsResponse)
async def get_nutrition_daily(
    date: Optional[date_type] = None,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    target_date = date or local_date(datetime.now(timezone.utc), current_user.timezone)
    range_start, range_end = local_date_bounds(target_date, current_user.timezone)
    return await daily_nutrition_totals(db, current_user.id, range_start, range_end, target_date)
