"""Weekly analytics (Phase-1 polish, part 2): one module backing
GET /analytics/weekly -- glucose TIR/GMI/trend, the food-glucose
correlation feature, health metric trends, and nutrition trends, all over
a rolling N-day window ending today in the user's own timezone. One
endpoint, one call per screen load, instead of five.

Every daily series here follows the same rule the rest of this app's
health/nutrition data already does: a day with no samples is represented
by nulls, never a fabricated 0 -- see docs/health-data-setup.md and
compute_daily_rollup's own docstring for why that distinction matters.
"""

from __future__ import annotations

from datetime import date as date_type, datetime, timedelta, timezone
from statistics import mean
from typing import Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ...models.glucose_reading import GlucoseReadingModel
from ...models.meal_log import MealLog
from ...models.user import InsulinProfile
from ...schemas.analytics import (
    DailyGlucosePoint,
    DailyMetricPoint,
    DailyNutritionPoint,
    DateRange,
    FoodGlucoseCorrelation,
    GlucoseWeeklySummary,
    HealthMetricTrend,
    HealthTrends,
    Insight,
    NutritionTrends,
    TIRBreakdown,
    WeeklyAnalyticsResponse,
)
from ...timescale_database import TimescaleSessionLocal
from ..health.daily_rollup import compute_daily_rollup, local_date, local_date_bounds
from ..nutrition.meals_today import load_todays_meals, meal_label

DEFAULT_WINDOW_DAYS = 7

# Baseline (pre-meal) reading must be within this many minutes before
# meal_time to count -- further back than this isn't really "before this
# meal" anymore, it's just whatever the sensor happened to say earlier.
BASELINE_TOLERANCE_MINUTES = 30

# Minimum number of days with both data points before an insight is
# offered at all -- "a few plain-language takeaways where the data
# supports them... never fabricate a correlation from thin data" is a
# direct instruction, not a nice-to-have. Two or three days either way of
# a split is not a pattern.
MIN_DAYS_FOR_INSIGHT = 4

# How different the two groups' average glucose needs to be before it's
# worth saying anything -- day-to-day glucose noise alone can easily
# produce a few mg/dL of "difference" that means nothing.
MIN_MEANINGFUL_GLUCOSE_DELTA = 10.0


async def _load_target_range(db: AsyncSession, user_id) -> tuple[int, int]:
    result = await db.execute(
        select(InsulinProfile)
        .where(InsulinProfile.user_id == user_id)
        .order_by(InsulinProfile.created_at.desc())
        .limit(1)
    )
    profile = result.scalar_one_or_none()
    target_min = int(profile.target_glucose_min) if profile and profile.target_glucose_min else 70
    target_max = int(profile.target_glucose_max) if profile and profile.target_glucose_max else 180
    return target_min, target_max


def _week_dates(end_date: date_type, window_days: int) -> list[date_type]:
    """[end_date - (window_days-1), ..., end_date], ascending."""
    return [end_date - timedelta(days=i) for i in range(window_days - 1, -1, -1)]


async def build_weekly_analytics(
    db: AsyncSession,
    user_id,
    user_timezone: str = "UTC",
    window_days: int = DEFAULT_WINDOW_DAYS,
) -> WeeklyAnalyticsResponse:
    now = datetime.now(timezone.utc)
    today = local_date(now, user_timezone)
    dates = _week_dates(today, window_days)
    range_start, _ = local_date_bounds(dates[0], user_timezone)
    _, range_end = local_date_bounds(dates[-1], user_timezone)

    glucose_summary, correlations = await _build_glucose_and_correlations(
        db, user_id, dates, range_start, range_end, user_timezone,
    )
    health_trends = await _build_health_trends(db, user_id, dates, user_timezone)
    nutrition_trends = await _build_nutrition_trends(db, user_id, dates, user_timezone)
    insights = _build_insights(glucose_summary, health_trends)

    return WeeklyAnalyticsResponse(
        range=DateRange(start=dates[0], end=dates[-1]),
        glucose=glucose_summary,
        food_glucose_correlations=correlations,
        health_trends=health_trends,
        nutrition_trends=nutrition_trends,
        insights=insights,
    )


# ── Glucose summary + food-glucose correlation ──────────────────────────────

