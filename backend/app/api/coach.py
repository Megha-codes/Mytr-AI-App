from datetime import datetime, timezone, timedelta
from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from ..database import get_db
from ..timescale_database import TimescaleSessionLocal
from ..models.user import User, InsulinProfile, LifestyleBaseline
from ..models.glucose_reading import GlucoseReadingModel
from ..models.meal_log import MealLog
from .auth import get_current_user

router = APIRouter()


@router.get("/insights")
async def get_coach_insights(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    now_utc = datetime.now(timezone.utc)
    today_start = now_utc.replace(hour=0, minute=0, second=0, microsecond=0)
    window_24h = now_utc - timedelta(hours=24)
    window_4h = now_utc - timedelta(hours=4)

    # Insulin profile for glucose thresholds
    ip_result = await db.execute(
        select(InsulinProfile)
        .where(InsulinProfile.user_id == current_user.id)
        .order_by(InsulinProfile.created_at.desc())
        .limit(1)
    )
    insulin = ip_result.scalar_one_or_none()
    target_min = int(insulin.target_glucose_min) if insulin and insulin.target_glucose_min else 70
    target_max = int(insulin.target_glucose_max) if insulin and insulin.target_glucose_max else 180

    # Lifestyle baseline
    lb_result = await db.execute(
        select(LifestyleBaseline)
        .where(LifestyleBaseline.user_id == current_user.id)
        .limit(1)
    )
    lifestyle = lb_result.scalar_one_or_none()

    # Glucose readings
    async with TimescaleSessionLocal() as ts:
        g_result = await ts.execute(
            select(GlucoseReadingModel)
            .where(GlucoseReadingModel.user_id == current_user.id)
            .where(GlucoseReadingModel.recorded_at >= window_24h)
            .order_by(GlucoseReadingModel.recorded_at.desc())
        )
        readings_24h = g_result.scalars().all()

    # Today's meals
    m_result = await db.execute(
        select(MealLog)
        .where(MealLog.user_id == current_user.id)
        .where(MealLog.meal_time >= today_start)
    )
    meals_today = m_result.scalars().all()
    meals_count = len(meals_today)

    # Compute time-in-range
    time_in_range = None
    glucose_stable = False
    last_4h_in_range = False

    if readings_24h:
        in_range = sum(1 for r in readings_24h if target_min <= r.value_mgdl <= target_max)
        time_in_range = round(in_range / len(readings_24h), 2)

        if len(readings_24h) >= 2:
            diff = abs(readings_24h[0].value_mgdl - readings_24h[1].value_mgdl)
            glucose_stable = diff <= 5

        last_4h = [r for r in readings_24h if r.recorded_at >= window_4h]
        last_4h_in_range = bool(last_4h) and all(
            target_min <= r.value_mgdl <= target_max for r in last_4h
        )

    # Morning briefing
    hour = now_utc.hour
    if hour < 12:
        greeting = "Good morning"
    elif hour < 17:
        greeting = "Good afternoon"
    else:
        greeting = "Good evening"

    if not readings_24h:
        briefing = f"{greeting}, {current_user.name or 'there'}! Connect your CGM or log a reading to get personalized insights."
    elif glucose_stable:
        briefing = f"{greeting}, {current_user.name or 'there'}! Your glucose has been stable. Keep up the great work."
    elif time_in_range and time_in_range >= 0.7:
        briefing = f"{greeting}, {current_user.name or 'there'}! You're in great range today — {int(time_in_range * 100)}% time-in-range so far."
    else:
        briefing = f"{greeting}, {current_user.name or 'there'}! Let's work on keeping your glucose in range today."

    # Today's focus
    if meals_count == 0:
        today_focus = "Log your first meal to start tracking"
    elif not last_4h_in_range and readings_24h:
        today_focus = "Focus on staying in range post-meals"
    else:
        today_focus = "Stay consistent — you're on a good track"

    # Insights
    insights = []

    if readings_24h:
        tir_pct = int((time_in_range or 0) * 100)
        insights.append({
            "title": "Post-meal walks help",
            "description": "A 10-minute walk after eating can reduce glucose spikes by up to 30%.",
            "category": "activity",
            "estimated_saving_units": 1.5,
            "progress": min(tir_pct / 100, 1.0),
        })

    sleep_hrs = lifestyle.baseline_sleep_hrs if lifestyle else None
    if sleep_hrs is not None:
        sleep_progress = min(float(sleep_hrs) / 8.0, 1.0)
        insights.append({
            "title": "Sleep quality matters",
            "description": "You're averaging {:.0f}h of sleep. Aim for 7–9 hours for better metabolic control.".format(sleep_hrs),
            "category": "wellness",
            "estimated_saving_units": 0.0,
            "progress": sleep_progress,
        })
    else:
        insights.append({
            "title": "Hydration on track",
            "description": "Staying hydrated helps regulate glucose levels throughout the day.",
            "category": "wellness",
            "estimated_saving_units": 0.0,
            "progress": 0.6,
        })

    # Targets
    targets = [
        {
            "title": "4h time-in-range streak",
            "description": f"Maintain glucose between {target_min}–{target_max} mg/dL for 4 consecutive hours.",
            "category": "diabetes",
            "progress": 1.0 if last_4h_in_range else (0.5 if readings_24h else 0.0),
        },
        {
            "title": "Log 3 meals today",
            "description": "Consistent meal logging helps identify patterns that affect your glucose.",
            "category": "nutrition",
            "progress": min(meals_count / 3, 1.0),
        },
    ]

    return {
        "morning_briefing": briefing,
        "today_focus": today_focus,
        "insights": insights,
        "targets": targets,
    }
