"""Device-facing read endpoints (architecture-v3.md §2.4): read-only,
scoped implicitly to the paired user via the device JWT's `uid` claim. No
endpoint here takes a `user_id` parameter — the token decides.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, Request
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..core.device_auth import get_current_device
from ..core.http_cache import etag_json_response
from ..database import get_db
from ..models.device import Device
from ..models.glucose_reading import GlucoseReadingModel
from ..models.user import CGMDevice, InsulinProfile, User
from ..services.health.daily_rollup import compute_daily_rollup, local_date, local_date_bounds
from ..services.nutrition.meals_today import load_todays_meals, meal_label
from ..services.realtime.glucose_state import resolve_glucose_state
from ..timescale_database import TimescaleSessionLocal

router = APIRouter()

GLUCOSE_RANGE_WINDOW_HOURS = 24


async def _load_user(db: AsyncSession, user_id: str) -> User:
    result = await db.execute(select(User).where(User.id == user_id))
    return result.scalar_one()


async def _load_active_cgm_device(db: AsyncSession, user_id: str):
    result = await db.execute(
        select(CGMDevice)
        .where(CGMDevice.user_id == user_id, CGMDevice.is_active.is_(True))
        .order_by(CGMDevice.connected_at.desc())
        .limit(1)
    )
    return result.scalar_one_or_none()


async def _load_insulin_targets(db: AsyncSession, user_id: str) -> tuple[int, int]:
    result = await db.execute(
        select(InsulinProfile)
        .where(InsulinProfile.user_id == user_id)
        .order_by(InsulinProfile.created_at.desc())
        .limit(1)
    )
    profile = result.scalar_one_or_none()
    target_low = int(profile.target_glucose_min) if profile and profile.target_glucose_min else 70
    target_high = int(profile.target_glucose_max) if profile and profile.target_glucose_max else 180
    return target_low, target_high


def _reading_data(reading: GlucoseReadingModel) -> dict:
    return {
        "ts": int(reading.recorded_at.timestamp()),
        "mgdl": reading.value_mgdl,
        "trend": reading.trend,
        "trend_arrow": reading.trend_arrow,
        "sensor_id": reading.sensor_id,
        "source": reading.source,
    }


@router.get("/device/snapshot")
async def get_device_snapshot(
    request: Request,
    current: tuple[Device, str] = Depends(get_current_device),
    db: AsyncSession = Depends(get_db),
):
    _device, user_id = current
    user = await _load_user(db, user_id)
    target_low, target_high = await _load_insulin_targets(db, user_id)
    cgm_device = await _load_active_cgm_device(db, user_id)

    now = datetime.now(timezone.utc)
    async with TimescaleSessionLocal() as ts:
        result = await ts.execute(
            select(GlucoseReadingModel)
            .where(GlucoseReadingModel.user_id == user_id)
            .order_by(GlucoseReadingModel.recorded_at.desc())
            .limit(1)
        )
        latest_reading = result.scalars().first()

        window_start = now - timedelta(hours=GLUCOSE_RANGE_WINDOW_HOURS)
        result = await ts.execute(
            select(GlucoseReadingModel)
            .where(GlucoseReadingModel.user_id == user_id, GlucoseReadingModel.recorded_at >= window_start)
            .order_by(GlucoseReadingModel.recorded_at.asc())
        )
        readings_24h = result.scalars().all()

    today = local_date(now, user.timezone)
    rollup = await compute_daily_rollup(db, user_id, today, user.timezone)

    today_start, today_end = local_date_bounds(today, user.timezone)
    meals_today = await load_todays_meals(db, user_id, today_start, today_end)

    payload = {
        "server_time": now.isoformat(),
        "user": {
            "name": user.name,
            "timezone": user.timezone,
            "target_low": target_low,
            "target_high": target_high,
        },
        "glucose": {
            "latest": _reading_data(latest_reading) if latest_reading else None,
            "readings": [_reading_data(r) for r in readings_24h],
            "state": resolve_glucose_state(cgm_device, latest_reading, now=now),
        },
        "health": {
            "date": today.isoformat(),
            "steps": rollup.get("steps"),
            "active_energy_kcal": rollup.get("active_energy_kcal"),
            "heart_rate": rollup.get("heart_rate"),
            "updated_at": rollup["updated_at"].isoformat() if rollup.get("updated_at") else None,
        },
        "calories": {
            "date": today.isoformat(),
            "consumed_kcal": sum(m["total_calories"] or 0 for m in meals_today),
            "carbs_g": float(sum(m["total_carbs_g"] or 0 for m in meals_today)),
            "protein_g": float(sum(m["total_protein_g"] or 0 for m in meals_today)),
            "fat_g": float(sum(m["total_fat_g"] or 0 for m in meals_today)),
            "fiber_g": float(sum(m["total_fiber_g"] or 0 for m in meals_today)),
            "meals": [
                {
                    "id": meal["id"],
                    "meal_time": meal["meal_time"].isoformat(),
                    "label": meal_label(meal["food_items"]),
                    "calories": meal["total_calories"],
                    "carbs_g": float(meal["total_carbs_g"]) if meal["total_carbs_g"] is not None else None,
                }
                for meal in meals_today
            ],
        },
    }
    # server_time is request-time-only — hashing it in would make the ETag
    # change on every call and defeat 304 caching entirely.
    etag_source = {k: v for k, v in payload.items() if k != "server_time"}
    return etag_json_response(request, payload, etag_source=etag_source)
