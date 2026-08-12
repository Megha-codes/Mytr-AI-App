"""Water intake logging (Phase-1 polish, part 3). Stored as an ordinary
health_metrics row (metric='water_ml', unit='ml', source='MANUAL') --
health_metrics is explicitly metric-agnostic for exactly this reason (see
its own model docstring), so this needed no new table or migration, just
one more entry in daily_rollup.py's _AGGREGATION map.

Two endpoints, both user-JWT: POST to log a quick add, GET for today's
(or any day's) total against the daily goal. GET /device/water/daily
(app/api/device_data.py) is the device-JWT twin, same pattern as
/health/daily + /device/health/daily.
"""

from __future__ import annotations

from datetime import date as date_type, datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from ..database import get_db
from ..models.health_metric import HealthMetric
from ..models.user import User
from ..schemas.water import WaterDailyResponse, WaterLogRequest, WaterLogResponse
from ..services.health.daily_rollup import compute_daily_rollup, local_date
from .auth import get_current_user

router = APIRouter()

# A round, commonly-cited daily target (~8 glasses) -- same status as
# dashboard.py's steps_goal/calorie_target: a fixed default, not a
# per-user setting yet. Shared with the device twin below so the desk and
# the app never disagree about what "the goal" is.
DEFAULT_WATER_GOAL_ML = 2000


@router.post("/water/log", response_model=WaterLogResponse, status_code=201)
async def log_water(
    request: WaterLogRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    now = datetime.now(timezone.utc)
    db.add(HealthMetric(
        user_id=current_user.id,
        metric="water_ml",
        value=float(request.amount_ml),
        unit="ml",
        started_at=now,
        ended_at=now,
        source="MANUAL",
    ))
    await db.commit()

    today = local_date(now, current_user.timezone)
    rollup = await compute_daily_rollup(db, current_user.id, today, current_user.timezone)
    total = int(rollup.get("water_ml") or request.amount_ml)

    return WaterLogResponse(success=True, total_ml_today=total)


@router.get("/water/daily", response_model=WaterDailyResponse)
async def get_water_daily(
    date: Optional[date_type] = None,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    target_date = date or local_date(datetime.now(timezone.utc), current_user.timezone)
    rollup = await compute_daily_rollup(db, current_user.id, target_date, current_user.timezone)
    total = rollup.get("water_ml")

    return WaterDailyResponse(
        date=target_date,
        total_ml=int(total) if total is not None else None,
        goal_ml=DEFAULT_WATER_GOAL_ML,
    )
