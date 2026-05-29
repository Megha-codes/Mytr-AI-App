from datetime import datetime, timezone, timedelta
from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func

from ..database import get_db
from ..timescale_database import TimescaleSessionLocal
from ..models.user import User, InsulinProfile
from ..models.meal_log import MealLog
from ..models.glucose_reading import GlucoseReadingModel
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

        in_range_count = sum(
            1 for r in readings_24h if target_min <= r.value_mgdl <= target_max
        )
        time_in_range_24h = round(in_range_count / len(readings_24h), 4)

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
            # TODO: Integrate with health package data — activity synced from phone
            "steps_today": 0,
            "steps_goal": 10000,
            "calories_burned": 0,
            "active_minutes": 0,
        },
        "challenges": challenges,
    }
