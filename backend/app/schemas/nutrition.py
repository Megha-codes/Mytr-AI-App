from datetime import datetime
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
