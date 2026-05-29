import base64
import logging
import os
from datetime import datetime, timezone
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..database import get_db
from ..models.meal_log import MealLog
from ..models.user import LifestyleBaseline, User
from ..schemas.nutrition import (
    AnalyzeImageRequest,
    AnalyzeImageResponse,
    FoodItemResponse,
    FoodSearchRequest,
    FoodSearchResponse,
    SaveMealRequest,
    SaveMealResponse,
    ManualLogRequest,
    NutritionDataResponse,
)
from ..services.gemini_service import GeminiVisionService
from ..services.meal_enrichment_service import MealEnrichmentService, RawFoodItem
from ..services.usda_service import USDAService
from .auth import get_current_user

logger = logging.getLogger(__name__)

router = APIRouter()

# ── Service singletons (initialised at import time) ───────────────────────────

gemini_service = GeminiVisionService(
    api_key=os.getenv("GOOGLE_API_KEY", "")
)
usda_service = USDAService(
    api_key=os.getenv("USDA_API_KEY", "DEMO_KEY")
)
meal_enrichment_service = MealEnrichmentService()


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
    ratio = request.portion_grams / 100.0

    raw = RawFoodItem(
        name=request.food_name,
        portion_grams=request.portion_grams,
        calories=request.calories_per_100g * ratio,
        carbs_g=request.carbs_per_100g * ratio,
        protein_g=request.protein_per_100g * ratio,
        fat_g=request.fat_per_100g * ratio,
        fiber_g=request.fiber_per_100g * ratio,
        confidence=1.0,
    )

    enriched = meal_enrichment_service.enrich([raw], confidence=1.0)
    meal_time = request.meal_time or datetime.now(timezone.utc)
    if meal_time.tzinfo is None:
        meal_time = meal_time.replace(tzinfo=timezone.utc)

    meal_log = MealLog(
        user_id=current_user.id,
        meal_time=meal_time,
        food_items=[
            {
                "name": request.food_name,
                "fdc_id": request.fdc_id,
                "portion_grams": request.portion_grams,
                "carbs_g": enriched.total_carbs_g,
                "gl": enriched.glycaemic_load,
            }
        ],
        recognition_confidence=None,
        total_calories=enriched.total_calories,
        total_carbs_g=enriched.total_carbs_g,
        total_protein_g=enriched.total_protein_g,
        total_fat_g=enriched.total_fat_g,
        total_fiber_g=enriched.total_fiber_g,
        glycaemic_load=enriched.glycaemic_load,
    )
    db.add(meal_log)
    await db.commit()
    await db.refresh(meal_log)

    logger.info(
        "Meal logged: user=%s food=%s portion=%dg calories=%.0f",
        current_user.id,
        request.food_name,
        request.portion_grams,
        enriched.total_calories,
    )

    return LogMealResponse(
        meal_id=str(meal_log.id),
        food_name=request.food_name,
        portion_grams=request.portion_grams,
        calories=enriched.total_calories,
        protein_g=enriched.total_protein_g,
        carbs_g=enriched.total_carbs_g,
        fat_g=enriched.total_fat_g,
        fiber_g=enriched.total_fiber_g,
        glycaemic_load=enriched.glycaemic_load,
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
    )
    db.add(meal_log)
    await db.commit()
    await db.refresh(meal_log)

    return {"success": True, "meal_log_id": str(meal_log.id)}
