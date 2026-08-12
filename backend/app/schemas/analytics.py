"""GET /analytics/weekly response shapes (Phase-1 polish, part 2)."""

from __future__ import annotations

from datetime import date, datetime
from typing import Optional

from pydantic import BaseModel


class DateRange(BaseModel):
    start: date
    end: date


# ── Glucose ──────────────────────────────────────────────────────────────────

class TIRBreakdown(BaseModel):
    below: float
    target: float
    above: float


class DailyGlucosePoint(BaseModel):
    date: date
    avg_mgdl: Optional[float] = None
    min_mgdl: Optional[int] = None
    max_mgdl: Optional[int] = None
    reading_count: int = 0


class GlucoseWeeklySummary(BaseModel):
    has_data: bool
    average_mgdl: Optional[float] = None
    # ADA-standard Glucose Management Indicator — an eA1c-style estimate
    # derived from mean glucose, not a substitute for a lab A1c.
    gmi_percent: Optional[float] = None
    reading_count: int = 0
    tir: Optional[TIRBreakdown] = None
    daily: list[DailyGlucosePoint]


# ── Food -> glucose correlation (the lead feature) ─────────────────────────

class FoodGlucoseCorrelation(BaseModel):
    meal_id: str
    meal_time: datetime
    label: str
    carbs_g: Optional[float] = None
    baseline_mgdl: int
    post_meal_mgdl: int
    delta_mgdl: int
    window: str  # "1hr" | "2hr" — which post-meal reading this used
    outcome: Optional[str] = None  # meal_logs.glucose_outcome, when set


# ── Health trends ────────────────────────────────────────────────────────────

class DailyMetricPoint(BaseModel):
    date: date
    value: Optional[float] = None


class HealthMetricTrend(BaseModel):
    has_data: bool
    unit: str
    daily: list[DailyMetricPoint]


class HealthTrends(BaseModel):
    steps: HealthMetricTrend
    sleep_minutes: HealthMetricTrend
    hrv: HealthMetricTrend
    resting_heart_rate: HealthMetricTrend
    water_ml: HealthMetricTrend


# ── Nutrition trends ─────────────────────────────────────────────────────────

class DailyNutritionPoint(BaseModel):
    date: date
    calories: Optional[int] = None
    carbs_g: Optional[float] = None
    protein_g: Optional[float] = None
    fat_g: Optional[float] = None


class NutritionTrends(BaseModel):
    has_data: bool
    daily: list[DailyNutritionPoint]


# ── Insights ─────────────────────────────────────────────────────────────────

class Insight(BaseModel):
    text: str
    kind: str


# ── Top level ────────────────────────────────────────────────────────────────

class WeeklyAnalyticsResponse(BaseModel):
    range: DateRange
    glucose: GlucoseWeeklySummary
    food_glucose_correlations: list[FoodGlucoseCorrelation]
    health_trends: HealthTrends
    nutrition_trends: NutritionTrends
    insights: list[Insight]