async def _build_glucose_and_correlations(
    db: AsyncSession,
    user_id,
    dates: list[date_type],
    range_start: datetime,
    range_end: datetime,
    user_timezone: str,
) -> tuple[GlucoseWeeklySummary, list[FoodGlucoseCorrelation]]:
    # Widen the fetch a bit before range_start so a meal near the start of
    # the window can still find a real pre-meal baseline, instead of
    # missing one just because it falls a few minutes before day 1's
    # midnight boundary.
    fetch_start = range_start - timedelta(minutes=BASELINE_TOLERANCE_MINUTES)
    async with TimescaleSessionLocal() as ts:
        result = await ts.execute(
            select(GlucoseReadingModel)
            .where(
                GlucoseReadingModel.user_id == user_id,
                GlucoseReadingModel.recorded_at >= fetch_start,
                GlucoseReadingModel.recorded_at < range_end,
            )
            .order_by(GlucoseReadingModel.recorded_at.asc())
        )
        readings = list(result.scalars().all())

    in_window = [r for r in readings if r.recorded_at >= range_start]

    if not in_window:
        glucose_summary = GlucoseWeeklySummary(
            has_data=False,
            daily=[DailyGlucosePoint(date=d) for d in dates],
        )
    else:
        target_min, target_max = await _load_target_range(db, user_id)
        values = [r.value_mgdl for r in in_window]
        average = mean(values)
        n = len(values)
        below = sum(1 for v in values if v < target_min)
        above = sum(1 for v in values if v > target_max)

        by_date: dict[date_type, list[int]] = {}
        for r in in_window:
            by_date.setdefault(local_date(r.recorded_at, user_timezone), []).append(r.value_mgdl)

        daily_points = []
        for d in dates:
            day_values = by_date.get(d)
            if not day_values:
                daily_points.append(DailyGlucosePoint(date=d))
                continue
            daily_points.append(DailyGlucosePoint(
                date=d,
                avg_mgdl=round(mean(day_values), 1),
                min_mgdl=min(day_values),
                max_mgdl=max(day_values),
                reading_count=len(day_values),
            ))

        glucose_summary = GlucoseWeeklySummary(
            has_data=True,
            average_mgdl=round(average, 1),
            # ADA-standard GMI formula: an eA1c-style estimate from mean
            # glucose. Not a lab A1c substitute -- presented as an
            # estimate in the UI, not a diagnosis.
            gmi_percent=round(3.31 + 0.02392 * average, 1),
            reading_count=n,
            tir=TIRBreakdown(
                below=round(below / n, 4),
                target=round((n - below - above) / n, 4),
                above=round(above / n, 4),
            ),
            daily=daily_points,
        )

    correlations = await _build_food_glucose_correlations(db, user_id, readings, range_start, range_end)
    return glucose_summary, correlations


async def _build_food_glucose_correlations(
    db: AsyncSession,
    user_id,
    readings: list[GlucoseReadingModel],
    range_start: datetime,
    range_end: datetime,
) -> list[FoodGlucoseCorrelation]:
    if not readings:
        return []

    result = await db.execute(
        select(MealLog)
        .where(
            MealLog.user_id == user_id,
            MealLog.meal_time >= range_start,
            MealLog.meal_time < range_end,
        )
        .order_by(MealLog.meal_time.desc())
    )
    meals = result.scalars().all()

    correlations: list[FoodGlucoseCorrelation] = []
    for meal in meals:
        post_value = meal.post_meal_glucose_2hr
        window = "2hr"
        if post_value is None:
            post_value = meal.post_meal_glucose_1hr
            window = "1hr"
        if post_value is None:
            continue  # no post-meal reading has landed yet -- nothing to show

        baseline = _nearest_reading_before(readings, meal.meal_time)
        if baseline is None:
            continue  # no honest delta computable without one

        correlations.append(FoodGlucoseCorrelation(
            meal_id=str(meal.id),
            meal_time=meal.meal_time,
            label=meal_label(meal.food_items or []),
            carbs_g=float(meal.total_carbs_g) if meal.total_carbs_g is not None else None,
            baseline_mgdl=baseline,
            post_meal_mgdl=post_value,
            delta_mgdl=post_value - baseline,
            window=window,
            outcome=meal.glucose_outcome,
        ))

    return correlations


def _nearest_reading_before(
    readings: list[GlucoseReadingModel], meal_time: datetime,
) -> Optional[int]:
    tolerance = timedelta(minutes=BASELINE_TOLERANCE_MINUTES)
    candidates = [
        r for r in readings
        if r.recorded_at <= meal_time and meal_time - r.recorded_at <= tolerance
    ]
    if not candidates:
        return None
    return max(candidates, key=lambda r: r.recorded_at).value_mgdl


