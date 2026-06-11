from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func

from ..database import get_db
from ..timescale_database import TimescaleSessionLocal
from ..models.user import User, InsulinProfile, CGMDevice
from ..models.meal_log import MealLog
from ..models.glucose_reading import GlucoseReadingModel
from .auth import get_current_user

router = APIRouter()


def _user_type_str(diabetes_type: str | None) -> str:
    return {"T1": "type1", "T2": "type2", "PRE": "type2"}.get(diabetes_type or "", "fitness")


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


@router.get("/profile")
async def get_user_profile(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    # ── Insulin profile ───────────────────────────────────────────────────────
    ip_result = await db.execute(
        select(InsulinProfile)
        .where(InsulinProfile.user_id == current_user.id)
        .order_by(InsulinProfile.created_at.desc())
        .limit(1)
    )
    insulin = ip_result.scalar_one_or_none()

    # ── Active CGM device ─────────────────────────────────────────────────────
    cgm_result = await db.execute(
        select(CGMDevice)
        .where(CGMDevice.user_id == current_user.id)
        .where(CGMDevice.deleted_at == None)  # noqa: E711
        .where(CGMDevice.is_active == True)   # noqa: E712
        .limit(1)
    )
    cgm = cgm_result.scalar_one_or_none()

    # ── XP calc ───────────────────────────────────────────────────────────────
    total_meals = await db.scalar(
        select(func.count()).select_from(MealLog)
        .where(MealLog.user_id == current_user.id)
    ) or 0

    async with TimescaleSessionLocal() as ts:
        total_glucose = await ts.scalar(
            select(func.count()).select_from(GlucoseReadingModel)
            .where(GlucoseReadingModel.user_id == current_user.id)
        ) or 0

    total_xp = round(total_meals * 10 + total_glucose / 10)
    level = total_xp // 300 + 1
    xp_in_level = total_xp % 300

    primary_goal = (
        "Manage blood glucose"
        if current_user.diabetes_type in ("T1", "T2")
        else "Get fit"
    )

    return {
        "display_name": current_user.name or "User",
        "avatar_url": None,
        "user_type": _user_type_str(current_user.diabetes_type),
        "current_level": level,
        "level_title": _level_title(level),
        "current_xp": xp_in_level,
        "xp_to_next_level": 300,
        "height_cm": float(current_user.height_cm) if current_user.height_cm else None,
        "starting_weight": float(current_user.weight_kg) if current_user.weight_kg else None,
        "weight_goal": None,
        "primary_goal": primary_goal,
        "recent_achievements": [],
        "insulin_profile": {
            "icr": float(insulin.icr) if insulin and insulin.icr else None,
            "isf": float(insulin.isf) if insulin and insulin.isf else None,
            "target_min": int(insulin.target_glucose_min) if insulin and insulin.target_glucose_min else None,
            "target_max": int(insulin.target_glucose_max) if insulin and insulin.target_glucose_max else None,
            "insulin_type": insulin.insulin_type if insulin else None,
        } if insulin else None,
        "cgm_device": {
            "type": cgm.device_type,
            "is_connected": True,
            "sensor_status": cgm.sensor_status,
        } if cgm else None,
    }
