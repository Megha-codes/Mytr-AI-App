from datetime import datetime, timezone, timedelta
from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func

from ..database import get_db
from ..timescale_database import TimescaleSessionLocal
from datetime import date
from ..models.user import User, InsulinProfile
from ..models.meal_log import MealLog
from ..models.glucose_reading import GlucoseReadingModel
from ..models.activity import ActivityLog
from .auth import get_current_user

router = APIRouter()


def _level_title(level: int) -> str:
    if level <= 2:
        return "Rookie"
    if level <= 4:
        return "Tracker"
    if level <= 6:
        return "Warrior"
    if level <= 8:
        return "Range Rider"
    if level <= 10:
        return "Master"
    return "Legend"


@router.get("")
async def get_dashboard(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    now_utc = datetime.now(timezone.utc)
    today_start = now_utc.replace(hour=0, minute=0, second=0, microsecond=0)
    window_24h = now_utc - timedelta(hours=24)
    window_4h = now_utc - timedelta(hours=4)

    # ── Insulin profile (glucose target thresholds) ───────────────────────────
    ip_result = await db.execute(
        select(InsulinProfile)
        .where(InsulinProfile.user_id == current_user.id)
        .order_by(InsulinProfile.created_at.desc())
        .limit(1)
    )
    insulin = ip_result.scalar_one_or_none()
    target_min = int(insulin.target_glucose_min) if insulin and insulin.target_glucose_min else 70
    target_max = int(insulin.target_glucose_max) if insulin and insulin.target_glucose_max else 180

    # ── Glucose readings from TimescaleDB ─────────────────────────────────────
    async with TimescaleSessionLocal() as ts:
        g_result = await ts.execute(
            select(GlucoseReadingModel)
            .where(GlucoseReadingModel.user_id == current_user.id)
            .where(GlucoseReadingModel.recorded_at >= window_24h)
            .order_by(GlucoseReadingModel.recorded_at.desc())
        )
        readings_24h = g_result.scalars().all()

        total_glucose = await ts.scalar(
            select(func.count()).select_from(GlucoseReadingModel)
            .where(GlucoseReadingModel.user_id == current_user.id)
        ) or 0

    # ── Build glucose section ─────────────────────────────────────────────────
    current_value = None
    trend = None
    trend_arrow = None
    time_in_range_24h = None
    tir_breakdown = None
    last_updated = None
    is_connected = False

    if readings_24h:
        latest = readings_24h[0]
        current_value = latest.value_mgdl
        last_updated = latest.recorded_at.isoformat()
        is_connected = True

        if len(readings_24h) >= 2:
            diff = readings_24h[0].value_mgdl - readings_24h[1].value_mgdl
            if diff > 5:
                trend, trend_arrow = "RISING", "↑"
            elif diff < -5:
                trend, trend_arrow = "FALLING", "↓"
            else:
                trend, trend_arrow = "STABLE", "→"

        n = len(readings_24h)
        below_count = sum(1 for r in readings_24h if r.value_mgdl < target_min)
        above_count = sum(1 for r in readings_24h if r.value_mgdl > target_max)
        in_range_count = n - below_count - above_count
        time_in_range_24h = round(in_range_count / n, 4)
        # Previously hardcoded to {below: 0, target: 0, above: 0} on the
        # frontend regardless of real data — this is the actual breakdown,
        # not a placeholder. Fractions (0-1), matching time_in_range_24h's
        # own convention; the frontend already expects that shape
        # (TIRBreakdown/TIRStackedBar in models.dart).
        tir_breakdown = {
            "below": round(below_count / n, 4),
            "target": round(in_range_count / n, 4),
            "above": round(above_count / n, 4),
        }

    # ── Today's meals from Postgres ───────────────────────────────────────────
    m_result = await db.execute(
        select(MealLog)
        .where(MealLog.user_id == current_user.id)
        .where(MealLog.meal_time >= today_start)
    )
    meals_today = m_result.scalars().all()
    meals_count = len(meals_today)

    calories_eaten = sum(m.total_calories or 0 for m in meals_today)
    carbs_g = float(sum(m.total_carbs_g or 0 for m in meals_today))
    protein_g = float(sum(m.total_protein_g or 0 for m in meals_today))
    fat_g = float(sum(m.total_fat_g or 0 for m in meals_today))

    # ── XP & level (meals * 10 + glucose_readings / 10) ──────────────────────
    total_meals = await db.scalar(
        select(func.count()).select_from(MealLog)
        .where(MealLog.user_id == current_user.id)
    ) or 0

    total_xp = round(total_meals * 10 + total_glucose / 10)
    level = total_xp // 300 + 1
    xp_in_level = total_xp % 300
    xp_to_next = 300 - xp_in_level

    # ── Challenges ────────────────────────────────────────────────────────────
    is_diabetic = current_user.diabetes_type in ("T1", "T2")

    last_4h_in_range = False
    if is_diabetic and readings_24h:
        last_4h = [r for r in readings_24h if r.recorded_at >= window_4h]
        last_4h_in_range = bool(last_4h) and all(
            target_min <= r.value_mgdl <= target_max for r in last_4h
        )

    # ── Today's activity (synced from phone) ─────────────────────────────────
    activity_result = await db.execute(
        select(ActivityLog)
        .where(ActivityLog.user_id == current_user.id)
        .where(ActivityLog.date == date.today())
    )
    activity = activity_result.scalar_one_or_none()

    challenges = [
        {
            "id": "log_first_meal",
            "title": "Log your first meal today",
            "xp_reward": 10,
            "is_completed": meals_count > 0,
            "category": "nutrition",
        },
        {
            "id": "stay_in_range" if is_diabetic else "drink_water",
            "title": "Stay in range for 4 hours" if is_diabetic else "Drink 8 glasses of water",
            "xp_reward": 25 if is_diabetic else 15,
            "is_completed": last_4h_in_range,
            "category": "diabetes" if is_diabetic else "wellness",
        },
        {
            "id": "log_3_meals",
            "title": "Log 3 meals today",
            "xp_reward": 30,
            "is_completed": meals_count >= 3,
            "category": "nutrition",
        },
    ]

    return {
        "user": {
            "name": current_user.name or "User",
            "level": level,
            "xp": xp_in_level,
            "xp_to_next_level": xp_to_next,
            "level_title": _level_title(level),
            "streak_days": 0,  # TODO: implement streak calculation
        },
        "glucose": {
            "current_value": current_value,
            "trend": trend,
            "trend_arrow": trend_arrow,
            "time_in_range_24h": time_in_range_24h,
            "time_in_range_breakdown": tir_breakdown,
            "last_updated": last_updated,
            "is_connected": is_connected,
        },
        "nutrition": {
            "calories_eaten": calories_eaten,
            "calorie_target": 2200,
            "carbs_g": carbs_g,
            "protein_g": protein_g,
            "fat_g": fat_g,
            "meals_logged_today": meals_count,
        },
        "activity": {
            # None (not 0) when no activity_logs row exists for today — no
            # row means no health sample has ever been projected for this
            # date, which is a different fact from "synced and genuinely
            # zero" (e.g. steps_today really is 0 right after midnight).
            # The frontend must render these as distinct "no data" vs "0"
            # states (docs/health-data-setup.md).
            "steps_today": activity.steps_today if activity else None,
            "steps_goal": 10000,
            "calories_burned": activity.calories_burned if activity else None,
            # No real data source exists for this yet — activity_logs has
            # no active_minutes column, and nothing computes it from
            # health_metrics. Always None rather than a fake 0; this is not
            # "no analytics yet", it's "never implemented at all".
            "active_minutes": None,
        },
        "challenges": challenges,
    }