# ── Health trends ────────────────────────────────────────────────────────────

async def _build_health_trends(
    db: AsyncSession, user_id, dates: list[date_type], user_timezone: str,
) -> HealthTrends:
    rollups = [await compute_daily_rollup(db, user_id, d, user_timezone) for d in dates]

    def trend_for(metric: str, unit: str) -> HealthMetricTrend:
        points = [DailyMetricPoint(date=d, value=r.get(metric)) for d, r in zip(dates, rollups)]
        return HealthMetricTrend(
            has_data=any(p.value is not None for p in points),
            unit=unit,
            daily=points,
        )

    return HealthTrends(
        steps=trend_for("steps", "count"),
        sleep_minutes=trend_for("sleep_minutes", "min"),
        hrv=trend_for("hrv", "ms"),
        resting_heart_rate=trend_for("resting_heart_rate", "bpm"),
        water_ml=trend_for("water_ml", "ml"),
    )


# ── Nutrition trends ─────────────────────────────────────────────────────────

async def _build_nutrition_trends(
    db: AsyncSession, user_id, dates: list[date_type], user_timezone: str,
) -> NutritionTrends:
    points: list[DailyNutritionPoint] = []
    any_data = False
    for d in dates:
        day_start, day_end = local_date_bounds(d, user_timezone)
        meals = await load_todays_meals(db, user_id, day_start, day_end)
        if not meals:
            points.append(DailyNutritionPoint(date=d))
            continue
        any_data = True
        points.append(DailyNutritionPoint(
            date=d,
            calories=sum(m["total_calories"] or 0 for m in meals),
            carbs_g=round(float(sum(m["total_carbs_g"] or 0 for m in meals)), 1),
            protein_g=round(float(sum(m["total_protein_g"] or 0 for m in meals)), 1),
            fat_g=round(float(sum(m["total_fat_g"] or 0 for m in meals)), 1),
        ))
    return NutritionTrends(has_data=any_data, daily=points)


# ── Insights ─────────────────────────────────────────────────────────────────

def _build_insights(glucose: GlucoseWeeklySummary, health: HealthTrends) -> list[Insight]:
    if not glucose.has_data:
        return []

    glucose_by_date = {p.date: p.avg_mgdl for p in glucose.daily if p.avg_mgdl is not None}
    insights: list[Insight] = []

    steps_insight = _compare_metric_vs_glucose(
        health.steps, glucose_by_date, kind="steps_glucose", more_label="you took more steps",
    )
    if steps_insight:
        insights.append(steps_insight)

    sleep_insight = _compare_metric_vs_glucose(
        health.sleep_minutes, glucose_by_date, kind="sleep_glucose", more_label="you slept more",
    )
    if sleep_insight:
        insights.append(sleep_insight)

    return insights


def _compare_metric_vs_glucose(
    metric_trend: HealthMetricTrend,
    glucose_by_date: dict[date_type, float],
    *,
    kind: str,
    more_label: str,
) -> Optional[Insight]:
    """Splits days with both data points into a low-metric half and a
    high-metric half by median, and compares their average glucose. Only
    returns an insight when there's enough data (MIN_DAYS_FOR_INSIGHT) and
    the difference is large enough to not just be noise
    (MIN_MEANINGFUL_GLUCOSE_DELTA) -- silence is the correct output far
    more often than a claim is.
    """
    paired = [
        (p.value, glucose_by_date[p.date])
        for p in metric_trend.daily
        if p.value is not None and p.date in glucose_by_date
    ]
    if len(paired) < MIN_DAYS_FOR_INSIGHT:
        return None

    paired.sort(key=lambda pair: pair[0])
    mid = len(paired) // 2
    if mid == 0:
        return None
    lower_half = paired[:mid]
    upper_half = paired[-mid:]

    lower_avg_glucose = mean(g for _, g in lower_half)
    upper_avg_glucose = mean(g for _, g in upper_half)
    delta = upper_avg_glucose - lower_avg_glucose

    if abs(delta) < MIN_MEANINGFUL_GLUCOSE_DELTA:
        return None

    direction = "lower" if delta < 0 else "higher"
    return Insight(
        text=f"Your average glucose tended to be {direction} on days {more_label}.",
        kind=kind,
    )
