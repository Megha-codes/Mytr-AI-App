from datetime import date, datetime
from typing import Optional
from uuid import UUID

from pydantic import BaseModel, Field


# ── Analyze Image ─────────────────────────────────────────────────────────────

class AnalyzeImageRequest(BaseModel):
    base64_image: str = Field(..., description="Base64-encoded JPEG image")


class FoodItemResponse(BaseModel):
    name: str
    portion: str
    portion_grams: int


class AnalyzeImageResponse(BaseModel):
    food_items: list[FoodItemResponse]


# ── USDA Search ───────────────────────────────────────────────────────────────

class FoodSearchRequest(BaseModel):
    food_name: str = Field(..., min_length=1, max_length=200)


class NutritionDataResponse(BaseModel):
    name: str
    calories: float
    protein_g: float
    carbs_g: float
    fat_g: float
    fiber_g: float
    fdc_id: str


class FoodSearchResponse(BaseModel):
    results: list[NutritionDataResponse]


# ── Log Meal ──────────────────────────────────────────────────────────────────

class SaveMealRequest(BaseModel):
    food_name: str
    portion_grams: int = Field(..., gt=0, le=5000)
    fdc_id: Optional[str] = None
    meal_time: Optional[datetime] = None
    # Nutrition per 100g. Omit all five to have the backend resolve them
    # itself (IFCT -> USDA -> Gemini estimate, services/nutrition/
    # source_router.py) from food_name; supply them, as before, when the
    # client already picked a specific result via /search.
    calories_per_100g: Optional[float] = Field(None, ge=0)
    protein_per_100g: Optional[float] = Field(None, ge=0)
    carbs_per_100g: Optional[float] = Field(None, ge=0)
    fat_per_100g: Optional[float] = Field(None, ge=0)
    fiber_per_100g: Optional[float] = Field(None, ge=0)


class SaveMealResponse(BaseModel):
    meal_id: str
    food_name: str
    portion_grams: int
    calories: float
    protein_g: float
    carbs_g: float
    fat_g: float
    fiber_g: float
    glycaemic_load: float
    nutrition_source: str
    nutrition_verified: bool


# ── Manual Log (backward compat) ──────────────────────────────────────────────

class ManualLogRequest(BaseModel):
    name: str
    calories: int
    carbs_g: float
    protein_g: float
    fat_g: float
    meal_time: datetime


# ── Meals list / edit / delete / daily totals (architecture-v3.md §2.5) ───────

class MealSummaryResponse(BaseModel):
    id: str
    meal_time: datetime
    food_name: str
    portion_grams: Optional[int] = None
    calories: Optional[int] = None
    carbs_g: Optional[float] = None
    protein_g: Optional[float] = None
    fat_g: Optional[float] = None
    fiber_g: Optional[float] = None
    glycaemic_load: Optional[float] = None
    nutrition_source: Optional[str] = None
    nutrition_verified: Optional[bool] = None


class MealListResponse(BaseModel):
    meals: list[MealSummaryResponse]


class MealPatchRequest(BaseModel):
    """All fields optional — only what's supplied is changed. Correcting a
    mis-logged meal, not resubmitting the whole thing.

    food_name/portion_grams re-resolve nutrition server-side through the
    same IFCT -> USDA -> Gemini chain every other logging path uses
    (source_router.resolve_nutrition) — the meal-detail screen's "edit
    food & quantity" always goes through this pair, never the direct
    numeric overrides below. calories/carbs_g/etc. stay as a separate,
    lower-priority path only for a caller that already knows the exact
    numbers it wants (kept for backward compatibility, unused by the new
    edit flow) — supplying both is allowed; the explicit numeric value
    wins over what re-resolution would have computed for that one field.
    """

    food_name: Optional[str] = None
    portion_grams: Optional[int] = Field(None, gt=0, le=5000)
    meal_time: Optional[datetime] = None
    calories: Optional[float] = Field(None, ge=0)
    carbs_g: Optional[float] = Field(None, ge=0)
    protein_g: Optional[float] = Field(None, ge=0)
    fat_g: Optional[float] = Field(None, ge=0)
    fiber_g: Optional[float] = Field(None, ge=0)


# ── Meal -> glucose response (meal-detail screen) ─────────────────────────────

class GlucoseResponsePoint(BaseModel):
    recorded_at: datetime
    value_mgdl: int


class MealGlucoseResponse(BaseModel):
    meal_id: str
    # False when the user has no CGM connected or nothing was recorded in
    # the window around this meal — drives the frontend's clean empty
    # state. Never a fabricated graph.
    has_data: bool
    target_min: Optional[int] = None
    target_max: Optional[int] = None
    baseline_mgdl: Optional[int] = None
    post_meal_mgdl: Optional[int] = None
    post_meal_window: Optional[str] = None  # "1hr" | "2hr" — which one was available
    delta_mgdl: Optional[int] = None
    # meal_logs.glucose_outcome, set by the post-meal Celery task:
    # "HYPO" | "LOW" | "IN_RANGE" | "HIGH" | "HYPER" | None (not classified yet)
    outcome: Optional[str] = None
    readings: list[GlucoseResponsePoint] = []


class DailyMealResponse(BaseModel):
    id: str
    meal_time: datetime
    label: str
    calories: Optional[int] = None
    carbs_g: Optional[float] = None


class DailyTotalsResponse(BaseModel):
    date: date
    consumed_kcal: int
    carbs_g: float
    protein_g: float
    fat_g: float
    fiber_g: float
    meals: list[DailyMealResponse]
